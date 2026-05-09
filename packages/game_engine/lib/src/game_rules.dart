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

  /// Hard ceiling on L1 distance for a candidate to be considered "similar
  /// enough." Candidates with `distance > maxCandidateL1Distance` are
  /// dropped during retrieval — even if the prefilter widened to find them.
  /// Without this ceiling the brain would silently learn from far-away
  /// states whenever the database is sparse, inverting the "fall back when
  /// I have no relevant data" intent. Per-game because diffused-image
  /// magnitudes scale with piece values and board size.
  int get maxCandidateL1Distance;
}
