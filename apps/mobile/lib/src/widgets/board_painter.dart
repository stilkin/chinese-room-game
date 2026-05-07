import 'package:flutter/material.dart';
import 'package:game_engine/game_engine.dart';

const _kBoardColor = Color(0xFF1F4FA8);
const _kEmptyColor = Color(0xFFE8ECF1);
const _kPlayerColor = Color(0xFFE53935);
const _kCloneColor = Color(0xFFFBC02D);

class BoardPainter extends CustomPainter {
  final Board board;

  BoardPainter(this.board);

  @override
  void paint(Canvas canvas, Size size) {
    final cellSize = size.width / board.cols;
    final boardHeight = cellSize * board.rows;

    final bgPaint = Paint()..color = _kBoardColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, boardHeight), bgPaint);

    final radius = cellSize * 0.4;
    for (var r = 0; r < board.rows; r++) {
      for (var c = 0; c < board.cols; c++) {
        final cx = c * cellSize + cellSize / 2;
        final cy = r * cellSize + cellSize / 2;
        final paint = Paint()..color = _colorFor(board.get(r, c));
        canvas.drawCircle(Offset(cx, cy), radius, paint);
      }
    }
  }

  Color _colorFor(int v) {
    switch (v) {
      case 1:
        return _kPlayerColor;
      case -1:
        return _kCloneColor;
      default:
        return _kEmptyColor;
    }
  }

  @override
  bool shouldRepaint(BoardPainter oldDelegate) => oldDelegate.board != board;
}

int? columnFromTap(Offset localPos, Size size, int cols) {
  if (localPos.dx < 0 || localPos.dx >= size.width) return null;
  if (localPos.dy < 0) return null;
  final cellSize = size.width / cols;
  final col = (localPos.dx / cellSize).floor();
  if (col < 0 || col >= cols) return null;
  return col;
}
