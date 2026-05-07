import 'package:flutter_test/flutter_test.dart';
import 'package:game_engine/game_engine.dart';
import 'package:pi_ying/src/db/database_service.dart';
import 'package:pi_ying/src/state/game_notifier.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Fixture {
  final DatabaseService db;
  final GameLog log;
  final GameNotifier notifier;

  _Fixture(this.db, this.log, this.notifier);

  static Future<_Fixture> create() async {
    final db = DatabaseService.withFactory(
      databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    await db.init();
    final rules = ConnectFourRules();
    final log = GameLog();
    final brain = CloneBrain(rules: rules, log: log);
    final notifier = GameNotifier(rules: rules, log: log, brain: brain, db: db);
    await notifier.init();
    return _Fixture(db, log, notifier);
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _Fixture f;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    f = await _Fixture.create();
  });

  tearDown(() async {
    await f.db.close();
  });

  test('startNewGame resets board and inserts a games row', () async {
    await f.notifier.startNewGame();

    expect(f.notifier.displayBoard, Board(6, 7));
    expect(f.notifier.currentSide, 1);
    expect(f.notifier.outcome, isNull);
    expect(f.notifier.isPlayerTurn, true);
  });

  test('playerMove triggers clone turn and persists both moves', () async {
    await f.notifier.startNewGame();

    await f.notifier.playerMove(3);
    await _settle();

    final loaded = await f.db.loadAllGameStates();
    expect(loaded, hasLength(2));
    expect(f.notifier.currentSide, 1);
    expect(f.notifier.isCloneThinking, false);
    expect(f.notifier.narration.isNotEmpty, true);
  });

  test('vertical win triggers _endGame and increments gamesPlayed', () async {
    await f.notifier.startNewGame();
    await f.notifier.setFallback(FallbackStrategy.edgeFocus);

    for (var i = 0; i < 3; i++) {
      await f.notifier.playerMove(3);
      await _settle();
    }
    expect(f.notifier.outcome, isNull);

    await f.notifier.playerMove(3);
    await _settle();

    expect(f.notifier.outcome, 1);
    expect(f.notifier.gamesPlayed, 1);
    expect(await f.db.getGamesPlayedCount(), 1);

    final loaded = await f.db.loadAllGameStates();
    for (final s in loaded) {
      expect(s.outcome, isNotNull);
      expect(s.movesToEnd, isNotNull);
    }
  });

  test('move on illegal column is silently ignored', () async {
    await f.notifier.startNewGame();
    final before = (await f.db.loadAllGameStates()).length;

    await f.notifier.playerMove(99);
    await _settle();

    final after = (await f.db.loadAllGameStates()).length;
    expect(after, before);
    expect(f.notifier.currentSide, 1);
  });

  test('move while clone is thinking is silently ignored', () async {
    await f.notifier.startNewGame();

    // Don't await: queue both calls; the second one should be rejected.
    final firstFuture = f.notifier.playerMove(3);
    final secondFuture = f.notifier.playerMove(4);
    await Future.wait([firstFuture, secondFuture]);
    await _settle();

    final loaded = await f.db.loadAllGameStates();
    // Only player's first move + clone's reply, no extra player move.
    expect(loaded.where((s) => s.side == 1), hasLength(1));
  });

  test('deleteAllData clears in-memory log and games count', () async {
    await f.notifier.startNewGame();
    await f.notifier.setFallback(FallbackStrategy.edgeFocus);
    for (var i = 0; i < 4; i++) {
      await f.notifier.playerMove(3);
      await _settle();
      if (f.notifier.outcome != null) break;
    }
    expect(f.notifier.gamesPlayed, 1);

    await f.notifier.deleteAllData();

    expect(f.notifier.gamesPlayed, 0);
    expect(f.log.states, isEmpty);
    expect(await f.db.getGamesPlayedCount(), 0);
  });

  test(
    'setFallback persists and rebuilds the brain with new strategy',
    () async {
      await f.notifier.setFallback(FallbackStrategy.middleFocus);
      expect(f.notifier.fallback, FallbackStrategy.middleFocus);
      expect(await f.db.loadFallback(), FallbackStrategy.middleFocus);
    },
  );
}
