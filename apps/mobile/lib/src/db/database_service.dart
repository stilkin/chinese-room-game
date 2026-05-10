import 'dart:typed_data';

import 'package:game_engine/game_engine.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'board_codec.dart';

const _kDbName = 'pi_ying.db';
const _kSchemaVersion = 4;
const _kFallbackKey = 'fallback';

const _kCreateGameStatesV3 = '''
  CREATE TABLE game_states (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    game_id TEXT NOT NULL,
    ply INTEGER NOT NULL,
    move_played INTEGER NOT NULL,
    diffused_image BLOB NOT NULL,
    board BLOB NOT NULL,
    rows INTEGER NOT NULL,
    cols INTEGER NOT NULL,
    total_material INTEGER NOT NULL,
    material_balance INTEGER NOT NULL,
    outcome INTEGER,
    moves_to_end INTEGER
  )
''';

class DatabaseService {
  final DatabaseFactory _factory;
  final String? _path;
  Database? _db;

  DatabaseService() : _factory = databaseFactory, _path = null;

  DatabaseService.withFactory(this._factory, {String? path}) : _path = path;

  Database get db {
    final d = _db;
    if (d == null) throw StateError('DatabaseService not initialized');
    return d;
  }

  Future<void> init() async {
    final path =
        _path ??
        p.join((await getApplicationDocumentsDirectory()).path, _kDbName);
    _db = await _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _kSchemaVersion,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE games (
              game_id TEXT PRIMARY KEY,
              started_at INTEGER NOT NULL,
              outcome INTEGER,
              total_moves INTEGER
            )
          ''');
          await db.execute(_kCreateGameStatesV3);
          await db.execute(
            'CREATE INDEX idx_game_states_game_id ON game_states(game_id)',
          );
          await db.execute(
            'CREATE INDEX idx_game_states_filter ON game_states(total_material, material_balance)',
          );
          await db.execute('''
            CREATE TABLE clone_config (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // Every prior migration was schema- or data-incompatible:
          // v1→v2 changed perspective convention (per-row → winner-POV).
          // v2→v3 swapped bit-hash for quantized images.
          // v3→v4 swaps the active game from Connect Four (6×7 boards,
          // 42-byte diffused images) to Go (13×13, 169-byte images); the
          // column shapes match but the byte sizes don't and the games
          // aren't strategically comparable. All three upgrades are
          // destructive: drop game_states, clear games, leave clone_config
          // alone. Indices are recreated.
          if (oldVersion < 4) {
            await db.execute('DROP TABLE IF EXISTS game_states');
            await db.execute(_kCreateGameStatesV3);
            await db.execute(
              'CREATE INDEX idx_game_states_game_id ON game_states(game_id)',
            );
            await db.execute(
              'CREATE INDEX idx_game_states_filter ON game_states(total_material, material_balance)',
            );
            await db.delete('games');
          }
        },
      ),
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> insertGame(String gameId) async {
    await db.insert('games', {
      'game_id': gameId,
      'started_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> updateGameOutcome(
    String gameId,
    int outcome,
    int totalMoves,
  ) async {
    await db.update(
      'games',
      {'outcome': outcome, 'total_moves': totalMoves},
      where: 'game_id = ?',
      whereArgs: [gameId],
    );
  }

  Future<void> insertGameState(GameState s) async {
    await db.insert('game_states', _gameStateColumns(s));
  }

  Map<String, Object?> _gameStateColumns(GameState s) {
    return {
      'game_id': s.gameId,
      'ply': s.ply,
      'move_played': s.movePlayed,
      'diffused_image': s.diffusedImage.buffer.asUint8List(
        s.diffusedImage.offsetInBytes,
        s.diffusedImage.lengthInBytes,
      ),
      'board': boardToBlob(s.board),
      'rows': s.board.rows,
      'cols': s.board.cols,
      'total_material': s.totalMaterial,
      'material_balance': s.materialBalance,
      'outcome': s.outcome,
      'moves_to_end': s.movesToEnd,
    };
  }

  Future<List<GameState>> loadAllGameStates() async {
    final rows = await db.query('game_states');
    return rows.map(_rowToGameState).toList();
  }

  Future<String?> findOngoingGame() async {
    final rows = await db.query(
      'games',
      columns: ['game_id'],
      where: 'outcome IS NULL',
      orderBy: 'started_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['game_id'] as String;
  }

  Future<List<GameState>> loadStatesForGame(String gameId) async {
    final rows = await db.query(
      'game_states',
      where: 'game_id = ?',
      whereArgs: [gameId],
      orderBy: 'ply ASC',
    );
    return rows.map(_rowToGameState).toList();
  }

  Future<void> deleteGame(String gameId) async {
    await db.transaction((txn) async {
      await txn.delete(
        'game_states',
        where: 'game_id = ?',
        whereArgs: [gameId],
      );
      await txn.delete('games', where: 'game_id = ?', whereArgs: [gameId]);
    });
  }

  /// Removes a game's per-position rows from `game_states` but leaves its
  /// `games` row alone. Used by the resign path: the resigned game still
  /// counts in win/loss statistics (the games row carries `outcome=-1`),
  /// but its stored positions don't enter the CBR candidate pool — resigning
  /// is a "I'm giving up" signal, not a "this position is a confirmed clone
  /// win" one, and learning from those positions would teach the brain
  /// false patterns.
  Future<void> deleteStatesForGame(String gameId) async {
    await db.delete('game_states', where: 'game_id = ?', whereArgs: [gameId]);
  }

  Future<void> replaceAllStatesForGameAtomic(
    String gameId,
    List<GameState> replacements,
  ) async {
    await db.transaction((txn) async {
      await txn.delete(
        'game_states',
        where: 'game_id = ?',
        whereArgs: [gameId],
      );
      for (final s in replacements) {
        await txn.insert('game_states', _gameStateColumns(s));
      }
    });
  }

  GameState _rowToGameState(Map<String, Object?> row) {
    final rows = row['rows']! as int;
    final cols = row['cols']! as int;
    final board = boardFromBlob(rows, cols, row['board']! as Uint8List);
    final imageBlob = row['diffused_image']! as Uint8List;
    final diffusedImage = Int8List.fromList(imageBlob);
    return GameState(
      board: board,
      diffusedImage: diffusedImage,
      movePlayed: row['move_played']! as int,
      ply: row['ply']! as int,
      gameId: row['game_id']! as String,
      totalMaterial: row['total_material']! as int,
      materialBalance: row['material_balance']! as int,
      outcome: row['outcome'] as int?,
      movesToEnd: row['moves_to_end'] as int?,
    );
  }

  // Outcome from the player's POV (player moves on even plies). The clone's
  // odd-ply rows get the opposite sign.
  Future<void> backfillStates(
    String gameId,
    int outcome,
    int totalMoves,
  ) async {
    await db.rawUpdate(
      '''
      UPDATE game_states
      SET outcome = CASE WHEN (ply % 2) = 0 THEN ? ELSE ? END,
          moves_to_end = ? - ply
      WHERE game_id = ?
      ''',
      [outcome, -outcome, totalMoves, gameId],
    );
  }

  Future<int> getGamesPlayedCount() async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM games WHERE outcome IS NOT NULL',
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Returns up to [limit] completed games' outcomes ordered most-recent-last
  /// (so a UI can render them left-to-right as a timeline). Each entry is the
  /// game's `outcome` column: `+1` (player won), `-1` (clone won), `0` (draw).
  Future<List<int>> loadRecentOutcomes({int limit = 100}) async {
    final rows = await db.query(
      'games',
      columns: ['outcome'],
      where: 'outcome IS NOT NULL',
      orderBy: 'started_at DESC',
      limit: limit,
    );
    // Reverse so caller receives oldest-first within the window.
    return rows.reversed.map((r) => r['outcome'] as int).toList();
  }

  /// Aggregate win/loss/draw counts across all completed games.
  Future<({int total, int playerWins, int cloneWins, int draws})>
  loadOutcomeStats() async {
    final rows = await db.rawQuery('''
      SELECT outcome, COUNT(*) AS c
      FROM games
      WHERE outcome IS NOT NULL
      GROUP BY outcome
    ''');
    var player = 0, clone = 0, draws = 0;
    for (final row in rows) {
      final o = row['outcome'] as int;
      final c = (row['c'] as int?) ?? 0;
      if (o == 1) {
        player = c;
      } else if (o == -1) {
        clone = c;
      } else {
        draws = c;
      }
    }
    return (
      total: player + clone + draws,
      playerWins: player,
      cloneWins: clone,
      draws: draws,
    );
  }

  /// User-facing fallback strategies for Go's launch. The Connect-Four-shaped
  /// personalities (`pileFocus`, `ownPileAdjacent`, `greedyConnect`,
  /// `greedyConnectDefense`) live on in the engine for benchmark use but are
  /// no longer surfaced via the slider — Go-specific personalities are the
  /// subject of a follow-up change. Any persisted value not in this set is
  /// silently mapped to the default.
  static const _kUserFacingFallbacks = {FallbackStrategy.random};
  static const _kDefaultFallback = FallbackStrategy.random;

  Future<FallbackStrategy> loadFallback() async {
    final rows = await db.query(
      'clone_config',
      where: 'key = ?',
      whereArgs: [_kFallbackKey],
    );
    if (rows.isEmpty) return _kDefaultFallback;
    final value = rows.first['value'] as String;
    final parsed = FallbackStrategy.values.firstWhere(
      (s) => s.name == value,
      orElse: () => _kDefaultFallback,
    );
    return _kUserFacingFallbacks.contains(parsed) ? parsed : _kDefaultFallback;
  }

  Future<void> saveFallback(FallbackStrategy strategy) async {
    await db.insert('clone_config', {
      'key': _kFallbackKey,
      'value': strategy.name,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteAllData() async {
    await db.transaction((txn) async {
      await txn.delete('game_states');
      await txn.delete('games');
    });
  }
}
