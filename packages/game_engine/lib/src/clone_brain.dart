import 'dart:math';
import 'dart:typed_data';

import 'board.dart';
import 'canonicalize.dart';
import 'diffusion.dart';
import 'game_rules.dart';
import 'game_state.dart';
import 'move_selection.dart';
import 'narration.dart';
import 'similarity.dart';

enum FallbackStrategy {
  random,
  middleFocus,
  pileFocus,
  ownPileAdjacent,
  greedyConnect,
  greedyConnectDefense,
}

/// Per-query cap on candidates that contribute to the heatmap. The matcher
/// returns all prefilter survivors sorted by L1 distance; we only use the
/// closest [_kNearestPerQuery] of them. Without a cap, late-game heatmaps
/// drown in low-relevance contributions because the prefilter passes
/// hundreds of vaguely-similar rows once the database grows. Tunable.
const int _kNearestPerQuery = 20;

class MoveDecision {
  final int move;
  final String narration;
  final bool usedFallback;
  final int candidatesFound;

  MoveDecision({
    required this.move,
    required this.narration,
    required this.usedFallback,
    required this.candidatesFound,
  });
}

class CloneBrain {
  final GameRules rules;
  final GameLog log;
  final FallbackStrategy fallback;
  final Random _random;

  CloneBrain({
    required this.rules,
    required this.log,
    this.fallback = FallbackStrategy.random,
    Random? random,
  }) : _random = random ?? Random();

  GameState createState({
    required Board board,
    required int movePlayed,
    required int ply,
    required String gameId,
  }) {
    final influence = rules.diffusionKernel.diffuse(board);
    return GameState(
      board: board,
      diffusedImage: quantizeInfluenceMap(influence),
      movePlayed: movePlayed,
      ply: ply,
      gameId: gameId,
      totalMaterial: computeTotalMaterial(board),
      materialBalance: computeMaterialBalance(board),
    );
  }

  MoveDecision selectMove(Board currentBoard, int side) {
    final legal = rules.legalMoves(currentBoard);
    if (legal.isEmpty) {
      return MoveDecision(
        move: -1,
        narration: 'No legal moves available',
        usedFallback: true,
        candidatesFound: 0,
      );
    }

    final completed = log.statesWithOutcome();
    if (completed.isEmpty) {
      return _fallbackDecision(legal, currentBoard);
    }

    // Four queries: perspective × mirror. Q_A and Q_B target different
    // populations of stored rows via the outcome filter — Q_A finds rows
    // where the +1 mover won (winner-mover candidates), Q_B finds rows where
    // the +1 mover lost (loser-mover candidates). Each query's orientation
    // (flipped vs not) makes its target population L1-near-aligned. All
    // candidates contribute with positive weight; the candidate image's
    // natural sign carries the win/loss lesson.
    final flipped = flipPerspective(currentBoard);
    final mirroredFlipped = mirrorBoard(flipped);
    final mirroredQuery = mirrorBoard(currentBoard);

    final all = <WeightedCandidate>[];
    var totalResults = 0;
    for (final q in [
      _Query(flipped, requiredOutcome: 1, mirror: false),
      _Query(mirroredFlipped, requiredOutcome: 1, mirror: true),
      _Query(currentBoard, requiredOutcome: -1, mirror: false),
      _Query(mirroredQuery, requiredOutcome: -1, mirror: true),
    ]) {
      final results = _runQuery(q, completed);
      totalResults += results.length;
      all.addAll(results);
    }

    if (all.isEmpty) {
      return _fallbackDecision(legal, currentBoard);
    }

    final selected = rules.moveSelectionStrategy.selectMove(
      all,
      legal,
      currentBoard,
    );
    if (selected == null) {
      return _fallbackDecision(legal, currentBoard);
    }

    // All-losing guard: rebuild the heatmap and check the chosen move's score.
    // Heatmap accumulation is microseconds for Connect Four — cheap to redo.
    final heatmap = InfluenceOverlayStrategy.buildHeatmap(
      all,
      currentBoard.rows,
      currentBoard.cols,
    );
    final score = rules.moveScorer.scoreMove(selected, currentBoard, heatmap);
    if (score <= 0) {
      final move = _fallbackMove(legal, currentBoard);
      return MoveDecision(
        move: move,
        narration: narrate(DecisionContext.allLosing),
        usedFallback: false,
        candidatesFound: totalResults,
      );
    }

    return MoveDecision(
      move: selected,
      narration: _buildNarration(all),
      usedFallback: false,
      candidatesFound: totalResults,
    );
  }

  List<WeightedCandidate> _runQuery(_Query q, List<GameState> candidates) {
    final image = quantizeInfluenceMap(rules.diffusionKernel.diffuse(q.board));
    final totalMaterial = computeTotalMaterial(q.board);
    final query = GameState(
      board: q.board,
      diffusedImage: image,
      movePlayed: 0,
      // For Connect Four, ply == totalMaterial (every move adds one piece).
      // The prefilter is the only consumer of this synthetic state, and CF's
      // ConnectFourFilter reads `ply`. Other games will plug in filters that
      // read whatever they need from this query state.
      ply: totalMaterial,
      gameId: '__query__',
      totalMaterial: totalMaterial,
      materialBalance: computeMaterialBalance(q.board),
    );

    final results = searchSimilar(
      queryDiffusedImage: image,
      prefilter: rules.prefilter(query),
      candidates: candidates,
    );

    final weighted = <WeightedCandidate>[];
    var kept = 0;
    for (final r in results) {
      if (r.state.outcome != q.requiredOutcome) continue;
      if (kept >= _kNearestPerQuery) break;
      final movesToEnd = r.state.movesToEnd;
      if (movesToEnd == null) continue;
      kept++;
      final efficiency = 1.0 / (1.0 + movesToEnd);
      final similarity = 1.0 / (1.0 + r.distance);
      // Always positive weight. The candidate image's natural sign carries
      // the lesson: a winner-mover candidate has positive territory at its
      // mover's cells (push heatmap up there → "play here"); a loser-mover
      // candidate has negative territory at its mover's cells (push heatmap
      // down there → "avoid here"). An explicit sign multiplier would
      // double-count and invert the loss signal. (Diagnosis recap in the
      // proposal: heatmap aggregation differs from per-column voting in how
      // it threads sign — this is the corrected formulation.)
      final weight = efficiency * similarity;
      if (weight == 0) continue;

      // For mirror queries, the candidate's diffused image and movePlayed need
      // to be reflected before they enter the heatmap / narration.
      final transformedState =
          q.mirror ? _mirrorStateForHeatmap(r.state) : r.state;
      weighted.add(WeightedCandidate(transformedState, weight));
    }
    return weighted;
  }

  /// Returns a `GameState` whose `diffusedImage` and `movePlayed` are mirrored
  /// (left-right flipped) so a candidate retrieved via a mirror query can be
  /// added to the heatmap directly. Other fields are preserved as-is — the
  /// strategy only reads `diffusedImage` from the state.
  GameState _mirrorStateForHeatmap(GameState s) {
    final mirroredImage = _mirrorImage(s.diffusedImage, rules.rows, rules.cols);
    return GameState(
      board: s.board,
      diffusedImage: mirroredImage,
      movePlayed: rules.cols - 1 - s.movePlayed,
      ply: s.ply,
      gameId: s.gameId,
      totalMaterial: s.totalMaterial,
      materialBalance: s.materialBalance,
      outcome: s.outcome,
      movesToEnd: s.movesToEnd,
    );
  }

  Int8List _mirrorImage(Int8List image, int rows, int cols) {
    final result = Int8List(image.length);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        result[r * cols + (cols - 1 - c)] = image[r * cols + c];
      }
    }
    return result;
  }

  String _buildNarration(List<WeightedCandidate> weighted) {
    if (weighted.isEmpty) return narrate(DecisionContext.allLosing);
    // Count distinct *games* the candidates came from, not stored state rows.
    // A single 14-ply past game can contribute 10+ candidate states to the
    // four queries, and saying "I've seen this 10 times" after one past game
    // reads as a lie. Distinct game IDs is the honest figure.
    final games = <String>{for (final c in weighted) c.state.gameId};
    if (games.length > 1) {
      return narrate(
        DecisionContext.multipleCandidates,
        candidateCount: games.length,
      );
    }
    return narrate(DecisionContext.fuzzyMatch);
  }

  MoveDecision _fallbackDecision(List<int> legalMoves, Board board) {
    final move = _fallbackMove(legalMoves, board);
    return MoveDecision(
      move: move,
      narration: narrate(
        DecisionContext.fallbackUsed,
        fallbackName: fallback.name,
      ),
      usedFallback: true,
      candidatesFound: 0,
    );
  }

  int _fallbackMove(List<int> legalMoves, Board board) {
    switch (fallback) {
      case FallbackStrategy.random:
        return legalMoves[_random.nextInt(legalMoves.length)];
      case FallbackStrategy.middleFocus:
        return _legalClosestToMid(legalMoves);
      case FallbackStrategy.pileFocus:
        return _stackerMove(legalMoves, board);
      case FallbackStrategy.ownPileAdjacent:
        return _builderMove(legalMoves, board);
      case FallbackStrategy.greedyConnect:
        return _connectorMove(legalMoves, board);
      case FallbackStrategy.greedyConnectDefense:
        return _sentinelMove(legalMoves, board);
    }
  }

  int _legalClosestToMid(List<int> legalMoves) {
    final mid = rules.cols ~/ 2;
    final sorted = [...legalMoves]
      ..sort((a, b) => (a - mid).abs().compareTo((b - mid).abs()));
    return sorted.first;
  }

  int _stackerMove(List<int> legalMoves, Board board) {
    final mid = rules.cols ~/ 2;
    var bestMove = legalMoves.first;
    var bestCount = -1;
    var bestDist = rules.cols;
    for (final move in legalMoves) {
      var count = 0;
      for (var r = 0; r < board.rows; r++) {
        if (board.get(r, move) != 0) count++;
      }
      final dist = (move - mid).abs();
      if (count > bestCount || (count == bestCount && dist < bestDist)) {
        bestCount = count;
        bestMove = move;
        bestDist = dist;
      }
    }
    return bestMove;
  }

  int _builderMove(List<int> legalMoves, Board board) {
    final mid = rules.cols ~/ 2;

    // Find the column with the most own (+1) pieces; ties broken by closeness
    // to mid, then by lower index for determinism.
    var cStar = -1;
    var bestCount = 0;
    var bestDist = rules.cols;
    for (var c = 0; c < rules.cols; c++) {
      var count = 0;
      for (var r = 0; r < board.rows; r++) {
        if (board.get(r, c) == 1) count++;
      }
      if (count == 0) continue;
      final dist = (c - mid).abs();
      if (count > bestCount ||
          (count == bestCount && dist < bestDist) ||
          (count == bestCount && dist == bestDist && c < cStar)) {
        bestCount = count;
        bestDist = dist;
        cStar = c;
      }
    }

    if (cStar < 0) {
      // No own pieces yet — open with the centre.
      return _legalClosestToMid(legalMoves);
    }

    final candidates = <int>[
      for (final c in [cStar - 1, cStar + 1])
        if (c >= 0 && c < rules.cols && legalMoves.contains(c)) c,
    ];

    if (candidates.isEmpty) return _legalClosestToMid(legalMoves);
    if (candidates.length == 1) return candidates.first;

    final dLeft = (candidates[0] - mid).abs();
    final dRight = (candidates[1] - mid).abs();
    if (dLeft < dRight) return candidates[0];
    if (dRight < dLeft) return candidates[1];
    // Equidistant: random tie-break (uses seeded _random for reproducibility).
    return candidates[_random.nextBool() ? 0 : 1];
  }

  int _connectorMove(List<int> legalMoves, Board board) {
    final mid = rules.cols ~/ 2;
    var bestMove = legalMoves.first;
    var bestScore = -1;
    var bestDist = rules.cols;
    for (final c in legalMoves) {
      final r = _gravityRow(board, c);
      final score = _longestRunThrough(board, r, c, side: 1);
      final dist = (c - mid).abs();
      if (score > bestScore || (score == bestScore && dist < bestDist)) {
        bestScore = score;
        bestMove = c;
        bestDist = dist;
      }
    }
    return bestMove;
  }

  int _sentinelMove(List<int> legalMoves, Board board) {
    final mid = rules.cols ~/ 2;
    final mustBlock = <int>[];
    for (final c in legalMoves) {
      final r = _gravityRow(board, c);
      // Imagine the *opponent* drops here next; would they reach 4-in-a-row?
      if (_longestRunThrough(board, r, c, side: -1) >= 4) {
        mustBlock.add(c);
      }
    }
    if (mustBlock.isEmpty) return _connectorMove(legalMoves, board);

    // Can only block one — pick the most central.
    var pick = mustBlock.first;
    var bestDist = (pick - mid).abs();
    for (final c in mustBlock.skip(1)) {
      final dist = (c - mid).abs();
      if (dist < bestDist) {
        pick = c;
        bestDist = dist;
      }
    }
    return pick;
  }

  /// Lowest empty row in [col]. Caller guarantees the column is legal (i.e.
  /// has at least one empty cell), so the loop always finds one.
  int _gravityRow(Board board, int col) {
    for (var r = board.rows - 1; r >= 0; r--) {
      if (board.get(r, col) == 0) return r;
    }
    // Should be unreachable given caller contract.
    return -1;
  }

  /// Longest contiguous run of [side] through (row, col), treating that cell
  /// as if it were [side]. Considers all four standard axes; returns the max.
  int _longestRunThrough(Board board, int row, int col, {required int side}) {
    const directions = [
      [0, 1],
      [1, 0],
      [1, 1],
      [1, -1],
    ];
    var best = 1;
    for (final d in directions) {
      var len = 1;
      // Walk forward.
      var r = row + d[0];
      var c = col + d[1];
      while (r >= 0 &&
          r < board.rows &&
          c >= 0 &&
          c < board.cols &&
          board.get(r, c) == side) {
        len++;
        r += d[0];
        c += d[1];
      }
      // Walk backward.
      r = row - d[0];
      c = col - d[1];
      while (r >= 0 &&
          r < board.rows &&
          c >= 0 &&
          c < board.cols &&
          board.get(r, c) == side) {
        len++;
        r -= d[0];
        c -= d[1];
      }
      if (len > best) best = len;
    }
    return best;
  }
}

class _Query {
  final Board board;
  final int requiredOutcome;
  final bool mirror;
  const _Query(
    this.board, {
    required this.requiredOutcome,
    required this.mirror,
  });
}
