import 'package:test/test.dart';
import 'package:game_engine/game_engine.dart';

void main() {
  group('Board', () {
    test('creates empty board with correct dimensions', () {
      final board = Board(6, 7);
      expect(board.rows, 6);
      expect(board.cols, 7);
      for (var r = 0; r < 6; r++) {
        for (var c = 0; c < 7; c++) {
          expect(board.get(r, c), 0);
        }
      }
    });

    test('Board.from deep-copies source', () {
      final source = [
        [1, 0, -1],
        [0, 1, 0],
      ];
      final board = Board.from(source);
      source[0][0] = 99;
      expect(board.get(0, 0), 1);
    });

    test('flat view is row-major', () {
      final board = Board.from([
        [1, 2],
        [3, 4],
      ]);
      expect(board.flat, [1, 2, 3, 4]);
    });

    test('flat view round-trips through Board.from', () {
      final original = Board.from([
        [1, 0, -1],
        [-1, 1, 0],
      ]);
      final flat = original.flat;
      final rebuilt = Board(original.rows, original.cols);
      for (var i = 0; i < flat.length; i++) {
        rebuilt.set(i ~/ original.cols, i % original.cols, flat[i]);
      }
      expect(rebuilt, original);
    });

    test('copy is independent', () {
      final board = Board(3, 3);
      board.set(1, 1, 5);
      final copy = board.copy();
      copy.set(1, 1, 99);
      expect(board.get(1, 1), 5);
    });

    test('equality works for identical boards', () {
      final a = Board.from([
        [1, -1],
        [0, 1],
      ]);
      final b = Board.from([
        [1, -1],
        [0, 1],
      ]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('equality fails for different boards', () {
      final a = Board.from([
        [1, 0],
      ]);
      final b = Board.from([
        [0, 1],
      ]);
      expect(a, isNot(b));
    });
  });

  group('GameLog', () {
    test('backfillGame sets outcome and movesToEnd', () {
      final log = GameLog();
      log.addState(GameState(
        board: Board(6, 7),
        zobristHash: 0,
        diffusedHash: [0],
        movePlayed: 0,
        side: 1,
        gameId: 'g1',
        totalMaterial: 0,
        materialBalance: 0,
      ));
      log.addState(GameState(
        board: Board(6, 7),
        zobristHash: 0,
        diffusedHash: [0],
        movePlayed: 1,
        side: -1,
        gameId: 'g1',
        totalMaterial: 0,
        materialBalance: 0,
      ));

      log.backfillGame('g1', 1, 2);

      expect(log.states[0].outcome, 1);
      expect(log.states[0].movesToEnd, 2);
      expect(log.states[1].outcome, -1);
      expect(log.states[1].movesToEnd, 1);
    });

    test('statesWithOutcome excludes unfinished games', () {
      final log = GameLog();
      log.addState(GameState(
        board: Board(6, 7),
        zobristHash: 0,
        diffusedHash: [0],
        movePlayed: 0,
        side: 1,
        gameId: 'g1',
        totalMaterial: 0,
        materialBalance: 0,
        outcome: 1,
        movesToEnd: 3,
      ));
      log.addState(GameState(
        board: Board(6, 7),
        zobristHash: 0,
        diffusedHash: [0],
        movePlayed: 0,
        side: 1,
        gameId: 'g2',
        totalMaterial: 0,
        materialBalance: 0,
      ));

      expect(log.statesWithOutcome(), hasLength(1));
    });
  });
}
