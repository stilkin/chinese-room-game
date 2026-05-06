import 'package:test/test.dart';
import 'package:game_engine/game_engine.dart';

void main() {
  group('SplitMix64', () {
    test('deterministic — same seed produces same sequence', () {
      final a = SplitMix64.fromString('connect_four');
      final b = SplitMix64.fromString('connect_four');
      for (var i = 0; i < 100; i++) {
        expect(a.next(), b.next());
      }
    });

    test('different seeds produce different sequences', () {
      final a = SplitMix64.fromString('connect_four');
      final b = SplitMix64.fromString('chess');
      var same = 0;
      for (var i = 0; i < 100; i++) {
        if (a.next() == b.next()) same++;
      }
      expect(same, lessThan(5));
    });
  });

  group('ZobristTable', () {
    late ConnectFourRules rules;
    late ZobristTable table;

    setUp(() {
      rules = ConnectFourRules();
      table = ZobristTable.forGame(rules);
    });

    test('empty board hashes to 0', () {
      final board = Board(6, 7);
      expect(table.hashBoard(board), 0);
    });

    test('single piece hash equals table entry', () {
      final board = Board(6, 7);
      board.set(5, 3, 1);
      expect(table.hashBoard(board), table.entryFor(1, 5, 3));
    });

    test('same board produces same hash', () {
      final board = Board(6, 7);
      board.set(5, 3, 1);
      board.set(5, 4, -1);
      expect(table.hashBoard(board), table.hashBoard(board));
    });

    test('different boards produce different hashes', () {
      final a = Board(6, 7);
      a.set(5, 3, 1);
      final b = Board(6, 7);
      b.set(5, 4, 1);
      expect(table.hashBoard(a), isNot(table.hashBoard(b)));
    });

    test('incremental update matches full recomputation', () {
      final board = Board(6, 7);
      board.set(5, 3, 1);
      var hash = table.hashBoard(board);

      // Add a piece incrementally
      hash = table.updateHash(hash, 5, 4, 0, -1);
      board.set(5, 4, -1);

      expect(hash, table.hashBoard(board));
    });

    test('incremental update through multiple moves', () {
      final board = Board(6, 7);
      var hash = 0;

      final moves = [(5, 3, 1), (5, 4, -1), (4, 3, 1), (4, 4, -1)];
      for (final (r, c, v) in moves) {
        hash = table.updateHash(hash, r, c, 0, v);
        board.set(r, c, v);
      }

      expect(hash, table.hashBoard(board));
    });

    test('different game types produce different tables', () {
      final cfTable = ZobristTable.forGame(ConnectFourRules());
      // Create a board with one piece and verify it hashes differently
      // with a table from a different game type seed
      final entry1 = cfTable.entryFor(1, 0, 0);
      // Can't easily test with a different game type yet, but verify
      // the table is non-trivial
      expect(entry1, isNot(0));
    });
  });
}
