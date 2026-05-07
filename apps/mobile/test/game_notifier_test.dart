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
// game has ended). The clone's turn runs as a scheduled microtask after
// playerMove returns, so a fixed N-iteration settle is timing-dependent under
// load. Poll instead.
Future<void> _settle(GameNotifier notifier) async {
  for (var i = 0; i < 200; i++) {
    await Future<void>.delayed(Duration.zero);
    if (notifier.outcome != null) return;
    if (!notifier.isCloneThinking && notifier.currentSide == 1) return;
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
    await _settle(f.notifier);

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
      await _settle(f.notifier);
    }
    expect(f.notifier.outcome, isNull);

    await f.notifier.playerMove(3);
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

  test('player-won game flips every row to bot-perspective space', () async {
    await f.notifier.setFallback(FallbackStrategy.edgeFocus);
    await f.notifier.startNewGame();

    for (var i = 0; i < 4; i++) {
      await f.notifier.playerMove(3);
      await _settle(f.notifier);
    }
    expect(f.notifier.outcome, 1);

    final loaded = await f.db.loadAllGameStates();
    expect(loaded, isNotEmpty);

    // After full-flip the whole game reads as if the bot played it.
    // The 4 player rows (originally side=+1, outcome=+1) are now
    // side=-1, outcome=+1. The 3 clone rows (originally side=-1,
    // outcome=-1) are now side=+1, outcome=-1.
    final winningRows = loaded.where((s) => s.outcome == 1).toList();
    final losingRows = loaded.where((s) => s.outcome == -1).toList();
    expect(winningRows, hasLength(4));
    expect(winningRows.every((s) => s.side == -1), true);
    expect(losingRows, hasLength(3));
    expect(losingRows.every((s) => s.side == 1), true);

    // In-memory log mirrors the DB.
    expect(
      f.log.states.where((s) => s.side == -1 && s.outcome == 1),
      hasLength(4),
    );
    expect(
      f.log.states.where((s) => s.side == 1 && s.outcome == -1),
      hasLength(3),
    );
  });

  test('clone-won game leaves player-side rows untouched', () async {
    // Make the clone win by feeding it data that biases it toward col 3.
    // Pre-seed the log + DB with a synthetic clone-victory game so the
    // brain has positive-weighted data from the bot's POV.
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
        side: m.side,
        gameId: 'seed',
      );
      f.log.addState(s);
      await f.db.insertGameState(s);
    }
    f.log.backfillGame('seed', -1, seedMoves.length);
    await f.db.backfillStates('seed', -1, seedMoves.length);
    await f.db.updateGameOutcome('seed', -1, seedMoves.length);

    // Force the brain to actually use that data by re-running init (rebuilds
    // the brain in the same way the app does on cold start).
    await f.notifier.startNewGame();

    // Player walks into a vertical loss at col 3 by avoiding it. Play col 0
    // four times; the clone, biased toward col 3 by the seed game, builds a
    // vertical 4 there.
    for (var i = 0; i < 6; i++) {
      if (f.notifier.outcome != null) break;
      // Find any non-3 legal column to advance the player.
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
    final fromCurrentGame = loaded.where((s) => s.gameId != 'seed').toList();
    final playerSide = fromCurrentGame.where((s) => s.side == 1).toList();
    final cloneSide = fromCurrentGame.where((s) => s.side == -1).toList();
    expect(playerSide, isNotEmpty);
    expect(cloneSide, isNotEmpty);
    // Bot win: player rows stay at side=+1 with outcome=-1. No inversion.
    expect(playerSide.every((s) => s.outcome == -1), true);
    expect(cloneSide.every((s) => s.outcome == 1), true);
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
    // Only player's first move + clone's reply, no extra player move.
    expect(loaded.where((s) => s.side == 1), hasLength(1));
  });

  test('deleteAllData clears in-memory log and games count', () async {
    await f.notifier.startNewGame();
    await f.notifier.setFallback(FallbackStrategy.edgeFocus);
    for (var i = 0; i < 4; i++) {
      await f.notifier.playerMove(3);
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
      await f.notifier.setFallback(FallbackStrategy.middleFocus);
      expect(f.notifier.fallback, FallbackStrategy.middleFocus);
      expect(await f.db.loadFallback(), FallbackStrategy.middleFocus);
    },
  );
}
