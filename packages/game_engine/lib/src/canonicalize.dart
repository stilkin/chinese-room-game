import 'board.dart';
import 'zobrist.dart';

class CanonicalResult {
  final Board board;
  final int zobristHash;
  final bool wasMirrored;
  final bool wasPerspectiveFlipped;

  CanonicalResult({
    required this.board,
    required this.zobristHash,
    this.wasMirrored = false,
    this.wasPerspectiveFlipped = false,
  });
}

Board mirror(Board board) {
  final result = Board(board.rows, board.cols);
  for (var r = 0; r < board.rows; r++) {
    for (var c = 0; c < board.cols; c++) {
      result.set(r, board.cols - 1 - c, board.get(r, c));
    }
  }
  return result;
}

Board flipPerspective(Board board) {
  final result = Board(board.rows, board.cols);
  for (var r = 0; r < board.rows; r++) {
    for (var c = 0; c < board.cols; c++) {
      result.set(r, c, -board.get(r, c));
    }
  }
  return result;
}

bool _shouldMirror(Board board, ZobristTable table) {
  var leftHash = 0;
  var rightHash = 0;
  final mid = board.cols ~/ 2;

  for (var r = 0; r < board.rows; r++) {
    for (var c = 0; c < mid; c++) {
      final v = board.get(r, c);
      if (v != 0) leftHash ^= table.entryFor(v, r, c);
    }
    for (var c = mid; c < board.cols; c++) {
      final v = board.get(r, c);
      if (v != 0) rightHash ^= table.entryFor(v, r, c);
    }
  }
  return leftHash < rightHash;
}

CanonicalResult canonicalize(Board board, int side, ZobristTable table) {
  var current = board;
  var mirrored = false;
  var perspectiveFlipped = false;

  if (_shouldMirror(current, table)) {
    current = mirror(current);
    mirrored = true;
  }

  if (side != 1) {
    current = flipPerspective(current);
    perspectiveFlipped = true;
  }

  final hash = table.hashBoard(current);
  return CanonicalResult(
    board: current,
    zobristHash: hash,
    wasMirrored: mirrored,
    wasPerspectiveFlipped: perspectiveFlipped,
  );
}
