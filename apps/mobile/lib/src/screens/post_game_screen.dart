import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme.dart';

class PostGameScreen extends StatelessWidget {
  const PostGameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = AppScope.of(context);
    final textTheme = Theme.of(context).textTheme;
    final outcome = notifier.outcome;
    final (label, color) = switch (outcome) {
      1 => ('YOU WIN', PiYingTheme.cinnabar),
      -1 => ('CLONE WINS', PiYingTheme.onSurfaceMuted),
      0 => ('DRAW', PiYingTheme.onSurface),
      _ => ('', PiYingTheme.onSurface),
    };

    // Live area readout for territory games. Computed from the current board
    // (which is preserved through `resign`), not from persisted columns —
    // resigns leave `player_area` / `clone_area` NULL by design but the live
    // board still reflects what was on the screen at end-of-game.
    final area = notifier.currentAreaScore;
    final showArea = area != null && (area.player + area.clone) > 0;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 1),
              Text(
                label,
                textAlign: TextAlign.center,
                style: textTheme.headlineLarge?.copyWith(
                  color: color,
                  letterSpacing: 4,
                ),
              ),
              if (showArea) ...[
                const SizedBox(height: 8),
                Text(
                  'AREA  ·  YOU ${area.player}  ·  CLONE ${area.clone}',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: PiYingTheme.onSurfaceMuted,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'game ${notifier.gamesPlayed}  ·  '
                'you ${notifier.playerWins}  ·  '
                'clone ${notifier.cloneWins}',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: PiYingTheme.onSurfaceMuted,
                ),
              ),
              const SizedBox(height: 36),
              // Final-thought speech bubble — same shape as the in-game
              // narration so the clone's "voice" stays consistent across
              // screens.
              _FinalThoughtBubble(
                narration: notifier.narration.isEmpty
                    ? '...'
                    : notifier.narration,
              ),
              const Spacer(flex: 2),
              FilledButton(
                onPressed: () async {
                  await notifier.startNewGame();
                  if (context.mounted) {
                    Navigator.pushReplacementNamed(context, '/game');
                  }
                },
                child: const Text('PLAY AGAIN'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () =>
                    Navigator.popUntil(context, ModalRoute.withName('/')),
                child: const Text('HOME'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _FinalThoughtBubble extends StatelessWidget {
  final String narration;
  const _FinalThoughtBubble({required this.narration});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            "CLONE'S FINAL THOUGHT",
            style: textTheme.titleSmall?.copyWith(
              color: PiYingTheme.lineColor,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: PiYingTheme.surfaceLow,
            border: Border.all(color: PiYingTheme.outline, width: 2),
          ),
          child: Text(
            narration,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
