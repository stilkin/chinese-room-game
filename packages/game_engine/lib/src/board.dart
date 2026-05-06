import 'dart:typed_data';

class Board {
  final int rows;
  final int cols;
  final List<List<int>> cells;

  Board(this.rows, this.cols)
      : cells = List.generate(rows, (_) => List.filled(cols, 0));

  Board.from(List<List<int>> source)
      : rows = source.length,
        cols = source[0].length,
        cells = [for (final row in source) [...row]];

  Int8List get flat {
    final result = Int8List(rows * cols);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        result[r * cols + c] = cells[r][c];
      }
    }
    return result;
  }

  Board copy() => Board.from(cells);

  int get(int row, int col) => cells[row][col];

  void set(int row, int col, int value) {
    cells[row][col] = value;
  }

  @override
  bool operator ==(Object other) {
    if (other is! Board) return false;
    if (rows != other.rows || cols != other.cols) return false;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (cells[r][c] != other.cells[r][c]) return false;
      }
    }
    return true;
  }

  @override
  int get hashCode {
    var hash = rows * 31 + cols;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        hash = hash * 31 + cells[r][c];
      }
    }
    return hash;
  }

  @override
  String toString() {
    final buf = StringBuffer();
    for (var r = 0; r < rows; r++) {
      buf.writeln(cells[r].join(' '));
    }
    return buf.toString();
  }
}
