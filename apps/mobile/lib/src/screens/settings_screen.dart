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

// Slider order is observed-strength order from the round-robin gate (50
// games/direction, seed 42): Hugger < Chaotic < Star-point < Contact < Greedy.
// Hugger lost 0/100 to Chaotic on 13×13 — overconcentrated dumpling shapes
// lose to spread-out random play — so it earns the slider's weakest seat.
// Star-point sits at slider mid as the recognisable textbook-Go default.
const List<_PersonalityLevel> _kSliderLevels = [
  _PersonalityLevel(
    FallbackStrategy.goHugger,
    'Hugger',
    'clusters stones into thick shapes.',
  ),
  _PersonalityLevel(
    FallbackStrategy.random,
    'Chaotic',
    'plays anywhere legal.',
  ),
  _PersonalityLevel(
    FallbackStrategy.goStarPoints,
    'Star-point',
    'favours classic opening points.',
  ),
  _PersonalityLevel(
    FallbackStrategy.goContact,
    'Contact',
    'plays right at your stones.',
  ),
  _PersonalityLevel(
    FallbackStrategy.goGreedyArea,
    'Greedy',
    'tries to maximise its territory.',
  ),
];

const int _kDefaultSliderIndex = 2; // Star-point

int _sliderIndexFor(FallbackStrategy strategy) {
  for (var i = 0; i < _kSliderLevels.length; i++) {
    if (_kSliderLevels[i].strategy == strategy) return i;
  }
  return _kDefaultSliderIndex;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Local drag state — the persisted value lives on the notifier, but the
  // slider thumb tracks the user's in-progress drag without committing until
  // they release. Initialised lazily in didChangeDependencies (InheritedWidget
  // lookups are illegal in initState).
  int? _sliderIndex;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sliderIndex ??= _sliderIndexFor(AppScope.of(context).fallback);
  }

  @override
  Widget build(BuildContext context) {
    final notifier = AppScope.of(context);
    final theme = Theme.of(context);
    final index = _sliderIndex ?? _kDefaultSliderIndex;
    final level = _kSliderLevels[index];

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
            const SizedBox(height: 16),
            Slider(
              min: 0,
              max: (_kSliderLevels.length - 1).toDouble(),
              divisions: _kSliderLevels.length - 1,
              value: index.toDouble(),
              activeColor: PiYingTheme.cinnabar,
              onChanged: (v) => setState(() => _sliderIndex = v.round()),
              onChangeEnd: (v) async {
                final i = v.round();
                await notifier.setFallback(_kSliderLevels[i].strategy);
              },
            ),
            const Divider(height: 48),
            FilledButton(
              // Plain FilledButton — picks up the theme's cinnabar bg and
              // ivory foreground automatically. The earlier `tonal` variant
              // with a per-button `foregroundColor: cinnabar` override
              // produced cinnabar text on cinnabar bg (invisible label).
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
