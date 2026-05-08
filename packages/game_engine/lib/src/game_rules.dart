import 'board.dart';
import 'diffusion.dart';
import 'game_state.dart';
import 'move_selection.dart';
import 'similarity.dart';

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

  /// Game-specific candidate pre-filter for `searchSimilar`. Returns the
  /// initial filter; the search loop calls `widened()` on it as needed.
  CandidateFilter prefilter(GameState query);

  /// Game-specific scorer used by `InfluenceOverlayStrategy`.
  MoveScorer get moveScorer;
}
