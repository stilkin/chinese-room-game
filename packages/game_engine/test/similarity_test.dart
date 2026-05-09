import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:game_engine/game_engine.dart';

GameState _makeState({
  required Int8List diffusedImage,
  int totalMaterial = 0,
  int materialBalance = 0,
  int movePlayed = 0,
  int ply = 0,
  String gameId = 'g1',
  int? outcome,
  int? movesToEnd,
}) {
  return GameState(
    board: Board(6, 7),
    diffusedImage: diffusedImage,
    movePlayed: movePlayed,
    ply: ply,
    gameId: gameId,
    totalMaterial: totalMaterial,
    materialBalance: materialBalance,
    outcome: outcome,
    movesToEnd: movesToEnd,
  );
}

/// Test-only filter that accepts candidates whose `ply` is within `±window` of
/// `queryPly`. The real `ConnectFourFilter` lives in `connect_four.dart`; this
/// is the narrow shape Phase 2 needs.
class _PlyFilter implements CandidateFilter {
  final int queryPly;
  final int window;
  const _PlyFilter(this.queryPly, this.window);

  @override
  bool matches(GameState candidate) =>
      (candidate.ply - queryPly).abs() <= window;

  @override
  CandidateFilter widened() => _PlyFilter(queryPly, window * 2);
}

class _AcceptAll implements CandidateFilter {
  const _AcceptAll();
  @override
  bool matches(GameState candidate) => true;
  @override
  CandidateFilter widened() => const _AcceptAll();
}

void main() {
  group('l1Distance', () {
    test('identical images have distance 0', () {
      final a = Int8List.fromList([1, -2, 3, 0]);
      final b = Int8List.fromList([1, -2, 3, 0]);
      expect(l1Distance(a, b), 0);
    });

    test('single-cell magnitude k contributes k', () {
      final a = Int8List.fromList([5, 0, 0, 0]);
      final b = Int8List.fromList([0, 0, 0, 0]);
      expect(l1Distance(a, b), 5);
    });

    test('signed differences accumulate as absolute values', () {
      // 5 - (-3) = 8; 0 - 0 = 0; -2 - 4 = -6 → 6.
      final a = Int8List.fromList([5, 0, -2]);
      final b = Int8List.fromList([-3, 0, 4]);
      expect(l1Distance(a, b), 14);
    });

    test('full sign-flip on a populated image gives 2 × sum |a|', () {
      final a = Int8List.fromList([1, -2, 3, -4]);
      final b = Int8List.fromList([-1, 2, -3, 4]);
      expect(l1Distance(a, b), 20); // 2 + 4 + 6 + 8
    });
  });

  group('computeTotalMaterial', () {
    test('empty board is 0', () {
      expect(computeTotalMaterial(Board(6, 7)), 0);
    });

    test('sums absolute values', () {
      final board = Board(6, 7);
      board.set(5, 0, 1);
      board.set(5, 1, -1);
      board.set(5, 2, 1);
      expect(computeTotalMaterial(board), 3);
    });
  });

  group('computeMaterialBalance', () {
    test('empty board is 0', () {
      expect(computeMaterialBalance(Board(6, 7)), 0);
    });

    test('balanced board is 0', () {
      final board = Board(6, 7);
      board.set(5, 0, 1);
      board.set(5, 1, -1);
      expect(computeMaterialBalance(board), 0);
    });

    test('unbalanced board reflects difference', () {
      final board = Board(6, 7);
      board.set(5, 0, 1);
      board.set(5, 1, 1);
      board.set(5, 2, -1);
      expect(computeMaterialBalance(board), 1);
    });
  });

  group('searchSimilar', () {
    test('empty candidates returns empty results', () {
      final results = searchSimilar(
        queryDiffusedImage: Int8List(42),
        prefilter: const _AcceptAll(),
        candidates: const [],
      );
      expect(results, isEmpty);
    });

    test('pre-filter excludes distant ply candidates', () {
      final candidates = [
        _makeState(diffusedImage: Int8List(42), ply: 4, gameId: 'near'),
        _makeState(diffusedImage: Int8List(42), ply: 30, gameId: 'far'),
      ];
      final results = searchSimilar(
        queryDiffusedImage: Int8List(42),
        prefilter: const _PlyFilter(5, 2),
        candidates: candidates,
        minCandidates: 1,
      );
      expect(results.length, 1);
      expect(results.first.state.gameId, 'near');
    });

    test('adaptive widening eventually finds candidates', () {
      // All candidates are far from query ply 0; only widening surfaces them.
      final candidates = List.generate(
        3,
        (i) =>
            _makeState(diffusedImage: Int8List(42), ply: 20 + i, gameId: 'g$i'),
      );
      final results = searchSimilar(
        queryDiffusedImage: Int8List(42),
        prefilter: const _PlyFilter(0, 1),
        candidates: candidates,
        minCandidates: 3,
      );
      expect(results.length, 3);
    });

    test('after maxWidens rounds without enough candidates, falls through', () {
      // Filter never widens past its initial (broken widened: returns same
      // window). minCandidates is impossible to satisfy from this small pool.
      final candidates = List.generate(
        2,
        (i) =>
            _makeState(diffusedImage: Int8List(42), ply: 20 + i, gameId: 'g$i'),
      );
      final results = searchSimilar(
        queryDiffusedImage: Int8List(42),
        prefilter: const _PlyFilter(0, 1),
        candidates: candidates,
        minCandidates: 100,
        maxWidens: 1,
      );
      // Falls through to the entire pool.
      expect(results.length, 2);
    });

    test('results are ordered by ascending L1 distance', () {
      final query = Int8List.fromList(List.filled(42, 0));

      final near = Int8List.fromList(List.filled(42, 0));
      near[0] = 1; // distance 1

      final mid = Int8List.fromList(List.filled(42, 0));
      mid[0] = 5; // distance 5

      final far = Int8List.fromList(List.filled(42, 0));
      far[0] = 20; // distance 20

      final candidates = [
        _makeState(diffusedImage: far, ply: 5, gameId: 'far'),
        _makeState(diffusedImage: near, ply: 5, gameId: 'near'),
        _makeState(diffusedImage: mid, ply: 5, gameId: 'mid'),
      ];

      final results = searchSimilar(
        queryDiffusedImage: query,
        prefilter: const _PlyFilter(5, 2),
        candidates: candidates,
        minCandidates: 1,
      );

      expect(results.map((r) => r.state.gameId).toList(), [
        'near',
        'mid',
        'far',
      ]);
      expect(results.map((r) => r.distance).toList(), [1, 5, 20]);
    });
  });
}
