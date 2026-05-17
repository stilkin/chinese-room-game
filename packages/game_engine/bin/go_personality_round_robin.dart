import 'dart:math';
import 'dart:typed_data';

import 'package:game_engine/game_engine.dart';

/// Round-robin among the Go-mode user-facing fallback personalities. Each
/// pairing plays N games per direction (alternating who moves first). Outputs
/// a 5×5 win-count matrix and an aggregate ranking — the strength gate before
/// shipping the slider order.
///
/// Both sides are CloneBrain instances sharing a single GameLog (so ko/pass
/// state is accurate for legality checks) but configured with different
/// fallback strategies. Neither side has any *completed* game data, so every
/// move falls through to the personality.
///
/// Usage:
///   dart run bin/go_personality_round_robin.dart [games_per_direction] [seed]
///   defaults: 50 games per direction, seed 42.
///
/// Tokens (all five Go personalities):
///   wanderer, gostar, diamond, gocontact, gogreedy
void main(List<String> args) {
  final gamesPerDir = args.isNotEmpty ? int.parse(args[0]) : 50;
  final seed = args.length > 1 ? int.parse(args[1]) : 42;

  final rules = GoRules(size: 13);
  final personalities = <String, FallbackStrategy>{
    'wanderer': FallbackStrategy.random,
    'gostar': FallbackStrategy.goStarPoints,
    'diamond': FallbackStrategy.goDiamond,
    'gocontact': FallbackStrategy.goContact,
    'gogreedy': FallbackStrategy.goGreedyArea,
  };
  final names = personalities.keys.toList();

  print('# go personality round-robin');
  print('# games per direction = $gamesPerDir, seed = $seed');
  print('# columns = wins of *row* personality vs *col* personality');
  print('# (rows are players-as-+1, cols are opponents-as-+1, alternated)');
  print('');

  final wins = <String, Map<String, int>>{
    for (final a in names) a: {for (final b in names) b: 0},
  };
  final draws = <String, Map<String, int>>{
    for (final a in names) a: {for (final b in names) b: 0},
  };

  final random = Random(seed);

  for (final a in names) {
    for (final b in names) {
      if (a == b) continue;
      for (var g = 0; g < gamesPerDir; g++) {
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

  const pad = 12;
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

  print('');
  print('# diagnostic: total games played per personality');
  for (final a in names) {
    var played = 0;
    var won = 0;
    var drew = 0;
    var lost = 0;
    for (final b in names) {
      if (a == b) continue;
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

/// Plays one Go game. Returns +1 if A (white/+1) won, -1 if B (black/-1) won,
/// 0 for a draw (equal area).
///
/// Hard ply cap (`size*size*2`) terminates pathological non-passing games —
/// in practice both fallbacks converge to passing once the board fills, but a
/// cap keeps the gate runtime bounded if a personality combination loops.
int _playGame(
  GoRules rules, {
  required FallbackStrategy aStrategy,
  required FallbackStrategy bStrategy,
  required bool aMovesFirst,
  required Random random,
}) {
  final log = GameLog();
  final brainA = CloneBrain(
    rules: rules,
    log: log,
    fallback: aStrategy,
    random: random,
  );
  final brainB = CloneBrain(
    rules: rules,
    log: log,
    fallback: bStrategy,
    random: random,
  );

  final cells = rules.rows * rules.cols;
  final maxPlies = cells * 2;
  final emptyImage = Int8List(cells);

  var board = Board(rules.rows, rules.cols);
  var ply = 0;
  while (ply < maxPlies && !rules.isTerminal(board, log: log)) {
    final aTurn = (ply.isEven && aMovesFirst) || (ply.isOdd && !aMovesFirst);
    final side = aTurn ? 1 : -1;
    final brain = aTurn ? brainA : brainB;
    final move = brain.selectMove(board, side).move;
    board = rules.applyMove(board, move, side);
    // Append an in-progress state so the next turn's legalMoves sees the
    // ko-relevant prior board and the pass history. Empty diffusedImage is
    // fine — neither legalMoves nor isTerminal reads it.
    log.addState(
      GameState(
        board: board,
        diffusedImage: emptyImage,
        movePlayed: move,
        ply: ply,
        gameId: 'g',
        totalMaterial: 0,
        materialBalance: 0,
      ),
    );
    ply++;
  }

  final outcome = rules.finalOutcome(board);
  // outcome == +1 → white won → A won. outcome == -1 → black won → B won.
  if (outcome == 0) return 0;
  return outcome == 1 ? 1 : -1;
}
