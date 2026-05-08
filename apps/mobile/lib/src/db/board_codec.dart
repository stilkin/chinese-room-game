import 'dart:typed_data';

import 'package:game_engine/game_engine.dart';

Uint8List boardToBlob(Board board) {
  return Uint8List.fromList(board.flat);
}

Board boardFromBlob(int rows, int cols, Uint8List blob) {
  final signed = blob.buffer.asInt8List(blob.offsetInBytes, blob.length);
  final cells = List.generate(
    rows,
    (r) => List<int>.generate(cols, (c) => signed[r * cols + c]),
  );
  return Board.from(cells);
}
