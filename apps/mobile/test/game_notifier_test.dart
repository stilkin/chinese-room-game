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

// Wait until the notifier is ready to accept the player's next move (or the
// game has ended and its end-of-game chain has fully settled). The clone's
// turn runs as a scheduled microtask after playerMove returns, and `_endGame`
// runs further awaits (backfill + invert) — we must wait for `isCloneThinking`
// to flip back to false before checking other state.
Future<void> _settle(GameNotifier notifier) async {
  for (var i = 0; i < 200; i++) {
    await Future<void>.delayed(Duration.zero);
    if (notifier.isCloneThinking) continue;
    if (notifier.outcome != null) return;
    if (notifier.currentSide == 1) return;
  }
  fail('Timed out waiting for GameNotifier to settle');
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
    expect(f.notifier.hasOngoingGame, true);
  });

  test('hasOngoingGame is false on a fresh fixture', () async {
    expect(f.notifier.hasOngoingGame, false);
  });

  test('hasOngoingGame flips to false at game end', () async {
    // middleFocus keeps the clone planted in the centre so the player can
    // stack col 0 four times and win vertically without interference.
    await f.notifier.setFallback(FallbackStrategy.middleFocus);
    await f.notifier.startNewGame();
    for (var i = 0; i < 4; i++) {
      await f.notifier.playerMove(0);
      await _settle(f.notifier);
    }
    expect(f.notifier.outcome, 1);
    expect(f.notifier.hasOngoingGame, false);
  });

  test('startNewGame deletes the prior ongoing game', () async {
    await f.notifier.startNewGame();
    final firstId = (await f.db.findOngoingGame())!;
    await f.notifier.playerMove(3);
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
    await f.notifier.playerMove(3);
    await _settle(f.notifier);
    await f.notifier.playerMove(4);
    await _settle(f.notifier);
    final ongoingId = (await f.db.findOngoingGame())!;
    final priorPly = f.notifier.currentSide; // capture for sanity

    // Build a fresh notifier on the same DB to simulate app restart.
    final brain = CloneBrain(rules: ConnectFourRules(), log: GameLog());
    final fresh = GameNotifier(
      rules: ConnectFourRules(),
      log: GameLog(),
      brain: brain,
      db: f.db,
    );
    await fresh.init();

    expect(fresh.hasOngoingGame, true);
    await fresh.resumeLastGame();

    // After resume: display board has the player's and clone's pieces in
    // their played columns; ply equals stored count; side parity follows.
    final stored = await f.db.loadStatesForGame(ongoingId);
    expect(fresh.displayBoard, isNot(Board(6, 7))); // not blank
    expect(fresh.currentSide, stored.length.isEven ? 1 : -1);
    expect(fresh.outcome, isNull);
    expect(priorPly, isNotNull); // (use captured value to avoid lint)
  });

  test('resumeLastGame on empty states clears the orphan and throws', () async {
    // Insert an ongoing game with NO states (corrupt scenario).
    await f.db.insertGame('orphan');

    final brain = CloneBrain(rules: ConnectFourRules(), log: GameLog());
    final fresh = GameNotifier(
      rules: ConnectFourRules(),
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

    await f.notifier.playerMove(3);
    await _settle(f.notifier);

    final loaded = await f.db.loadAllGameStates();
    expect(loaded, hasLength(2));
    expect(f.notifier.currentSide, 1);
    expect(f.notifier.isCloneThinking, false);
    expect(f.notifier.narration.isNotEmpty, true);
  });

  test('vertical win triggers _endGame and increments gamesPlayed', () async {
    await f.notifier.startNewGame();
    await f.notifier.setFallback(FallbackStrategy.middleFocus);

    for (var i = 0; i < 3; i++) {
      await f.notifier.playerMove(0);
      await _settle(f.notifier);
    }
    expect(f.notifier.outcome, isNull);

    await f.notifier.playerMove(0);
    await _settle(f.notifier);

    expect(f.notifier.outcome, 1);
    expect(f.notifier.gamesPlayed, 1);
    expect(await f.db.getGamesPlayedCount(), 1);

    final loaded = await f.db.loadAllGameStates();
    for (final s in loaded) {
      expect(s.outcome, isNotNull);
      expect(s.movesToEnd, isNotNull);
    }
  });

  test('player-won game is stored as-is (no flip)', () async {
    await f.notifier.setFallback(FallbackStrategy.middleFocus);
    await f.notifier.startNewGame();

    for (var i = 0; i < 4; i++) {
      await f.notifier.playerMove(0);
      await _settle(f.notifier);
    }
    expect(f.notifier.outcome, 1);

    final loaded = await f.db.loadAllGameStates()
      ..sort((a, b) => a.ply.compareTo(b.ply));
    expect(loaded, isNotEmpty);

    // Player won → no perspective flip. Stored boards match display POV:
    // (5,0) was the player's first move at +1 in display, so the ply-0
    // board has +1 there.
    expect(loaded.first.board.get(5, 0), 1);

    // Even-ply rows are player moves: outcome=+1 (winner moved).
    // Odd-ply rows are clone moves: outcome=-1 (loser moved).
    final evenPlyRows = loaded.where((s) => s.ply.isEven).toList();
    final oddPlyRows = loaded.where((s) => s.ply.isOdd).toList();
    expect(evenPlyRows, hasLength(4));
    expect(evenPlyRows.every((s) => s.outcome == 1), true);
    expect(oddPlyRows, hasLength(3));
    expect(oddPlyRows.every((s) => s.outcome == -1), true);
  });

  test('bot-won game is whole-flipped to winner-POV', () async {
    // Pre-seed a clone-win game so the bot has data biasing it toward col 3.
    final rules = ConnectFourRules();
    final seedBrain = CloneBrain(rules: rules, log: f.log);
    var seedBoard = Board(rules.rows, rules.cols);
    final seedMoves = [
      (col: 0, side: 1),
      (col: 3, side: -1),
      (col: 0, side: 1),
      (col: 3, side: -1),
      (col: 0, side: 1),
      (col: 3, side: -1),
      (col: 6, side: 1),
      (col: 3, side: -1),
    ];
    await f.db.insertGame('seed');
    for (var i = 0; i < seedMoves.length; i++) {
      final m = seedMoves[i];
      seedBoard = rules.applyMove(seedBoard, m.col, m.side);
      final s = seedBrain.createState(
        board: seedBoard,
        movePlayed: m.col,
        ply: i,
        gameId: 'seed',
      );
      f.log.addState(s);
      await f.db.insertGameState(s);
    }
    f.log.backfillGame('seed', -1, seedMoves.length);
    await f.db.backfillStates('seed', -1, seedMoves.length);
    await f.db.updateGameOutcome('seed', -1, seedMoves.length);
    // Apply winner-POV inversion on the seed (clone won).
    final invertedSeed = f.log.replaceStatesForGame(
      'seed',
      (s) => invertState(s, rules.diffusionKernel),
    );
    await f.db.replaceAllStatesForGameAtomic('seed', invertedSeed);

    await f.notifier.startNewGame();

    for (var i = 0; i < 6; i++) {
      if (f.notifier.outcome != null) break;
      final move = (i.isEven) ? 0 : 6;
      await f.notifier.playerMove(move);
      await _settle(f.notifier);
    }

    expect(
      f.notifier.outcome,
      -1,
      reason: 'Synthetic clone-win setup did not produce a clone win',
    );

    final loaded = await f.db.loadAllGameStates();
    final currentGameRows = loaded.where((s) => s.gameId != 'seed').toList()
      ..sort((a, b) => a.ply.compareTo(b.ply));
    expect(currentGameRows, isNotEmpty);

    // Bot won → whole-game flip. Clone's odd-ply rows (the winner) should
    // have outcome=+1; player's even-ply rows (the loser) should have
    // outcome=-1.
    final evenPlyRows = currentGameRows.where((s) => s.ply.isEven).toList();
    final oddPlyRows = currentGameRows.where((s) => s.ply.isOdd).toList();
    expect(evenPlyRows.every((s) => s.outcome == -1), true);
    expect(oddPlyRows.every((s) => s.outcome == 1), true);
  });

  test('move on illegal column is silently ignored', () async {
    await f.notifier.startNewGame();
    final before = (await f.db.loadAllGameStates()).length;

    await f.notifier.playerMove(99);
    await _settle(f.notifier);

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
    await _settle(f.notifier);

    final loaded = await f.db.loadAllGameStates();
    // Only player's first move (ply 0) + clone's reply (ply 1), no extra
    // player move.
    expect(loaded.where((s) => s.ply.isEven), hasLength(1));
  });

  test('deleteAllData clears in-memory log and games count', () async {
    await f.notifier.startNewGame();
    await f.notifier.setFallback(FallbackStrategy.middleFocus);
    for (var i = 0; i < 4; i++) {
      await f.notifier.playerMove(0);
      await _settle(f.notifier);
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
      await f.notifier.setFallback(FallbackStrategy.greedyConnect);
      expect(f.notifier.fallback, FallbackStrategy.greedyConnect);
      expect(await f.db.loadFallback(), FallbackStrategy.greedyConnect);
    },
  );
}
