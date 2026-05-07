import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:game_engine/game_engine.dart';

import '../db/database_service.dart';

class GameNotifier extends ChangeNotifier {
  final GameRules rules;
  final GameLog log;
  final DatabaseService db;

  CloneBrain _brain;
  Board _displayBoard;
  int _currentSide = 1;
  int? _outcome;
  String _narration = '';
  String _gameId = '';
  int _ply = 0;
  bool _isCloneThinking = false;
  int _gamesPlayed = 0;
  FallbackStrategy _fallback;

  GameNotifier({
    required this.rules,
    required this.log,
    required CloneBrain brain,
    required this.db,
  }) : _brain = brain,
       _fallback = brain.fallback,
       _displayBoard = Board(rules.rows, rules.cols);

  Board get displayBoard => _displayBoard;
  int get currentSide => _currentSide;
  int? get outcome => _outcome;
  String get narration => _narration;
  int get gamesPlayed => _gamesPlayed;
  bool get isCloneThinking => _isCloneThinking;
  bool get isPlayerTurn =>
      _currentSide == 1 && _outcome == null && !_isCloneThinking;
  FallbackStrategy get fallback => _fallback;

  Future<void> init() async {
    final loaded = await db.loadAllGameStates();
    for (final state in loaded) {
      log.addState(state);
    }
    _fallback = await db.loadFallback();
    _brain = CloneBrain(rules: rules, log: log, fallback: _fallback);
    _gamesPlayed = await db.getGamesPlayedCount();
    notifyListeners();
  }

  Future<void> startNewGame() async {
    _displayBoard = Board(rules.rows, rules.cols);
    _currentSide = 1;
    _outcome = null;
    _narration = '';
    _ply = 0;
    _isCloneThinking = false;
    _gameId = DateTime.now().microsecondsSinceEpoch.toString();
    await db.insertGame(_gameId);
    notifyListeners();
  }

  Future<void> playerMove(int col) async {
    if (_outcome != null || _currentSide != 1 || _isCloneThinking) return;
    if (!rules.legalMoves(_displayBoard).contains(col)) return;

    // Synchronous state mutation: anything below sees turn already flipped.
    final state = _applySync(col, 1);
    _currentSide = -1;
    final winner = rules.checkWinner(_displayBoard);
    if (winner == null) {
      _isCloneThinking = true;
    }
    notifyListeners();

    await db.insertGameState(state);

    if (winner != null) {
      await _endGame(winner);
      notifyListeners();
      return;
    }

    scheduleMicrotask(_cloneTurn);
  }

  Future<void> _cloneTurn() async {
    final decision = _brain.selectMove(_displayBoard, -1);
    _narration = decision.narration;
    final state = _applySync(decision.move, -1);
    await db.insertGameState(state);

    final winner = rules.checkWinner(_displayBoard);
    if (winner != null) {
      await _endGame(winner);
    } else {
      _currentSide = 1;
    }
    _isCloneThinking = false;
    notifyListeners();
  }

  GameState _applySync(int col, int side) {
    _displayBoard = rules.applyMove(_displayBoard, col, side);
    final state = _brain.createState(
      board: _displayBoard,
      movePlayed: col,
      ply: _ply,
      side: side,
      gameId: _gameId,
    );
    log.addState(state);
    _ply += 1;
    return state;
  }

  Future<void> _endGame(int winner) async {
    _outcome = winner;
    log.backfillGame(_gameId, winner, _ply);
    await db.backfillStates(_gameId, winner, _ply);
    await db.updateGameOutcome(_gameId, winner, _ply);
    _gamesPlayed += 1;
  }

  Future<void> setFallback(FallbackStrategy strategy) async {
    _fallback = strategy;
    await db.saveFallback(strategy);
    _brain = CloneBrain(rules: rules, log: log, fallback: strategy);
    notifyListeners();
  }

  Future<void> deleteAllData() async {
    await db.deleteAllData();
    log.states.clear();
    _gamesPlayed = 0;
    notifyListeners();
  }
}
