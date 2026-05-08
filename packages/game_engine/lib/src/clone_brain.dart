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

enum FallbackStrategy { random, middleFocus, edgeFocus, pileFocus }

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
    if (weighted.length > 1) {
      return narrate(
        DecisionContext.multipleCandidates,
        candidateCount: weighted.length,
      );
    }
    if (weighted.length == 1) {
      return narrate(
        DecisionContext.fuzzyMatch,
        gameId: weighted.first.state.gameId,
      );
    }
    return narrate(DecisionContext.allLosing);
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
        final mid = rules.cols ~/ 2;
        final sorted = [...legalMoves]
          ..sort((a, b) => (a - mid).abs().compareTo((b - mid).abs()));
        return sorted.first;
      case FallbackStrategy.edgeFocus:
        final mid = rules.cols ~/ 2;
        final sorted = [...legalMoves]
          ..sort((a, b) => (b - mid).abs().compareTo((a - mid).abs()));
        return sorted.first;
      case FallbackStrategy.pileFocus:
        var bestMove = legalMoves.first;
        var bestCount = -1;
        for (final move in legalMoves) {
          var count = 0;
          for (var r = 0; r < board.rows; r++) {
            if (board.get(r, move) != 0) count++;
          }
          if (count > bestCount) {
            bestCount = count;
            bestMove = move;
          }
        }
        return bestMove;
    }
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
