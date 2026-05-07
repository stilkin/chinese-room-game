import 'package:flutter_test/flutter_test.dart';
import 'package:game_engine/game_engine.dart';
import 'package:pi_ying/src/db/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

GameState _state({
  required String gameId,
  required int ply,
  required int side,
  required int movePlayed,
  Board? board,
}) {
  final b = board ?? Board(6, 7);
  return GameState(
    board: b,
    zobristHash: 0xDEADBEEF + ply,
    diffusedHash: const [0x1234567890ABCDEF, 0x0FEDCBA987654321],
    movePlayed: movePlayed,
    ply: ply,
    side: side,
    gameId: gameId,
    totalMaterial: ply,
    materialBalance: side,
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
    final original = _state(gameId: 'g1', ply: 0, side: 1, movePlayed: 3);
    await service.insertGameState(original);

    final loaded = await service.loadAllGameStates();

    expect(loaded, hasLength(1));
    final s = loaded.first;
    expect(s.gameId, 'g1');
    expect(s.ply, 0);
    expect(s.side, 1);
    expect(s.movePlayed, 3);
    expect(s.zobristHash, original.zobristHash);
    expect(s.diffusedHash, original.diffusedHash);
    expect(s.board, original.board);
  });

  test('preserves non-empty board through blob round-trip', () async {
    final board = Board.from(const [
      [0, 0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0, 0],
      [0, 0, 0, 1, 0, 0, 0],
      [-1, 0, 1, -1, 1, 0, 0],
    ]);
    await service.insertGameState(
      _state(gameId: 'g1', ply: 5, side: 1, movePlayed: 2, board: board),
    );

    final loaded = await service.loadAllGameStates();
    expect(loaded.first.board, board);
  });

  test(
    'backfills outcome with per-side flip and ply-based moves_to_end',
    () async {
      await service.insertGame('g1');
      await service.insertGameState(
        _state(gameId: 'g1', ply: 0, side: 1, movePlayed: 3),
      );
      await service.insertGameState(
        _state(gameId: 'g1', ply: 1, side: -1, movePlayed: 4),
      );
      await service.insertGameState(
        _state(gameId: 'g1', ply: 2, side: 1, movePlayed: 3),
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

  test('fallback config defaults to random and persists', () async {
    expect(await service.loadFallback(), FallbackStrategy.random);

    await service.saveFallback(FallbackStrategy.edgeFocus);
    expect(await service.loadFallback(), FallbackStrategy.edgeFocus);

    await service.saveFallback(FallbackStrategy.middleFocus);
    expect(await service.loadFallback(), FallbackStrategy.middleFocus);
  });

  test('deleteAllData clears states and games', () async {
    await service.insertGame('g1');
    await service.insertGameState(
      _state(gameId: 'g1', ply: 0, side: 1, movePlayed: 3),
    );
    await service.updateGameOutcome('g1', 1, 1);

    await service.deleteAllData();

    expect(await service.loadAllGameStates(), isEmpty);
    expect(await service.getGamesPlayedCount(), 0);
  });
}
