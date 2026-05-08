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

  group('quantizeInfluenceMap', () {
    test('all-zero influence produces all-zero image', () {
      final influence = List.generate(6, (_) => List.filled(7, 0.0));
      final image = quantizeInfluenceMap(influence);
      expect(image.length, 42);
      expect(image.every((v) => v == 0), isTrue);
    });

    test('row-major flatten preserves cell positions', () {
      final influence = List.generate(6, (_) => List.filled(7, 0.0));
      influence[0][0] = 5.0;
      influence[5][6] = -3.0;
      final image = quantizeInfluenceMap(influence);
      expect(image[0], 5);
      expect(image[5 * 7 + 6], -3);
    });

    test('rounds to nearest integer', () {
      final influence = List.generate(1, (_) => List.filled(4, 0.0));
      influence[0][0] = 1.4;
      influence[0][1] = 1.5;
      influence[0][2] = -1.4;
      influence[0][3] = -1.5;
      final image = quantizeInfluenceMap(influence);
      expect(image[0], 1);
      expect(image[1], 2);
      expect(image[2], -1);
      expect(image[3], -2);
    });

    test('clamps to Int8 range', () {
      final influence = List.generate(1, (_) => List.filled(2, 0.0));
      influence[0][0] = 200.0;
      influence[0][1] = -200.0;
      final image = quantizeInfluenceMap(influence);
      expect(image[0], 127);
      expect(image[1], -128);
    });

    test('identical influence maps produce identical images', () {
      final board = Board(6, 7);
      board.set(5, 3, 1);
      final kernel = ConnectFourDiffusion();
      final i1 = quantizeInfluenceMap(kernel.diffuse(board));
      final i2 = quantizeInfluenceMap(kernel.diffuse(board));
      expect(i1, i2);
    });
  });
}
