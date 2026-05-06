import 'dart:math';
import 'package:test/test.dart';
import 'package:game_engine/game_engine.dart';

void main() {
  group('Integration', () {
    test('full pipeline: play game, store, query clone', () {
      final rules = ConnectFourRules();
      final log = GameLog();
      final brain = CloneBrain(
        rules: rules,
        log: log,
        fallback: FallbackStrategy.middleFocus,
        random: Random(42),
      );

      // Play a game: player 1 wins vertically in column 3
      var board = Board(6, 7);
      final moves = [3, 4, 3, 4, 3, 4, 3];
      for (var i = 0; i < moves.length; i++) {
        final side = i.isEven ? 1 : -1;
        board = rules.applyMove(board, moves[i], side);
        final state = brain.createState(
          board: board,
          movePlayed: moves[i],
          side: side,
          gameId: 'game-1',
        );
        log.addState(state);
      }

      // Verify game ended with player 1 winning
      expect(rules.checkWinner(board), 1);

      // Backfill outcomes
      log.backfillGame('game-1', 1, moves.length);

      // Verify backfill
      for (final state in log.states) {
        expect(state.outcome, isNotNull);
        expect(state.movesToEnd, isNotNull);
      }

      // Query the clone from a similar opening
      final queryBoard = Board(6, 7);
      final decision = brain.selectMove(queryBoard, 1);

      // Should return a valid move with narration
      expect(decision.move, greaterThanOrEqualTo(0));
      expect(decision.move, lessThan(7));
      expect(rules.legalMoves(queryBoard), contains(decision.move));
      expect(decision.narration.isNotEmpty, true);
    });

    test('clone uses fallback when no data exists', () {
      final rules = ConnectFourRules();
      final log = GameLog();
      final brain = CloneBrain(
        rules: rules,
        log: log,
        fallback: FallbackStrategy.middleFocus,
      );

      final board = Board(6, 7);
      final decision = brain.selectMove(board, 1);

      expect(decision.usedFallback, true);
      expect(decision.move, 3); // middle focus picks center
      expect(decision.candidatesFound, 0);
    });

    test('multiple games build up clone knowledge', () {
      final rules = ConnectFourRules();
      final log = GameLog();
      final brain = CloneBrain(
        rules: rules,
        log: log,
        fallback: FallbackStrategy.random,
        random: Random(42),
      );

      // Play several games
      for (var gameNum = 0; gameNum < 3; gameNum++) {
        var board = Board(6, 7);
        final gameId = 'game-$gameNum';
        var moveCount = 0;
        int? winner;

        while (winner == null && rules.legalMoves(board).isNotEmpty) {
          final side = moveCount.isEven ? 1 : -1;
          final legal = rules.legalMoves(board);
          final move = legal[Random(gameNum * 100 + moveCount).nextInt(legal.length)];
          board = rules.applyMove(board, move, side);
          moveCount++;

          final state = brain.createState(
            board: board,
            movePlayed: move,
            side: side,
            gameId: gameId,
          );
          log.addState(state);
          winner = rules.checkWinner(board);
        }

        final outcome = winner == null ? 0 : winner;
        log.backfillGame(gameId, outcome, moveCount);
      }

      expect(log.states.length, greaterThan(10));
      expect(log.statesWithOutcome().length, log.states.length);

      // Clone should now have data to work with
      final board = Board(6, 7);
      final decision = brain.selectMove(board, 1);
      expect(decision.move, greaterThanOrEqualTo(0));
      expect(decision.narration.isNotEmpty, true);
    });
  });
}
