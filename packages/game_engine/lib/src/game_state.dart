import 'board.dart';

class GameState {
  final Board board;
  final int zobristHash;
  final List<int> diffusedHash;
  final int movePlayed;
  final int ply;
  final int side;
  final String gameId;
  final int totalMaterial;
  final int materialBalance;
  int? outcome;
  int? movesToEnd;

  GameState({
    required this.board,
    required this.zobristHash,
    required this.diffusedHash,
    required this.movePlayed,
    required this.ply,
    required this.side,
    required this.gameId,
    required this.totalMaterial,
    required this.materialBalance,
    this.outcome,
    this.movesToEnd,
  });
}

class GameLog {
  final List<GameState> _states = [];

  List<GameState> get states => _states;

  void addState(GameState state) {
    _states.add(state);
  }

  void backfillGame(String gameId, int outcome, int totalMoves) {
    for (final state in _states) {
      if (state.gameId != gameId) continue;
      final sideOutcome = state.side == 1 ? outcome : -outcome;
      state.outcome = sideOutcome;
      state.movesToEnd = totalMoves - state.ply;
    }
  }

  List<GameState> statesWithOutcome() {
    return _states.where((s) => s.outcome != null).toList();
  }

  List<GameState> replaceStatesForGame(
    String gameId,
    GameState Function(GameState) transform,
  ) {
    final replaced = <GameState>[];
    for (var i = 0; i < _states.length; i++) {
      final s = _states[i];
      if (s.gameId != gameId) continue;
      final next = transform(s);
      _states[i] = next;
      replaced.add(next);
    }
    return replaced;
  }
}
