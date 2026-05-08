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

/// Game-specific scoring of a candidate move against an aggregated heatmap.
/// Connect Four looks up the gravity-aware landing cell; chess will read both
/// from-square and to-square; etc.
abstract class MoveScorer {
  double scoreMove(int move, Board currentBoard, List<List<double>> heatmap);
}

/// Accumulates each candidate's quantized diffused image into a single signed
/// heatmap, weighted by the candidate's signed weight, then asks a per-game
/// [MoveScorer] to score every legal move against the heatmap. Highest score
/// wins.
///
/// This is the project's primary move-selection strategy. Per-column voting
/// (the previous default) collapsed spatial information; the heatmap preserves
/// it. See `openspec/specs/move-selection/spec.md`.
class InfluenceOverlayStrategy implements MoveSelectionStrategy {
  final MoveScorer scorer;
  const InfluenceOverlayStrategy(this.scorer);

  @override
  int? selectMove(
    List<WeightedCandidate> candidates,
    List<int> legalMoves,
    Board currentBoard,
  ) {
    if (candidates.isEmpty || legalMoves.isEmpty) return null;

    final heatmap = _accumulate(
      candidates,
      currentBoard.rows,
      currentBoard.cols,
    );

    int? bestMove;
    var bestScore = -double.infinity;
    for (final move in legalMoves) {
      final score = scorer.scoreMove(move, currentBoard, heatmap);
      if (score > bestScore) {
        bestScore = score;
        bestMove = move;
      }
    }
    return bestMove;
  }

  /// Public for the brain's all-losing guard: rebuild the same heatmap and
  /// look up the chosen move's score so the brain can decide whether to
  /// fall back. Cheap (microseconds for Connect Four).
  static List<List<double>> buildHeatmap(
    List<WeightedCandidate> candidates,
    int rows,
    int cols,
  ) => _accumulate(candidates, rows, cols);

  static List<List<double>> _accumulate(
    List<WeightedCandidate> candidates,
    int rows,
    int cols,
  ) {
    final heatmap = List.generate(rows, (_) => List<double>.filled(cols, 0));
    for (final c in candidates) {
      if (c.weight == 0) continue;
      final image = c.state.diffusedImage;
      for (var r = 0; r < rows; r++) {
        final rowOffset = r * cols;
        final row = heatmap[r];
        for (var col = 0; col < cols; col++) {
          row[col] += c.weight * image[rowOffset + col];
        }
      }
    }
    return heatmap;
  }
}
