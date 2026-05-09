import 'dart:typed_data';

import 'package:game_engine/game_engine.dart';
import 'package:test/test.dart';

void main() {
  group('GoRules', () {
    final rules = GoRules();

    test('default size is 13', () {
      expect(rules.size, 13);
      expect(rules.rows, 13);
      expect(rules.cols, 13);
    });

    test('passMove is size * size', () {
      expect(GoRules().passMove, 169);
      expect(GoRules(size: 9).passMove, 81);
    });

    test('legalMoves on empty board returns every intersection plus pass', () {
      final board = Board(13, 13);
      final legal = rules.legalMoves(board);
      // 169 intersections + pass.
      expect(legal.length, 170);
      expect(legal.last, rules.passMove);
      // First intersection is index 0; last is 168.
      expect(legal.contains(0), isTrue);
      expect(legal.contains(168), isTrue);
      expect(legal.contains(169), isTrue);
    });

    test('pass is always legal even when every intersection is occupied', () {
      // Fill the board with alternating colours; Go boards aren't normally
      // full because passing avoids it, but `legalMoves` should still report
      // pass.
      final board = Board(13, 13);
      for (var r = 0; r < 13; r++) {
        for (var c = 0; c < 13; c++) {
          board.set(r, c, ((r + c) % 2 == 0) ? 1 : -1);
        }
      }
      final legal = rules.legalMoves(board);
      // Most intersections occupied; only suicidal placements would be legal,
      // but they're filtered. Pass is legal regardless.
      expect(legal.contains(rules.passMove), isTrue);
    });

    test('applyMove with passMove returns board byte-equal to input', () {
      final board = Board.from([
        [1, 0, -1],
        [0, 1, 0],
        [-1, 0, 1],
      ]);
      final small = GoRules(size: 3);
      final after = small.applyMove(board, small.passMove, 1);
      expect(after, equals(board));
      // Mutating `after` must not affect input.
      after.set(0, 1, 1);
      expect(board.get(0, 1), 0);
    });

    test('applyMove places a stone at the encoded intersection', () {
      final small = GoRules(size: 5);
      final board = Board(5, 5);
      final move = 2 * 5 + 2; // (2, 2) — centre.
      final after = small.applyMove(board, move, 1);
      expect(after.get(2, 2), 1);
      // Original untouched.
      expect(board.get(2, 2), 0);
    });

    test('single-stone capture removes the surrounded enemy stone', () {
      // 3×3 with a W stone at (1,1) surrounded on three sides by B; B plays
      // the fourth liberty at (1,2) and captures the W stone.
      // Before:                       After:
      //   . B .                         . B .
      //   B W .                         B . B
      //   . B .                         . B .
      final small = GoRules(size: 3);
      final board = Board.from([
        [0, -1, 0],
        [-1, 1, 0],
        [0, -1, 0],
      ]);
      final move = 1 * 3 + 2; // (1, 2)
      final after = small.applyMove(board, move, -1);
      expect(after.get(1, 1), 0, reason: 'W stone should be captured');
      expect(after.get(1, 2), -1, reason: 'B stone should be placed');
    });

    test('multi-stone group capture removes the entire group', () {
      // 4×4. A 3-stone W chain along the top edge with one liberty; B fills
      // the liberty and captures all three.
      // Before:                       After:
      //   W W W .                       . . . B
      //   B B B .                       B B B .
      //   . . . .                       . . . .
      //   . . . .                       . . . .
      final small = GoRules(size: 4);
      final board = Board.from([
        [1, 1, 1, 0],
        [-1, -1, -1, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]);
      final move = 0 * 4 + 3; // (0, 3)
      final after = small.applyMove(board, move, -1);
      expect(after.get(0, 0), 0);
      expect(after.get(0, 1), 0);
      expect(after.get(0, 2), 0);
      expect(after.get(0, 3), -1);
    });

    test('legalMoves rejects suicide that captures nothing', () {
      // 3×3. B's three corner liberties around (0, 0) are all occupied by W.
      // Placing B at (0, 0) would have zero liberties and capture nothing.
      // Before:
      //   . W .
      //   W . .
      //   . . .
      final small = GoRules(size: 3);
      final board = Board.from([
        [0, 1, 0],
        [1, 0, 0],
        [0, 0, 0],
      ]);
      final legal = small.legalMoves(board, side: -1);
      expect(legal.contains(0), isFalse, reason: '(0,0) is suicide for B');
    });

    test('legalMoves accepts suicide that captures (capture resolves first)', () {
      // Position chosen so placement WITHOUT capture is suicide, but each
      // adjacent enemy stone has only the placement square as its sole
      // liberty — so capture resolves first and frees the placed stone.
      //   B W B       B plays (1,1). Pre-capture: B has 0 liberties.
      //   W . W       Each W is a single stone whose only liberty is the
      //   B W B       centre we're filling, so all four W are captured.
      //               Post-capture: B has 4 liberties → legal.
      final small = GoRules(size: 3);
      final board = Board.from([
        [-1, 1, -1],
        [1, 0, 1],
        [-1, 1, -1],
      ]);
      final centre = 1 * 3 + 1; // (1, 1)
      final legal = small.legalMoves(board, side: -1);
      expect(
        legal.contains(centre),
        isTrue,
        reason:
            'B at centre captures all four W stones first, then has 4 liberties',
      );
      final after = small.applyMove(board, centre, -1);
      expect(after.get(0, 1), 0);
      expect(after.get(1, 0), 0);
      expect(after.get(1, 2), 0);
      expect(after.get(2, 1), 0);
      expect(after.get(1, 1), -1);
    });

    test('simple ko is rejected on immediate recapture', () {
      // Canonical single-stone ko on a 4×4.
      //   . B W .       Pre-capture: W at (1,1) has only liberty (1,2).
      //   B W . .       B plays (1,2): W is captured.
      //   . B . .       Post-capture board has B at (1,2), no W at (1,1).
      //   . . . .       W's hypothetical recapture at (1,1) would recreate
      //                 the pre-capture board exactly → ko violation.
      final small = GoRules(size: 4);
      final dummyImage = Int8List(small.size * small.size);
      // Pre-capture board. W at (1,1) has one liberty at (1,2).
      final boardBeforeCapture = Board.from([
        [0, 1, -1, 0],
        [1, -1, 0, 0],
        [0, 1, 0, 0],
        [0, 0, 0, 0],
      ]);
      // B plays move = 1*4+2 = 6 (cell (1,2)): captures W at (1,1). After:
      //   . B W .
      //   B . B .
      //   . B . .
      //   . . . .
      final captureMove = 1 * 4 + 2;
      final captured = small.applyMove(boardBeforeCapture, captureMove, 1);
      expect(captured.get(1, 1), 0, reason: 'W captured');
      expect(captured.get(1, 2), 1, reason: 'B placed');

      // Build a log encoding the ko history. states.length-2 must be the
      // board state we want to ban W from recreating — that's
      // boardBeforeCapture (the position that existed *before* B's capture
      // move). W playing (1,1) would recreate that board exactly, modulo
      // the captured stone reappearing.
      final log = GameLog();
      log.addState(
        GameState(
          board: boardBeforeCapture,
          diffusedImage: dummyImage,
          movePlayed: -1, // some prior W move; specifics don't matter
          ply: 5,
          gameId: 'ko-test',
          totalMaterial: 6,
          materialBalance: 0,
        ),
      );
      log.addState(
        GameState(
          board: captured,
          diffusedImage: dummyImage,
          movePlayed: captureMove,
          ply: 6,
          gameId: 'ko-test',
          totalMaterial: 6,
          materialBalance: 2,
        ),
      );

      // W (side -1) should NOT be allowed to recapture at (1,1):
      final legalForW = small.legalMoves(captured, side: -1, log: log);
      final koMove = 1 * 4 + 1; // (1, 1)
      expect(
        legalForW.contains(koMove),
        isFalse,
        reason:
            'W recapture at (1,1) recreates the prior board state — ko violation',
      );
    });
  });

  group('GoRules termination', () {
    final rules = GoRules(size: 5);

    test('isTerminal is false on empty log', () {
      final board = Board(5, 5);
      expect(rules.isTerminal(board), isFalse);
      expect(rules.isTerminal(board, log: GameLog()), isFalse);
    });

    test('isTerminal is false after a single pass', () {
      final board = Board(5, 5);
      final log =
          GameLog()..addState(
            _goState(rules: rules, ply: 0, movePlayed: rules.passMove),
          );
      expect(rules.isTerminal(board, log: log), isFalse);
    });

    test('isTerminal is true after two consecutive passes', () {
      final board = Board(5, 5);
      final log =
          GameLog()
            ..addState(
              _goState(rules: rules, ply: 0, movePlayed: rules.passMove),
            )
            ..addState(
              _goState(rules: rules, ply: 1, movePlayed: rules.passMove),
            );
      expect(rules.isTerminal(board, log: log), isTrue);
    });

    test('isTerminal ignores passes from completed games', () {
      final board = Board(5, 5);
      final log = GameLog();
      // Two passes from a completed (outcome != null) prior game.
      log.addState(
        _goState(rules: rules, ply: 0, movePlayed: rules.passMove, outcome: 1),
      );
      log.addState(
        _goState(rules: rules, ply: 1, movePlayed: rules.passMove, outcome: 1),
      );
      // Current game: just one move so far.
      log.addState(_goState(rules: rules, ply: 0, movePlayed: 12));
      expect(rules.isTerminal(board, log: log), isFalse);
    });

    test('finalOutcome on synthetic position with white area majority', () {
      // 5×5 with a clear white-territory shape:
      //   . . . . .
      //   . W W W .
      //   . W . W .
      //   . W W W .
      //   . . . . .
      // White stones: 8. Empty interior at (2,2): 1 (surrounded by white).
      // Empty exterior: 16 cells touching the edge, neighbouring white only
      // along their inner side. Whether they're "white territory" depends on
      // whether they touch any black stone — there are no black stones, so
      // every empty region touching only white scores for white. Total
      // white area = 8 + 17 = 25. Black = 0.
      final board = Board.from([
        [0, 0, 0, 0, 0],
        [0, 1, 1, 1, 0],
        [0, 1, 0, 1, 0],
        [0, 1, 1, 1, 0],
        [0, 0, 0, 0, 0],
      ]);
      expect(rules.finalOutcome(board), 1);
    });

    test('finalOutcome ties on empty board', () {
      final board = Board(5, 5);
      expect(rules.finalOutcome(board), 0);
    });

    test('finalOutcome ties when white and black areas are equal', () {
      // Half-and-half board:
      //   B B . W W
      //   B B . W W
      //   . . . . .
      //   B B . W W
      //   B B . W W
      // White stones: 8 + territory around them on the right (some). Black
      // mirror. By symmetry totals are equal → tie.
      final board = Board.from([
        [-1, -1, 0, 1, 1],
        [-1, -1, 0, 1, 1],
        [0, 0, 0, 0, 0],
        [-1, -1, 0, 1, 1],
        [-1, -1, 0, 1, 1],
      ]);
      expect(rules.finalOutcome(board), 0);
    });
  });

  group('GoDiffusionKernel', () {
    const kernel = GoDiffusionKernel();

    test('empty board produces all-zero map', () {
      final influence = kernel.diffuse(Board(13, 13));
      for (final row in influence) {
        for (final v in row) {
          expect(v, 0.0);
        }
      }
    });

    test('single stone radiates orthogonally', () {
      final board = Board(13, 13)..set(6, 6, 1);
      final influence = kernel.diffuse(board);
      expect(influence[6][6], greaterThan(0));
      expect(influence[5][6], greaterThan(0));
      expect(influence[7][6], greaterThan(0));
      expect(influence[6][5], greaterThan(0));
      expect(influence[6][7], greaterThan(0));
      // Attenuates with distance: closer cells should be at least as large
      // as further cells along the same axis.
      expect(
        influence[5][6].abs(),
        greaterThanOrEqualTo(influence[4][6].abs()),
      );
    });

    test('opposing stone radiates negative influence', () {
      final board = Board(13, 13)..set(6, 6, -1);
      final influence = kernel.diffuse(board);
      expect(influence[6][6], lessThan(0));
      expect(influence[5][6], lessThan(0));
      expect(influence[7][6], lessThan(0));
      expect(influence[6][5], lessThan(0));
      expect(influence[6][7], lessThan(0));
    });

    test('2 steps spread further than 1 step', () {
      final board = Board(13, 13)..set(6, 6, 1);
      final oneStep = kernel.diffuse(board, steps: 1);
      final twoStep = kernel.diffuse(board, steps: 2);
      // After 1 step, cells 2 away on an axis should be 0; after 2 steps
      // they should be non-zero.
      expect(oneStep[4][6], 0.0);
      expect(twoStep[4][6], isNot(0.0));
    });

    test(
      'diagonal cells receive zero direct contribution from a single stone',
      () {
        // After 1 step, diagonal cells must be exactly zero — there is no
        // 4-neighbour path of length 1 from (6,6) to (5,5).
        final board = Board(13, 13)..set(6, 6, 1);
        final influence = kernel.diffuse(board, steps: 1);
        expect(influence[5][5], 0.0);
        expect(influence[7][7], 0.0);
        expect(influence[5][7], 0.0);
        expect(influence[7][5], 0.0);
      },
    );
  });

  group('GoFilter', () {
    test('matches within window', () {
      const filter = GoFilter(10, 4);
      expect(filter.matches(_goStateRaw(ply: 10)), isTrue);
      expect(filter.matches(_goStateRaw(ply: 14)), isTrue);
      expect(filter.matches(_goStateRaw(ply: 6)), isTrue);
    });

    test('rejects outside window', () {
      const filter = GoFilter(10, 4);
      expect(filter.matches(_goStateRaw(ply: 15)), isFalse);
      expect(filter.matches(_goStateRaw(ply: 5)), isFalse);
    });

    test('widened doubles the window', () {
      const filter = GoFilter(10, 4);
      final wider = filter.widened() as GoFilter;
      expect(wider.window, 8);
      expect(wider.queryPly, 10);
    });

    test('widened from zero produces window of 1', () {
      const filter = GoFilter(10, 0);
      final wider = filter.widened() as GoFilter;
      expect(wider.window, 1);
    });
  });

  group('GoMoveScorer', () {
    const scorer = GoMoveScorer(13);

    test('pass returns the fixed pass score', () {
      final heatmap = List.generate(13, (_) => List.filled(13, 5.0));
      expect(
        scorer.scoreMove(169, Board(13, 13), heatmap),
        GoMoveScorer.passScore,
      );
    });

    test('intersection returns heatmap value at decoded coordinate', () {
      final heatmap = List.generate(13, (_) => List.filled(13, 0.0));
      heatmap[3][7] = 2.5;
      final move = 3 * 13 + 7;
      expect(scorer.scoreMove(move, Board(13, 13), heatmap), 2.5);
    });

    test('intersection at (0,0) reads heatmap[0][0]', () {
      final heatmap = List.generate(13, (_) => List.filled(13, 0.0));
      heatmap[0][0] = -1.0;
      expect(scorer.scoreMove(0, Board(13, 13), heatmap), -1.0);
    });
  });
}

GameState _goState({
  required GoRules rules,
  required int ply,
  required int movePlayed,
  int? outcome,
}) {
  final cells = rules.size * rules.size;
  return GameState(
    board: Board(rules.size, rules.size),
    diffusedImage: Int8List(cells),
    movePlayed: movePlayed,
    ply: ply,
    gameId: 'g',
    totalMaterial: 0,
    materialBalance: 0,
    outcome: outcome,
  );
}

GameState _goStateRaw({required int ply}) => GameState(
  board: Board(13, 13),
  diffusedImage: Int8List(169),
  movePlayed: 0,
  ply: ply,
  gameId: 'g',
  totalMaterial: 0,
  materialBalance: 0,
);
