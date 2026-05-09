// Go smoke benchmark — confirms the engine runs Go games end-to-end without
// crashing. Not a strength benchmark.
//
// Usage: dart run bin/go_smoke_benchmark.dart [games=10] [size=13] [seed=42]
//
// Pass criteria (printed and exit-coded):
//   - all games terminate before hitting the max-moves safety cap
//   - at least one game ends with a non-zero outcome (sanity check on scoring)

import 'dart:io';
import 'dart:math';

import 'package:game_engine/game_engine.dart';

void main(List<String> args) {
  final games = args.isNotEmpty ? int.parse(args[0]) : 10;
  final size = args.length > 1 ? int.parse(args[1]) : 13;
  final seed = args.length > 2 ? int.parse(args[2]) : 42;

  final rules = GoRules(size: size);
  final log = GameLog();
  final brain = CloneBrain(
    rules: rules,
    log: log,
    fallback: FallbackStrategy.random,
    random: Random(seed),
  );

  // Safety cap. Real Go games terminate well under 2× cell count once both
  // sides start passing. Cap at 4× as a liveness guard against runaway loops.
  final maxMoves = size * size * 4;

  stdout.writeln(
    'Go smoke benchmark: $games games on ${size}x$size, seed=$seed',
  );
  stdout.writeln('game | moves | outcome | avg-candidates');

  var nonZeroOutcomes = 0;
  var totalMoves = 0;
  var hitCap = false;

  for (var g = 0; g < games; g++) {
    final gameId = 'smoke-$g';
    var board = Board(size, size);
    var ply = 0;
    var candidatesTotal = 0;

    while (!rules.isTerminal(board, log: log) && ply < maxMoves) {
      final side = ply.isEven ? 1 : -1;
      final decision = brain.selectMove(board, side);
      candidatesTotal += decision.candidatesFound;
      board = rules.applyMove(board, decision.move, side);
      log.addState(
        brain.createState(
          board: board,
          movePlayed: decision.move,
          ply: ply,
          gameId: gameId,
        ),
      );
      ply++;
    }

    if (ply >= maxMoves) hitCap = true;

    final outcome = rules.finalOutcome(board);
    log.backfillGame(gameId, outcome, ply);
    if (outcome == -1) {
      // Winner-POV storage: -1 won, so flip every row of this game.
      log.replaceStatesForGame(
        gameId,
        (s) => invertState(s, rules.diffusionKernel),
      );
    }

    if (outcome != 0) nonZeroOutcomes++;
    totalMoves += ply;
    final avgCandidates = ply == 0 ? 0.0 : candidatesTotal / ply;
    stdout.writeln(
      '$g | $ply | $outcome | ${avgCandidates.toStringAsFixed(1)}',
    );
  }

  final avgMoves = totalMoves / games;
  stdout.writeln('---');
  stdout.writeln('Avg moves/game: ${avgMoves.toStringAsFixed(1)}');
  stdout.writeln('Non-zero outcomes: $nonZeroOutcomes/$games');

  var ok = true;
  if (hitCap) {
    stdout.writeln('FAIL: at least one game hit the max-moves cap');
    ok = false;
  }
  if (nonZeroOutcomes == 0) {
    stdout.writeln('FAIL: every game ended in a tie (possible scoring bug)');
    ok = false;
  }

  stdout.writeln(ok ? 'PASS' : 'FAIL');
  exit(ok ? 0 : 1);
}
