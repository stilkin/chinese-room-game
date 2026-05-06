import 'package:test/test.dart';
import 'package:game_engine/game_engine.dart';

void main() {
  late ConnectFourDiffusion kernel;

  setUp(() {
    kernel = ConnectFourDiffusion();
  });

  group('ConnectFourDiffusion', () {
    test('empty board produces all-zero influence', () {
      final board = Board(6, 7);
      final influence = kernel.diffuse(board);
      for (var r = 0; r < 6; r++) {
        for (var c = 0; c < 7; c++) {
          expect(influence[r][c], 0.0);
        }
      }
    });

    test('single piece produces non-zero influence in neighbors', () {
      final board = Board(6, 7);
      board.set(3, 3, 1);
      final influence = kernel.diffuse(board);
      // Center has the piece + accumulated self-influence
      expect(influence[3][3], greaterThan(0));
      // Horizontal neighbors get influence
      expect(influence[3][2], greaterThan(0));
      expect(influence[3][4], greaterThan(0));
      // Vertical neighbors
      expect(influence[2][3], greaterThan(0));
      expect(influence[4][3], greaterThan(0));
    });

    test('opponent piece produces negative influence', () {
      final board = Board(6, 7);
      board.set(3, 3, -1);
      final influence = kernel.diffuse(board);
      expect(influence[3][3], lessThan(0));
    });

    test('identical boards produce identical influence maps', () {
      final a = Board(6, 7);
      a.set(5, 3, 1);
      a.set(4, 3, -1);

      final b = Board(6, 7);
      b.set(5, 3, 1);
      b.set(4, 3, -1);

      final ia = kernel.diffuse(a);
      final ib = kernel.diffuse(b);
      for (var r = 0; r < 6; r++) {
        for (var c = 0; c < 7; c++) {
          expect(ia[r][c], ib[r][c]);
        }
      }
    });

    test('influence map dimensions match board', () {
      final board = Board(6, 7);
      final influence = kernel.diffuse(board);
      expect(influence.length, 6);
      expect(influence[0].length, 7);
    });
  });

  group('influenceMapToBitHash', () {
    test('all-zero influence produces zero hash', () {
      final influence = List.generate(6, (_) => List.filled(7, 0.0));
      final hash = influenceMapToBitHash(influence);
      expect(hash, [0]);
    });

    test('positive values set bits to 1', () {
      final influence = List.generate(6, (_) => List.filled(7, 0.0));
      influence[0][0] = 1.0;
      final hash = influenceMapToBitHash(influence);
      expect(hash[0] & 1, 1);
    });

    test('identical influence maps produce identical hashes', () {
      final board = Board(6, 7);
      board.set(5, 3, 1);
      final kernel = ConnectFourDiffusion();
      final h1 = influenceMapToBitHash(kernel.diffuse(board));
      final h2 = influenceMapToBitHash(kernel.diffuse(board));
      expect(h1, h2);
    });
  });
}
