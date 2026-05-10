import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  int _playerWins = 0;
  int _cloneWins = 0;
  int _draws = 0;
  List<int> _recentOutcomes = const [];
  FallbackStrategy _fallback;
  bool _hasOngoingGame = false;
  // Latest move's intersection — used by the UI to highlight the most recent
  // placement with a small ring. -1 when no move has been made yet (start of
  // a game) or when the most recent move was a pass.
  int _lastMoveRow = -1;
  int _lastMoveCol = -1;
  int _lastMoveSide = 0;
  int _moveCounter = 0;

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
  int get playerWins => _playerWins;
  int get cloneWins => _cloneWins;
  int get draws => _draws;
  List<int> get recentOutcomes => _recentOutcomes;
  bool get isCloneThinking => _isCloneThinking;
  bool get isPlayerTurn =>
      _currentSide == 1 && _outcome == null && !_isCloneThinking;
  FallbackStrategy get fallback => _fallback;
  bool get hasOngoingGame => _hasOngoingGame;
  int get lastMoveRow => _lastMoveRow;
  int get lastMoveCol => _lastMoveCol;
  int get lastMoveSide => _lastMoveSide;
  int get moveCounter => _moveCounter;

  Future<void> init() async {
    final loaded = await db.loadAllGameStates();
    for (final state in loaded) {
      log.addState(state);
    }
    _fallback = await db.loadFallback();
    _brain = CloneBrain(rules: rules, log: log, fallback: _fallback);
    await _refreshStats();
    final ongoingId = await db.findOngoingGame();
    if (ongoingId != null) {
      _gameId = ongoingId;
      _hasOngoingGame = true;
    }
    notifyListeners();
  }

  Future<void> _refreshStats() async {
    final stats = await db.loadOutcomeStats();
    _gamesPlayed = stats.total;
    _playerWins = stats.playerWins;
    _cloneWins = stats.cloneWins;
    _draws = stats.draws;
    _recentOutcomes = await db.loadRecentOutcomes();
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
    _lastMoveRow = -1;
    _lastMoveCol = -1;
    _lastMoveSide = 0;
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
      _lastMoveRow = -1;
      _lastMoveCol = -1;
      _lastMoveSide = 0;
      _hasOngoingGame = true;
      notifyListeners();
    } catch (e) {
      await db.deleteGame(id);
      _hasOngoingGame = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> playerMove(int move) async {
    if (_outcome != null || _currentSide != 1 || _isCloneThinking) return;
    final legal = rules.legalMoves(_displayBoard, side: 1, log: log);
    if (!legal.contains(move)) {
      // Tap registered but the move is illegal (occupied, suicide, ko).
      // A short selection click confirms the tap landed on something
      // tappable without misleading the user into thinking a move played.
      HapticFeedback.selectionClick();
      return;
    }
    HapticFeedback.lightImpact();

    // Synchronous state mutation: anything below sees turn already flipped.
    final state = _applySync(move, 1);
    _currentSide = -1;
    final terminal = rules.isTerminal(_displayBoard, log: log);
    if (!terminal) {
      _isCloneThinking = true;
    }
    notifyListeners();

    await db.insertGameState(state);

    if (terminal) {
      await _endGame(rules.finalOutcome(_displayBoard));
      notifyListeners();
      return;
    }

    scheduleMicrotask(_cloneTurn);
  }

  /// Player passes their turn. Currently Go-only; CF doesn't support passing
  /// and the call no-ops there. Returns silently if it's not the player's
  /// turn or the game is already over.
  Future<void> pass() async {
    final pm = _passMove;
    if (pm == null) return;
    await playerMove(pm);
  }

  Future<void> _cloneTurn() async {
    // Visible "thinking" pause: without this, the bot's stone (and any
    // captures it triggers) appears on the same frame as the player's move
    // resolves, reading as a flicker rather than a turn. 250ms is the
    // minimum-perceptible-pause for cause-and-effect in UI animation
    // research; tunable.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final decision = _brain.selectMove(_displayBoard, -1);
    _narration = decision.narration;
    final state = _applySync(decision.move, -1);
    await db.insertGameState(state);

    final terminal = rules.isTerminal(_displayBoard, log: log);
    if (terminal) {
      await _endGame(rules.finalOutcome(_displayBoard));
    } else {
      _currentSide = 1;
    }
    _isCloneThinking = false;
    notifyListeners();
  }

  GameState _applySync(int move, int side) {
    // Capture detection: count opposing stones before and after applyMove.
    // Any decrement is captured stones — fire a medium haptic so the user
    // viscerally registers the board event regardless of which side acted.
    final opponent = -side;
    var beforeOpponent = 0;
    for (var r = 0; r < _displayBoard.rows; r++) {
      for (var c = 0; c < _displayBoard.cols; c++) {
        if (_displayBoard.get(r, c) == opponent) beforeOpponent++;
      }
    }
    _displayBoard = rules.applyMove(_displayBoard, move, side);
    var afterOpponent = 0;
    for (var r = 0; r < _displayBoard.rows; r++) {
      for (var c = 0; c < _displayBoard.cols; c++) {
        if (_displayBoard.get(r, c) == opponent) afterOpponent++;
      }
    }
    if (afterOpponent < beforeOpponent) {
      HapticFeedback.mediumImpact();
    }
    final r = move ~/ rules.cols;
    final c = move % rules.cols;
    if (r >= 0 && r < rules.rows) {
      _lastMoveRow = r;
      _lastMoveCol = c;
    } else {
      // Non-board move (e.g. Go pass). The widget treats -1 as "no highlight".
      _lastMoveRow = -1;
      _lastMoveCol = -1;
    }
    _lastMoveSide = side;
    _moveCounter += 1;
    final state = _brain.createState(
      board: _displayBoard,
      movePlayed: move,
      ply: _ply,
      gameId: _gameId,
    );
    log.addState(state);
    _ply += 1;
    return state;
  }

  /// The integer encoding of the pass move for the active rules, or null if
  /// the game has no pass move. Computed once via type-check rather than
  /// dragging an abstract `passMove` getter through `GameRules` for one user.
  late final int? _passMove = (rules is GoRules)
      ? (rules as GoRules).passMove
      : null;

  /// Running Chinese-style area score for the current board, or null when
  /// the game has no concept of area (e.g. Connect Four). Mid-game the
  /// number is noisy (most of the empty board is dame) but the trend is
  /// meaningful and the late-game number is exact.
  ({int player, int clone})? get currentAreaScore {
    final r = rules;
    if (r is! GoRules) return null;
    final score = r.areaScore(_displayBoard);
    // areaScore returns ({white, black}); our display convention has
    // player as +1 (white-coloured stones) and clone as -1 (dark stones).
    return (player: score.white, clone: score.black);
  }

  /// Player concedes the game. The resigned game counts as a loss in stats
  /// (the `games` row keeps `outcome=-1`), but its per-position rows are
  /// scrubbed from the CBR candidate pool — resigns happen at positions the
  /// player merely *thinks* they're losing, which doesn't make those
  /// positions confirmed clone-winning territory. Letting the brain learn
  /// from them would teach false patterns.
  Future<void> resign() async {
    if (_outcome != null || !_hasOngoingGame) return;
    HapticFeedback.mediumImpact();
    _isCloneThinking = false;
    if (_gameId.isNotEmpty) {
      await db.deleteStatesForGame(_gameId);
      log.states.removeWhere((s) => s.gameId == _gameId);
      await db.updateGameOutcome(_gameId, -1, _ply);
    }
    _outcome = -1;
    _hasOngoingGame = false;
    await _refreshStats();
    notifyListeners();
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

    _hasOngoingGame = false;
    await _refreshStats();
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
    // Reset the live game too — otherwise the next playerMove would persist
    // into a wiped gameId with no `games` row backing it.
    _displayBoard = Board(rules.rows, rules.cols);
    _currentSide = 1;
    _outcome = null;
    _narration = '';
    _ply = 0;
    _isCloneThinking = false;
    _lastMoveRow = -1;
    _lastMoveCol = -1;
    _lastMoveSide = 0;
    _gamesPlayed = 0;
    _playerWins = 0;
    _cloneWins = 0;
    _draws = 0;
    _recentOutcomes = const [];
    _hasOngoingGame = false;
    _gameId = '';
    notifyListeners();
  }
}
