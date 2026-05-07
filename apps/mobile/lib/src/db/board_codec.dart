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

Uint8List hashListToBlob(List<int> hashes) {
  final bytes = ByteData(hashes.length * 8);
  for (var i = 0; i < hashes.length; i++) {
    bytes.setInt64(i * 8, hashes[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}

List<int> hashListFromBlob(Uint8List blob) {
  final bytes = ByteData.sublistView(blob);
  final count = blob.length ~/ 8;
  return List<int>.generate(count, (i) => bytes.getInt64(i * 8, Endian.little));
}
