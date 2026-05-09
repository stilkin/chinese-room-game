import 'package:flutter/material.dart';
import 'package:game_engine/game_engine.dart';

import '../theme.dart';

const _kBoardColor = PiYingTheme.surface;
const _kBoardOutline = PiYingTheme.yellow;
const _kEmptyColor = PiYingTheme.surfaceLow; // empty hole — deeper than panel
const _kPlayerColor = PiYingTheme.red;
const _kCloneColor = PiYingTheme.yellow;

/// Renders the Connect Four board: a chunky panel with circular holes, a
/// chip in each occupied cell, and an optional winning-line highlight.
///
/// Two affordances for animation:
///   - [excludeRow]/[excludeCol]: skip drawing the chip at that cell so the
///     game screen can render it as an animated overlay falling into place.
///   - [winningCells]: when non-null, draws a bright outline around each
///     given cell to celebrate the four-in-a-row.
class BoardPainter extends CustomPainter {
  final Board board;
  final int? excludeRow;
  final int? excludeCol;
  final List<({int row, int col})>? winningCells;

  BoardPainter(
    this.board, {
    this.excludeRow,
    this.excludeCol,
    this.winningCells,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cellSize = size.width / board.cols;
    final boardHeight = cellSize * board.rows;
    final boardRect = Rect.fromLTWH(0, 0, size.width, boardHeight);

    // Board panel background.
    canvas.drawRect(boardRect, Paint()..color = _kBoardColor);

    // Board outline — chunky 2px amber border, matching theme's button stroke.
    canvas.drawRect(
      boardRect,
      Paint()
        ..color = _kBoardOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final radius = cellSize * 0.4;

    // Empty holes first (so chips render on top with shadow).
    final holePaint = Paint()..color = _kEmptyColor;
    for (var r = 0; r < board.rows; r++) {
      for (var c = 0; c < board.cols; c++) {
        if (board.get(r, c) != 0) continue;
        final cx = c * cellSize + cellSize / 2;
        final cy = r * cellSize + cellSize / 2;
        canvas.drawCircle(Offset(cx, cy), radius, holePaint);
      }
    }

    // Chips with gloss + drop shadow.
    for (var r = 0; r < board.rows; r++) {
      for (var c = 0; c < board.cols; c++) {
        final v = board.get(r, c);
        if (v == 0) continue;
        if (excludeRow == r && excludeCol == c) continue;
        final cx = c * cellSize + cellSize / 2;
        final cy = r * cellSize + cellSize / 2;
        _paintChip(canvas, Offset(cx, cy), radius, v);
      }
    }

    // Winning-line highlight on top of everything. We draw a thick ring +
    // a softer outer halo so the four cells clearly read as "the winner",
    // not just decoration.
    final w = winningCells;
    if (w != null) {
      final ringPaint = Paint()
        ..color = PiYingTheme.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4;
      final haloPaint = Paint()
        ..color = PiYingTheme.blue.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      for (final cell in w) {
        final cx = cell.col * cellSize + cellSize / 2;
        final cy = cell.row * cellSize + cellSize / 2;
        canvas.drawCircle(Offset(cx, cy), radius + 3, haloPaint);
        canvas.drawCircle(Offset(cx, cy), radius + 3, ringPaint);
      }
    }
  }

  /// Render a single chip with a soft drop-shadow and a subtle radial gloss.
  /// Intended to feel like a checkers chip / arcade token under spot lighting.
  static void _paintChip(
    Canvas canvas,
    Offset center,
    double radius,
    int side,
  ) {
    final base = side == 1 ? _kPlayerColor : _kCloneColor;

    // Drop shadow — slightly offset, slightly larger, dark.
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(center.translate(0, 2), radius + 1, shadow);

    // Body — radial gradient from a slightly lighter top-left to the base.
    final gradient = RadialGradient(
      center: const Alignment(-0.4, -0.4),
      radius: 0.9,
      colors: [_lighten(base, 0.25), base],
      stops: const [0.0, 0.85],
    );
    final bodyPaint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      );
    canvas.drawCircle(center, radius, bodyPaint);

    // Inner outline — keeps the chip's edge crisp against any background.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = _darken(base, 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Highlight gloss — small white-ish ellipse on the upper-left.
    final glossRect = Rect.fromCenter(
      center: center.translate(-radius * 0.3, -radius * 0.4),
      width: radius * 0.9,
      height: radius * 0.45,
    );
    final glossPaint = Paint()..color = Colors.white.withValues(alpha: 0.22);
    canvas.drawOval(glossRect, glossPaint);
  }

  static Color _lighten(Color c, double amount) =>
      Color.lerp(c, Colors.white, amount)!;
  static Color _darken(Color c, double amount) =>
      Color.lerp(c, Colors.black, amount)!;

  /// Convenience for the game screen's animated overlay: render a single
  /// chip at an arbitrary point (used while the latest piece falls into place).
  static void paintFloatingChip(
    Canvas canvas,
    Offset center,
    double radius,
    int side,
  ) {
    _paintChip(canvas, center, radius, side);
  }

  @override
  bool shouldRepaint(BoardPainter old) => true;
}

int? columnFromTap(Offset localPos, Size size, int cols) {
  if (localPos.dx < 0 || localPos.dx >= size.width) return null;
  if (localPos.dy < 0) return null;
  final cellSize = size.width / cols;
  final col = (localPos.dx / cellSize).floor();
  if (col < 0 || col >= cols) return null;
  return col;
}

/// Returns the visual cell size in logical pixels given the board's pixel
/// width and the column count. Centralized so the widget and the painter
/// agree.
double cellSizeFor(double widgetWidth, int cols) => widgetWidth / cols;
