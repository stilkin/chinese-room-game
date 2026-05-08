import 'board.dart';
import 'game_state.dart';

class SimilarityResult {
  final GameState state;
  final int distance;

  SimilarityResult({required this.state, required this.distance});
}

int hammingDistance(List<int> a, List<int> b) {
  var distance = 0;
  final len = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < len; i++) {
    distance += _popcount(a[i] ^ b[i]);
  }
  return distance;
}

int _popcount(int x) {
  var count = 0;
  var v = x;
  while (v != 0) {
    count += v & 1;
    v = v >>> 1;
  }
  return count;
}

int computeTotalMaterial(Board board) {
  var total = 0;
  for (var r = 0; r < board.rows; r++) {
    for (var c = 0; c < board.cols; c++) {
      final v = board.get(r, c);
      if (v < 0) {
        total += -v;
      } else {
        total += v;
      }
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

List<SimilarityResult> searchSimilar({
  required List<int> queryDiffusedHash,
  required int queryTotalMaterial,
  required int queryMaterialBalance,
  required List<GameState> candidates,
  int minCandidates = 5,
  int initialWindow = 2,
}) {
  var window = initialWindow;
  var filtered = <GameState>[];

  while (true) {
    filtered = [];
    for (final state in candidates) {
      final matDiff = (state.totalMaterial - queryTotalMaterial).abs();
      final balDiff = (state.materialBalance - queryMaterialBalance).abs();
      if (matDiff <= window && balDiff <= window) {
        filtered.add(state);
      }
    }
    if (filtered.length >= minCandidates) break;
    window *= 2;
    if (window > 1000) {
      filtered = candidates.toList();
      break;
    }
  }

  final results = <SimilarityResult>[];
  for (final state in filtered) {
    final dist = hammingDistance(state.diffusedHash, queryDiffusedHash);
    results.add(SimilarityResult(state: state, distance: dist));
  }
  results.sort((a, b) => a.distance.compareTo(b.distance));

  return results;
}
