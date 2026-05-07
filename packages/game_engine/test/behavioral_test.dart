import 'dart:math';
import 'package:test/test.dart';
import 'package:game_engine/game_engine.dart';

void main() {
  late ConnectFourRules rules;

  setUp(() {
    rules = ConnectFourRules();
  });

  group('Canonicalization behavior', () {
    test('mirror-image games produce identical canonical states', () {
      final brain = CloneBrain(rules: rules, log: GameLog());

      // Play a move on the left
      var leftBoard = Board(6, 7);
      leftBoard = rules.applyMove(leftBoard, 1, 1);
      final leftState = brain.createState(
        board: leftBoard,
        movePlayed: 1,
        ply: 0,
        side: 1,
        gameId: 'left',
      );

      // Play the mirror move on the right
      var rightBoard = Board(6, 7);
      rightBoard = rules.applyMove(rightBoard, 5, 1);
      final rightState = brain.createState(
        board: rightBoard,
        movePlayed: 5,
        ply: 0,
        side: 1,
        gameId: 'right',
      );

      // Canonical boards should be identical
      expect(leftState.zobristHash, rightState.zobristHash);
      expect(leftState.board, rightState.board);
    });
  });

  group('Clone learning', () {
    test('fallback rate decreases as data grows', () {
      final log = GameLog();
      final brain = CloneBrain(
        rules: rules,
        log: log,
        fallback: FallbackStrategy.random,
        random: Random(42),
      );

      // Measure fallback rate with no data
      var fallbacks = 0;
      final trials = 20;
      for (var i = 0; i < trials; i++) {
        final board = Board(6, 7);
        final decision = brain.selectMove(board, 1);
        if (decision.usedFallback) fallbacks++;
      }
      expect(fallbacks, trials, reason: 'Empty log should always use fallback');

      // Play several games to build data
      final rng = Random(123);
      for (var g = 0; g < 10; g++) {
        var board = Board(6, 7);
        var moveCount = 0;
        int? winner;
        while (winner == null && rules.legalMoves(board).isNotEmpty) {
          final side = moveCount.isEven ? 1 : -1;
          final legal = rules.legalMoves(board);
          final move = legal[rng.nextInt(legal.length)];
          board = rules.applyMove(board, move, side);
          log.addState(
            brain.createState(
              board: board,
              movePlayed: move,
              ply: moveCount,
              side: side,
              gameId: 'game-$g',
            ),
          );
          moveCount++;
          winner = rules.checkWinner(board);
        }
        log.backfillGame('game-$g', winner ?? 0, moveCount);
      }

      // Measure fallback rate with data
      fallbacks = 0;
      for (var i = 0; i < trials; i++) {
        final board = Board(6, 7);
        var b = board;
        final startMoves = [3, 4];
        for (var j = 0; j < startMoves.length; j++) {
          b = rules.applyMove(b, startMoves[j], j.isEven ? 1 : -1);
        }
        final decision = brain.selectMove(b, 1);
        if (decision.usedFallback) fallbacks++;
      }
      expect(
        fallbacks,
        lessThan(trials),
        reason: 'With data, clone should sometimes find candidates',
      );
    });

    test('clone prefers winning moves over losing moves', () {
      final log = GameLog();
      final brain = CloneBrain(
        rules: rules,
        log: log,
        fallback: FallbackStrategy.random,
        random: Random(42),
      );

      // Store a winning game where col 3 leads to victory
      var board = Board(6, 7);
      final winMoves = [3, 0, 3, 0, 3, 0, 3];
      for (var i = 0; i < winMoves.length; i++) {
        final side = i.isEven ? 1 : -1;
        board = rules.applyMove(board, winMoves[i], side);
        log.addState(
          brain.createState(
            board: board,
            movePlayed: winMoves[i],
            ply: i,
            side: side,
            gameId: 'win-game',
          ),
        );
      }
      log.backfillGame('win-game', 1, winMoves.length);

      // Store a losing game where col 6 leads to defeat
      board = Board(6, 7);
      final loseMoves = [6, 3, 6, 3, 6, 3, 1, 3];
      for (var i = 0; i < loseMoves.length; i++) {
        final side = i.isEven ? 1 : -1;
        board = rules.applyMove(board, loseMoves[i], side);
        log.addState(
          brain.createState(
            board: board,
            movePlayed: loseMoves[i],
            ply: i,
            side: side,
            gameId: 'lose-game',
          ),
        );
      }
      log.backfillGame('lose-game', -1, loseMoves.length);

      // Query from empty board — clone should prefer col 3 (winning) over col 6 (losing)
      final queryBoard = Board(6, 7);
      final decision = brain.selectMove(queryBoard, 1);
      expect(decision.usedFallback, false);
      expect(
        decision.move,
        3,
        reason: 'Clone should prefer the move from winning games',
      );
    });
  });

  group('Loss inversion', () {
    // Build a synthetic game where the player wins by stacking col 3.
    // Player plays col 3 four times (sides +1), clone plays col 0 between
    // (sides -1). Player wins on the 4th vertical piece at ply 6.
    void synthesizeAndStorePlayerWin(GameLog log, CloneBrain brain) {
      var board = Board(6, 7);
      final moves = [
        (col: 3, side: 1),
        (col: 0, side: -1),
        (col: 3, side: 1),
        (col: 0, side: -1),
        (col: 3, side: 1),
        (col: 0, side: -1),
        (col: 3, side: 1),
      ];
      for (var i = 0; i < moves.length; i++) {
        final m = moves[i];
        board = rules.applyMove(board, m.col, m.side);
        log.addState(
          brain.createState(
            board: board,
            movePlayed: m.col,
            ply: i,
            side: m.side,
            gameId: 'won',
          ),
        );
      }
      log.backfillGame('won', 1, moves.length);
    }

    int countWinningForBot(GameLog log) {
      return log
          .statesWithOutcome()
          .where((s) => s.side == -1 && s.outcome == 1)
          .length;
    }

    test(
      'without inversion, the bot has no winning candidates to learn from',
      () {
        final log = GameLog();
        final brain = CloneBrain(rules: rules, log: log, random: Random(7));
        synthesizeAndStorePlayerWin(log, brain);

        // The player's winning states sit at side=+1 (in +canonical space). The
        // bot's own states sit at side=-1 with outcome=-1 (the bot lost). Query
        // weighting drops loss-weighted rows, so the bot has nothing useful.
        expect(countWinningForBot(log), 0);
      },
    );

    test('after inversion, the whole game lives in bot-perspective space', () {
      final log = GameLog();
      final brain = CloneBrain(rules: rules, log: log, random: Random(7));
      synthesizeAndStorePlayerWin(log, brain);

      // This is exactly what the mobile app does in _endGame when winner==1:
      // invert every row so the whole game reads as if the bot played it.
      log.replaceStatesForGame(
        'won',
        (s) => invertState(s, brain.zobristTable, rules.diffusionKernel),
      );

      // Player's 4 winning moves are now in the bot's POV with outcome=+1.
      expect(countWinningForBot(log), 4);

      // Clone's 3 losing moves flipped too: side=+1, outcome=-1.
      final losingForOpponent =
          log.states
              .where((s) => s.gameId == 'won' && s.side == 1 && s.outcome == -1)
              .length;
      expect(losingForOpponent, 3);

      // No row of this game still sits in +canonical-mover-side==+1 space
      // with outcome=+1 (which is what would have lingered under the old
      // asymmetric scheme).
      expect(
        log.states.any(
          (s) => s.gameId == 'won' && s.side == 1 && s.outcome == 1,
        ),
        false,
      );

      // And the player's moves are query-reachable: feed the same display
      // position the bot would face mid-stack and confirm the weighted
      // candidate is the player's stacking move.
      var midStack = Board(6, 7);
      midStack = rules.applyMove(midStack, 3, 1);
      midStack = rules.applyMove(midStack, 0, -1);
      midStack = rules.applyMove(midStack, 3, 1);
      midStack = rules.applyMove(midStack, 0, -1);

      final decision = brain.selectMove(midStack, -1);
      expect(decision.usedFallback, false);
      expect(decision.candidatesFound, greaterThan(0));
    });
  });

  group('Data growth', () {
    test('game states are stored correctly through full pipeline', () {
      final log = GameLog();
      final brain = CloneBrain(rules: rules, log: log);

      var board = Board(6, 7);
      board = rules.applyMove(board, 3, 1);

      final state = brain.createState(
        board: board,
        movePlayed: 3,
        ply: 0,
        side: 1,
        gameId: 'g1',
      );
      log.addState(state);

      expect(log.states, hasLength(1));
      expect(state.zobristHash, isNot(0));
      expect(state.diffusedHash, isNotEmpty);
      expect(state.totalMaterial, 1);
    });

    test('backfill sets correct outcome from each side perspective', () {
      final log = GameLog();
      final brain = CloneBrain(rules: rules, log: log);

      var board = Board(6, 7);
      board = rules.applyMove(board, 3, 1);
      log.addState(
        brain.createState(
          board: board,
          movePlayed: 3,
          ply: 0,
          side: 1,
          gameId: 'g1',
        ),
      );

      board = rules.applyMove(board, 4, -1);
      log.addState(
        brain.createState(
          board: board,
          movePlayed: 4,
          ply: 1,
          side: -1,
          gameId: 'g1',
        ),
      );

      // Player 1 wins
      log.backfillGame('g1', 1, 2);

      expect(log.states[0].outcome, 1, reason: 'Side 1 should see win');
      expect(log.states[1].outcome, -1, reason: 'Side -1 should see loss');
      expect(log.states[0].movesToEnd, 2);
      expect(log.states[1].movesToEnd, 1);
    });
  });
}
