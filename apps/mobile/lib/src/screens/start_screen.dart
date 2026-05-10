import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme.dart';
import '../widgets/recent_games_strip.dart';

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = AppScope.of(context);
    final textTheme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: notifier,
      builder: (context, _) {
        final cloneWinPct = notifier.gamesPlayed == 0
            ? 0.0
            : (notifier.cloneWins / notifier.gamesPlayed) * 100;
        return Scaffold(
          body: SafeArea(
            // LayoutBuilder + ConstrainedBox(minHeight) + IntrinsicHeight is the
            // standard Flutter pattern for "scroll if needed but let Spacer
            // expand when there's room." Without IntrinsicHeight the Spacer
            // throws inside a SingleChildScrollView (unbounded vertical axis).
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.topRight,
                            child: IconButton(
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/settings'),
                              icon: const Icon(
                                Icons.settings,
                                color: PiYingTheme.onSurface,
                              ),
                              tooltip: 'Settings',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: Image.asset(
                              'assets/icon/icon.png',
                              width: 96,
                              height: 96,
                              filterQuality: FilterQuality.none,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'PI-YING',
                            textAlign: TextAlign.center,
                            style: textTheme.headlineMedium?.copyWith(
                              letterSpacing: 4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // 皮影 (the brand mark) is already shown by the
                          // launcher-icon image above; the subtitle stays
                          // text-only to avoid duplicating the characters.
                          // The longer explanation lives in Settings → About.
                          Text(
                            'shadow play of go',
                            textAlign: TextAlign.center,
                            style: textTheme.bodyMedium?.copyWith(
                              color: PiYingTheme.onSurfaceMuted,
                            ),
                          ),
                          const SizedBox(height: 32),
                          _StatsPanel(
                            cloneWinPct: cloneWinPct,
                            gamesPlayed: notifier.gamesPlayed,
                            playerWins: notifier.playerWins,
                            cloneWins: notifier.cloneWins,
                            draws: notifier.draws,
                          ),
                          const SizedBox(height: 16),
                          Text('LAST GAMES', style: textTheme.titleSmall),
                          const SizedBox(height: 8),
                          RecentGamesStrip(outcomes: notifier.recentOutcomes),
                          const Spacer(),
                          if (notifier.hasOngoingGame) ...[
                            FilledButton(
                              onPressed: () => _onResume(context),
                              child: const Text('RESUME'),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () =>
                                  _onNewGame(context, confirm: true),
                              child: const Text('NEW GAME'),
                            ),
                          ] else
                            FilledButton(
                              onPressed: () =>
                                  _onNewGame(context, confirm: false),
                              child: const Text('NEW GAME'),
                            ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _onResume(BuildContext context) async {
    final notifier = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await notifier.resumeLastGame();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text("couldn't resume that game — it's been cleared."),
        ),
      );
      return;
    }
    if (!context.mounted) return;
    Navigator.pushNamed(context, '/game');
  }

  Future<void> _onNewGame(BuildContext context, {required bool confirm}) async {
    final notifier = AppScope.of(context);
    if (confirm) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('DISCARD?'),
          content: const Text(
            'starting a new game will erase your current one.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('DISCARD'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await notifier.startNewGame();
    if (!context.mounted) return;
    Navigator.pushNamed(context, '/game');
  }
}

class _StatsPanel extends StatelessWidget {
  final double cloneWinPct;
  final int gamesPlayed;
  final int playerWins;
  final int cloneWins;
  final int draws;

  const _StatsPanel({
    required this.cloneWinPct,
    required this.gamesPlayed,
    required this.playerWins,
    required this.cloneWins,
    required this.draws,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PiYingTheme.surface,
        border: Border.all(color: PiYingTheme.outline, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('YOUR CLONE', style: textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${cloneWinPct.toStringAsFixed(0)}%',
                style: textTheme.headlineLarge?.copyWith(
                  color: PiYingTheme.lineColor,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'win rate',
                style: textTheme.bodyMedium?.copyWith(
                  color: PiYingTheme.onSurfaceMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$gamesPlayed games · '
            'you $playerWins · clone $cloneWins'
            '${draws > 0 ? ' · draws $draws' : ''}',
            style: textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
