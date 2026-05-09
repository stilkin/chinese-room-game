import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_ying/src/widgets/board_painter.dart';

void main() {
  const size = Size(700, 600);
  const cols = 7;

  test('left edge maps to column 0', () {
    expect(columnFromTap(const Offset(0, 100), size, cols), 0);
  });

  test('center column 3 captures middle taps', () {
    expect(columnFromTap(const Offset(350, 300), size, cols), 3);
  });

  test('right edge maps to column 6', () {
    expect(columnFromTap(const Offset(699, 100), size, cols), 6);
  });

  test('out-of-bounds horizontal returns null', () {
    expect(columnFromTap(const Offset(-1, 100), size, cols), isNull);
    expect(columnFromTap(const Offset(700, 100), size, cols), isNull);
  });

  test('negative y returns null', () {
    expect(columnFromTap(const Offset(100, -1), size, cols), isNull);
  });

  test('column boundaries are exclusive on the right', () {
    final cellWidth = size.width / cols;
    expect(columnFromTap(Offset(cellWidth - 0.001, 100), size, cols), 0);
    expect(columnFromTap(Offset(cellWidth, 100), size, cols), 1);
  });
}
