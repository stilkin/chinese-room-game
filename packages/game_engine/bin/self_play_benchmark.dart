import 'dart:math';

import 'package:game_engine/game_engine.dart';

/// Self-play benchmark: a CloneBrain trainee (side = -1) plays a fixed
/// rule-based coach (side = +1) for N games. Coach moves first (matching the
/// real game's player-first convention). When the trainee is in "recording"
/// mode, after each game the log is backfilled and winner-POV inversion is
/// applied on trainee wins (exactly as the mobile app's _endGame does).
///
/// Run modes (positional arg count):
///
/// 1. Single-coach (3 args). All games record. Brain learns continuously.
///      dart run bin/self_play_benchmark.dart 200 42 builder
///
/// 2. Two-phase (5 args). Phase A trains against `trainCoach` for
///    `trainGames` games (recording). Phase B switches to `evalCoach` for
///    the remaining games. Phase B's record policy defaults to `freeze`.
///      dart run bin/self_play_benchmark.dart 200 42 builder connector 100
///
/// Coach kinds:
///      chaotic / random        — uniform random legal column
///      middle                  — closest to centre (benchmark-only baseline)
///      stacker / pile          — tallest pile, mid-distance tie-break
///      builder                 — adjacent to own tallest stack
///      connector               — extends own longest chain
///      sentinel                — connector + blocks opponent length-4
///
/// 3. Two-phase with explicit policy (6 args). Phase B record policy:
///      freeze     — phase B never records (artificial, but baseline)
///      continuous — phase B always records (online learning)
///      freeze:N   — phase B is frozen for the first N games, then records
///                   the rest (cold introduction, then learn from losses)
///      dart run bin/self_play_benchmark.dart 200 42 middle pile 100 continuous
void main(List<String> args) {
  final games = args.isNotEmpty ? int.parse(args[0]) : 200;
  final seed = args.length > 1 ? int.parse(args[1]) : 42;
  final trainCoachKind = args.length > 2 ? args[2] : 'middle';
  final isTwoPhase = args.length >= 5;
  final evalCoachKind = isTwoPhase ? args[3] : trainCoachKind;
  final trainGames = isTwoPhase ? int.parse(args[4]) : games;
  final policy =
      isTwoPhase
          ? _parsePolicy(args.length > 5 ? args[5] : 'freeze')
          : const _RecordPolicy('freeze', 0);
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
  final trainCoach = _coachFor(trainCoachKind, rules, random);
  final evalCoach = _coachFor(evalCoachKind, rules, random);

  if (isTwoPhase) {
    print('# self-play benchmark (two-phase)');
    print('# trainee     = CloneBrain (random fallback) on side -1');
    print('# train coach = $trainCoachKind on side +1, moves first');
    print('# eval coach  = $evalCoachKind on side +1, moves first');
    print(
      '# train games = $trainGames, eval games = ${games - trainGames}, '
      'seed = $seed',
    );
    print('# eval policy = ${policy.describe}');
  } else {
    print('# self-play benchmark');
    print('# trainee = CloneBrain (random fallback) on side -1');
    print('# coach   = $trainCoachKind on side +1, moves first');
    print('# games=$games, seed=$seed');
  }
  print('# window=$windowSize');
  print('');
  print('game,phase,winner,plies,trainee_fallback_moves,trainee_candidate_avg');

  final outcomes = <int>[];
  final plies = <int>[];

  final phases = <String>[];
  for (var g = 0; g < games; g++) {
    final inTraining = g < trainGames;
    final coach = inTraining ? trainCoach : evalCoach;
    final record = inTraining || policy.recordsAtEvalGame(g - trainGames);
    final phase = inTraining ? 'train' : (record ? 'learn' : 'eval');
    phases.add(phase);
    final result = _playGame(
      rules,
      brain,
      coach,
      log,
      gameIndex: g,
      record: record,
    );
    outcomes.add(result.winner);
    plies.add(result.plies);
    final candAvg =
        result.traineeMoves == 0
            ? 0.0
            : result.traineeCandidatesTotal / result.traineeMoves;
    print(
      '${g + 1},$phase,${result.winner},'
      '${result.plies},${result.traineeFallbackMoves},'
      '${candAvg.toStringAsFixed(1)}',
    );
  }

  print('');
  _printWindowStats(outcomes, plies, windowSize);
  print('');
  if (isTwoPhase) {
    _printPhaseSummary(
      label: 'training summary ($trainCoachKind, recording)',
      outcomes: outcomes.sublist(0, trainGames),
      plies: plies.sublist(0, trainGames),
    );
    // For phase B, break out the frozen and learning sub-segments separately
    // when the policy mixes them.
    final frozenIndices = <int>[];
    final learningIndices = <int>[];
    for (var i = trainGames; i < games; i++) {
      if (phases[i] == 'eval') {
        frozenIndices.add(i);
      } else {
        learningIndices.add(i);
      }
    }
    if (frozenIndices.isNotEmpty) {
      print('');
      _printPhaseSummary(
        label: 'eval (frozen) summary ($evalCoachKind)',
        outcomes: [for (final i in frozenIndices) outcomes[i]],
        plies: [for (final i in frozenIndices) plies[i]],
      );
    }
    if (learningIndices.isNotEmpty) {
      print('');
      _printPhaseSummary(
        label: 'eval (learning) summary ($evalCoachKind, recording)',
        outcomes: [for (final i in learningIndices) outcomes[i]],
        plies: [for (final i in learningIndices) plies[i]],
      );
    }
  } else {
    _printSummary(outcomes, plies);
  }
}

class _RecordPolicy {
  /// One of: 'freeze', 'continuous', 'thaw'.
  final String name;

  /// Number of games to keep frozen at the start of phase B before
  /// recording resumes (only meaningful for 'thaw'). 0 for the others.
  final int freezeFor;

  const _RecordPolicy(this.name, this.freezeFor);

  String get describe {
    switch (name) {
      case 'freeze':
        return 'freeze (eval phase never records)';
      case 'continuous':
        return 'continuous (eval phase always records)';
      case 'thaw':
        return 'freeze:$freezeFor (frozen for $freezeFor games, then records)';
    }
    return name;
  }

  /// Whether the i-th eval-phase game (0-indexed within phase B) records.
  bool recordsAtEvalGame(int i) {
    switch (name) {
      case 'freeze':
        return false;
      case 'continuous':
        return true;
      case 'thaw':
        return i >= freezeFor;
    }
    return false;
  }
}

_RecordPolicy _parsePolicy(String s) {
  if (s == 'freeze') return const _RecordPolicy('freeze', 0);
  if (s == 'continuous') return const _RecordPolicy('continuous', 0);
  if (s.startsWith('freeze:')) {
    final n = int.parse(s.substring('freeze:'.length));
    return _RecordPolicy('thaw', n);
  }
  throw ArgumentError(
    'Unknown policy: "$s" (try freeze, continuous, freeze:N)',
  );
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
  required bool record,
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
      if (record) {
        log.addState(
          brain.createState(
            board: board,
            movePlayed: move,
            ply: ply,
            gameId: gameId,
          ),
        );
      }
    } else {
      // Trainee moves on -1.
      final decision = brain.selectMove(board, -1);
      traineeMoves += 1;
      if (decision.usedFallback) traineeFallbackMoves += 1;
      traineeCandidatesTotal += decision.candidatesFound;
      board = rules.applyMove(board, decision.move, -1);
      if (record) {
        log.addState(
          brain.createState(
            board: board,
            movePlayed: decision.move,
            ply: ply,
            gameId: gameId,
          ),
        );
      }
    }
    ply += 1;

    final winner = rules.checkWinner(board);
    if (winner != null) {
      if (record) {
        log.backfillGame(gameId, winner, ply);
        if (winner == -1) {
          // Trainee won → flip every row to winner-POV (matches mobile _endGame).
          log.replaceStatesForGame(
            gameId,
            (s) => invertState(s, rules.diffusionKernel),
          );
        }
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
  // The named coaches are aliases for fallback strategies. We delegate to a
  // disposable CloneBrain with an empty log so every move falls through to
  // the named personality — the engine stays the single source of truth.
  FallbackStrategy? strategy;
  switch (kind) {
    case 'middle':
      strategy = FallbackStrategy.middleFocus;
      break;
    case 'random':
    case 'chaotic':
      strategy = FallbackStrategy.random;
      break;
    case 'pile':
    case 'stacker':
      strategy = FallbackStrategy.pileFocus;
      break;
    case 'builder':
      strategy = FallbackStrategy.ownPileAdjacent;
      break;
    case 'connector':
      strategy = FallbackStrategy.greedyConnect;
      break;
    case 'sentinel':
      strategy = FallbackStrategy.greedyConnectDefense;
      break;
  }
  if (strategy == null) {
    throw ArgumentError(
      'Unknown coach kind: $kind '
      '(try middle, chaotic/random, stacker/pile, builder, connector, sentinel)',
    );
  }
  // Coaches play as side +1; the fallback strategies all assume own = +1, so
  // selectMove can be called directly without flipping perspective.
  final coachBrain = CloneBrain(
    rules: rules,
    log: GameLog(),
    fallback: strategy,
    random: random,
  );
  return (board) => coachBrain.selectMove(board, 1).move;
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

void _printPhaseSummary({
  required String label,
  required List<int> outcomes,
  required List<int> plies,
}) {
  final n = outcomes.length;
  print('# $label');
  print('total_games,$n');
  if (n == 0) return;
  final wins = outcomes.where((o) => o == -1).length;
  final losses = outcomes.where((o) => o == 1).length;
  final draws = outcomes.where((o) => o == 0).length;
  print('trainee_wins,$wins');
  print('coach_wins,$losses');
  print('draws,$draws');
  print('trainee_win_rate,${(wins / n).toStringAsFixed(3)}');
  print('trainee_nonloss_rate,${((wins + draws) / n).toStringAsFixed(3)}');
  print(
    'avg_plies,${(plies.fold<int>(0, (a, b) => a + b) / n).toStringAsFixed(1)}',
  );
}
