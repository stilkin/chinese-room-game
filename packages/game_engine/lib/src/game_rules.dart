import 'board.dart';
import 'diffusion.dart';
import 'move_selection.dart';

abstract class GameRules {
  int get rows;
  int get cols;
  String get gameType;
  List<int> get pieceValues;

  List<int> legalMoves(Board board);
  Board applyMove(Board board, int move, int side);

  /// Returns null if the game is ongoing, 0 for a draw,
  /// or +1/-1 indicating which side won.
  int? checkWinner(Board board);

  DiffusionKernel get diffusionKernel;
  MoveSelectionStrategy get moveSelectionStrategy;
}
