import 'package:flutter/material.dart';
import 'package:game_engine/game_engine.dart';

import '../theme.dart';

const _kBoardBackground = PiYingTheme.surface;
const _kLineColor = PiYingTheme.yellow;
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
/// The widget is presentation-only: legality is enforced upstream by
/// [GameNotifier.playerMove], which ignores illegal candidates. The widget
/// just emits any intersection within the hit radius of a tap.
class GoBoard extends StatelessWidget {
  final Board board;

  /// `(lastMoveRow, lastMoveCol)` highlights the most recent placement with a
  /// small ring. Use `-1` for either to skip the highlight (e.g. on a pass).
  final int lastMoveRow;
  final int lastMoveCol;

  /// Called when the user taps within the hit radius of an intersection.
  /// The argument is the move integer `r * cols + c`. The widget never emits
  /// a pass move; pass is wired through a separate UI control.
  final void Function(int move)? onTap;

  const GoBoard({
    super.key,
    required this.board,
    this.lastMoveRow = -1,
    this.lastMoveCol = -1,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Square board: take the smaller dimension. The painter handles the
        // margin internally so external layout just provides a square slot.
        final side = constraints.maxWidth.clamp(0.0, constraints.maxHeight);
        return GestureDetector(
          onTapUp: (details) {
            final cb = onTap;
            if (cb == null) return;
            final move = intersectionFromTap(
              details.localPosition,
              Size(side, side),
              board.cols,
            );
            if (move != null) cb(move);
          },
          child: SizedBox(
            width: side,
            height: side,
            child: CustomPaint(
              painter: _GoBoardPainter(
                board: board,
                lastMoveRow: lastMoveRow,
                lastMoveCol: lastMoveCol,
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

  _GoBoardPainter({
    required this.board,
    required this.lastMoveRow,
    required this.lastMoveCol,
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

    // Stones.
    final stoneRadius = geom.cellSize * 0.45;
    for (var r = 0; r < board.rows; r++) {
      for (var c = 0; c < board.cols; c++) {
        final v = board.get(r, c);
        if (v == 0) continue;
        _paintStone(
          canvas,
          Offset(geom.intersectionX(c), geom.intersectionY(r)),
          stoneRadius,
          v,
        );
      }
    }

    // Last-move marker: a thin ring of contrasting colour over the most
    // recent placement. Skipped when the most recent move was a pass
    // (sentinel `-1`).
    if (lastMoveRow >= 0 && lastMoveCol >= 0) {
      canvas.drawCircle(
        Offset(
          geom.intersectionX(lastMoveCol),
          geom.intersectionY(lastMoveRow),
        ),
        stoneRadius * 0.55,
        Paint()
          ..color = PiYingTheme.blue
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
    final base = side == 1 ? _kPlayerStone : _kCloneStone;

    // Drop shadow for visual depth; matches the CF chip style.
    canvas.drawCircle(
      center.translate(0, 1.5),
      radius + 0.5,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // Body: radial gradient from a slightly lighter top-left to the base.
    final gradient = RadialGradient(
      center: const Alignment(-0.4, -0.4),
      radius: 0.9,
      colors: [Color.lerp(base, Colors.white, 0.25)!, base],
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

    // Crisp edge. For dark stones we lighten the outline so the silhouette
    // separates from the dark board; for light stones we darken it so the
    // edge reads cleanly.
    final outline = side == 1
        ? Color.lerp(base, Colors.black, 0.3)!
        : Color.lerp(base, Colors.white, 0.45)!;
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
