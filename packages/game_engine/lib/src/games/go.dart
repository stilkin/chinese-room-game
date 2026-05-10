import '../board.dart';
import '../diffusion.dart';
import '../game_rules.dart';
import '../game_state.dart';
import '../move_selection.dart';
import '../similarity.dart';

/// Go on an `size × size` board with simple-ko prevention, group capture,
/// two-pass termination, and Chinese-style area scoring.
///
/// Move encoding: integers `0..size*size-1` are intersection indices in
/// row-major order (`r * size + c`). The integer `size * size` is the **pass**
/// sentinel. Pass is always legal.
class GoRules extends GameRules {
  final int size;

  GoRules({this.size = 13});

  @override
  int get rows => size;
  @override
  int get cols => size;
  @override
  String get gameType => 'go';
  @override
  List<int> get pieceValues => const [-1, 1];

  /// The pass move's integer encoding.
  int get passMove => size * size;

  @override
  bool isPassMove(int move) => move == passMove;

  late final MoveScorer _scorer = GoMoveScorer(size);
  late final MoveSelectionStrategy _strategy = InfluenceOverlayStrategy(
    _scorer,
  );

  @override
  DiffusionKernel get diffusionKernel => const GoDiffusionKernel();

  @override
  MoveSelectionStrategy get moveSelectionStrategy => _strategy;

  @override
  MoveScorer get moveScorer => _scorer;

  @override
  CandidateFilter prefilter(GameState query) => GoFilter(query.ply, 4);

  /// 13×13 = 169 cells. After two diffusion steps with attenuation 0.5, an
  /// isolated stone spreads along ~9 cells per axis at quantized magnitudes
  /// up to ~2; accounting for overlap, a "1 stone different" board produces
  /// an L1 distance roughly an order of magnitude larger than CF's 6×7.
  /// `120` is a starting guess (~2× CF's 60); tune from observed retrieval
  /// distances once the smoke benchmark surfaces representative numbers.
  @override
  int get maxCandidateL1Distance => 120;

  @override
  List<int> legalMoves(Board board, {int side = 1, GameLog? log}) {
    // The board to compare against for simple-ko: the in-progress board state
    // immediately before the opponent's most recent move. Available only when
    // the log carries at least two in-progress states.
    Board? koCompareBoard;
    if (log != null) {
      final inProgress = log.states.where((s) => s.outcome == null).toList();
      if (inProgress.length >= 2) {
        koCompareBoard = inProgress[inProgress.length - 2].board;
      }
    }

    final moves = <int>[];
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        if (board.get(r, c) != 0) continue;
        final trial = board.copy();
        trial.set(r, c, side);
        _captureAdjacentEnemyGroups(trial, r, c, side);
        if (_floodGroup(trial, r, c).liberties == 0) continue; // suicide
        if (koCompareBoard != null && trial == koCompareBoard) continue; // ko
        moves.add(r * size + c);
      }
    }
    moves.add(passMove);
    return moves;
  }

  @override
  Board applyMove(Board board, int move, int side) {
    final result = board.copy();
    if (move == passMove) return result;
    final r = move ~/ size;
    final c = move % size;
    if (result.get(r, c) != 0) {
      throw ArgumentError('Intersection ($r, $c) is occupied');
    }
    result.set(r, c, side);
    _captureAdjacentEnemyGroups(result, r, c, side);
    return result;
  }

  /// Go has no auto-win on the board alone; termination is always a log-level
  /// concept (two consecutive passes). Always returns null.
  @override
  int? checkWinner(Board board) => null;

  @override
  bool isTerminal(Board board, {GameLog? log}) {
    if (log == null) return false;
    final inProgress = log.states.where((s) => s.outcome == null).toList();
    if (inProgress.length < 2) return false;
    return inProgress[inProgress.length - 1].movePlayed == passMove &&
        inProgress[inProgress.length - 2].movePlayed == passMove;
  }

  @override
  int finalOutcome(Board board) {
    final score = areaScore(board);
    if (score.white > score.black) return 1;
    if (score.white < score.black) return -1;
    return 0;
  }

  /// Chinese-style area score for the given board. Each side's count is
  /// stones-on-board plus empty intersections whose connected region touches
  /// only that side's stones. Empty regions touching both colours (dame)
  /// score for neither. Public so the UI can surface a running tally
  /// mid-game; the result on a partial board is noisy (most of the empty
  /// space is dame) but the trend is meaningful.
  ({int white, int black}) areaScore(Board board) => _areaScore(board);

  /// True iff playing `move` for `side` would land in an empty region that
  /// is bounded only by `side`-coloured stones (own enclosed territory or an
  /// own-eye). Used by the brain layer as a sanity gate after the opponent
  /// has just passed: if the only "good" move on the heatmap is to fill our
  /// own territory, we'd rather pass too. Pass moves and occupied cells
  /// always return false.
  bool isOwnEnclosedTerritory(Board board, int move, int side) {
    if (isPassMove(move)) return false;
    final r = move ~/ size;
    final c = move % size;
    if (r < 0 || r >= size || c < 0 || c >= size) return false;
    if (board.get(r, c) != 0) return false;
    final visited = <int>{};
    final stack = <(int, int)>[(r, c)];
    var touchesEnemy = false;
    var touchesOwn = false;
    while (stack.isNotEmpty) {
      final pos = stack.removeLast();
      final cr = pos.$1;
      final cc = pos.$2;
      if (cr < 0 || cr >= size || cc < 0 || cc >= size) continue;
      final v = board.get(cr, cc);
      if (v == side) {
        touchesOwn = true;
        continue;
      }
      if (v == -side) {
        touchesEnemy = true;
        continue;
      }
      final key = cr * size + cc;
      if (visited.contains(key)) continue;
      visited.add(key);
      stack.add((cr - 1, cc));
      stack.add((cr + 1, cc));
      stack.add((cr, cc - 1));
      stack.add((cr, cc + 1));
    }
    return touchesOwn && !touchesEnemy;
  }

  /// Flood-fill the same-colour group containing `(r, c)`. Returns the cells
  /// of the group (as flat indices `r * size + c`) and the count of distinct
  /// liberty intersections. The starting cell SHALL be non-empty.
  ({Set<int> cells, int liberties}) _floodGroup(Board board, int r, int c) {
    final colour = board.get(r, c);
    final cells = <int>{};
    final liberties = <int>{};
    final stack = <(int, int)>[(r, c)];
    while (stack.isNotEmpty) {
      final pos = stack.removeLast();
      final cr = pos.$1;
      final cc = pos.$2;
      if (cr < 0 || cr >= size || cc < 0 || cc >= size) continue;
      final key = cr * size + cc;
      if (cells.contains(key)) continue;
      final v = board.get(cr, cc);
      if (v == 0) {
        liberties.add(key);
        continue;
      }
      if (v != colour) continue;
      cells.add(key);
      stack.add((cr - 1, cc));
      stack.add((cr + 1, cc));
      stack.add((cr, cc - 1));
      stack.add((cr, cc + 1));
    }
    return (cells: cells, liberties: liberties.length);
  }

  /// For each of the four neighbours of `(r, c)`, if it holds an opposing-side
  /// stone, flood-fill its group and remove it if liberties are zero. Mutates
  /// the board in place. Returns the count of stones removed.
  int _captureAdjacentEnemyGroups(Board board, int r, int c, int side) {
    final enemy = -side;
    var captured = 0;
    const offsets = [
      [-1, 0],
      [1, 0],
      [0, -1],
      [0, 1],
    ];
    for (final off in offsets) {
      final nr = r + off[0];
      final nc = c + off[1];
      if (nr < 0 || nr >= size || nc < 0 || nc >= size) continue;
      if (board.get(nr, nc) != enemy) continue;
      final group = _floodGroup(board, nr, nc);
      if (group.liberties == 0) {
        for (final cell in group.cells) {
          board.set(cell ~/ size, cell % size, 0);
        }
        captured += group.cells.length;
      }
    }
    return captured;
  }

  ({int white, int black}) _areaScore(Board board) {
    var white = 0;
    var black = 0;
    final visited = List.generate(size, (_) => List.filled(size, false));
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        final v = board.get(r, c);
        if (v == 1) {
          white++;
          continue;
        }
        if (v == -1) {
          black++;
          continue;
        }
        if (visited[r][c]) continue;
        // Empty cell, not yet visited: flood-fill the empty region.
        var touchesWhite = false;
        var touchesBlack = false;
        var regionSize = 0;
        final stack = <(int, int)>[(r, c)];
        while (stack.isNotEmpty) {
          final pos = stack.removeLast();
          final er = pos.$1;
          final ec = pos.$2;
          if (er < 0 || er >= size || ec < 0 || ec >= size) continue;
          if (visited[er][ec]) continue;
          final ev = board.get(er, ec);
          if (ev == 1) {
            touchesWhite = true;
            continue;
          }
          if (ev == -1) {
            touchesBlack = true;
            continue;
          }
          visited[er][ec] = true;
          regionSize++;
          stack.add((er - 1, ec));
          stack.add((er + 1, ec));
          stack.add((er, ec - 1));
          stack.add((er, ec + 1));
        }
        if (touchesWhite && !touchesBlack) {
          white += regionSize;
        } else if (touchesBlack && !touchesWhite) {
          black += regionSize;
        }
        // Otherwise dame (touches both, or neither on a fully-empty board).
      }
    }
    return (white: white, black: black);
  }
}

/// Accept candidates whose ply differs from the query's by at most `window`.
/// Mirrors `ConnectFourFilter`; Go starts with a wider initial window (4 vs
/// CF's 2) because game length is much longer and per-ply structural change
/// is smaller.
class GoFilter implements CandidateFilter {
  final int queryPly;
  final int window;
  const GoFilter(this.queryPly, this.window);

  @override
  bool matches(GameState candidate) =>
      (candidate.ply - queryPly).abs() <= window;

  @override
  CandidateFilter widened() => GoFilter(queryPly, window == 0 ? 1 : window * 2);
}

/// Score an intersection move by its heatmap value at `(r, c)`. The pass move
/// scores at a small fixed positive value so the brain prefers any positive
/// placement but falls back to passing rather than to the chaotic personality
/// when no placement scores positively.
class GoMoveScorer implements MoveScorer {
  final int size;
  static const double passScore = 0.01;

  const GoMoveScorer(this.size);

  @override
  double scoreMove(int move, Board currentBoard, List<List<double>> heatmap) {
    if (move == size * size) return passScore;
    final r = move ~/ size;
    final c = move % size;
    return heatmap[r][c];
  }
}

/// Diffuses stone influence along the four orthogonal directions only. Go's
/// connectivity is 4-neighbour; diagonal influence would over-claim corners
/// because diagonally-adjacent stones are not connected groups.
class GoDiffusionKernel implements DiffusionKernel {
  /// Orthogonal axes; each iterates with `[+1, -1]` to reach both neighbours
  /// along the axis.
  static const _axes = [
    [0, 1], // horizontal
    [1, 0], // vertical
  ];

  static const _attenuation = 0.5;

  const GoDiffusionKernel();

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
          for (final axis in _axes) {
            for (final sign in const [1, -1]) {
              final nr = r + axis[0] * sign;
              final nc = c + axis[1] * sign;
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
