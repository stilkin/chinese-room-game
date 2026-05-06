import 'package:test/test.dart';
import 'package:game_engine/game_engine.dart';

void main() {
  late ConnectFourRules rules;

  setUp(() {
    rules = ConnectFourRules();
  });

  group('ConnectFourRules', () {
    test('board dimensions are 6x7', () {
      expect(rules.rows, 6);
      expect(rules.cols, 7);
    });

    test('empty board has 7 legal moves', () {
      final board = Board(6, 7);
      expect(rules.legalMoves(board), [0, 1, 2, 3, 4, 5, 6]);
    });

    test('full column is excluded from legal moves', () {
      final board = Board(6, 7);
      for (var r = 0; r < 6; r++) {
        board.set(r, 3, 1);
      }
      final moves = rules.legalMoves(board);
      expect(moves, isNot(contains(3)));
      expect(moves, hasLength(6));
    });

    test('drop lands at bottom of empty column', () {
      final board = Board(6, 7);
      final result = rules.applyMove(board, 3, 1);
      expect(result.get(5, 3), 1);
      for (var r = 0; r < 5; r++) {
        expect(result.get(r, 3), 0);
      }
    });

    test('drop stacks on existing pieces', () {
      var board = Board(6, 7);
      board = rules.applyMove(board, 3, 1);
      board = rules.applyMove(board, 3, -1);
      expect(board.get(5, 3), 1);
      expect(board.get(4, 3), -1);
    });

    test('drop into full column throws', () {
      final board = Board(6, 7);
      for (var r = 0; r < 6; r++) {
        board.set(r, 0, 1);
      }
      expect(() => rules.applyMove(board, 0, -1), throwsArgumentError);
    });

    test('does not mutate original board', () {
      final board = Board(6, 7);
      rules.applyMove(board, 3, 1);
      expect(board.get(5, 3), 0);
    });

    test('horizontal win detected', () {
      final board = Board(6, 7);
      for (var c = 0; c < 4; c++) {
        board.set(5, c, 1);
      }
      expect(rules.checkWinner(board), 1);
    });

    test('vertical win detected', () {
      final board = Board(6, 7);
      for (var r = 2; r < 6; r++) {
        board.set(r, 0, -1);
      }
      expect(rules.checkWinner(board), -1);
    });

    test('diagonal down-right win detected', () {
      final board = Board(6, 7);
      board.set(2, 1, 1);
      board.set(3, 2, 1);
      board.set(4, 3, 1);
      board.set(5, 4, 1);
      expect(rules.checkWinner(board), 1);
    });

    test('diagonal down-left win detected', () {
      final board = Board(6, 7);
      board.set(2, 5, -1);
      board.set(3, 4, -1);
      board.set(4, 3, -1);
      board.set(5, 2, -1);
      expect(rules.checkWinner(board), -1);
    });

    test('three in a row is not a win', () {
      final board = Board(6, 7);
      board.set(5, 0, 1);
      board.set(5, 1, 1);
      board.set(5, 2, 1);
      expect(rules.checkWinner(board), null);
    });

    test('full board with no winner is draw', () {
      // Build a full board with no four-in-a-row
      final board = Board.from([
        [1, -1, 1, -1, 1, -1, 1],
        [1, -1, 1, -1, 1, -1, 1],
        [-1, 1, -1, 1, -1, 1, -1],
        [1, -1, 1, -1, 1, -1, 1],
        [1, -1, 1, -1, 1, -1, 1],
        [-1, 1, -1, 1, -1, 1, -1],
      ]);
      expect(rules.checkWinner(board), 0);
    });

    test('ongoing game returns null', () {
      final board = Board(6, 7);
      board.set(5, 3, 1);
      expect(rules.checkWinner(board), null);
    });
  });
}
