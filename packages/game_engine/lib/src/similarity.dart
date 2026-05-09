import 'dart:typed_data';

import 'board.dart';
import 'game_state.dart';

class SimilarityResult {
  final GameState state;
  final int distance;

  SimilarityResult({required this.state, required this.distance});
}

/// L1 distance between two equal-length quantized influence images. Both
/// inputs SHALL have the same length (callers ensure this — for a given game
/// every row's `diffusedImage` is `rows × cols` long).
int l1Distance(Int8List a, Int8List b) {
  var distance = 0;
  for (var i = 0; i < a.length; i++) {
    final d = a[i] - b[i];
    distance += d < 0 ? -d : d;
  }
  return distance;
}

/// Decides which stored states are eligible candidates before the L1 ranking
/// step. Game-specific: Connect Four uses ply-window matching; chess and Go
/// will plug in their own implementations.
abstract class CandidateFilter {
  bool matches(GameState candidate);

  /// Return a strictly more permissive filter for adaptive widening. If the
  /// initial filter doesn't surface enough candidates, the search loop calls
  /// `widened()` and retries.
  CandidateFilter widened();
}

int computeTotalMaterial(Board board) {
  var total = 0;
  for (var r = 0; r < board.rows; r++) {
    for (var c = 0; c < board.cols; c++) {
      final v = board.get(r, c);
      total += v < 0 ? -v : v;
    }
  }
  return total;
}

int computeMaterialBalance(Board board) {
  var balance = 0;
  for (var r = 0; r < board.rows; r++) {
    for (var c = 0; c < board.cols; c++) {
      balance += board.get(r, c);
    }
  }
  return balance;
}

/// Find candidates similar to the query image, ranked by ascending L1 distance.
///
/// The pre-filter is applied first; if fewer than [minCandidates] survive, the
/// filter is widened and tried again, up to [maxWidens] rounds. If the loop
/// runs out of widening rounds, the entire candidate pool is searched.
List<SimilarityResult> searchSimilar({
  required Int8List queryDiffusedImage,
  required CandidateFilter prefilter,
  required List<GameState> candidates,
  int minCandidates = 5,
  int maxWidens = 8,
}) {
  if (candidates.isEmpty) return const [];

  var filter = prefilter;
  var filtered = <GameState>[];
  for (var round = 0; round <= maxWidens; round++) {
    filtered = candidates.where(filter.matches).toList();
    if (filtered.length >= minCandidates) break;
    if (round == maxWidens) {
      filtered = candidates.toList();
      break;
    }
    filter = filter.widened();
  }

  final results = [
    for (final state in filtered)
      SimilarityResult(
        state: state,
        distance: l1Distance(state.diffusedImage, queryDiffusedImage),
      ),
  ];
  results.sort((a, b) => a.distance.compareTo(b.distance));
  return results;
}
