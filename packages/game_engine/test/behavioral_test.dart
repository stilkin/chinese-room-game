import 'dart:math';
import 'package:test/test.dart';
import 'package:game_engine/game_engine.dart';

void main() {
  late ConnectFourRules rules;

  setUp(() {
    rules = ConnectFourRules();
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

      var fallbacks = 0;
      final trials = 20;
      for (var i = 0; i < trials; i++) {
        final board = Board(6, 7);
        final decision = brain.selectMove(board, 1);
        if (decision.usedFallback) fallbacks++;
      }
      expect(fallbacks, trials, reason: 'Empty log should always use fallback');

      // Play several games to build data. Per-game winner-POV: invert the
      // whole game when the bot (-1) wins.
      final rng = Random(123);
      for (var g = 0; g < 10; g++) {
        var board = Board(6, 7);
        var moveCount = 0;
        while (!rules.isTerminal(board, log: log)) {
          final side = moveCount.isEven ? 1 : -1;
          final legal = rules.legalMoves(board, log: log);
          if (legal.isEmpty) break;
          final move = legal[rng.nextInt(legal.length)];
          board = rules.applyMove(board, move, side);
          log.addState(
            brain.createState(
              board: board,
              movePlayed: move,
              ply: moveCount,
              gameId: 'game-$g',
            ),
          );
          moveCount++;
        }
        final winner = rules.finalOutcome(board);
        log.backfillGame('game-$g', winner, moveCount);
        if (winner == -1) {
          log.replaceStatesForGame(
            'game-$g',
            (s) => invertState(s, rules.diffusionKernel),
          );
        }
      }

      fallbacks = 0;
      for (var i = 0; i < trials; i++) {
        var b = Board(6, 7);
        final startMoves = [3, 4];
        for (var j = 0; j < startMoves.length; j++) {
          b = rules.applyMove(b, startMoves[j], j.isEven ? 1 : -1);
        }
        final decision = brain.selectMove(b, -1);
        if (decision.usedFallback) fallbacks++;
      }
      expect(
        fallbacks,
        lessThan(trials),
        reason: 'With data, clone should sometimes find candidates',
      );
    });
  });

  group('Winner-POV storage', () {
    // Synthesize a game where the player wins by stacking col 3.
    // Returns the full move list with sides.
    List<({int col, int side})> playerWinMoves() => [
      (col: 3, side: 1),
      (col: 0, side: -1),
      (col: 3, side: 1),
      (col: 0, side: -1),
      (col: 3, side: 1),
      (col: 0, side: -1),
      (col: 3, side: 1),
    ];

    void synthesizeAndStore(
      GameLog log,
      CloneBrain brain,
      String gameId,
      List<({int col, int side})> moves,
      int winner,
    ) {
      var board = Board(6, 7);
      for (var i = 0; i < moves.length; i++) {
        final m = moves[i];
        board = rules.applyMove(board, m.col, m.side);
        log.addState(
          brain.createState(
            board: board,
            movePlayed: m.col,
            ply: i,
            gameId: gameId,
          ),
        );
      }
      log.backfillGame(gameId, winner, moves.length);
      if (winner == -1) {
        log.replaceStatesForGame(
          gameId,
          (s) => invertState(s, rules.diffusionKernel),
        );
      }
    }

    test('player-won game is stored as-is (no flip)', () {
      final log = GameLog();
      final brain = CloneBrain(rules: rules, log: log, random: Random(7));
      synthesizeAndStore(log, brain, 'p-won', playerWinMoves(), 1);

      // Boards should still be in display POV: player pieces at +1.
      final firstRow = log.states.firstWhere((s) => s.gameId == 'p-won');
      // After player's first move at col 3, (5,3) should be +1 (player's piece).
      expect(firstRow.board.get(5, 3), 1);

      // Even-ply rows are player moves → outcome=+1.
      final playerRows =
          log.states.where((s) => s.gameId == 'p-won' && s.ply.isEven).toList();
      expect(playerRows.every((s) => s.outcome == 1), true);
      // Odd-ply rows are clone moves → outcome=-1.
      final cloneRows =
          log.states.where((s) => s.gameId == 'p-won' && s.ply.isOdd).toList();
      expect(cloneRows.every((s) => s.outcome == -1), true);
    });

    test('bot-won game is whole-flipped to winner-POV', () {
      final log = GameLog();
      final brain = CloneBrain(rules: rules, log: log, random: Random(7));

      // Construct a clone-vertical-win in col 3: clone moves at indices 1,3,5,7 (col 3 each).
      final moves = <({int col, int side})>[
        (col: 0, side: 1),
        (col: 3, side: -1),
        (col: 0, side: 1),
        (col: 3, side: -1),
        (col: 0, side: 1),
        (col: 3, side: -1),
        (col: 6, side: 1),
        (col: 3, side: -1),
      ];
      synthesizeAndStore(log, brain, 'b-won', moves, -1);

      // After the whole-game flip, every cell value is sign-flipped from
      // display: clone pieces (originally -1) are now +1 in stored boards.
      final lastRow = log.states.lastWhere((s) => s.gameId == 'b-won');
      // Clone played col 3 four times, so (5,3)..(2,3) all have clone pieces.
      // Post-flip those positions read +1 (winner=clone=+1 in storage).
      expect(lastRow.board.get(5, 3), 1);
      expect(lastRow.board.get(2, 3), 1);
      // Player's pieces in col 0 should now read -1.
      expect(lastRow.board.get(5, 0), -1);

      // Odd-ply rows are clone moves; clone won → outcome=+1.
      final cloneRows =
          log.states.where((s) => s.gameId == 'b-won' && s.ply.isOdd).toList();
      expect(cloneRows.every((s) => s.outcome == 1), true);
      // Even-ply rows are player moves; player lost → outcome=-1.
      final playerRows =
          log.states.where((s) => s.gameId == 'b-won' && s.ply.isEven).toList();
      expect(playerRows.every((s) => s.outcome == -1), true);
    });

    test(
      'with mixed data, the bot finds non-fallback move via two-query search',
      () {
        final log = GameLog();
        final brain = CloneBrain(rules: rules, log: log, random: Random(7));
        synthesizeAndStore(log, brain, 'p-won', playerWinMoves(), 1);

        // Bot queries from a position the synthesized game's stored canonicals
        // could match against (mid-stack).
        var midStack = Board(6, 7);
        midStack = rules.applyMove(midStack, 3, 1);
        midStack = rules.applyMove(midStack, 0, -1);
        midStack = rules.applyMove(midStack, 3, 1);
        midStack = rules.applyMove(midStack, 0, -1);

        final decision = brain.selectMove(midStack, -1);
        expect(decision.candidatesFound, greaterThan(0));
      },
    );
  });
}
