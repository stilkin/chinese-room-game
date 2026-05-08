import 'dart:math';

import 'board.dart';
import 'canonicalize.dart';
import 'diffusion.dart';
import 'game_rules.dart';
import 'game_state.dart';
import 'move_selection.dart';
import 'narration.dart';
import 'similarity.dart';

enum FallbackStrategy { random, middleFocus, edgeFocus, pileFocus }

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
      diffusedHash: influenceMapToBitHash(influence),
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

    // Query A: assume bot is the eventual winner. Bot's pieces become +1
    // in the query, matching bot-won games' winner-POV stored canonicals.
    // outcome=+1 rows there = bot played this move and won.
    final aResults = _searchOnce(flipPerspective(currentBoard), completed);

    // Query B: assume bot is the eventual loser. Bot's pieces stay -1 in the
    // query, matching player-won games' winner-POV stored canonicals.
    // outcome=-1 rows there = bot played this move and lost.
    final bResults = _searchOnce(currentBoard, completed);

    final weighted = <WeightedCandidate>[];
    for (final r in aResults) {
      if (r.state.outcome != 1) continue;
      final w = _weightFor(r, sign: 1);
      if (w != 0) weighted.add(WeightedCandidate(r.state, w));
    }
    for (final r in bResults) {
      if (r.state.outcome != -1) continue;
      final w = _weightFor(r, sign: -1);
      if (w != 0) weighted.add(WeightedCandidate(r.state, w));
    }

    if (weighted.isEmpty) {
      return _fallbackDecision(legal, currentBoard);
    }

    final selectedMove = rules.moveSelectionStrategy.selectMove(
      weighted,
      legal,
      currentBoard,
    );

    if (selectedMove == null) {
      return _fallbackDecision(legal, currentBoard);
    }

    // Sum the net weight on the selected column. If <= 0, the data points
    // to a losing-flavoured choice — let the fallback strategy pick instead.
    var netWeight = 0.0;
    for (final c in weighted) {
      if (c.state.movePlayed == selectedMove) netWeight += c.weight;
    }
    if (netWeight <= 0) {
      final move = _fallbackMove(legal, currentBoard);
      return MoveDecision(
        move: move,
        narration: narrate(DecisionContext.allLosing),
        usedFallback: false,
        candidatesFound: aResults.length + bResults.length,
      );
    }

    return MoveDecision(
      move: selectedMove,
      narration: _buildNarration(weighted),
      usedFallback: false,
      candidatesFound: aResults.length + bResults.length,
    );
  }

  List<SimilarityResult> _searchOnce(Board query, List<GameState> candidates) {
    final influence = rules.diffusionKernel.diffuse(query);
    return searchSimilar(
      queryDiffusedHash: influenceMapToBitHash(influence),
      queryTotalMaterial: computeTotalMaterial(query),
      queryMaterialBalance: computeMaterialBalance(query),
      candidates: candidates,
    );
  }

  double _weightFor(SimilarityResult r, {required int sign}) {
    final movesToEnd = r.state.movesToEnd;
    if (movesToEnd == null) return 0;
    final efficiency = 1.0 / (1.0 + movesToEnd);
    final similarity = 1.0 / (1.0 + r.distance);
    return sign * efficiency * similarity;
  }

  String _buildNarration(List<WeightedCandidate> weighted) {
    final positives = weighted.where((c) => c.weight > 0).toList();
    if (positives.length > 1) {
      return narrate(
        DecisionContext.multipleCandidates,
        candidateCount: positives.length,
      );
    }
    if (positives.length == 1) {
      return narrate(
        DecisionContext.fuzzyMatch,
        gameId: positives.first.state.gameId,
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
