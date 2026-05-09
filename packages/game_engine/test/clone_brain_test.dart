import 'dart:math';
import 'package:test/test.dart';
import 'package:game_engine/game_engine.dart';

void main() {
  late ConnectFourRules rules;

  setUp(() {
    rules = ConnectFourRules();
  });

  group('CloneBrain', () {
    test('returns fallback on empty log', () {
      final brain = CloneBrain(
        rules: rules,
        log: GameLog(),
        fallback: FallbackStrategy.middleFocus,
      );
      final board = Board(6, 7);
      final decision = brain.selectMove(board, 1);
      expect(decision.usedFallback, true);
      expect(decision.move, 3); // middle column
      expect(decision.narration, contains('middleFocus'));
    });

    test('random fallback returns legal move', () {
      final brain = CloneBrain(
        rules: rules,
        log: GameLog(),
        fallback: FallbackStrategy.random,
        random: Random(42),
      );
      final board = Board(6, 7);
      final decision = brain.selectMove(board, 1);
      expect(rules.legalMoves(board), contains(decision.move));
    });

    test('pileFocus prefers columns with existing pieces', () {
      final brain = CloneBrain(
        rules: rules,
        log: GameLog(),
        fallback: FallbackStrategy.pileFocus,
      );
      final board = Board(6, 7);
      board.set(5, 2, 1);
      board.set(4, 2, -1);
      board.set(5, 5, 1);
      final decision = brain.selectMove(board, 1);
      expect(decision.move, 2); // col 2 has 2 pieces, col 5 has 1
    });

    test('pileFocus on empty board picks the middle column', () {
      final brain = CloneBrain(
        rules: rules,
        log: GameLog(),
        fallback: FallbackStrategy.pileFocus,
      );
      final decision = brain.selectMove(Board(6, 7), 1);
      expect(decision.move, 3);
    });

    test('pileFocus tie-break prefers closer-to-middle column', () {
      final brain = CloneBrain(
        rules: rules,
        log: GameLog(),
        fallback: FallbackStrategy.pileFocus,
      );
      final board = Board(6, 7);
      // Cols 1 and 5 both have one piece; both at distance 2 from mid (=3).
      // Ties go to lower index (sort stability), so col 1 wins.
      board.set(5, 1, 1);
      board.set(5, 5, -1);
      final decision = brain.selectMove(board, 1);
      expect(decision.move, 1);
    });

    test('createState produces valid GameState', () {
      final brain = CloneBrain(rules: rules, log: GameLog());
      final board = Board(6, 7);
      board.set(5, 3, 1);

      final state = brain.createState(
        board: board,
        movePlayed: 3,
        ply: 0,
        gameId: 'g1',
      );

      expect(state.diffusedImage, isNotEmpty);
      expect(state.movePlayed, 3);
      expect(state.gameId, 'g1');
      expect(state.totalMaterial, greaterThan(0));
    });

    test('selectMove with populated log returns valid move', () {
      final brain = CloneBrain(rules: rules, log: GameLog());
      final board = Board(6, 7);

      // Play a quick game and store states
      var current = board;
      final moves = [3, 4, 3, 4, 3, 4, 3]; // player wins column 3
      for (var i = 0; i < moves.length; i++) {
        final side = i.isEven ? 1 : -1;
        current = rules.applyMove(current, moves[i], side);
        final state = brain.createState(
          board: current,
          movePlayed: moves[i],
          ply: i,
          gameId: 'g1',
        );
        brain.log.addState(state);
      }
      brain.log.backfillGame('g1', 1, moves.length);

      // Query from a similar position
      final queryBoard = Board(6, 7);
      queryBoard.set(5, 3, 1);
      queryBoard.set(5, 4, -1);

      final decision = brain.selectMove(queryBoard, -1);
      expect(rules.legalMoves(queryBoard), contains(decision.move));
      expect(decision.narration.isNotEmpty, true);
    });
  });

  CloneBrain buildBrain(FallbackStrategy strategy, {Random? random}) =>
      CloneBrain(
        rules: rules,
        log: GameLog(),
        fallback: strategy,
        random: random,
      );

  group('Builder fallback', () {
    test('empty board picks the centre column', () {
      final brain = buildBrain(FallbackStrategy.ownPileAdjacent);
      final decision = brain.selectMove(Board(6, 7), 1);
      expect(decision.move, 3);
    });

    test('single own piece in col 0 plays the legal adjacent (col 1)', () {
      final brain = buildBrain(FallbackStrategy.ownPileAdjacent);
      final board = Board(6, 7);
      board.set(5, 0, 1); // own at col 0, cStar = 0
      // Adjacents are -1 (off-board) and 1 → only col 1 is legal.
      final decision = brain.selectMove(board, 1);
      expect(decision.move, 1);
    });

    test(
      'tied own piles pick lower-index cStar then closer-to-mid adjacent',
      () {
        final brain = buildBrain(FallbackStrategy.ownPileAdjacent);
        final board = Board(6, 7);
        // Own piles tied at cols 1 and 5 (both single piece, both distance 2
        // from mid=3). Tie-break by lower index → cStar=1. Adjacents are 0
        // (dist 3) and 2 (dist 1) → col 2.
        board.set(5, 1, 1);
        board.set(5, 5, 1);
        final decision = brain.selectMove(board, 1);
        expect(decision.move, 2);
      },
    );

    test('equidistant adjacents resolve via seeded random tie-break', () {
      // cStar = 3 (centre). Adjacents 2 and 4 are both distance 1 from mid.
      // With a seeded Random the choice is deterministic for that seed but
      // we only contract that the result is one of the two valid candidates.
      final brain = buildBrain(
        FallbackStrategy.ownPileAdjacent,
        random: Random(42),
      );
      final board = Board(6, 7);
      board.set(5, 3, 1);
      final decision = brain.selectMove(board, 1);
      expect(decision.move == 2 || decision.move == 4, true);
    });
  });

  group('Connector fallback', () {
    test('empty board picks centre column', () {
      final brain = buildBrain(FallbackStrategy.greedyConnect);
      final decision = brain.selectMove(Board(6, 7), 1);
      expect(decision.move, 3);
    });

    test('vertical own pair extends upward', () {
      final brain = buildBrain(FallbackStrategy.greedyConnect);
      final board = Board(6, 7);
      // Two own pieces stacked at col 0 (rows 5 and 4). Dropping at col 0
      // lands at row 3 → vertical run of 3.
      board.set(5, 0, 1);
      board.set(4, 0, 1);
      final decision = brain.selectMove(board, 1);
      expect(decision.move, 0);
    });

    test('horizontal own pair extends with mid-distance tie-break', () {
      final brain = buildBrain(FallbackStrategy.greedyConnect);
      final board = Board(6, 7);
      // Own pieces at row 5, cols 2 and 3. Dropping at col 1 → run of 3
      // (cols 1,2,3). Dropping at col 4 → run of 3 (cols 2,3,4). Both
      // candidates score 3; col 4 (dist 1 from mid=3) beats col 1 (dist 2).
      board.set(5, 2, 1);
      board.set(5, 3, 1);
      final decision = brain.selectMove(board, 1);
      expect(decision.move, 4);
    });

    test('length-4 winning move is selected', () {
      final brain = buildBrain(FallbackStrategy.greedyConnect);
      final board = Board(6, 7);
      // Own pieces at row 5 cols 1,2,3 → playing col 4 wins (run of 4).
      board.set(5, 1, 1);
      board.set(5, 2, 1);
      board.set(5, 3, 1);
      final decision = brain.selectMove(board, 1);
      expect(decision.move, 4);
    });
  });

  group('Sentinel fallback', () {
    test('blocks opponent winning move at row level', () {
      final brain = buildBrain(FallbackStrategy.greedyConnectDefense);
      final board = Board(6, 7);
      // Opponent has 3-in-a-row at row 5 cols 0,1,2. Dropping at col 3
      // lands at row 5 and would extend opponent run to 4. Sentinel blocks
      // col 3 even though Connector might have preferred a different move.
      board.set(5, 0, -1);
      board.set(5, 1, -1);
      board.set(5, 2, -1);
      final decision = brain.selectMove(board, 1);
      expect(decision.move, 3);
    });

    test('blocks opponent threat over preferring own offence', () {
      final brain = buildBrain(FallbackStrategy.greedyConnectDefense);
      final board = Board(6, 7);
      // Opponent threat at row 5 cols 0,1,2 (block at col 3).
      // Own pair at row 5 cols 5 and 6 — Connector might prefer extending,
      // but Sentinel must block first.
      board.set(5, 0, -1);
      board.set(5, 1, -1);
      board.set(5, 2, -1);
      board.set(5, 5, 1);
      board.set(5, 6, 1);
      final decision = brain.selectMove(board, 1);
      expect(decision.move, 3);
    });

    test('without opponent threat behaves like Connector', () {
      final connector = buildBrain(FallbackStrategy.greedyConnect);
      final sentinel = buildBrain(FallbackStrategy.greedyConnectDefense);
      final board = Board(6, 7);
      board.set(5, 2, 1);
      board.set(5, 3, 1); // no opponent threat present
      final c = connector.selectMove(board, 1);
      final s = sentinel.selectMove(board, 1);
      expect(s.move, c.move);
    });
  });
}
