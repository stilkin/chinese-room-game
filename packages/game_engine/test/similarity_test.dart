import 'package:test/test.dart';
import 'package:game_engine/game_engine.dart';

GameState _makeState({
  required List<int> diffusedHash,
  required int totalMaterial,
  required int materialBalance,
  int movePlayed = 0,
  int ply = 0,
  String gameId = 'g1',
  int? outcome,
  int? movesToEnd,
}) {
  return GameState(
    board: Board(6, 7),
    diffusedHash: diffusedHash,
    movePlayed: movePlayed,
    ply: ply,
    gameId: gameId,
    totalMaterial: totalMaterial,
    materialBalance: materialBalance,
    outcome: outcome,
    movesToEnd: movesToEnd,
  );
}

void main() {
  group('hammingDistance', () {
    test('identical hashes have distance 0', () {
      expect(hammingDistance([42], [42]), 0);
    });

    test('completely different bits', () {
      expect(hammingDistance([0], [7]), 3); // 7 = 0b111
    });

    test('works with multi-int hashes', () {
      expect(hammingDistance([0, 0], [1, 1]), 2);
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
    test('pre-filter excludes distant states', () {
      final candidates = [
        _makeState(
          diffusedHash: [0],
          totalMaterial: 5,
          materialBalance: 1,
          outcome: 1,
          movesToEnd: 3,
        ),
        _makeState(
          diffusedHash: [0],
          totalMaterial: 50,
          materialBalance: 40,
          gameId: 'far',
          outcome: 1,
          movesToEnd: 3,
        ),
      ];

      final results = searchSimilar(
        queryDiffusedHash: [0],
        queryTotalMaterial: 5,
        queryMaterialBalance: 1,
        candidates: candidates,
        minCandidates: 1,
        initialWindow: 2,
      );

      expect(results.every((r) => r.state.gameId != 'far'), true);
    });

    test('adaptive widening finds candidates', () {
      final candidates = List.generate(
        3,
        (i) => _makeState(
          diffusedHash: [i],
          totalMaterial: 20 + i,
          materialBalance: 10 + i,
          gameId: 'g$i',
          outcome: 1,
          movesToEnd: 3,
        ),
      );

      final results = searchSimilar(
        queryDiffusedHash: [0],
        queryTotalMaterial: 20,
        queryMaterialBalance: 10,
        candidates: candidates,
        minCandidates: 5,
        initialWindow: 1,
      );

      expect(results.isNotEmpty, true);
    });

    test('empty candidates returns empty results', () {
      final results = searchSimilar(
        queryDiffusedHash: [0],
        queryTotalMaterial: 0,
        queryMaterialBalance: 0,
        candidates: [],
      );
      expect(results, isEmpty);
    });

    test('results are ordered by Hamming distance', () {
      final candidates = [
        _makeState(
          diffusedHash: [7], // 3 bits set
          totalMaterial: 5,
          materialBalance: 1,
          gameId: 'far',
          outcome: 1,
          movesToEnd: 3,
        ),
        _makeState(
          diffusedHash: [1], // 1 bit set
          totalMaterial: 5,
          materialBalance: 1,
          gameId: 'close',
          outcome: 1,
          movesToEnd: 3,
        ),
      ];

      final results = searchSimilar(
        queryDiffusedHash: [0],
        queryTotalMaterial: 5,
        queryMaterialBalance: 1,
        candidates: candidates,
        minCandidates: 1,
      );

      expect(results.first.state.gameId, 'close');
    });
  });
}
