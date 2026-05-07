import 'board.dart';
import 'diffusion.dart';
import 'game_state.dart';
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

// Mirror choice in canonicalize is computed before perspective flip and is
// sign-asymmetric, so canonicalize(B, +side) and canonicalize(B, -side) make
// the same mirror choice. Their canonical boards differ only by perspective
// flip, so inverting a canonical state is exactly flipPerspective on the
// stored board — no need to re-run canonicalize.
GameState invertState(GameState s, ZobristTable table, DiffusionKernel kernel) {
  final invertedBoard = flipPerspective(s.board);
  return GameState(
    board: invertedBoard,
    zobristHash: table.hashBoard(invertedBoard),
    diffusedHash: influenceMapToBitHash(kernel.diffuse(invertedBoard)),
    movePlayed: s.movePlayed,
    ply: s.ply,
    side: -s.side,
    gameId: s.gameId,
    totalMaterial: s.totalMaterial,
    materialBalance: -s.materialBalance,
    outcome: s.outcome,
    movesToEnd: s.movesToEnd,
  );
}
