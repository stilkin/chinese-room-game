import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_ying/src/widgets/go_board.dart';

void main() {
  // Layout convention used by `intersectionFromTap`:
  //   cell = size.width / cols
  //   margin = cell / 2  (half-cell on each side)
  //   intersection (r, c) at (margin + c*cell, margin + r*cell)
  //
  // For a 13×13 board on a 130×130 widget: cell = 10, margin = 5,
  // intersections from (5, 5) to (125, 125) at 10px steps.
  const cols = 13;
  const size = Size(130, 130);

  test('exact-centre tap returns the centre intersection move int', () {
    // Centre of 13×13 is (6, 6) → pixel (5 + 6*10, 5 + 6*10) = (65, 65).
    final move = intersectionFromTap(const Offset(65, 65), size, cols);
    expect(move, 6 * 13 + 6);
  });

  test('tap on the top-left intersection returns move 0', () {
    final move = intersectionFromTap(const Offset(5, 5), size, cols);
    expect(move, 0);
  });

  test('tap on the bottom-right intersection returns move cols*cols - 1', () {
    // (12, 12) → pixel (125, 125).
    final move = intersectionFromTap(const Offset(125, 125), size, cols);
    expect(move, 12 * 13 + 12);
  });

  test('tap slightly off an intersection still snaps within hit radius', () {
    // 3px off centre is well within `cell * 0.4` = 4 on a 10px cell.
    final move = intersectionFromTap(const Offset(68, 67), size, cols);
    expect(move, 6 * 13 + 6);
  });

  test('tap mid-gutter (outside hit radius) returns null', () {
    // Halfway between (6, 6) and (6, 7): pixel (70, 65). Distance to either
    // intersection is 5px, beyond the 4px hit radius.
    final move = intersectionFromTap(const Offset(70, 65), size, cols);
    expect(move, isNull);
  });

  test('tap entirely outside the board returns null', () {
    expect(intersectionFromTap(const Offset(-10, -10), size, cols), isNull);
    expect(intersectionFromTap(const Offset(200, 200), size, cols), isNull);
  });

  test('zero-width size returns null gracefully', () {
    expect(intersectionFromTap(const Offset(5, 5), Size.zero, cols), isNull);
  });
}
