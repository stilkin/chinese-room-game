import 'dart:typed_data';

import 'board.dart';

abstract class DiffusionKernel {
  List<List<double>> diffuse(Board board, {int steps = 2});
}

/// Quantize a real-valued influence map to one signed byte per cell, packed
/// row-major. Each cell is rounded to the nearest integer and clamped to the
/// Int8 range [-128, 127]. For Connect Four (piece values ±1, 2 diffusion
/// steps at attenuation 0.5) influence stays comfortably inside Int8 — no
/// scale factor needed. Chess will need its own scale when it arrives.
Int8List quantizeInfluenceMap(List<List<double>> influenceMap) {
  final rows = influenceMap.length;
  final cols = influenceMap[0].length;
  final result = Int8List(rows * cols);
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      var v = influenceMap[r][c].round();
      if (v > 127) v = 127;
      if (v < -128) v = -128;
      result[r * cols + c] = v;
    }
  }
  return result;
}
