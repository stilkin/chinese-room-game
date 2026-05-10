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

  /// Legal moves for the given board. Games whose legality depends on the side
  /// to move (e.g. Go's suicide rule) consult `side`. Games whose legality
  /// depends on history (e.g. Go's simple-ko check) consult `log`. Games
  /// without such dependencies (e.g. Connect Four) ignore both.
  List<int> legalMoves(Board board, {int side = 1, GameLog? log});
  Board applyMove(Board board, int move, int side);

  /// Returns null if the game is ongoing, 0 for a draw,
  /// or +1/-1 indicating which side won. Board-only contract; for games whose
  /// termination depends on move history (e.g. Go's two consecutive passes),
  /// use `isTerminal` / `finalOutcome` instead.
  int? checkWinner(Board board);

  /// True when the game is over. Board is always supplied; `log` is optional
  /// and consulted by games whose termination depends on move history (Go).
  /// Connect Four ignores `log` and decides purely from the board.
  bool isTerminal(Board board, {GameLog? log});

  /// `+1` / `-1` / `0` indicating who won (or draw) at game end. Caller is
  /// responsible for invoking this only when `isTerminal` first returns true.
  /// Board-only because both Chinese-style area scoring (Go) and four-in-a-row
  /// detection (Connect Four) are pure board operations.
  int finalOutcome(Board board);

  /// True if `move` is the game's pass sentinel — i.e. a "no placement" move
  /// whose stored `GameState` row carries no positional teaching content
  /// (the board is byte-equal to the prior state's board). Pass rows are
  /// excluded from the CBR candidate pool so they don't pollute retrieval.
  /// Default false; games without a pass concept (e.g. Connect Four) inherit
  /// the default. Go overrides on `move == passMove`.
  bool isPassMove(int move) => false;

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
