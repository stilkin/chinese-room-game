import 'package:flutter/material.dart';
import 'package:game_engine/game_engine.dart';

import '../app_scope.dart';
import '../state/game_notifier.dart';
import '../theme.dart';

class _PersonalityLevel {
  final FallbackStrategy strategy;
  final String name;
  final String blurb;
  const _PersonalityLevel(this.strategy, this.name, this.blurb);
}

// Single-entry roster for the Go launch. The Connect-Four-shaped personalities
// (Builder, Stacker, Connector, Sentinel) survive in the engine package for
// benchmark use but aren't surfaced on the slider — Go-specific personalities
// arrive in a follow-up change. The slider widget is replaced by a static
// label below until there are enough entries to make a slider meaningful.
const List<_PersonalityLevel> _kSliderLevels = [
  _PersonalityLevel(
    FallbackStrategy.random,
    'Chaotic',
    'plays anywhere legal.',
  ),
];

const int _kDefaultSliderIndex = 0;

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = AppScope.of(context);
    final theme = Theme.of(context);
    // Single-entry roster — slider is restored to a real Stateful widget when
    // the personality ladder lands. Until then, just render the lone level.
    final level = _kSliderLevels[_kDefaultSliderIndex];

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Quiet earned-discovery moment for the curious. Lives in Settings
            // rather than the main UI so the brand doesn't lecture; users who
            // want to know what 皮影 means find it here.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text('About', style: theme.textTheme.titleSmall),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Pi-Ying — 皮影 (pí yǐng), Chinese shadow theatre, where a '
                'puppeteer animates flat figures behind a backlit screen. '
                'Your clone is your shadow, learning your moves and playing '
                'them back at you.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const Divider(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(
                'Fallback personality',
                style: theme.textTheme.headlineMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'used by the clone when it has no relevant data.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 32),
            Center(
              child: Text(
                level.name,
                style: theme.textTheme.displayMedium,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                level.blurb,
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 32),
            // Single personality at launch — slider is restored when a Go
            // personality ladder lands.
            Center(
              child: Text(
                'more personalities arrive in a future update.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: PiYingTheme.onSurfaceMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const Divider(height: 48),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                foregroundColor: PiYingTheme.cinnabar,
              ),
              onPressed: () => _confirmDelete(context, notifier),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Delete All Game Logs'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _confirmDelete(
    BuildContext context,
    GameNotifier notifier,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all game logs?'),
        content: const Text(
          'This resets the clone. All stored games will be removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: PiYingTheme.cinnabar,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await notifier.deleteAllData();
    }
  }
}
