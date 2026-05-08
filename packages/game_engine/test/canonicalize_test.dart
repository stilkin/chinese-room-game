import 'package:test/test.dart';
import 'package:game_engine/game_engine.dart';

void main() {
  late ConnectFourRules rules;

  setUp(() {
    rules = ConnectFourRules();
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

    test('double flip is the identity', () {
      final board = Board(6, 7);
      board.set(5, 3, 1);
      board.set(4, 2, -1);
      board.set(3, 5, 1);

      final twice = flipPerspective(flipPerspective(board));
      for (var r = 0; r < board.rows; r++) {
        for (var c = 0; c < board.cols; c++) {
          expect(twice.get(r, c), board.get(r, c));
        }
      }
    });
  });

  group('invertState', () {
    late CloneBrain brain;

    setUp(() {
      brain = CloneBrain(rules: rules, log: GameLog());
    });

    GameState buildState({
      required Board displayBoard,
      required int movePlayed,
      required int ply,
      String gameId = 'g',
      int? outcome,
      int? movesToEnd,
    }) {
      final s = brain.createState(
        board: displayBoard,
        movePlayed: movePlayed,
        ply: ply,
        gameId: gameId,
      );
      s.outcome = outcome;
      s.movesToEnd = movesToEnd;
      return s;
    }

    test('flips every cell value in board', () {
      var board = Board(6, 7);
      board = rules.applyMove(board, 3, 1);
      board = rules.applyMove(board, 4, -1);
      final s = buildState(displayBoard: board, movePlayed: 4, ply: 1);

      final inv = invertState(s, rules.diffusionKernel);

      for (var r = 0; r < board.rows; r++) {
        for (var c = 0; c < board.cols; c++) {
          expect(inv.board.get(r, c), -s.board.get(r, c));
        }
      }
    });

    test('flips materialBalance sign', () {
      var board = Board(6, 7);
      board = rules.applyMove(board, 3, 1);
      board = rules.applyMove(board, 3, 1);
      final s = buildState(displayBoard: board, movePlayed: 3, ply: 1);
      expect(s.materialBalance, 2);

      final inv = invertState(s, rules.diffusionKernel);
      expect(inv.materialBalance, -2);
    });

    test('preserves move metadata', () {
      var board = Board(6, 7);
      board = rules.applyMove(board, 3, 1);
      final s = buildState(
        displayBoard: board,
        movePlayed: 3,
        ply: 7,
        gameId: 'meta-test',
        outcome: 1,
        movesToEnd: 9,
      );

      final inv = invertState(s, rules.diffusionKernel);
      expect(inv.movePlayed, 3);
      expect(inv.ply, 7);
      expect(inv.gameId, 'meta-test');
      expect(inv.outcome, 1);
      expect(inv.movesToEnd, 9);
      expect(inv.totalMaterial, s.totalMaterial);
    });

    test('diffused hash matches a fresh recompute on the inverted board', () {
      var board = Board(6, 7);
      board = rules.applyMove(board, 1, 1);
      board = rules.applyMove(board, 5, -1);
      final s = buildState(displayBoard: board, movePlayed: 5, ply: 1);

      final inv = invertState(s, rules.diffusionKernel);
      final fresh = influenceMapToBitHash(
        rules.diffusionKernel.diffuse(inv.board),
      );
      expect(inv.diffusedHash, fresh);
    });

    test('double inversion is the identity', () {
      var board = Board(6, 7);
      board = rules.applyMove(board, 3, 1);
      board = rules.applyMove(board, 3, -1);
      board = rules.applyMove(board, 4, 1);

      final s = buildState(
        displayBoard: board,
        movePlayed: 4,
        ply: 2,
        outcome: 1,
        movesToEnd: 3,
      );

      final once = invertState(s, rules.diffusionKernel);
      final twice = invertState(once, rules.diffusionKernel);

      for (var r = 0; r < board.rows; r++) {
        for (var c = 0; c < board.cols; c++) {
          expect(twice.board.get(r, c), s.board.get(r, c));
        }
      }
      expect(twice.diffusedHash, s.diffusedHash);
      expect(twice.materialBalance, s.materialBalance);
    });
  });
}
