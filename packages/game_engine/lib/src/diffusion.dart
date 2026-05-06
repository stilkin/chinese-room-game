import 'board.dart';

abstract class DiffusionKernel {
  List<List<double>> diffuse(Board board, {int steps = 2});
}

List<int> influenceMapToBitHash(List<List<double>> influenceMap) {
  final rows = influenceMap.length;
  final cols = influenceMap[0].length;
  final totalBits = rows * cols;
  final numInts = (totalBits + 63) ~/ 64;
  final result = List.filled(numInts, 0);

  var bitIndex = 0;
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      if (influenceMap[r][c] > 0) {
        final intIndex = bitIndex ~/ 64;
        final bitOffset = bitIndex % 64;
        result[intIndex] |= 1 << bitOffset;
      }
      bitIndex++;
    }
  }
  return result;
}
