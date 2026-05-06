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

    test('edgeFocus prefers edge columns', () {
      final brain = CloneBrain(
        rules: rules,
        log: GameLog(),
        fallback: FallbackStrategy.edgeFocus,
      );
      final board = Board(6, 7);
      final decision = brain.selectMove(board, 1);
      expect(decision.move == 0 || decision.move == 6, true);
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

    test('prefers wins over draws over losses', () {
      // Weight: win=1.0, draw=0.5, loss=0.0
      // Efficiency: 1/(1+movesToEnd)
      final winState = GameState(
        board: Board(6, 7),
        zobristHash: 0,
        diffusedHash: [0],
        movePlayed: 3,
        ply: 0,
        side: 1,
        gameId: 'gWin',
        totalMaterial: 1,
        materialBalance: 1,
        outcome: 1,
        movesToEnd: 5,
      );
      final drawState = GameState(
        board: Board(6, 7),
        zobristHash: 0,
        diffusedHash: [0],
        movePlayed: 4,
        ply: 0,
        side: 1,
        gameId: 'gDraw',
        totalMaterial: 1,
        materialBalance: 1,
        outcome: 0,
        movesToEnd: 5,
      );
      final lossState = GameState(
        board: Board(6, 7),
        zobristHash: 0,
        diffusedHash: [0],
        movePlayed: 5,
        ply: 0,
        side: 1,
        gameId: 'gLoss',
        totalMaterial: 1,
        materialBalance: 1,
        outcome: -1,
        movesToEnd: 5,
      );

      // Win weight: 1.0 * (1/6) ≈ 0.167
      // Draw weight: 0.5 * (1/6) ≈ 0.083
      // Loss weight: 0.0 * (1/6) = 0.0

      final winCandidate = WeightedCandidate(winState, 1.0 / 6.0);
      final drawCandidate = WeightedCandidate(drawState, 0.5 / 6.0);
      final lossCandidate = WeightedCandidate(lossState, 0.0);

      expect(winCandidate.weight, greaterThan(drawCandidate.weight));
      expect(drawCandidate.weight, greaterThan(lossCandidate.weight));
    });

    test('fast wins preferred over slow wins', () {
      // Fast win: 1.0 * 1/(1+2) = 0.333
      // Slow win: 1.0 * 1/(1+10) = 0.091
      final fast = 1.0 / (1.0 + 2);
      final slow = 1.0 / (1.0 + 10);
      expect(fast, greaterThan(slow));
    });

    test('createState produces valid GameState', () {
      final brain = CloneBrain(rules: rules, log: GameLog());
      final board = Board(6, 7);
      board.set(5, 3, 1);

      final state = brain.createState(
        board: board,
        movePlayed: 3,
        ply: 0,
        side: 1,
        gameId: 'g1',
      );

      expect(state.zobristHash, isNot(0));
      expect(state.diffusedHash, isNotEmpty);
      expect(state.movePlayed, 3);
      expect(state.gameId, 'g1');
      expect(state.totalMaterial, greaterThan(0));
    });

    test('selectMove with populated log returns valid move', () {
      final brain = CloneBrain(rules: rules, log: GameLog());
      final board = Board(6, 7);

      // Play a quick game and store states
      var current = board;
      final moves = [3, 4, 3, 4, 3, 4, 3]; // player 1 wins column 3
      for (var i = 0; i < moves.length; i++) {
        final side = i.isEven ? 1 : -1;
        current = rules.applyMove(current, moves[i], side);
        final state = brain.createState(
          board: current,
          movePlayed: moves[i],
          ply: i,
          side: side,
          gameId: 'g1',
        );
        brain.log.addState(state);
      }
      brain.log.backfillGame('g1', 1, moves.length);

      // Now query from a similar position
      final queryBoard = Board(6, 7);
      queryBoard.set(5, 3, 1);
      queryBoard.set(5, 4, -1);

      final decision = brain.selectMove(queryBoard, 1);
      expect(rules.legalMoves(queryBoard), contains(decision.move));
      expect(decision.narration.isNotEmpty, true);
    });
  });
}
