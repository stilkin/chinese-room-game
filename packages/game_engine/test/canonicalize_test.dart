import 'package:test/test.dart';
import 'package:game_engine/game_engine.dart';

void main() {
  late ConnectFourRules rules;
  late ZobristTable table;

  setUp(() {
    rules = ConnectFourRules();
    table = ZobristTable.forGame(rules);
  });

  group('mirror', () {
    test('mirrors columns left-to-right', () {
      final board = Board(6, 7);
      board.set(5, 0, 1);
      board.set(5, 6, -1);

      final mirrored = mirror(board);
      expect(mirrored.get(5, 6), 1);
      expect(mirrored.get(5, 0), -1);
    });
  });

  group('flipPerspective', () {
    test('negates all cell values', () {
      final board = Board(6, 7);
      board.set(5, 3, 1);
      board.set(4, 3, -1);

      final flipped = flipPerspective(board);
      expect(flipped.get(5, 3), -1);
      expect(flipped.get(4, 3), 1);
      expect(flipped.get(0, 0), 0);
    });
  });

  group('canonicalize', () {
    test('mirror-image boards produce same canonical form', () {
      final a = Board(6, 7);
      a.set(5, 1, 1);

      final b = Board(6, 7);
      b.set(5, 5, 1);

      final ca = canonicalize(a, 1, table);
      final cb = canonicalize(b, 1, table);
      expect(ca.zobristHash, cb.zobristHash);
      expect(ca.board, cb.board);
    });

    test('perspective flip when side is -1', () {
      final board = Board(6, 7);
      board.set(5, 3, 1);
      board.set(4, 3, -1);

      final result = canonicalize(board, -1, table);
      // After perspective flip, side -1's pieces become positive
      expect(result.wasPerspectiveFlipped, true);
    });

    test('no perspective flip when side is 1', () {
      final board = Board(6, 7);
      board.set(5, 3, 1);

      final result = canonicalize(board, 1, table);
      expect(result.wasPerspectiveFlipped, false);
    });

    test('canonical form is idempotent', () {
      final board = Board(6, 7);
      board.set(5, 3, 1);
      board.set(4, 2, -1);

      final first = canonicalize(board, 1, table);
      final second = canonicalize(first.board, 1, table);
      expect(first.zobristHash, second.zobristHash);
      expect(first.board, second.board);
    });

    test('truly symmetric board has stable canonical form', () {
      // Place pieces symmetrically around center
      final board = Board(6, 7);
      board.set(5, 1, 1);
      board.set(5, 5, 1);
      board.set(5, 2, -1);
      board.set(5, 4, -1);

      final result = canonicalize(board, 1, table);
      // Re-canonicalizing should be idempotent
      final again = canonicalize(result.board, 1, table);
      expect(result.board, again.board);
      expect(result.zobristHash, again.zobristHash);
    });
  });
}
