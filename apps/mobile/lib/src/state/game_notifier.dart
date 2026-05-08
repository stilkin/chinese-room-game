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
  bool _hasOngoingGame = false;

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
  bool get hasOngoingGame => _hasOngoingGame;

  Future<void> init() async {
    final loaded = await db.loadAllGameStates();
    for (final state in loaded) {
      log.addState(state);
    }
    _fallback = await db.loadFallback();
    _brain = CloneBrain(rules: rules, log: log, fallback: _fallback);
    _gamesPlayed = await db.getGamesPlayedCount();
    final ongoingId = await db.findOngoingGame();
    if (ongoingId != null) {
      _gameId = ongoingId;
      _hasOngoingGame = true;
    }
    notifyListeners();
  }

  Future<void> startNewGame() async {
    // Single-slot policy: at most one ongoing game. Wipe any prior one
    // before creating a new one. Caller (start screen) is responsible for
    // user confirmation when an ongoing game exists.
    if (_hasOngoingGame && _gameId.isNotEmpty) {
      await db.deleteGame(_gameId);
      log.states.removeWhere((s) => s.gameId == _gameId);
    }
    _displayBoard = Board(rules.rows, rules.cols);
    _currentSide = 1;
    _outcome = null;
    _narration = '';
    _ply = 0;
    _isCloneThinking = false;
    _gameId = DateTime.now().microsecondsSinceEpoch.toString();
    await db.insertGame(_gameId);
    _hasOngoingGame = true;
    notifyListeners();
  }

  Future<void> resumeLastGame() async {
    final id = await db.findOngoingGame();
    if (id == null) {
      _hasOngoingGame = false;
      notifyListeners();
      throw StateError('No ongoing game to resume');
    }
    final states = await db.loadStatesForGame(id);
    if (states.isEmpty) {
      await db.deleteGame(id);
      _hasOngoingGame = false;
      notifyListeners();
      throw StateError('Ongoing game has no moves; record cleared');
    }
    try {
      var board = Board(rules.rows, rules.cols);
      for (final s in states) {
        final mover = s.ply.isEven ? 1 : -1;
        board = rules.applyMove(board, s.movePlayed, mover);
      }
      _displayBoard = board;
      _gameId = id;
      _ply = states.length;
      _currentSide = _ply.isEven ? 1 : -1;
      _outcome = null;
      _narration = '';
      _isCloneThinking = false;
      _hasOngoingGame = true;
      notifyListeners();
    } catch (e) {
      await db.deleteGame(id);
      _hasOngoingGame = false;
      notifyListeners();
      rethrow;
    }
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

    // Per-game winner-POV invariant: storage holds the winner's pieces as +1.
    // Player wins → already +1, leave as-is. Bot wins → flip every row.
    if (winner == -1) {
      await _invertCurrentGameToWinnerPerspective();
    }

    _gamesPlayed += 1;
    _hasOngoingGame = false;
  }

  Future<void> _invertCurrentGameToWinnerPerspective() async {
    final kernel = rules.diffusionKernel;
    final inverted = log.replaceStatesForGame(
      _gameId,
      (s) => invertState(s, kernel),
    );
    await db.replaceAllStatesForGameAtomic(_gameId, inverted);
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
    _hasOngoingGame = false;
    _gameId = '';
    notifyListeners();
  }
}
