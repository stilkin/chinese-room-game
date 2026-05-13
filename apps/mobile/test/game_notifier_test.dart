import 'package:flutter_test/flutter_test.dart';
import 'package:game_engine/game_engine.dart';
import 'package:pi_ying/src/db/database_service.dart';
import 'package:pi_ying/src/state/game_notifier.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Fixture {
  final DatabaseService db;
  final GameLog log;
  final GameNotifier notifier;
  final GoRules rules;

  _Fixture(this.db, this.log, this.notifier, this.rules);

  static Future<_Fixture> create() async {
    final db = DatabaseService.withFactory(
      databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    await db.init();
    final rules = GoRules(size: 13);
    final log = GameLog();
    final brain = CloneBrain(rules: rules, log: log);
    final notifier = GameNotifier(rules: rules, log: log, brain: brain, db: db);
    await notifier.init();
    return _Fixture(db, log, notifier, rules);
  }
}

// Wait until the notifier is ready to accept the player's next move (or the
// game has ended and its end-of-game chain has fully settled). The clone's
// turn runs as a scheduled microtask after playerMove returns, and `_endGame`
// runs further awaits (backfill + invert) — we must wait for `isCloneThinking`
// to flip back to false before checking other state.
Future<void> _settle(GameNotifier notifier) async {
  // Wall-clock polling, not microtask polling. The notifier's `_cloneTurn`
  // includes a 250ms visible "thinking" delay; pure-microtask waits never
  // advance the timer queue, so we have to actually sleep here.
  for (var i = 0; i < 200; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (notifier.isCloneThinking) continue;
    if (notifier.outcome != null) return;
    if (notifier.currentSide == 1) return;
  }
  fail('Timed out waiting for GameNotifier to settle');
}

/// Convert (row, col) to a Go intersection move on a 13×13 board.
int _move(int r, int c) => r * 13 + c;

void main() {
  late _Fixture f;

  setUpAll(() {
    // Initialize the Flutter test binding so platform channels (used by
    // `HapticFeedback`) have a mock handler in place; without this the
    // notifier's haptic calls throw MissingPluginException.
    TestWidgetsFlutterBinding.ensureInitialized();
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

    expect(f.notifier.displayBoard, Board(13, 13));
    expect(f.notifier.currentSide, 1);
    expect(f.notifier.outcome, isNull);
    expect(f.notifier.isPlayerTurn, true);
    expect(f.notifier.hasOngoingGame, true);
  });

  test('hasOngoingGame is false on a fresh fixture', () async {
    expect(f.notifier.hasOngoingGame, false);
  });

  test('startNewGame deletes the prior ongoing game', () async {
    await f.notifier.startNewGame();
    final firstId = (await f.db.findOngoingGame())!;
    await f.notifier.playerMove(_move(6, 6));
    await _settle(f.notifier);
    expect((await f.db.loadStatesForGame(firstId)), isNotEmpty);

    await f.notifier.startNewGame();
    final secondId = (await f.db.findOngoingGame())!;

    expect(secondId, isNot(firstId));
    expect(await f.db.loadStatesForGame(firstId), isEmpty);
    expect(f.log.states.where((s) => s.gameId == firstId), isEmpty);
  });

  test('resumeLastGame replays moves and restores side parity', () async {
    await f.notifier.startNewGame();
    await f.notifier.playerMove(_move(6, 6));
    await _settle(f.notifier);
    await f.notifier.playerMove(_move(7, 7));
    await _settle(f.notifier);
    final ongoingId = (await f.db.findOngoingGame())!;

    // Build a fresh notifier on the same DB to simulate app restart.
    final freshRules = GoRules(size: 13);
    final brain = CloneBrain(rules: freshRules, log: GameLog());
    final fresh = GameNotifier(
      rules: freshRules,
      log: GameLog(),
      brain: brain,
      db: f.db,
    );
    await fresh.init();

    expect(fresh.hasOngoingGame, true);
    await fresh.resumeLastGame();

    final stored = await f.db.loadStatesForGame(ongoingId);
    expect(fresh.displayBoard, isNot(Board(13, 13))); // not blank
    expect(fresh.currentSide, stored.length.isEven ? 1 : -1);
    expect(fresh.outcome, isNull);
  });

  test('resumeLastGame on empty states clears the orphan and throws', () async {
    // Insert an ongoing game with NO states (corrupt scenario).
    await f.db.insertGame('orphan');

    final freshRules = GoRules(size: 13);
    final brain = CloneBrain(rules: freshRules, log: GameLog());
    final fresh = GameNotifier(
      rules: freshRules,
      log: GameLog(),
      brain: brain,
      db: f.db,
    );
    await fresh.init();
    expect(fresh.hasOngoingGame, true);

    await expectLater(fresh.resumeLastGame(), throwsA(isA<StateError>()));
    expect(fresh.hasOngoingGame, false);
    expect(await f.db.findOngoingGame(), isNull);
  });

  test('playerMove triggers clone turn and persists both moves', () async {
    await f.notifier.startNewGame();

    await f.notifier.playerMove(_move(6, 6));
    await _settle(f.notifier);

    final loaded = await f.db.loadAllGameStates();
    expect(loaded, hasLength(2));
    expect(f.notifier.currentSide, 1);
    expect(f.notifier.isCloneThinking, false);
    expect(f.notifier.narration.isNotEmpty, true);
  });

  test('pass advances the turn and persists a pass state', () async {
    await f.notifier.startNewGame();

    await f.notifier.pass();
    await _settle(f.notifier);

    final loaded = await f.db.loadAllGameStates();
    // Two states: player's pass at ply 0, clone's response at ply 1.
    expect(loaded, hasLength(2));
    expect(loaded.first.movePlayed, f.rules.passMove);
    // Player's pass leaves the board untouched.
    final playerState = loaded.firstWhere((s) => s.ply == 0);
    expect(playerState.board, Board(13, 13));
  });

  test('move at illegal intersection is silently ignored', () async {
    await f.notifier.startNewGame();
    final before = (await f.db.loadAllGameStates()).length;

    // 99999 is far outside the legal-move set.
    await f.notifier.playerMove(99999);
    await _settle(f.notifier);

    final after = (await f.db.loadAllGameStates()).length;
    expect(after, before);
    expect(f.notifier.currentSide, 1);
  });

  test('move while clone is thinking is silently ignored', () async {
    await f.notifier.startNewGame();

    // Don't await: queue both calls; the second one should be rejected.
    final firstFuture = f.notifier.playerMove(_move(6, 6));
    final secondFuture = f.notifier.playerMove(_move(7, 7));
    await Future.wait([firstFuture, secondFuture]);
    await _settle(f.notifier);

    final loaded = await f.db.loadAllGameStates();
    // Only player's first move (ply 0) + clone's reply (ply 1), no extra
    // player move.
    expect(loaded.where((s) => s.ply.isEven), hasLength(1));
  });

  test('deleteAllData clears in-memory log and DB rows', () async {
    await f.notifier.startNewGame();
    await f.notifier.playerMove(_move(6, 6));
    await _settle(f.notifier);
    await f.notifier.playerMove(_move(7, 7));
    await _settle(f.notifier);
    expect(f.log.states, isNotEmpty);
    expect(await f.db.loadAllGameStates(), isNotEmpty);

    await f.notifier.deleteAllData();

    expect(f.notifier.gamesPlayed, 0);
    expect(f.log.states, isEmpty);
    expect(await f.db.loadAllGameStates(), isEmpty);
    expect(f.notifier.hasOngoingGame, false);
  });

  test('resign records a loss but scrubs the position rows', () async {
    await f.notifier.startNewGame();
    // Play a couple of moves so there are stored states to scrub.
    await f.notifier.playerMove(_move(6, 6));
    await _settle(f.notifier);
    await f.notifier.playerMove(_move(6, 7));
    await _settle(f.notifier);
    expect(await f.db.loadAllGameStates(), isNotEmpty);

    await f.notifier.resign();

    expect(f.notifier.outcome, -1);
    expect(f.notifier.hasOngoingGame, false);
    expect(f.notifier.gamesPlayed, 1);
    // Position rows scrubbed so they don't pollute CBR. The games row
    // remains (counts as a loss in stats).
    expect(await f.db.loadAllGameStates(), isEmpty);
    expect(f.log.states, isEmpty);
  });

  test(
    'resign on empty game records the loss without any stored states',
    () async {
      await f.notifier.startNewGame();
      await f.notifier.resign();

      expect(f.notifier.outcome, -1);
      expect(f.notifier.hasOngoingGame, false);
      expect(f.notifier.gamesPlayed, 1);
    },
  );

  test(
    'setFallback persists; loadFallback coerces non-user-facing values',
    () async {
      // Go-mode user-facing values round-trip faithfully.
      await f.notifier.setFallback(FallbackStrategy.goDiamond);
      expect(f.notifier.fallback, FallbackStrategy.goDiamond);
      expect(await f.db.loadFallback(), FallbackStrategy.goDiamond);

      // Legacy CF personalities still exist in the engine but aren't surfaced
      // in Go mode. If they're somehow persisted, `loadFallback` silently
      // returns the user-facing default (Star-point) rather than reviving them.
      await f.db.saveFallback(FallbackStrategy.greedyConnect);
      expect(await f.db.loadFallback(), FallbackStrategy.goStarPoints);
    },
  );
}
