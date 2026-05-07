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

  group('invertState', () {
    late CloneBrain brain;

    GameState buildState({
      required Board displayBoard,
      required int movePlayed,
      required int ply,
      required int side,
      String gameId = 'g',
      int? outcome,
      int? movesToEnd,
    }) {
      final s = brain.createState(
        board: displayBoard,
        movePlayed: movePlayed,
        ply: ply,
        side: side,
        gameId: gameId,
      );
      s.outcome = outcome;
      s.movesToEnd = movesToEnd;
      return s;
    }

    setUp(() {
      brain = CloneBrain(rules: rules, log: GameLog());
    });

    test('flips side from +1 to -1 and back', () {
      var board = Board(6, 7);
      board = rules.applyMove(board, 3, 1);
      final s = buildState(
        displayBoard: board,
        movePlayed: 3,
        ply: 0,
        side: 1,
        outcome: 1,
        movesToEnd: 4,
      );

      final inverted = invertState(
        s,
        brain.zobristTable,
        rules.diffusionKernel,
      );
      expect(inverted.side, -1);

      final twice = invertState(
        inverted,
        brain.zobristTable,
        rules.diffusionKernel,
      );
      expect(twice.side, 1);
    });

    test('flips materialBalance sign', () {
      var board = Board(6, 7);
      board = rules.applyMove(board, 3, 1);
      board = rules.applyMove(board, 3, 1);
      final s = buildState(displayBoard: board, movePlayed: 3, ply: 1, side: 1);
      expect(s.materialBalance, 2);

      final inverted = invertState(
        s,
        brain.zobristTable,
        rules.diffusionKernel,
      );
      expect(inverted.materialBalance, -2);
    });

    test('preserves move metadata', () {
      var board = Board(6, 7);
      board = rules.applyMove(board, 3, 1);
      final s = buildState(
        displayBoard: board,
        movePlayed: 3,
        ply: 7,
        side: 1,
        gameId: 'meta-test',
        outcome: 1,
        movesToEnd: 9,
      );

      final inv = invertState(s, brain.zobristTable, rules.diffusionKernel);
      expect(inv.movePlayed, 3);
      expect(inv.ply, 7);
      expect(inv.gameId, 'meta-test');
      expect(inv.outcome, 1);
      expect(inv.movesToEnd, 9);
      expect(inv.totalMaterial, s.totalMaterial);
    });

    test('zobrist hash matches canonicalize from opposite POV', () {
      var displayBoard = Board(6, 7);
      displayBoard = rules.applyMove(displayBoard, 3, 1);
      displayBoard = rules.applyMove(displayBoard, 4, -1);
      displayBoard = rules.applyMove(displayBoard, 2, 1);

      final s = buildState(
        displayBoard: displayBoard,
        movePlayed: 2,
        ply: 2,
        side: 1,
      );

      final inv = invertState(s, brain.zobristTable, rules.diffusionKernel);
      final fromOpposite = canonicalize(displayBoard, -1, brain.zobristTable);
      expect(inv.zobristHash, fromOpposite.zobristHash);
      expect(inv.board, fromOpposite.board);
    });

    test('diffused hash matches a fresh recompute on the inverted board', () {
      var board = Board(6, 7);
      board = rules.applyMove(board, 1, 1);
      board = rules.applyMove(board, 5, -1);
      final s = buildState(
        displayBoard: board,
        movePlayed: 5,
        ply: 1,
        side: -1,
      );

      final inv = invertState(s, brain.zobristTable, rules.diffusionKernel);
      final fresh = influenceMapToBitHash(
        rules.diffusionKernel.diffuse(inv.board),
      );
      expect(inv.diffusedHash, fresh);
    });

    test('double inversion is the identity on canonical input', () {
      var board = Board(6, 7);
      board = rules.applyMove(board, 3, 1);
      board = rules.applyMove(board, 3, -1);
      board = rules.applyMove(board, 4, 1);

      final s = buildState(
        displayBoard: board,
        movePlayed: 4,
        ply: 2,
        side: 1,
        outcome: 1,
        movesToEnd: 3,
      );

      final once = invertState(s, brain.zobristTable, rules.diffusionKernel);
      final twice = invertState(
        once,
        brain.zobristTable,
        rules.diffusionKernel,
      );

      expect(twice.board, s.board);
      expect(twice.zobristHash, s.zobristHash);
      expect(twice.diffusedHash, s.diffusedHash);
      expect(twice.side, s.side);
      expect(twice.materialBalance, s.materialBalance);
    });
  });
}
