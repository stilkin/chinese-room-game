import 'dart:math';

import 'package:game_engine/game_engine.dart';

/// Round-robin among the user-facing fallback personalities. Each pairing
/// plays N games per direction (alternating who moves first). Outputs a
/// 5×5 win-count matrix and an aggregate ranking.
///
/// Both sides are CloneBrain instances with empty GameLogs so every move
/// falls back to the personality. The fallback path assumes own = +1, so
/// when a personality plays side -1 the board is flipped before the call.
///
/// Usage: dart run bin/personality_round_robin.dart [games_per_direction] [seed]
///        (defaults: 50 games per direction, seed 42)
void main(List<String> args) {
  final gamesPerDir = args.isNotEmpty ? int.parse(args[0]) : 50;
  final seed = args.length > 1 ? int.parse(args[1]) : 42;

  final rules = ConnectFourRules();
  final personalities = <String, FallbackStrategy>{
    'chaotic': FallbackStrategy.random,
    'stacker': FallbackStrategy.pileFocus,
    'builder': FallbackStrategy.ownPileAdjacent,
    'connector': FallbackStrategy.greedyConnect,
    'sentinel': FallbackStrategy.greedyConnectDefense,
  };
  final names = personalities.keys.toList();

  print('# personality round-robin');
  print('# games per direction = $gamesPerDir, seed = $seed');
  print('# columns = wins of *row* personality vs *col* personality');
  print('# (rows are players-as-+1, cols are opponents-as-+1, alternated)');
  print('');

  // Win counts: wins[a][b] = number of games personality a won against b.
  final wins = <String, Map<String, int>>{
    for (final a in names) a: {for (final b in names) b: 0},
  };
  final draws = <String, Map<String, int>>{
    for (final a in names) a: {for (final b in names) b: 0},
  };

  // Use a single random for both seeds to make ordering reproducible.
  final random = Random(seed);

  for (final a in names) {
    for (final b in names) {
      if (a == b) continue;
      for (var g = 0; g < gamesPerDir; g++) {
        // Alternate who moves first to neutralise first-move advantage.
        final aMovesFirst = g.isEven;
        final result = _playGame(
          rules,
          aStrategy: personalities[a]!,
          bStrategy: personalities[b]!,
          aMovesFirst: aMovesFirst,
          random: random,
        );
        if (result == 0) {
          draws[a]![b] = draws[a]![b]! + 1;
        } else if (result == 1) {
          wins[a]![b] = wins[a]![b]! + 1;
        } else {
          wins[b]![a] = wins[b]![a]! + 1;
        }
      }
    }
  }

  // Print the win matrix.
  final pad = 10;
  final header = ['name'.padRight(pad), ...names.map((n) => n.padLeft(pad))];
  print(header.join(' '));
  for (final a in names) {
    final row = [a.padRight(pad)];
    for (final b in names) {
      if (a == b) {
        row.add('—'.padLeft(pad));
      } else {
        row.add('${wins[a]![b]}'.padLeft(pad));
      }
    }
    print(row.join(' '));
  }

  // Aggregate ranking.
  print('');
  print('# aggregate (total wins across all opponents and directions)');
  final totals = <String, int>{};
  for (final a in names) {
    var sum = 0;
    for (final b in names) {
      if (a == b) continue;
      sum += wins[a]![b]!;
    }
    totals[a] = sum;
  }
  final ranked =
      totals.entries.toList()..sort((x, y) => y.value.compareTo(x.value));
  for (final entry in ranked) {
    print('${entry.key.padRight(pad)} ${entry.value}');
  }

  // Sanity: total wins + total draws + total opponent wins == games played.
  print('');
  print('# diagnostic: total games played per personality');
  for (final a in names) {
    var played = 0;
    var won = 0;
    var drew = 0;
    var lost = 0;
    for (final b in names) {
      if (a == b) continue;
      // Each pair plays gamesPerDir games per direction, so 2× per opponent.
      // wins[a][b] aggregates across both directions in _playGame; draws[a][b]
      // does not, so we must add the (b, a) draws here too.
      played += 2 * gamesPerDir;
      won += wins[a]![b]!;
      drew += draws[a]![b]! + draws[b]![a]!;
      lost += wins[b]![a]!;
    }
    final winRate = played == 0 ? 0.0 : won / played;
    print(
      '${a.padRight(pad)} played=$played won=$won drew=$drew lost=$lost '
      'win_rate=${winRate.toStringAsFixed(3)}',
    );
  }
}

/// Plays one game. Returns +1 if A won, -1 if B won, 0 for draw.
int _playGame(
  ConnectFourRules rules, {
  required FallbackStrategy aStrategy,
  required FallbackStrategy bStrategy,
  required bool aMovesFirst,
  required Random random,
}) {
  final brainA = CloneBrain(
    rules: rules,
    log: GameLog(),
    fallback: aStrategy,
    random: random,
  );
  final brainB = CloneBrain(
    rules: rules,
    log: GameLog(),
    fallback: bStrategy,
    random: random,
  );

  var board = Board(rules.rows, rules.cols);
  var ply = 0;
  // A is +1 by convention; B is -1. aMovesFirst flips the side that drops first.
  while (true) {
    final aTurn = (ply.isEven && aMovesFirst) || (ply.isOdd && !aMovesFirst);
    if (aTurn) {
      // A plays as +1: own = +1 already.
      final move = brainA.selectMove(board, 1).move;
      board = rules.applyMove(board, move, 1);
    } else {
      // B plays as -1: flip the board so B's perspective is own = +1.
      final flipped = flipPerspective(board);
      final move = brainB.selectMove(flipped, 1).move;
      board = rules.applyMove(board, move, -1);
    }
    ply++;
    if (rules.isTerminal(board)) {
      final winner = rules.finalOutcome(board);
      // winner is +1 or -1 in board frame; A is +1, B is -1.
      if (winner == 0) return 0;
      return winner == 1 ? 1 : -1;
    }
  }
}
