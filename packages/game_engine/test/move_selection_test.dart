import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:game_engine/game_engine.dart';

GameState _makeState({
  required Int8List diffusedImage,
  int movePlayed = 0,
  int rows = 6,
  int cols = 7,
}) {
  return GameState(
    board: Board(rows, cols),
    diffusedImage: diffusedImage,
    movePlayed: movePlayed,
    ply: 0,
    gameId: 'g1',
    totalMaterial: 0,
    materialBalance: 0,
  );
}

void main() {
  group('InfluenceOverlayStrategy', () {
    test('null on empty candidates', () {
      const strategy = InfluenceOverlayStrategy(ConnectFourMoveScorer());
      expect(strategy.selectMove(const [], const [0, 1, 2], Board(6, 7)), null);
    });

    test('null on empty legal moves', () {
      const strategy = InfluenceOverlayStrategy(ConnectFourMoveScorer());
      final candidates = [
        WeightedCandidate(_makeState(diffusedImage: Int8List(42)), 1.0),
      ];
      expect(strategy.selectMove(candidates, const [], Board(6, 7)), null);
    });

    test('positive heatmap concentrated on column 3 picks column 3', () {
      // Build an image that's all-zero except for column 3, top-to-bottom
      // strongly positive. After the bot drops a piece, the landing cell at
      // (5,3) should have the highest heatmap value.
      final image = Int8List(42);
      for (var r = 0; r < 6; r++) {
        image[r * 7 + 3] = 10;
      }
      final candidates = [
        WeightedCandidate(_makeState(diffusedImage: image), 1.0),
      ];
      const strategy = InfluenceOverlayStrategy(ConnectFourMoveScorer());
      expect(
        strategy.selectMove(candidates, const [
          0,
          1,
          2,
          3,
          4,
          5,
          6,
        ], Board(6, 7)),
        3,
      );
    });

    test('negative candidate subtracts from a region', () {
      // Two candidates: column 3 strongly positive, column 4 subtly more so
      // due to the negative pulling down the col-3 score.
      final pos = Int8List(42);
      for (var r = 0; r < 6; r++) {
        pos[r * 7 + 3] = 5;
        pos[r * 7 + 4] = 1;
      }
      final neg = Int8List(42);
      for (var r = 0; r < 6; r++) {
        neg[r * 7 + 3] = 10; // negative weight will subtract this from col 3
      }
      final candidates = [
        WeightedCandidate(_makeState(diffusedImage: pos), 1.0),
        WeightedCandidate(_makeState(diffusedImage: neg), -1.0),
      ];
      // Col 3 net: +5 - 10 = -5. Col 4 net: +1. Col 4 wins.
      const strategy = InfluenceOverlayStrategy(ConnectFourMoveScorer());
      expect(strategy.selectMove(candidates, const [3, 4], Board(6, 7)), 4);
    });

    test('zero-weight candidates contribute nothing', () {
      final image = Int8List(42);
      for (var r = 0; r < 6; r++) {
        image[r * 7 + 3] = 100;
      }
      final candidates = [
        WeightedCandidate(_makeState(diffusedImage: image), 0.0),
      ];
      const strategy = InfluenceOverlayStrategy(ConnectFourMoveScorer());
      // Heatmap all-zero ⇒ all legal columns score 0 ⇒ first one (column 0).
      expect(
        strategy.selectMove(candidates, const [
          0,
          1,
          2,
          3,
          4,
          5,
          6,
        ], Board(6, 7)),
        0,
      );
    });
  });

  group('InfluenceOverlayStrategy.buildHeatmap', () {
    test('accumulates weighted images cell-by-cell', () {
      final a = Int8List.fromList(List.generate(42, (i) => i % 7));
      final b = Int8List.fromList(List.generate(42, (i) => -(i % 7)));
      final candidates = [
        WeightedCandidate(_makeState(diffusedImage: a), 2.0),
        WeightedCandidate(_makeState(diffusedImage: b), 1.0),
      ];
      final heatmap = InfluenceOverlayStrategy.buildHeatmap(candidates, 6, 7);
      // Row 0, col 0: a=0, b=0 → 0. Row 0, col 1: a=1, b=-1 → 2*1 + 1*-1 = 1.
      expect(heatmap[0][1], 1.0);
      // Row 0, col 6: a=6, b=-6 → 12 - 6 = 6.
      expect(heatmap[0][6], 6.0);
    });
  });
}
