import 'dart:math';
import 'dart:typed_data';

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

  // Go fallbacks need a GoRules instance, not the CF `rules` from setUp.
  // Build a fresh brain per test so log state never leaks between tests.
  CloneBrain buildGoBrain(
    FallbackStrategy strategy, {
    Random? random,
    int size = 13,
  }) => CloneBrain(
    rules: GoRules(size: size),
    log: GameLog(),
    fallback: strategy,
    random: random ?? Random(42),
  );

  group('Go Star-point fallback', () {
    test('empty board picks one of the nine hoshi (weight 3)', () {
      final brain = buildGoBrain(FallbackStrategy.goStarPoints);
      final decision = brain.selectMove(Board(13, 13), 1);
      const hoshi = {
        3 * 13 + 3,
        3 * 13 + 6,
        3 * 13 + 9,
        6 * 13 + 3,
        6 * 13 + 6,
        6 * 13 + 9,
        9 * 13 + 3,
        9 * 13 + 6,
        9 * 13 + 9,
      };
      expect(hoshi.contains(decision.move), true);
    });

    test('passMove is excluded even when legal', () {
      final brain = buildGoBrain(FallbackStrategy.goStarPoints);
      final board = Board(13, 13);
      final decision = brain.selectMove(board, 1);
      // 169 is the pass sentinel for size=13.
      expect(decision.move, isNot(169));
    });
  });

  group('Go Hugger fallback', () {
    test('empty board falls through to Star-point (hoshi opener)', () {
      final brain = buildGoBrain(FallbackStrategy.goHugger);
      final decision = brain.selectMove(Board(13, 13), 1);
      const hoshi = {
        3 * 13 + 3,
        3 * 13 + 6,
        3 * 13 + 9,
        6 * 13 + 3,
        6 * 13 + 6,
        6 * 13 + 9,
        9 * 13 + 3,
        9 * 13 + 6,
        9 * 13 + 9,
      };
      expect(hoshi.contains(decision.move), true);
    });

    test('one own stone at tengen → picks one of its four neighbours', () {
      final brain = buildGoBrain(FallbackStrategy.goHugger);
      final board = Board(13, 13);
      board.set(6, 6, 1);
      final decision = brain.selectMove(board, 1);
      const neighbours = {5 * 13 + 6, 7 * 13 + 6, 6 * 13 + 5, 6 * 13 + 7};
      expect(neighbours.contains(decision.move), true);
    });

    test(
      'two own stones with one shared empty neighbour → picks shared cell',
      () {
        final brain = buildGoBrain(FallbackStrategy.goHugger);
        final board = Board(13, 13);
        // Stones at (6,5) and (6,7) — the empty cell at (6,6) touches both
        // (score 2). Every other cell touches at most one (score ≤ 1).
        board.set(6, 5, 1);
        board.set(6, 7, 1);
        final decision = brain.selectMove(board, 1);
        expect(decision.move, 6 * 13 + 6);
      },
    );
  });

  group('Go Contact fallback', () {
    test('empty board falls through to Star-point', () {
      final brain = buildGoBrain(FallbackStrategy.goContact);
      final decision = brain.selectMove(Board(13, 13), 1);
      const hoshi = {
        3 * 13 + 3,
        3 * 13 + 6,
        3 * 13 + 9,
        6 * 13 + 3,
        6 * 13 + 6,
        6 * 13 + 9,
        9 * 13 + 3,
        9 * 13 + 6,
        9 * 13 + 9,
      };
      expect(hoshi.contains(decision.move), true);
    });

    test('one enemy stone at tengen → picks one of its four neighbours', () {
      final brain = buildGoBrain(FallbackStrategy.goContact);
      final board = Board(13, 13);
      board.set(6, 6, -1);
      final decision = brain.selectMove(board, 1);
      const neighbours = {5 * 13 + 6, 7 * 13 + 6, 6 * 13 + 5, 6 * 13 + 7};
      expect(neighbours.contains(decision.move), true);
    });

    test(
      'mixed friendly + enemy → picks enemy-adjacent, ignoring friendly',
      () {
        final brain = buildGoBrain(FallbackStrategy.goContact);
        final board = Board(13, 13);
        // Two friendlies at (3,3) and (3,4) — Hugger would happily play (3,2)
        // or (3,5). Contact ignores friendlies; one enemy at (9,9) is the only
        // stone with a positive enemy-neighbour score, so Contact plays one of
        // its four neighbours.
        board.set(3, 3, 1);
        board.set(3, 4, 1);
        board.set(9, 9, -1);
        final decision = brain.selectMove(board, 1);
        const enemyNeighbours = {
          8 * 13 + 9,
          10 * 13 + 9,
          9 * 13 + 8,
          9 * 13 + 10,
        };
        expect(enemyNeighbours.contains(decision.move), true);
      },
    );
  });

  group('Go Greedy fallback', () {
    test('empty board falls through to Star-point (prefilter empty)', () {
      final brain = buildGoBrain(FallbackStrategy.goGreedyArea);
      final decision = brain.selectMove(Board(13, 13), 1);
      const hoshi = {
        3 * 13 + 3,
        3 * 13 + 6,
        3 * 13 + 9,
        6 * 13 + 3,
        6 * 13 + 6,
        6 * 13 + 9,
        9 * 13 + 3,
        9 * 13 + 6,
        9 * 13 + 9,
      };
      expect(hoshi.contains(decision.move), true);
    });

    test('move that captures a single enemy stone is preferred', () {
      final brain = buildGoBrain(FallbackStrategy.goGreedyArea);
      final board = Board(13, 13);
      // Single black stone at (6,6) with three of its four neighbours already
      // own-coloured (white). Playing the fourth neighbour at (5,6) captures
      // black and removes a stone — area diff swings hard for white. Other
      // legal candidates in the prefilter set (the friendlies' free
      // neighbours) don't capture and have a much smaller diff.
      board.set(6, 6, -1);
      board.set(7, 6, 1); // south of black
      board.set(6, 5, 1); // west of black
      board.set(6, 7, 1); // east of black
      final decision = brain.selectMove(board, 1);
      expect(decision.move, 5 * 13 + 6);
    });

    test('candidates far from any stone are excluded by prefilter', () {
      // With one white stone at (0,0), the prefilter set is exactly its
      // three legal neighbours: (0,1), (1,0), (1,1)? — actually only the
      // 4-orthogonal neighbours: (0,1) and (1,0). Greedy must pick one of
      // those, never an isolated cell at e.g. tengen.
      final brain = buildGoBrain(FallbackStrategy.goGreedyArea);
      final board = Board(13, 13);
      board.set(0, 0, 1);
      final decision = brain.selectMove(board, 1);
      expect(decision.move == 0 * 13 + 1 || decision.move == 1 * 13 + 0, true);
    });
  });

  group('Go opponent-passed self-fill override', () {
    // Build a 5×5 board where every empty interior cell is bounded only by
    // white stones — pure own-enclosed territory. With the player just having
    // passed, the brain SHALL override the fallback's chosen move to passMove.
    Board enclosedBoard() => Board.from([
      [1, 1, 1, 1, 1],
      [1, 0, 0, 0, 1],
      [1, 0, 1, 0, 1],
      [1, 0, 0, 0, 1],
      [1, 1, 1, 1, 1],
    ]);

    GameState passState(GoRules rules, int ply) => GameState(
      board: Board(rules.size, rules.size),
      diffusedImage: Int8List(rules.size * rules.size),
      movePlayed: rules.passMove,
      ply: ply,
      gameId: 'g',
      totalMaterial: 0,
      materialBalance: 0,
    );

    test('overrides Star-point fallback to pass when opponent just passed', () {
      final rules = GoRules(size: 5);
      final log = GameLog()..addState(passState(rules, 0));
      final brain = CloneBrain(
        rules: rules,
        log: log,
        fallback: FallbackStrategy.goStarPoints,
        random: Random(42),
      );
      final decision = brain.selectMove(enclosedBoard(), 1);
      expect(decision.move, rules.passMove);
      expect(decision.narration, contains('nothing left'));
    });

    test('does NOT override when opponent has not passed', () {
      // Same enclosed board but no pass state in the log → bot picks a real
      // placement, even though it lands in own-enclosed territory.
      final rules = GoRules(size: 5);
      final brain = CloneBrain(
        rules: rules,
        log: GameLog(),
        fallback: FallbackStrategy.goStarPoints,
        random: Random(42),
      );
      final decision = brain.selectMove(enclosedBoard(), 1);
      expect(decision.move, isNot(rules.passMove));
    });

    test('does NOT override when chosen move borders enemy stones', () {
      // Two friendly stones at top-left and one enemy stone inside what would
      // otherwise be own-territory. The empty region touches the enemy → not
      // enclosed → bot still plays.
      final rules = GoRules(size: 5);
      final log = GameLog()..addState(passState(rules, 0));
      final brain = CloneBrain(
        rules: rules,
        log: log,
        fallback: FallbackStrategy.goStarPoints,
        random: Random(42),
      );
      final board = Board.from([
        [1, 1, 1, 1, 1],
        [1, 0, 0, 0, 1],
        [1, 0, -1, 0, 1],
        [1, 0, 0, 0, 1],
        [1, 1, 1, 1, 1],
      ]);
      final decision = brain.selectMove(board, 1);
      expect(decision.move, isNot(rules.passMove));
    });
  });

  group('candidate distance ceiling', () {
    test('zero ceiling rejects all non-exact candidates', () {
      // Use a rules wrapper with the ceiling pinned to 0. Anything that
      // isn't a byte-identical diffused image gets dropped, so even with a
      // populated log the brain must fall back.
      final tightRules = _ZeroCeilingConnectFourRules();
      final brain = CloneBrain(
        rules: tightRules,
        log: GameLog(),
        fallback: FallbackStrategy.middleFocus,
      );

      var board = Board(tightRules.rows, tightRules.cols);
      final moves = [3, 4, 3, 4, 3, 4, 3];
      for (var i = 0; i < moves.length; i++) {
        final side = i.isEven ? 1 : -1;
        board = tightRules.applyMove(board, moves[i], side);
        brain.log.addState(
          brain.createState(
            board: board,
            movePlayed: moves[i],
            ply: i,
            gameId: 'g1',
          ),
        );
      }
      brain.log.backfillGame('g1', 1, moves.length);

      // Query a position with the same ply as some stored state (so the
      // prefilter passes it through) but a shape no stored state actually
      // has — pieces at the corners. With ceiling=0, no candidate has L1=0
      // to this query, so all are dropped and the brain falls back.
      final query = Board(tightRules.rows, tightRules.cols);
      query.set(5, 0, 1);
      query.set(5, 6, -1);
      final decision = brain.selectMove(query, 1);

      expect(decision.usedFallback, true);
      expect(decision.candidatesFound, 0);
    });
  });
}

/// ConnectFour rules with the candidate distance ceiling pinned to 0 — used
/// to verify the ceiling filter in `clone_brain` rejects non-identical
/// candidates regardless of how dense the log is.
class _ZeroCeilingConnectFourRules extends ConnectFourRules {
  @override
  int get maxCandidateL1Distance => 0;
}
