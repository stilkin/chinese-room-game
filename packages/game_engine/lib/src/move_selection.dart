import 'board.dart';
import 'game_state.dart';

class WeightedCandidate {
  final GameState state;
  final double weight;

  WeightedCandidate(this.state, this.weight);
}

abstract class MoveSelectionStrategy {
  int? selectMove(
    List<WeightedCandidate> candidates,
    List<int> legalMoves,
    Board currentBoard,
  );
}

class VoteByMoveStrategy implements MoveSelectionStrategy {
  @override
  int? selectMove(
    List<WeightedCandidate> candidates,
    List<int> legalMoves,
    Board currentBoard,
  ) {
    if (candidates.isEmpty || legalMoves.isEmpty) return null;

    final legalSet = legalMoves.toSet();
    final weightPerMove = <int, double>{};
    final bestIndividual = <int, double>{};

    for (final candidate in candidates) {
      final move = candidate.state.movePlayed;
      if (!legalSet.contains(move)) continue;
      weightPerMove[move] = (weightPerMove[move] ?? 0) + candidate.weight;
      final current = bestIndividual[move] ?? 0;
      if (candidate.weight > current) {
        bestIndividual[move] = candidate.weight;
      }
    }

    if (weightPerMove.isEmpty) return null;

    int? bestMove;
    double bestWeight = -1;
    double bestTieBreak = -1;

    for (final entry in weightPerMove.entries) {
      final move = entry.key;
      final weight = entry.value;
      final tieBreak = bestIndividual[move] ?? 0;
      if (weight > bestWeight ||
          (weight == bestWeight && tieBreak > bestTieBreak)) {
        bestMove = move;
        bestWeight = weight;
        bestTieBreak = tieBreak;
      }
    }
    return bestMove;
  }
}

abstract class InfluenceOverlayStrategy implements MoveSelectionStrategy {
  // Future: average candidate diffusion maps weighted by outcome,
  // score legal moves by target map lookup.
}
