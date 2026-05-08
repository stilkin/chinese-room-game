import 'board.dart';
import 'diffusion.dart';
import 'game_state.dart';

Board flipPerspective(Board board) {
  final result = Board(board.rows, board.cols);
  for (var r = 0; r < board.rows; r++) {
    for (var c = 0; c < board.cols; c++) {
      result.set(r, c, -board.get(r, c));
    }
  }
  return result;
}

GameState invertState(GameState s, DiffusionKernel kernel) {
  final inv = flipPerspective(s.board);
  return GameState(
    board: inv,
    diffusedHash: influenceMapToBitHash(kernel.diffuse(inv)),
    movePlayed: s.movePlayed,
    ply: s.ply,
    gameId: s.gameId,
    totalMaterial: s.totalMaterial,
    materialBalance: -s.materialBalance,
    outcome: s.outcome,
    movesToEnd: s.movesToEnd,
  );
}
