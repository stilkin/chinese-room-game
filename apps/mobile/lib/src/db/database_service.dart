import 'dart:typed_data';

import 'package:game_engine/game_engine.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'board_codec.dart';

const _kDbName = 'pi_ying.db';
const _kSchemaVersion = 2;
const _kFallbackKey = 'fallback';

const _kCreateGameStatesV2 = '''
  CREATE TABLE game_states (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    game_id TEXT NOT NULL,
    ply INTEGER NOT NULL,
    move_played INTEGER NOT NULL,
    diffused_hash BLOB NOT NULL,
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
          await db.execute(_kCreateGameStatesV2);
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
          if (oldVersion < 2) {
            // Schema-incompatible: v1 data was per-row perspective canonicalized,
            // v2 expects per-game winner-POV. Wipe and recreate.
            await db.execute('DROP TABLE IF EXISTS game_states');
            await db.execute(_kCreateGameStatesV2);
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
      'diffused_hash': hashListToBlob(s.diffusedHash),
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
    final diffused = hashListFromBlob(row['diffused_hash']! as Uint8List);
    return GameState(
      board: board,
      diffusedHash: diffused,
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

  Future<FallbackStrategy> loadFallback() async {
    final rows = await db.query(
      'clone_config',
      where: 'key = ?',
      whereArgs: [_kFallbackKey],
    );
    if (rows.isEmpty) return FallbackStrategy.random;
    final value = rows.first['value'] as String;
    return FallbackStrategy.values.firstWhere(
      (s) => s.name == value,
      orElse: () => FallbackStrategy.random,
    );
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
