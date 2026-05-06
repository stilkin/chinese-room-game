import '../board.dart';
import '../diffusion.dart';
import '../game_rules.dart';
import '../move_selection.dart';

class ConnectFourRules extends GameRules {
  @override
  int get rows => 6;
  @override
  int get cols => 7;
  @override
  String get gameType => 'connect_four';
  @override
  List<int> get pieceValues => const [-1, 1];

  @override
  List<int> legalMoves(Board board) {
    final moves = <int>[];
    for (var c = 0; c < cols; c++) {
      if (board.get(0, c) == 0) moves.add(c);
    }
    return moves;
  }

  @override
  Board applyMove(Board board, int move, int side) {
    final result = board.copy();
    for (var r = rows - 1; r >= 0; r--) {
      if (result.get(r, move) == 0) {
        result.set(r, move, side);
        return result;
      }
    }
    throw ArgumentError('Column $move is full');
  }

  @override
  int? checkWinner(Board board) {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final v = board.get(r, c);
        if (v == 0) continue;
        if (c + 3 < cols &&
            v == board.get(r, c + 1) &&
            v == board.get(r, c + 2) &&
            v == board.get(r, c + 3)) {
          return v;
        }
        if (r + 3 < rows &&
            v == board.get(r + 1, c) &&
            v == board.get(r + 2, c) &&
            v == board.get(r + 3, c)) {
          return v;
        }
        if (r + 3 < rows &&
            c + 3 < cols &&
            v == board.get(r + 1, c + 1) &&
            v == board.get(r + 2, c + 2) &&
            v == board.get(r + 3, c + 3)) {
          return v;
        }
        if (r + 3 < rows &&
            c - 3 >= 0 &&
            v == board.get(r + 1, c - 1) &&
            v == board.get(r + 2, c - 2) &&
            v == board.get(r + 3, c - 3)) {
          return v;
        }
      }
    }
    // Check draw: no empty cells
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (board.get(r, c) == 0) return null;
      }
    }
    return 0;
  }

  @override
  DiffusionKernel get diffusionKernel => ConnectFourDiffusion();

  @override
  MoveSelectionStrategy get moveSelectionStrategy => VoteByMoveStrategy();
}

class ConnectFourDiffusion implements DiffusionKernel {
  static const _directions = [
    [0, 1], // horizontal
    [1, 0], // vertical
    [1, 1], // diagonal down-right
    [1, -1], // diagonal down-left
  ];

  static const _attenuation = 0.5;

  @override
  List<List<double>> diffuse(Board board, {int steps = 2}) {
    var influence = List.generate(
      board.rows,
      (r) => List.generate(board.cols, (c) => board.get(r, c).toDouble()),
    );

    for (var step = 0; step < steps; step++) {
      final next = List.generate(
        board.rows,
        (r) => List<double>.from(influence[r]),
      );
      for (var r = 0; r < board.rows; r++) {
        for (var c = 0; c < board.cols; c++) {
          final v = influence[r][c];
          if (v == 0) continue;
          for (final dir in _directions) {
            for (final sign in const [1, -1]) {
              final nr = r + dir[0] * sign;
              final nc = c + dir[1] * sign;
              if (nr >= 0 && nr < board.rows && nc >= 0 && nc < board.cols) {
                next[nr][nc] += v * _attenuation;
              }
            }
          }
        }
      }
      influence = next;
    }
    return influence;
  }
}
