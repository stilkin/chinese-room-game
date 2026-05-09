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

const List<_PersonalityLevel> _kSliderLevels = [
  _PersonalityLevel(
    FallbackStrategy.random,
    'Chaotic',
    'plays anywhere. no plan.',
  ),
  _PersonalityLevel(
    FallbackStrategy.ownPileAdjacent,
    'Builder',
    'builds next to its own pieces.',
  ),
  _PersonalityLevel(
    FallbackStrategy.pileFocus,
    'Stacker',
    'stacks the tallest pile.',
  ),
  _PersonalityLevel(
    FallbackStrategy.greedyConnect,
    'Connector',
    'plays for longer chains.',
  ),
  _PersonalityLevel(
    FallbackStrategy.greedyConnectDefense,
    'Sentinel',
    'plays for chains. blocks losses.',
  ),
];

const int _kDefaultSliderIndex = 2; // Stacker

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _position;

  @override
  void initState() {
    super.initState();
    _position = _initialPosition(AppScope.of(context).fallback);
  }

  int _initialPosition(FallbackStrategy current) {
    final idx = _kSliderLevels.indexWhere((l) => l.strategy == current);
    return idx == -1 ? _kDefaultSliderIndex : idx;
  }

  @override
  Widget build(BuildContext context) {
    final notifier = AppScope.of(context);
    final theme = Theme.of(context);
    final level = _kSliderLevels[_position];

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
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
              value: _position.toDouble(),
              min: 0,
              max: (_kSliderLevels.length - 1).toDouble(),
              divisions: _kSliderLevels.length - 1,
              label: level.name,
              onChanged: (v) {
                setState(() => _position = v.round());
              },
              onChangeEnd: (v) {
                final idx = v.round();
                notifier.setFallback(_kSliderLevels[idx].strategy);
              },
            ),
            const Divider(height: 48),
            FilledButton.tonal(
              style: FilledButton.styleFrom(foregroundColor: PiYingTheme.red),
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

  Future<void> _confirmDelete(
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
            style: FilledButton.styleFrom(backgroundColor: PiYingTheme.red),
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
