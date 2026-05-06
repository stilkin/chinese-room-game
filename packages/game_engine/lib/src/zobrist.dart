import 'board.dart';
import 'game_rules.dart';

class SplitMix64 {
  int _state;

  SplitMix64(this._state);

  SplitMix64.fromString(String seed) : _state = _hashString(seed);

  static int _hashString(String s) {
    var hash = 0;
    for (var i = 0; i < s.length; i++) {
      hash = (hash * 31 + s.codeUnitAt(i)) & 0x7FFFFFFFFFFFFFFF;
    }
    return hash == 0 ? 1 : hash;
  }

  int next() {
    _state = (_state + 0x9E3779B97F4A7C15) & 0x7FFFFFFFFFFFFFFF;
    var z = _state;
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & 0x7FFFFFFFFFFFFFFF;
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & 0x7FFFFFFFFFFFFFFF;
    return z ^ (z >> 31);
  }
}

class ZobristTable {
  final Map<int, List<int>> _table;
  final int _cols;

  ZobristTable._(this._table, this._cols);

  factory ZobristTable.forGame(GameRules rules) {
    final rng = SplitMix64.fromString(rules.gameType);
    final table = <int, List<int>>{};
    final size = rules.rows * rules.cols;

    for (final pieceValue in rules.pieceValues) {
      final entries = List<int>.generate(size, (_) => rng.next());
      table[pieceValue] = entries;
    }
    return ZobristTable._(table, rules.cols);
  }

  int hashBoard(Board board) {
    var hash = 0;
    for (var r = 0; r < board.rows; r++) {
      for (var c = 0; c < board.cols; c++) {
        final v = board.get(r, c);
        if (v == 0) continue;
        final entries = _table[v];
        if (entries != null) {
          hash ^= entries[r * _cols + c];
        }
      }
    }
    return hash;
  }

  int updateHash(int currentHash, int row, int col, int oldValue, int newValue) {
    if (oldValue != 0) {
      final entries = _table[oldValue];
      if (entries != null) {
        currentHash ^= entries[row * _cols + col];
      }
    }
    if (newValue != 0) {
      final entries = _table[newValue];
      if (entries != null) {
        currentHash ^= entries[row * _cols + col];
      }
    }
    return currentHash;
  }

  int entryFor(int pieceValue, int row, int col) {
    return _table[pieceValue]![row * _cols + col];
  }
}
