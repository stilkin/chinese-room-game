import 'dart:math';

import 'package:game_engine/game_engine.dart';

/// Self-play benchmark: a CloneBrain trainee (side = -1) plays a fixed
/// middle-focus coach (side = +1) for N games. Coach moves first (matching the
/// real game's player-first convention). After each game the log is backfilled
/// and winner-POV inversion is applied on trainee wins, exactly as the mobile
/// app does at game end. Stdout is CSV-ish so the numbers can be eyeballed or
/// piped into something else.
///
/// Usage:
///   dart run bin/self_play_benchmark.dart                  # 200 games, seed 42
///   dart run bin/self_play_benchmark.dart 500              # 500 games
///   dart run bin/self_play_benchmark.dart 500 7            # 500 games, seed 7
///   dart run bin/self_play_benchmark.dart 500 7 random     # coach = random
void main(List<String> args) {
  final games = args.isNotEmpty ? int.parse(args[0]) : 200;
  final seed = args.length > 1 ? int.parse(args[1]) : 42;
  final coachKind = args.length > 2 ? args[2] : 'middle';
  const windowSize = 25;

  final rules = ConnectFourRules();
  final log = GameLog();
  final random = Random(seed);
  final brain = CloneBrain(
    rules: rules,
    log: log,
    fallback: FallbackStrategy.random,
    random: random,
  );
  final coach = _coachFor(coachKind, rules, random);

  print('# self-play benchmark');
  print('# trainee = CloneBrain (random fallback) on side -1');
  print('# coach   = $coachKind on side +1, moves first');
  print('# games=$games, window=$windowSize, seed=$seed');
  print('');
  print('game,winner,plies,trainee_fallback_moves,trainee_candidate_avg');

  final outcomes = <int>[];
  final plies = <int>[];

  for (var g = 0; g < games; g++) {
    final result = _playGame(rules, brain, coach, log, gameIndex: g);
    outcomes.add(result.winner);
    plies.add(result.plies);
    final candAvg =
        result.traineeMoves == 0
            ? 0.0
            : result.traineeCandidatesTotal / result.traineeMoves;
    print(
      '${g + 1},${result.winner},${result.plies},'
      '${result.traineeFallbackMoves},${candAvg.toStringAsFixed(1)}',
    );
  }

  print('');
  _printWindowStats(outcomes, plies, windowSize);
  print('');
  _printSummary(outcomes, plies);
}

class _GameResult {
  final int winner; // +1 coach, -1 trainee, 0 draw
  final int plies;
  final int traineeMoves;
  final int traineeFallbackMoves;
  final int traineeCandidatesTotal;

  _GameResult({
    required this.winner,
    required this.plies,
    required this.traineeMoves,
    required this.traineeFallbackMoves,
    required this.traineeCandidatesTotal,
  });
}

typedef _CoachFn = int Function(Board);

_GameResult _playGame(
  ConnectFourRules rules,
  CloneBrain brain,
  _CoachFn coach,
  GameLog log, {
  required int gameIndex,
}) {
  final gameId = 'bench-$gameIndex';
  var board = Board(rules.rows, rules.cols);
  var ply = 0;
  var traineeMoves = 0;
  var traineeFallbackMoves = 0;
  var traineeCandidatesTotal = 0;

  while (true) {
    if (ply.isEven) {
      // Coach moves on +1.
      final move = coach(board);
      board = rules.applyMove(board, move, 1);
      log.addState(
        brain.createState(
          board: board,
          movePlayed: move,
          ply: ply,
          gameId: gameId,
        ),
      );
    } else {
      // Trainee moves on -1.
      final decision = brain.selectMove(board, -1);
      traineeMoves += 1;
      if (decision.usedFallback) traineeFallbackMoves += 1;
      traineeCandidatesTotal += decision.candidatesFound;
      board = rules.applyMove(board, decision.move, -1);
      log.addState(
        brain.createState(
          board: board,
          movePlayed: decision.move,
          ply: ply,
          gameId: gameId,
        ),
      );
    }
    ply += 1;

    final winner = rules.checkWinner(board);
    if (winner != null) {
      log.backfillGame(gameId, winner, ply);
      if (winner == -1) {
        // Trainee won → flip every row to winner-POV (matches mobile _endGame).
        log.replaceStatesForGame(
          gameId,
          (s) => invertState(s, rules.diffusionKernel),
        );
      }
      return _GameResult(
        winner: winner,
        plies: ply,
        traineeMoves: traineeMoves,
        traineeFallbackMoves: traineeFallbackMoves,
        traineeCandidatesTotal: traineeCandidatesTotal,
      );
    }
  }
}

_CoachFn _coachFor(String kind, ConnectFourRules rules, Random random) {
  switch (kind) {
    case 'middle':
      return (board) {
        final legal = rules.legalMoves(board);
        final mid = rules.cols ~/ 2;
        final sorted = [...legal]
          ..sort((a, b) => (a - mid).abs().compareTo((b - mid).abs()));
        return sorted.first;
      };
    case 'random':
      return (board) {
        final legal = rules.legalMoves(board);
        return legal[random.nextInt(legal.length)];
      };
    case 'edge':
      return (board) {
        final legal = rules.legalMoves(board);
        final mid = rules.cols ~/ 2;
        final sorted = [...legal]
          ..sort((a, b) => (b - mid).abs().compareTo((a - mid).abs()));
        return sorted.first;
      };
    default:
      throw ArgumentError(
        'Unknown coach kind: $kind (try middle, random, edge)',
      );
  }
}

void _printWindowStats(List<int> outcomes, List<int> plies, int windowSize) {
  print('# rolling-window stats');
  print(
    'window_end,trainee_wins,coach_wins,draws,trainee_win_rate,trainee_nonloss_rate,avg_plies',
  );
  for (var end = windowSize; end <= outcomes.length; end += windowSize) {
    final start = end - windowSize;
    final slice = outcomes.sublist(start, end);
    final pliesSlice = plies.sublist(start, end);
    final trainee = slice.where((o) => o == -1).length;
    final coachWins = slice.where((o) => o == 1).length;
    final draws = slice.where((o) => o == 0).length;
    final n = slice.length;
    final winRate = trainee / n;
    final nonLoss = (trainee + draws) / n;
    final avgPlies = pliesSlice.fold<int>(0, (a, b) => a + b) / n;
    print(
      '$end,$trainee,$coachWins,$draws,'
      '${winRate.toStringAsFixed(3)},${nonLoss.toStringAsFixed(3)},'
      '${avgPlies.toStringAsFixed(1)}',
    );
  }
}

void _printSummary(List<int> outcomes, List<int> plies) {
  final n = outcomes.length;
  if (n == 0) return;
  final half = n ~/ 2;
  final firstHalf = outcomes.take(half).toList();
  final secondHalf = outcomes.skip(half).toList();
  double winRate(List<int> xs) =>
      xs.isEmpty ? 0 : xs.where((o) => o == -1).length / xs.length;
  double nonLossRate(List<int> xs) =>
      xs.isEmpty ? 0 : xs.where((o) => o == -1 || o == 0).length / xs.length;
  print('# summary');
  print('total_games,$n');
  print('trainee_wins,${outcomes.where((o) => o == -1).length}');
  print('coach_wins,${outcomes.where((o) => o == 1).length}');
  print('draws,${outcomes.where((o) => o == 0).length}');
  if (half > 0) {
    print(
      'first_half_trainee_win_rate,${winRate(firstHalf).toStringAsFixed(3)}',
    );
    print(
      'second_half_trainee_win_rate,${winRate(secondHalf).toStringAsFixed(3)}',
    );
    print(
      'first_half_trainee_nonloss_rate,${nonLossRate(firstHalf).toStringAsFixed(3)}',
    );
    print(
      'second_half_trainee_nonloss_rate,${nonLossRate(secondHalf).toStringAsFixed(3)}',
    );
  }
  print(
    'avg_plies_overall,${(plies.fold<int>(0, (a, b) => a + b) / n).toStringAsFixed(1)}',
  );
}
