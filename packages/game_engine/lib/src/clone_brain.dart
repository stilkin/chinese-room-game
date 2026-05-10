import 'dart:math';
import 'dart:typed_data';

import 'board.dart';
import 'canonicalize.dart';
import 'diffusion.dart';
import 'game_rules.dart';
import 'game_state.dart';
import 'games/go.dart';
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
  // Go-mode personalities. Selectable only when `rules is GoRules`; the
  // mobile slider's user-facing set gates this. The Go helpers below assert
  // `rules is GoRules` for clarity.
  goStarPoints,
  goDiamond,
  goContact,
  goGreedyArea,
}

/// Per-query cap on candidates that contribute to the heatmap. The matcher
/// returns all prefilter survivors sorted by L1 distance; we only use the
/// closest [_kNearestPerQuery] of them. Without a cap, late-game heatmaps
/// drown in low-relevance contributions because the prefilter passes
/// hundreds of vaguely-similar rows once the database grows. Tunable.
const int _kNearestPerQuery = 20;

/// Standard 4-orthogonal offsets used by several Go fallbacks (Diamond,
/// Contact, Greedy prefilter). Hoisted to module scope so each helper can
/// reuse the same constant without re-declaring it inline.
const _kOrthogonalOffsets = [
  [-1, 0],
  [1, 0],
  [0, -1],
  [0, 1],
];

/// 4-diagonal offsets (NE, NW, SE, SW). Used by the Diamond fallback's
/// "diagonal-friendly" count.
const _kDiagonalOffsets = [
  [-1, -1],
  [-1, 1],
  [1, -1],
  [1, 1],
];

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
    final legal = rules.legalMoves(currentBoard, side: side, log: log);
    if (legal.isEmpty) {
      return MoveDecision(
        move: -1,
        narration: 'No legal moves available',
        usedFallback: true,
        candidatesFound: 0,
      );
    }

    // Pass should only enter the brain's selection set when the opponent just
    // passed — that's the game-end signal where mirroring is correct.
    // Otherwise a weak heatmap (small magnitudes from low-relevance
    // candidates) would let the pass score (`GoMoveScorer.passScore = 0.01`)
    // beat every legal placement, and the bot would pass turn after turn
    // even with plenty of board to play on. The same flag also gates both
    // the fallback pool below (so e.g. `random` can't spontaneously pass on
    // a 13×13 cold-start) and the self-fill→pass override applied to the
    // chosen move at every emit point below.
    final inProgress = log.states.where((s) => s.outcome == null).toList();
    final opponentJustPassed =
        inProgress.isNotEmpty && rules.isPassMove(inProgress.last.movePlayed);

    // `fallbackPool` excludes `passMove` unless the opponent just passed.
    // Without this filter, `FallbackStrategy.random` would spontaneously
    // pass on Go cold-start (~0.6% of moves on an empty 13×13), and any
    // future fallback path would inherit the same bug. The Go scorer-based
    // fallbacks (Diamond/Contact/Greedy/Star-point) already strip pass via
    // `_goPlacementMoves` — this pool gives the same protection to
    // `random` and to any CF fallback that happens to be configured.
    final fallbackPool =
        opponentJustPassed
            ? legal
            : legal.where((m) => !rules.isPassMove(m)).toList();
    // Last-resort safety: if filtering eliminated every move (pass-only
    // position, opponent hasn't passed — should be unreachable in practice),
    // fall back to the original legal list so we never call into the
    // fallback with an empty pool.
    final fallbackLegal = fallbackPool.isEmpty ? legal : fallbackPool;

    // Filter out pass-state rows: their boards are byte-equal to the prior
    // state's board, so they teach nothing positionally and inflate the
    // candidate pool with duplicate signal at the cells the player previously
    // touched. Keep them in the log for replay/termination but exclude from
    // CBR retrieval.
    final completed =
        log
            .statesWithOutcome()
            .where((s) => !rules.isPassMove(s.movePlayed))
            .toList();
    if (completed.isEmpty) {
      return _maybePassOnEnclosed(
        _fallbackDecision(fallbackLegal, currentBoard, side),
        currentBoard,
        side,
        opponentJustPassed,
      );
    }

    final brainLegal = fallbackLegal;
    if (brainLegal.isEmpty) {
      return _maybePassOnEnclosed(
        _fallbackDecision(fallbackLegal, currentBoard, side),
        currentBoard,
        side,
        opponentJustPassed,
      );
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
      return _maybePassOnEnclosed(
        _fallbackDecision(fallbackLegal, currentBoard, side),
        currentBoard,
        side,
        opponentJustPassed,
      );
    }

    final selected = rules.moveSelectionStrategy.selectMove(
      all,
      brainLegal,
      currentBoard,
    );
    if (selected == null) {
      return _maybePassOnEnclosed(
        _fallbackDecision(fallbackLegal, currentBoard, side),
        currentBoard,
        side,
        opponentJustPassed,
      );
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
      final move = _fallbackMove(fallbackLegal, currentBoard, side);
      return _maybePassOnEnclosed(
        MoveDecision(
          move: move,
          narration: narrate(DecisionContext.allLosing),
          usedFallback: true,
          candidatesFound: totalResults,
        ),
        currentBoard,
        side,
        opponentJustPassed,
      );
    }

    return _maybePassOnEnclosed(
      MoveDecision(
        move: selected,
        narration: _buildNarration(all),
        usedFallback: false,
        candidatesFound: totalResults,
      ),
      currentBoard,
      side,
      opponentJustPassed,
    );
  }

  /// If the opponent has just passed and the chosen move would land in a
  /// region of the board enclosed only by our own stones (own territory,
  /// own eyes), pass instead. The check is deliberately narrow: it never
  /// fires unless the opponent has signalled the game is winding down, and
  /// it never converts a capturing or invading move (those moves border
  /// enemy stones). Replaces the narration to make the decision audible.
  MoveDecision _maybePassOnEnclosed(
    MoveDecision decision,
    Board board,
    int side,
    bool opponentJustPassed,
  ) {
    if (!opponentJustPassed) return decision;
    final go = rules;
    if (go is! GoRules) return decision;
    if (go.isPassMove(decision.move)) return decision;
    if (!go.isOwnEnclosedTerritory(board, decision.move, side)) return decision;
    return MoveDecision(
      move: go.passMove,
      narration: 'I have nothing left worth playing.',
      usedFallback: decision.usedFallback,
      candidatesFound: decision.candidatesFound,
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
    final maxDist = rules.maxCandidateL1Distance;
    var kept = 0;
    for (final r in results) {
      // Results are sorted ascending by distance, so once we cross the
      // ceiling every remaining candidate is too far away.
      if (r.distance > maxDist) break;
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
  /// added to the heatmap directly. The strategy currently reads only
  /// `diffusedImage`, but the mirrored `movePlayed` is computed correctly
  /// regardless so any future consumer reads a consistent value.
  GameState _mirrorStateForHeatmap(GameState s) {
    final mirroredImage = _mirrorImage(s.diffusedImage, rules.rows, rules.cols);
    // Pass moves are sentinel values outside the grid — leave untouched.
    // For grid moves, mirror the column only. The formula reduces correctly
    // for both CF (column-only encoding: `movePlayed ~/ cols == 0`) and Go
    // (row-major: `r * cols + c`).
    final mirroredMove =
        rules.isPassMove(s.movePlayed)
            ? s.movePlayed
            : (s.movePlayed ~/ rules.cols) * rules.cols +
                (rules.cols - 1 - (s.movePlayed % rules.cols));
    return GameState(
      board: s.board,
      diffusedImage: mirroredImage,
      movePlayed: mirroredMove,
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

  MoveDecision _fallbackDecision(List<int> legalMoves, Board board, int side) {
    final move = _fallbackMove(legalMoves, board, side);
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

  int _fallbackMove(List<int> legalMoves, Board board, int side) {
    switch (fallback) {
      case FallbackStrategy.random:
        // For Go this is the "Wanderer" personality: uniformly random among
        // empty cells within Manhattan-2 of any stone. The prefilter exists
        // because pure-random on 13×13 spreads stones so thin they get
        // individually claimed; concentrating play near existing stones
        // produces actual interactions. Empty board (no stones) falls
        // through to the Star-point opener. CF (no `rules is GoRules`)
        // keeps the original uniform-random behaviour over `legalMoves`.
        if (rules is GoRules) {
          return _goWandererMove(legalMoves, board);
        }
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
      case FallbackStrategy.goStarPoints:
        return _goStarPointMove(_goPlacementMoves(legalMoves), board);
      case FallbackStrategy.goDiamond:
        return _goDiamondMove(_goPlacementMoves(legalMoves), board, side);
      case FallbackStrategy.goContact:
        return _goContactMove(_goPlacementMoves(legalMoves), board, side);
      case FallbackStrategy.goGreedyArea:
        return _goGreedyAreaMove(_goPlacementMoves(legalMoves), board, side);
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
    // to mid. Iteration is ascending and we only update on a strict
    // improvement, so first-match-wins handles the lower-index tie-break.
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
      if (count > bestCount || (count == bestCount && dist < bestDist)) {
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

  /// Strip Go's `passMove` sentinel from `legal`, so the Go fallbacks score
  /// only real placements. If only pass is legal (board full / suicide-only),
  /// fall back to the original list — the chosen helper will pick passMove
  /// as the sole option without crashing.
  List<int> _goPlacementMoves(List<int> legal) {
    final placements = legal.where((m) => !rules.isPassMove(m)).toList();
    return placements.isEmpty ? legal : placements;
  }

  /// Static board-position weight for Go. Single function, used by all four
  /// Go fallbacks. Hard-coded for `size == 13`; other sizes get a
  /// degenerate-but-safe lookup (every cell scores 0, so callers fall through
  /// to their secondary tie-break — random for `goStarPoints`, the primary
  /// score for the others). 13×13 is the only shipping board.
  int _goStarPointWeight(int r, int c, int size) {
    if (size != 13) return 0;
    final hoshi = (r == 3 || r == 6 || r == 9) && (c == 3 || c == 6 || c == 9);
    if (hoshi) return 3;
    final on34 = r == 2 || r == 3 || r == 9 || r == 10;
    final oc34 = c == 2 || c == 3 || c == 9 || c == 10;
    if (on34 || oc34) return 2;
    final firstLine = r == 0 || r == 12 || c == 0 || c == 12;
    final centreCross = r == 6 || c == 6;
    if (firstLine || centreCross) return 1;
    return 0;
  }

  int _goStarPointMove(List<int> legalMoves, Board board) {
    assert(rules is GoRules, 'goStarPoints fallback requires GoRules');
    return _pickByStarPointWeight(legalMoves);
  }

  /// Wanderer: uniformly random among empty cells within Manhattan-2 of any
  /// stone. Empty board → falls through to the Star-point opener so the
  /// first move isn't a corner stone with no friends.
  int _goWandererMove(List<int> legalMoves, Board board) {
    assert(rules is GoRules, 'goWanderer fallback requires GoRules');
    final placements = _goPlacementMoves(legalMoves);
    final nearby = _goCellsNearStones(board, 2);
    final candidates = placements.where(nearby.contains).toList();
    if (candidates.isEmpty) return _pickByStarPointWeight(placements);
    return candidates[_random.nextInt(candidates.length)];
  }

  /// Diamond: prefer cells diagonally adjacent to our own stones, actively
  /// avoiding cells orthogonally adjacent to them. The resulting shape is a
  /// "ponnuki"-style diamond / rhombus around our stones — Go-correct (each
  /// stone covers 4 cells worth of influence) instead of a "dumpling" cluster.
  /// Score = (diagonal-friendly count) - (orthogonal-friendly count).
  int _goDiamondMove(List<int> legalMoves, Board board, int side) {
    assert(rules is GoRules, 'goDiamond fallback requires GoRules');
    return _pickByDiamondScore(legalMoves, board, friendlySign: side);
  }

  int _goContactMove(List<int> legalMoves, Board board, int side) {
    assert(rules is GoRules, 'goContact fallback requires GoRules');
    return _pickByOrthogonalNeighbour(legalMoves, board, neighbourSign: -side);
  }

  /// Score by 4-orthogonal-adjacent count of stones with the given sign.
  /// Tie-break pyramid: count → Star-point weight → uniform random.
  /// Empty board / no stones of the target sign: count is uniformly zero,
  /// Star-point weight dominates → opens at hoshi without a special-case.
  int _pickByOrthogonalNeighbour(
    List<int> legalMoves,
    Board board, {
    required int neighbourSign,
  }) {
    final size = rules.cols;
    final scored = <(int move, int count, int weight)>[];
    for (final move in legalMoves) {
      if (rules.isPassMove(move)) continue;
      final r = move ~/ size;
      final c = move % size;
      var count = 0;
      for (final off in _kOrthogonalOffsets) {
        final nr = r + off[0];
        final nc = c + off[1];
        if (nr < 0 || nr >= size || nc < 0 || nc >= size) continue;
        if (board.get(nr, nc) == neighbourSign) count++;
      }
      scored.add((move, count, _goStarPointWeight(r, c, size)));
    }
    return _pickFromScored(scored, legalMoves);
  }

  /// Score = diagonal-friendly count minus orthogonal-friendly count. The
  /// minus actively penalises "dumpling shape" (馬鹿形): two own stones in
  /// orthogonal adjacency are weak in Go because they cover overlapping
  /// territory. Diagonal pairs cover disjoint cells. Tie-break pyramid:
  /// score → Star-point weight → uniform random.
  int _pickByDiamondScore(
    List<int> legalMoves,
    Board board, {
    required int friendlySign,
  }) {
    final size = rules.cols;
    final scored = <(int move, int score, int weight)>[];
    for (final move in legalMoves) {
      if (rules.isPassMove(move)) continue;
      final r = move ~/ size;
      final c = move % size;
      var diag = 0;
      var orth = 0;
      for (final off in _kDiagonalOffsets) {
        final nr = r + off[0];
        final nc = c + off[1];
        if (nr < 0 || nr >= size || nc < 0 || nc >= size) continue;
        if (board.get(nr, nc) == friendlySign) diag++;
      }
      for (final off in _kOrthogonalOffsets) {
        final nr = r + off[0];
        final nc = c + off[1];
        if (nr < 0 || nr >= size || nc < 0 || nc >= size) continue;
        if (board.get(nr, nc) == friendlySign) orth++;
      }
      scored.add((move, diag - orth, _goStarPointWeight(r, c, size)));
    }
    return _pickFromScored(scored, legalMoves);
  }

  /// Shared tie-break + random-survivor pick. `scored` is `(move, score,
  /// weight)`; primary by score, secondary by weight, then uniform-random
  /// among the maxima. Empty `scored` → first legal move (degenerate; the
  /// caller is expected to hand at least one placement).
  int _pickFromScored(
    List<(int move, int score, int weight)> scored,
    List<int> legalMoves,
  ) {
    if (scored.isEmpty) return legalMoves.first;
    var bestScore = scored.first.$2;
    var bestWeight = scored.first.$3;
    for (final s in scored) {
      if (s.$2 > bestScore || (s.$2 == bestScore && s.$3 > bestWeight)) {
        bestScore = s.$2;
        bestWeight = s.$3;
      }
    }
    final survivors =
        scored
            .where((s) => s.$2 == bestScore && s.$3 == bestWeight)
            .map((s) => s.$1)
            .toList();
    return survivors[_random.nextInt(survivors.length)];
  }

  int _pickByStarPointWeight(List<int> legalMoves) {
    final size = rules.cols;
    final placements = legalMoves.where((m) => !rules.isPassMove(m)).toList();
    if (placements.isEmpty) return legalMoves.first;
    var bestWeight = -1;
    for (final move in placements) {
      final w = _goStarPointWeight(move ~/ size, move % size, size);
      if (w > bestWeight) bestWeight = w;
    }
    final survivors =
        placements
            .where(
              (m) =>
                  _goStarPointWeight(m ~/ size, m % size, size) == bestWeight,
            )
            .toList();
    return survivors[_random.nextInt(survivors.length)];
  }

  /// Empty intersections within `maxDistance` Manhattan steps of any stone.
  /// Used by Greedy (`maxDistance = 1`, ~30–50 candidates mid-game) and
  /// Wanderer (`maxDistance = 2`, broader neighbourhood for random play).
  /// Both keep per-turn cost predictable on a phone vs. evaluating every
  /// empty intersection. Acknowledged downside: neither bot founds new
  /// frameworks far from existing stones; fine for a fallback's "weak
  /// heuristic" role.
  Set<int> _goCellsNearStones(Board board, int maxDistance) {
    final size = rules.cols;
    final result = <int>{};
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        if (board.get(r, c) != 0) continue;
        if (_hasStoneWithin(board, r, c, maxDistance, size)) {
          result.add(r * size + c);
        }
      }
    }
    return result;
  }

  bool _hasStoneWithin(Board board, int r, int c, int maxDistance, int size) {
    for (var dr = -maxDistance; dr <= maxDistance; dr++) {
      for (var dc = -maxDistance; dc <= maxDistance; dc++) {
        if (dr == 0 && dc == 0) continue;
        if (dr.abs() + dc.abs() > maxDistance) continue;
        final nr = r + dr;
        final nc = c + dc;
        if (nr < 0 || nr >= size || nc < 0 || nc >= size) continue;
        if (board.get(nr, nc) != 0) return true;
      }
    }
    return false;
  }

  int _goGreedyAreaMove(List<int> legalMoves, Board board, int side) {
    assert(rules is GoRules, 'goGreedyArea fallback requires GoRules');
    final goRules = rules as GoRules;
    final neighbourhood = _goCellsNearStones(board, 1);
    final candidates =
        legalMoves
            .where((m) => !rules.isPassMove(m) && neighbourhood.contains(m))
            .toList();
    if (candidates.isEmpty) {
      // Empty board (or all stones isolated from any legal placement) — fall
      // through to the Star-point opener.
      return _pickByStarPointWeight(legalMoves);
    }
    final size = rules.cols;
    final scored = <(int move, int diff, int weight)>[];
    for (final move in candidates) {
      final trial = goRules.applyMove(board, move, side);
      final s = goRules.areaScore(trial);
      // areaScore is white-centric (white = +1, black = -1), not side-relative.
      // Flip to "own − opponent" by multiplying by `side`.
      final diff = (s.white - s.black) * side;
      scored.add((
        move,
        diff,
        _goStarPointWeight(move ~/ size, move % size, size),
      ));
    }
    var bestDiff = scored.first.$2;
    var bestWeight = scored.first.$3;
    for (final s in scored) {
      if (s.$2 > bestDiff || (s.$2 == bestDiff && s.$3 > bestWeight)) {
        bestDiff = s.$2;
        bestWeight = s.$3;
      }
    }
    final survivors =
        scored
            .where((s) => s.$2 == bestDiff && s.$3 == bestWeight)
            .map((s) => s.$1)
            .toList();
    return survivors[_random.nextInt(survivors.length)];
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
