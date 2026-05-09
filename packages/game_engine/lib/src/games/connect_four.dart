import '../board.dart';
import '../diffusion.dart';
import '../game_rules.dart';
import '../game_state.dart';
import '../move_selection.dart';
import '../similarity.dart';

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
  List<int> legalMoves(Board board, {int side = 1, GameLog? log}) {
    final moves = <int>[];
    for (var c = 0; c < cols; c++) {
      if (board.get(0, c) == 0) moves.add(c);
    }
    return moves;
  }

  @override
  bool isTerminal(Board board, {GameLog? log}) => checkWinner(board) != null;

  @override
  int finalOutcome(Board board) => checkWinner(board) ?? 0;

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
    final cells = findWinningCells(board);
    if (cells != null) return board.get(cells.first.row, cells.first.col);
    // No winner — draw if every cell is filled, otherwise still ongoing.
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (board.get(r, c) == 0) return null;
      }
    }
    return 0;
  }

  /// If the board contains a four-in-a-row, returns the list of four
  /// `(row, col)` cells forming it. Returns null when there's no winner.
  /// Single source of truth for win detection; `checkWinner` calls into this.
  List<({int row, int col})>? findWinningCells(Board board) {
    const directions = [
      [0, 1], // horizontal
      [1, 0], // vertical
      [1, 1], // diagonal down-right
      [1, -1], // diagonal down-left
    ];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final v = board.get(r, c);
        if (v == 0) continue;
        for (final d in directions) {
          final dr = d[0];
          final dc = d[1];
          final r3 = r + 3 * dr;
          final c3 = c + 3 * dc;
          if (r3 < 0 || r3 >= rows || c3 < 0 || c3 >= cols) continue;
          if (v == board.get(r + dr, c + dc) &&
              v == board.get(r + 2 * dr, c + 2 * dc) &&
              v == board.get(r3, c3)) {
            return [
              (row: r, col: c),
              (row: r + dr, col: c + dc),
              (row: r + 2 * dr, col: c + 2 * dc),
              (row: r3, col: c3),
            ];
          }
        }
      }
    }
    return null;
  }

  @override
  DiffusionKernel get diffusionKernel => ConnectFourDiffusion();

  @override
  MoveSelectionStrategy get moveSelectionStrategy =>
      const InfluenceOverlayStrategy(ConnectFourMoveScorer());

  @override
  CandidateFilter prefilter(GameState query) => ConnectFourFilter(query.ply, 2);

  @override
  MoveScorer get moveScorer => const ConnectFourMoveScorer();

  /// 6×7 = 42 cells. After two diffusion steps with attenuation 0.5, an
  /// isolated piece spreads to ~9 cells with quantized magnitudes ≤ 2; a
  /// "1 piece different" board produces an L1 difference of roughly
  /// 8–15 once you account for overlap. A "vaguely similar" board lands
  /// in 30–50, "different game phase" 60+. Setting the ceiling at 60
  /// keeps clearly-similar candidates and discards the noisy long tail
  /// the prefilter scrapes together when the DB is sparse. Tunable via
  /// the self-play benchmark; see `bin/self_play_benchmark.dart`.
  @override
  int get maxCandidateL1Distance => 60;
}

/// Accept candidates whose ply differs from the query's by at most `window`.
/// Connect Four's `totalMaterial` equals `ply` (every move adds one piece, no
/// captures), so this is the natural one-axis filter.
class ConnectFourFilter implements CandidateFilter {
  final int queryPly;
  final int window;
  const ConnectFourFilter(this.queryPly, this.window);

  @override
  bool matches(GameState candidate) =>
      (candidate.ply - queryPly).abs() <= window;

  @override
  CandidateFilter widened() =>
      ConnectFourFilter(queryPly, window == 0 ? 1 : window * 2);
}

/// Score a column move by the heatmap value at the cell where gravity would
/// drop the piece. Full columns score `-double.infinity` so they can never be
/// chosen.
class ConnectFourMoveScorer implements MoveScorer {
  const ConnectFourMoveScorer();

  @override
  double scoreMove(int move, Board currentBoard, List<List<double>> heatmap) {
    for (var r = currentBoard.rows - 1; r >= 0; r--) {
      if (currentBoard.get(r, move) == 0) {
        return heatmap[r][move];
      }
    }
    return -double.infinity;
  }
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
