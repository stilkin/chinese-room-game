import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_engine/game_engine.dart';
import 'package:pi_ying/src/db/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

GameState _state({
  required String gameId,
  required int ply,
  required int movePlayed,
  Board? board,
  int materialBalance = 0,
}) {
  final b = board ?? Board(13, 13);
  // Distinct image so round-trip assertions can detect drift.
  final image = Int8List.fromList(
    List<int>.generate(b.rows * b.cols, (i) => ((i * 7) % 31) - 15),
  );
  return GameState(
    board: b,
    diffusedImage: image,
    movePlayed: movePlayed,
    ply: ply,
    gameId: gameId,
    totalMaterial: ply,
    materialBalance: materialBalance,
  );
}

void main() {
  late DatabaseService service;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    service = DatabaseService.withFactory(
      databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    await service.init();
  });

  tearDown(() async {
    await service.close();
  });

  test('round-trips a game state', () async {
    final original = _state(gameId: 'g1', ply: 0, movePlayed: 3);
    await service.insertGameState(original);

    final loaded = await service.loadAllGameStates();

    expect(loaded, hasLength(1));
    final s = loaded.first;
    expect(s.gameId, 'g1');
    expect(s.ply, 0);
    expect(s.movePlayed, 3);
    expect(s.diffusedImage, original.diffusedImage);
    expect(s.board, original.board);
  });

  test('preserves non-empty board through blob round-trip', () async {
    // Sparse 13×13 with stones at a few intersections.
    final board = Board(13, 13);
    board.set(6, 6, 1); // centre, white
    board.set(6, 7, -1);
    board.set(7, 6, -1);
    board.set(0, 0, 1);
    board.set(12, 12, -1);
    await service.insertGameState(
      _state(gameId: 'g1', ply: 5, movePlayed: 6 * 13 + 6, board: board),
    );

    final loaded = await service.loadAllGameStates();
    expect(loaded.first.board, board);
  });

  test(
    'backfillStates uses ply parity to assign outcome (even=player, odd=clone)',
    () async {
      await service.insertGame('g1');
      await service.insertGameState(
        _state(gameId: 'g1', ply: 0, movePlayed: 6 * 13 + 6),
      );
      await service.insertGameState(
        _state(gameId: 'g1', ply: 1, movePlayed: 6 * 13 + 7),
      );
      await service.insertGameState(
        _state(gameId: 'g1', ply: 2, movePlayed: 7 * 13 + 6),
      );

      await service.backfillStates('g1', 1, 3);
      await service.updateGameOutcome('g1', 1, 3);

      final loaded = await service.loadAllGameStates()
        ..sort((a, b) => a.ply.compareTo(b.ply));

      expect(loaded[0].outcome, 1);
      expect(loaded[0].movesToEnd, 3);
      expect(loaded[1].outcome, -1);
      expect(loaded[1].movesToEnd, 2);
      expect(loaded[2].outcome, 1);
      expect(loaded[2].movesToEnd, 1);

      expect(await service.getGamesPlayedCount(), 1);
    },
  );

  test('getGamesPlayedCount excludes ongoing games', () async {
    await service.insertGame('g1');
    await service.updateGameOutcome('g1', 1, 5);
    await service.insertGame('g2');

    expect(await service.getGamesPlayedCount(), 1);
  });

  test('fallback defaults to Star-point and round-trips Go values', () async {
    expect(await service.loadFallback(), FallbackStrategy.goStarPoints);

    // All five user-facing Go-mode values round-trip cleanly.
    for (final s in [
      FallbackStrategy.random,
      FallbackStrategy.goStarPoints,
      FallbackStrategy.goHugger,
      FallbackStrategy.goContact,
      FallbackStrategy.goGreedyArea,
    ]) {
      await service.saveFallback(s);
      expect(await service.loadFallback(), s);
    }
  });

  test(
    'fallback coerces non-user-facing CF values to Star-point on read',
    () async {
      // CF personalities still exist in the engine (benchmark use) but aren't
      // surfaced in Go mode; loadFallback silently coerces them. Same
      // coercion catches `middleFocus` and any legacy persisted string.
      for (final s in [
        FallbackStrategy.pileFocus,
        FallbackStrategy.ownPileAdjacent,
        FallbackStrategy.greedyConnect,
        FallbackStrategy.greedyConnectDefense,
        FallbackStrategy.middleFocus,
      ]) {
        await service.saveFallback(s);
        expect(await service.loadFallback(), FallbackStrategy.goStarPoints);
      }
    },
  );

  test('fallback maps unknown / legacy stored value to Star-point', () async {
    // Simulate legacy data: write a string that no longer corresponds to any
    // enum value (like the removed `edgeFocus`).
    await service.db.insert('clone_config', {
      'key': 'fallback_personality',
      'value': 'edgeFocus',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    expect(await service.loadFallback(), FallbackStrategy.goStarPoints);
  });

  test('deleteAllData clears states and games', () async {
    await service.insertGame('g1');
    await service.insertGameState(_state(gameId: 'g1', ply: 0, movePlayed: 3));
    await service.updateGameOutcome('g1', 1, 1);

    await service.deleteAllData();

    expect(await service.loadAllGameStates(), isEmpty);
    expect(await service.getGamesPlayedCount(), 0);
  });

  test('findOngoingGame returns null when no games exist', () async {
    expect(await service.findOngoingGame(), isNull);
  });

  test('findOngoingGame returns null when every game has an outcome', () async {
    await service.insertGame('g1');
    await service.updateGameOutcome('g1', 1, 5);
    await service.insertGame('g2');
    await service.updateGameOutcome('g2', -1, 7);
    expect(await service.findOngoingGame(), isNull);
  });

  test('findOngoingGame returns the single ongoing game', () async {
    await service.insertGame('g1');
    await service.updateGameOutcome('g1', 1, 5);
    await service.insertGame('g2'); // ongoing
    expect(await service.findOngoingGame(), 'g2');
  });

  test(
    'findOngoingGame returns most recent when multiple ongoing rows',
    () async {
      await service.insertGame('older');
      // Force a deterministic gap so the more-recent insert wins by started_at.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await service.insertGame('newer');
      expect(await service.findOngoingGame(), 'newer');
    },
  );

  test('loadStatesForGame returns rows ordered by ply', () async {
    await service.insertGameState(_state(gameId: 'g1', ply: 2, movePlayed: 4));
    await service.insertGameState(_state(gameId: 'g1', ply: 0, movePlayed: 3));
    await service.insertGameState(_state(gameId: 'g1', ply: 1, movePlayed: 0));
    await service.insertGameState(_state(gameId: 'g2', ply: 0, movePlayed: 5));

    final result = await service.loadStatesForGame('g1');
    expect(result, hasLength(3));
    expect(result.map((s) => s.ply), [0, 1, 2]);
    expect(result.every((s) => s.gameId == 'g1'), true);
  });

  test('deleteGame removes both the games row and its game_states', () async {
    await service.insertGame('g1');
    await service.insertGameState(_state(gameId: 'g1', ply: 0, movePlayed: 3));
    await service.insertGameState(_state(gameId: 'g1', ply: 1, movePlayed: 4));
    await service.insertGame('g2');
    await service.insertGameState(_state(gameId: 'g2', ply: 0, movePlayed: 1));

    await service.deleteGame('g1');

    expect(await service.findOngoingGame(), 'g2');
    final remaining = await service.loadAllGameStates();
    expect(remaining, hasLength(1));
    expect(remaining.first.gameId, 'g2');
  });

  test('deleteGame is a no-op on a missing gameId', () async {
    await service.insertGame('g1');
    await service.insertGameState(_state(gameId: 'g1', ply: 0, movePlayed: 3));

    await service.deleteGame('does-not-exist');

    expect(await service.findOngoingGame(), 'g1');
    expect(await service.loadAllGameStates(), hasLength(1));
  });

  test(
    'replaceAllStatesForGameAtomic swaps every row of the game atomically',
    () async {
      await service.insertGameState(
        _state(gameId: 'g1', ply: 0, movePlayed: 3),
      );
      await service.insertGameState(
        _state(gameId: 'g1', ply: 1, movePlayed: 0),
      );
      await service.insertGameState(
        _state(gameId: 'g1', ply: 2, movePlayed: 4),
      );
      // Unrelated game must be untouched.
      await service.insertGameState(
        _state(gameId: 'g2', ply: 0, movePlayed: 5),
      );

      // Replacements use a marker materialBalance so we can verify the
      // swap actually happened.
      final replacements = [
        _state(gameId: 'g1', ply: 0, movePlayed: 3, materialBalance: 99),
        _state(gameId: 'g1', ply: 1, movePlayed: 0, materialBalance: 99),
        _state(gameId: 'g1', ply: 2, movePlayed: 4, materialBalance: 99),
      ];

      await service.replaceAllStatesForGameAtomic('g1', replacements);

      final all = await service.loadAllGameStates();
      expect(all, hasLength(4));

      final g1Rows = all.where((s) => s.gameId == 'g1').toList()
        ..sort((a, b) => a.ply.compareTo(b.ply));
      expect(g1Rows, hasLength(3));
      expect(g1Rows.every((s) => s.materialBalance == 99), true);
      expect(g1Rows.map((s) => s.movePlayed), [3, 0, 4]);

      // Unrelated game untouched (materialBalance==0 from default).
      final g2Rows = all.where((s) => s.gameId == 'g2').toList();
      expect(g2Rows, hasLength(1));
      expect(g2Rows.first.materialBalance, 0);
    },
  );

  group('area-score persistence (v6)', () {
    test('updateGameAreaScore round-trips via loadRecentGames', () async {
      await service.insertGame('g1');
      await service.updateGameOutcome('g1', 1, 80);
      await service.updateGameAreaScore('g1', 96, 73);

      final recent = await service.loadRecentGames();
      expect(recent, hasLength(1));
      expect(recent.first.outcome, 1);
      expect(recent.first.playerArea, 96);
      expect(recent.first.cloneArea, 73);
    });

    test(
      'loadRecentGames orders most-recent-first and skips ongoing',
      () async {
        await service.insertGame('older');
        await service.updateGameOutcome('older', 1, 50);
        await service.updateGameAreaScore('older', 70, 30);
        // Force a started_at gap so order is deterministic.
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await service.insertGame('newer');
        await service.updateGameOutcome('newer', -1, 80);
        await service.updateGameAreaScore('newer', 40, 60);
        // Ongoing — must not appear in the results.
        await service.insertGame('ongoing');

        final recent = await service.loadRecentGames();
        expect(recent.map((g) => g.outcome), [-1, 1]);
        expect(recent.first.playerArea, 40);
        expect(recent.first.cloneArea, 60);
      },
    );

    test('loadRecentGames surfaces NULL area for resigned games', () async {
      await service.insertGame('resigned');
      // Resign path: outcome set, area NEVER persisted.
      await service.updateGameOutcome('resigned', -1, 12);

      final recent = await service.loadRecentGames();
      expect(recent, hasLength(1));
      expect(recent.first.outcome, -1);
      expect(recent.first.playerArea, isNull);
      expect(recent.first.cloneArea, isNull);
    });

    test('loadRecentGames honours limit', () async {
      for (var i = 0; i < 5; i++) {
        final id = 'g$i';
        await service.insertGame(id);
        await service.updateGameOutcome(id, 1, 10);
        await service.updateGameAreaScore(id, 50, 50);
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      final recent = await service.loadRecentGames(limit: 3);
      expect(recent, hasLength(3));
    });
  });
}
