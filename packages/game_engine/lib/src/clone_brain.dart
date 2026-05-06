import 'dart:math';

import 'board.dart';
import 'canonicalize.dart';
import 'diffusion.dart';
import 'game_rules.dart';
import 'game_state.dart';
import 'move_selection.dart';
import 'narration.dart';
import 'similarity.dart';
import 'zobrist.dart';

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
  final ZobristTable _zobristTable;
  final Random _random;

  CloneBrain({
    required this.rules,
    required this.log,
    this.fallback = FallbackStrategy.random,
    Random? random,
  })  : _zobristTable = ZobristTable.forGame(rules),
        _random = random ?? Random();

  ZobristTable get zobristTable => _zobristTable;

  GameState createState({
    required Board board,
    required int movePlayed,
    required int side,
    required String gameId,
  }) {
    final canonical = canonicalize(board, side, _zobristTable);
    final influence = rules.diffusionKernel.diffuse(canonical.board);
    final diffusedHash = influenceMapToBitHash(influence);
    return GameState(
      board: canonical.board,
      zobristHash: canonical.zobristHash,
      diffusedHash: diffusedHash,
      movePlayed: movePlayed,
      side: side,
      gameId: gameId,
      totalMaterial: computeTotalMaterial(canonical.board),
      materialBalance: computeMaterialBalance(canonical.board),
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

    final canonical = canonicalize(currentBoard, side, _zobristTable);
    final influence = rules.diffusionKernel.diffuse(canonical.board);
    final diffusedHash = influenceMapToBitHash(influence);
    final totalMat = computeTotalMaterial(canonical.board);
    final matBal = computeMaterialBalance(canonical.board);

    final completed = log.statesWithOutcome();
    if (completed.isEmpty) {
      return _fallbackDecision(legal, currentBoard);
    }

    final results = searchSimilar(
      queryZobristHash: canonical.zobristHash,
      queryDiffusedHash: diffusedHash,
      queryTotalMaterial: totalMat,
      queryMaterialBalance: matBal,
      candidates: completed,
    );

    if (results.isEmpty) {
      return _fallbackDecision(legal, currentBoard);
    }

    final weighted = <WeightedCandidate>[];
    for (final result in results) {
      final w = _weightCandidate(result.state);
      if (w > 0) {
        weighted.add(WeightedCandidate(result.state, w));
      }
    }

    if (weighted.isEmpty) {
      final move = _fallbackMove(legal, currentBoard);
      return MoveDecision(
        move: move,
        narration: narrate(DecisionContext.allLosing),
        usedFallback: false,
        candidatesFound: results.length,
      );
    }

    final selectedMove = rules.moveSelectionStrategy.selectMove(
      weighted,
      legal,
      currentBoard,
    );

    if (selectedMove == null) {
      return _fallbackDecision(legal, currentBoard);
    }

    final narrationText = _buildNarration(results, weighted);

    return MoveDecision(
      move: selectedMove,
      narration: narrationText,
      usedFallback: false,
      candidatesFound: results.length,
    );
  }

  double _weightCandidate(GameState state) {
    final outcome = state.outcome;
    final movesToEnd = state.movesToEnd;
    if (outcome == null || movesToEnd == null) return 0;

    final outcomeScore = switch (outcome) {
      1 => 1.0,
      0 => 0.5,
      _ => 0.0,
    };
    final efficiency = 1.0 / (1.0 + movesToEnd);
    return outcomeScore * efficiency;
  }

  String _buildNarration(
    List<SimilarityResult> results,
    List<WeightedCandidate> weighted,
  ) {
    if (results.length == 1 && results.first.isExactMatch) {
      final s = results.first.state;
      return narrate(
        DecisionContext.exactMatch,
        gameId: s.gameId,
        movesToEnd: s.movesToEnd,
      );
    }
    if (weighted.length > 1) {
      return narrate(
        DecisionContext.multipleCandidates,
        candidateCount: weighted.length,
      );
    }
    return narrate(
      DecisionContext.fuzzyMatch,
      gameId: weighted.first.state.gameId,
    );
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
