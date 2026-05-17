import 'package:flutter/material.dart';
import 'package:game_engine/game_engine.dart';

import '../theme.dart';

const _kBoardBackground = PiYingTheme.boardPanel;
const _kLineColor = PiYingTheme.lineColor;
// Player and clone stones approximate Go's white/black convention. The board
// is dark, so the "black" stone is rendered as a near-black with a lighter
// outline ring to keep it readable against the surface.
const _kPlayerStone = PiYingTheme.onSurface; // warm ivory "white"
const _kCloneStone = Color(0xFF0E0E14); // near-black

/// Standard 13×13 star points (hoshi), spaced as a 3×3 grid of dots.
const _k13x13StarPoints = [
  (3, 3),
  (3, 6),
  (3, 9),
  (6, 3),
  (6, 6),
  (6, 9),
  (9, 3),
  (9, 6),
  (9, 9),
];

/// Renders a Go board as a grid of intersections with stones placed on
/// vertices. Tap an intersection to emit its move-int via [onTap].
///
/// Placement of the last move animates: the stone grows from half-size to
/// full size over [animationDuration] with an ease-out curve. Any stones
/// captured by that same move animate the inverse — shrinking out as the
/// new stone settles. Multi-cell board transitions that don't match
/// "one placement + zero or more captures from that placement" snap
/// instantly (so slider scrubbing in the replay viewer doesn't trigger
/// dozens of overlapping animations).
class GoBoard extends StatefulWidget {
  final Board board;

  /// `(lastMoveRow, lastMoveCol)` highlights the most recent placement with a
  /// small ring and triggers the placement animation. Use `-1` for either to
  /// skip (e.g. on a pass or the initial empty board).
  final int lastMoveRow;
  final int lastMoveCol;

  /// Called when the user taps within the hit radius of an intersection.
  /// The argument is the move integer `r * cols + c`. The widget never emits
  /// a pass move; pass is wired through a separate UI control. Pass `null`
  /// (the default) for a read-only board.
  final void Function(int move)? onTap;

  /// Duration of the stone placement / capture animation. Defaults to 120ms
  /// — long enough to feel physical, short enough to stay out of the way at
  /// 1× replay (600ms per move). Replay screen passes a shorter 60ms when
  /// playing at 2× and above so animations stay non-overlapping.
  final Duration animationDuration;

  const GoBoard({
    super.key,
    required this.board,
    this.lastMoveRow = -1,
    this.lastMoveCol = -1,
    this.onTap,
    this.animationDuration = const Duration(milliseconds: 120),
  });

  @override
  State<GoBoard> createState() => _GoBoardState();
}

enum _AnimKind { placement, capture }

class _StoneAnim {
  final AnimationController controller;
  final _AnimKind kind;
  final int side; // colour to draw — frozen at animation start

  _StoneAnim({
    required this.controller,
    required this.kind,
    required this.side,
  });

  /// Eased animation progress in `[0, 1]`.
  double get t => kind == _AnimKind.placement
      ? Curves.easeOutCubic.transform(controller.value)
      : Curves.easeInCubic.transform(controller.value);
}

class _GoBoardState extends State<GoBoard> with TickerProviderStateMixin {
  // Active animations keyed by `row * cols + col`.
  final Map<int, _StoneAnim> _anims = {};

  @override
  void didUpdateWidget(GoBoard old) {
    super.didUpdateWidget(old);
    if (old.board != widget.board) {
      _onBoardChanged(old.board, widget.board);
    }
  }

  void _onBoardChanged(Board oldBoard, Board newBoard) {
    if (oldBoard.rows != newBoard.rows || oldBoard.cols != newBoard.cols) {
      // Board dimensions changed (e.g. game-mode switch). Snap.
      _cancelAllAnims();
      return;
    }
    final cols = newBoard.cols;
    final lastR = widget.lastMoveRow;
    final lastC = widget.lastMoveCol;

    int? placementKey;
    final captures = <(int, int)>[]; // (key, captured side)
    var newStoneCount = 0;

    for (var r = 0; r < newBoard.rows; r++) {
      for (var c = 0; c < cols; c++) {
        final ov = oldBoard.get(r, c);
        final nv = newBoard.get(r, c);
        if (ov == 0 && nv != 0) {
          newStoneCount++;
          if (r == lastR && c == lastC) {
            placementKey = r * cols + c;
          }
        } else if (ov != 0 && nv == 0) {
          captures.add((r * cols + c, ov));
        }
      }
    }

    // A normal placement: exactly one new stone, at the lastMove intersection,
    // plus zero or more captures from that move.
    final isPlacement = newStoneCount == 1 && placementKey != null;
    // A pass: no new stones, no captures, lastMove is sentinel.
    final isPass = newStoneCount == 0 && captures.isEmpty;

    if (!isPlacement && !isPass) {
      // Slider scrub / jump / multi-step transition. Snap and bail.
      _cancelAllAnims();
      return;
    }

    if (placementKey != null) {
      _disposeAnim(placementKey);
      final side = newBoard.get(placementKey ~/ cols, placementKey % cols);
      _startAnim(placementKey, _AnimKind.placement, side);
    }
    for (final cap in captures) {
      _disposeAnim(cap.$1);
      _startAnim(cap.$1, _AnimKind.capture, cap.$2);
    }
  }

  void _startAnim(int key, _AnimKind kind, int side) {
    final ctrl = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _anims[key] = _StoneAnim(controller: ctrl, kind: kind, side: side);
    ctrl.addListener(() {
      if (mounted) setState(() {});
    });
    ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _disposeAnim(key));
      }
    });
    ctrl.forward();
  }

  void _disposeAnim(int key) {
    final a = _anims.remove(key);
    a?.controller.dispose();
  }

  void _cancelAllAnims() {
    for (final a in _anims.values) {
      a.controller.dispose();
    }
    _anims.clear();
  }

  @override
  void dispose() {
    _cancelAllAnims();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Square board: take the smaller dimension. The painter handles the
        // margin internally so external layout just provides a square slot.
        final side = constraints.maxWidth.clamp(0.0, constraints.maxHeight);
        return GestureDetector(
          onTapUp: (details) {
            final cb = widget.onTap;
            if (cb == null) return;
            final move = intersectionFromTap(
              details.localPosition,
              Size(side, side),
              widget.board.cols,
            );
            if (move != null) cb(move);
          },
          child: SizedBox(
            width: side,
            height: side,
            child: CustomPaint(
              painter: _GoBoardPainter(
                board: widget.board,
                lastMoveRow: widget.lastMoveRow,
                lastMoveCol: widget.lastMoveCol,
                anims: _anims,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GoBoardPainter extends CustomPainter {
  final Board board;
  final int lastMoveRow;
  final int lastMoveCol;
  final Map<int, _StoneAnim> anims;

  _GoBoardPainter({
    required this.board,
    required this.lastMoveRow,
    required this.lastMoveCol,
    required this.anims,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final geom = _Geometry.of(size, board.cols);

    // Background panel.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = _kBoardBackground,
    );

    // Grid lines: 13 horizontals + 13 verticals from the first to the last
    // intersection. Drawn at 1.5px to read crisp on retro-themed surface.
    final linePaint = Paint()
      ..color = _kLineColor
      ..strokeWidth = 1.5;
    final firstX = geom.intersectionX(0);
    final lastX = geom.intersectionX(board.cols - 1);
    final firstY = geom.intersectionY(0);
    final lastY = geom.intersectionY(board.rows - 1);
    for (var i = 0; i < board.rows; i++) {
      final y = geom.intersectionY(i);
      canvas.drawLine(Offset(firstX, y), Offset(lastX, y), linePaint);
    }
    for (var i = 0; i < board.cols; i++) {
      final x = geom.intersectionX(i);
      canvas.drawLine(Offset(x, firstY), Offset(x, lastY), linePaint);
    }

    // Star points (hoshi). Only configured for 13×13; other sizes get no dots
    // — acceptable since 13×13 is the only shipping configuration.
    if (board.rows == 13 && board.cols == 13) {
      final dotPaint = Paint()..color = _kLineColor;
      for (final star in _k13x13StarPoints) {
        canvas.drawCircle(
          Offset(geom.intersectionX(star.$2), geom.intersectionY(star.$1)),
          geom.cellSize * 0.08,
          dotPaint,
        );
      }
    }

    final stoneRadius = geom.cellSize * 0.45;

    // Stones currently on the board. If a cell has an in-flight placement
    // animation, scale its radius accordingly (0.5 → 1.0).
    for (var r = 0; r < board.rows; r++) {
      for (var c = 0; c < board.cols; c++) {
        final v = board.get(r, c);
        if (v == 0) continue;
        final key = r * board.cols + c;
        final anim = anims[key];
        var radius = stoneRadius;
        if (anim != null && anim.kind == _AnimKind.placement) {
          radius = stoneRadius * (0.5 + 0.5 * anim.t);
        }
        _paintStone(
          canvas,
          Offset(geom.intersectionX(c), geom.intersectionY(r)),
          radius,
          v,
        );
      }
    }

    // Capture animations: stones that have left the board but are still
    // shrinking out. Scale shrinks 1.0 → 0.0; the stone vanishes naturally.
    for (final entry in anims.entries) {
      final a = entry.value;
      if (a.kind != _AnimKind.capture) continue;
      final r = entry.key ~/ board.cols;
      final c = entry.key % board.cols;
      final radius = stoneRadius * (1.0 - a.t);
      if (radius < 0.5) continue;
      _paintStone(
        canvas,
        Offset(geom.intersectionX(c), geom.intersectionY(r)),
        radius,
        a.side,
      );
    }

    // Last-move marker: a thin ring of contrasting colour over the most
    // recent placement. Skipped when the most recent move was a pass
    // (sentinel `-1`). Drawn instantly (not animated) — it's a marker, not
    // a placement.
    if (lastMoveRow >= 0 && lastMoveCol >= 0) {
      canvas.drawCircle(
        Offset(
          geom.intersectionX(lastMoveCol),
          geom.intersectionY(lastMoveRow),
        ),
        stoneRadius * 0.55,
        Paint()
          ..color = PiYingTheme.cinnabar
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  static void _paintStone(
    Canvas canvas,
    Offset center,
    double radius,
    int side,
  ) {
    if (radius <= 0) return;
    final base = side == 1 ? _kPlayerStone : _kCloneStone;

    // Drop shadow for visual depth; matches the CF chip style.
    canvas.drawCircle(
      center.translate(0, 1.5),
      radius + 0.5,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // Body. Player (ivory) stones get a 3-stop gradient (bright highlight →
    // base → subtle warm shadow at the lower-right edge) so they read as
    // domed clamshell rather than flat circles. Clone (dark) stones use a
    // 2-stop highlight-to-base gradient — black slate is visually flatter
    // in real Go too, so a single highlight hint is enough.
    final gradient = side == 1
        ? RadialGradient(
            center: const Alignment(-0.4, -0.4),
            radius: 1.0,
            colors: [
              Color.lerp(base, Colors.white, 0.35)!,
              base,
              Color.lerp(base, Colors.black, 0.18)!,
            ],
            stops: const [0.0, 0.55, 1.0],
          )
        : RadialGradient(
            center: const Alignment(-0.4, -0.4),
            radius: 0.9,
            colors: [Color.lerp(base, Colors.white, 0.3)!, base],
            stops: const [0.0, 0.85],
          );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = gradient.createShader(
          Rect.fromCircle(center: center, radius: radius),
        ),
    );

    // Crisp edge. For dark stones the outline used to be lerp 0.45 toward
    // white, which read as a too-prominent grey ring. Dropping to 0.18
    // keeps the silhouette but lets the dark body dominate.
    final outline = side == 1
        ? Color.lerp(base, Colors.black, 0.3)!
        : Color.lerp(base, Colors.white, 0.18)!;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(_GoBoardPainter old) => true;
}

/// Layout helper: a Go board's playable area covers `size - 1` cell-widths
/// (between the outermost lines), with a half-cell margin on each side.
/// The visual board is square; the painter caller passes a square Size.
class _Geometry {
  final double cellSize;
  final double margin;

  const _Geometry._(this.cellSize, this.margin);

  factory _Geometry.of(Size size, int cols) {
    // `cols` intersections need `cols - 1` intervals between them. Half-cell
    // margin on each side so stones at edges aren't clipped.
    final available = size.width;
    final cell = available / cols;
    final margin = cell / 2;
    return _Geometry._(cell, margin);
  }

  double intersectionX(int col) => margin + col * cellSize;
  double intersectionY(int row) => margin + row * cellSize;
}

/// Returns the move-int for the intersection nearest to [localPos], or null
/// if no intersection is within `cellSize * 0.4` of the tap. Coordinates are
/// in the painter's local space (origin at top-left of the square Size).
int? intersectionFromTap(Offset localPos, Size size, int cols) {
  if (size.width <= 0) return null;
  final cell = size.width / cols;
  final margin = cell / 2;
  if (cell <= 0) return null;
  // Nearest intersection by row/col. Round to handle taps slightly past the
  // outer line; clamp to valid range.
  final col = ((localPos.dx - margin) / cell).round();
  final row = ((localPos.dy - margin) / cell).round();
  if (row < 0 || row >= cols || col < 0 || col >= cols) return null;
  // Hit-radius gate: distance from tap to chosen intersection must be within
  // 40% of a cell. Filters out taps in the gutters between intersections.
  final ix = margin + col * cell;
  final iy = margin + row * cell;
  final dx = localPos.dx - ix;
  final dy = localPos.dy - iy;
  if (dx * dx + dy * dy > (cell * 0.4) * (cell * 0.4)) return null;
  return row * cols + col;
}
