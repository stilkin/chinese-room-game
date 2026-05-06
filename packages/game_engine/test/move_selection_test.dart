import 'package:test/test.dart';
import 'package:game_engine/game_engine.dart';

GameState _makeState({int movePlayed = 0}) {
  return GameState(
    board: Board(6, 7),
    zobristHash: 0,
    diffusedHash: [0],
    movePlayed: movePlayed,
    ply: 0,
    side: 1,
    gameId: 'g1',
    totalMaterial: 0,
    materialBalance: 0,
  );
}

void main() {
  late VoteByMoveStrategy strategy;

  setUp(() {
    strategy = VoteByMoveStrategy();
  });

  group('VoteByMoveStrategy', () {
    test('single candidate returns its move', () {
      final candidates = [
        WeightedCandidate(_makeState(movePlayed: 3), 1.0),
      ];
      expect(strategy.selectMove(candidates, [0, 1, 2, 3, 4, 5, 6], Board(6, 7)), 3);
    });

    test('aggregates weights per move', () {
      final candidates = [
        WeightedCandidate(_makeState(movePlayed: 3), 0.5),
        WeightedCandidate(_makeState(movePlayed: 3), 0.5),
        WeightedCandidate(_makeState(movePlayed: 4), 0.8),
      ];
      // Column 3 has aggregate 1.0, column 4 has 0.8
      expect(strategy.selectMove(candidates, [3, 4], Board(6, 7)), 3);
    });

    test('tie-breaking uses best individual weight', () {
      final candidates = [
        WeightedCandidate(_makeState(movePlayed: 3), 0.5),
        WeightedCandidate(_makeState(movePlayed: 3), 0.5),
        WeightedCandidate(_makeState(movePlayed: 4), 0.4),
        WeightedCandidate(_makeState(movePlayed: 4), 0.6),
      ];
      // Both aggregate to 1.0, but col 4's best individual is 0.6 > col 3's 0.5
      expect(strategy.selectMove(candidates, [3, 4], Board(6, 7)), 4);
    });

    test('filters out illegal moves', () {
      final candidates = [
        WeightedCandidate(_makeState(movePlayed: 3), 1.0),
        WeightedCandidate(_makeState(movePlayed: 5), 0.5),
      ];
      // Column 3 is not in legal moves
      expect(strategy.selectMove(candidates, [5, 6], Board(6, 7)), 5);
    });

    test('returns null when no candidates', () {
      expect(strategy.selectMove([], [0, 1, 2], Board(6, 7)), null);
    });

    test('returns null when no legal moves', () {
      final candidates = [
        WeightedCandidate(_makeState(movePlayed: 3), 1.0),
      ];
      expect(strategy.selectMove(candidates, [], Board(6, 7)), null);
    });

    test('returns null when no candidate move is legal', () {
      final candidates = [
        WeightedCandidate(_makeState(movePlayed: 3), 1.0),
      ];
      expect(strategy.selectMove(candidates, [0, 1], Board(6, 7)), null);
    });
  });
}
