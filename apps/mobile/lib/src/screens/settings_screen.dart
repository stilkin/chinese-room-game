import 'package:flutter/material.dart';
import 'package:game_engine/game_engine.dart';

import '../app_scope.dart';
import '../state/game_notifier.dart';

const _fallbackLabels = {
  FallbackStrategy.random: 'Random',
  FallbackStrategy.middleFocus: 'Middle Focus',
  FallbackStrategy.edgeFocus: 'Edge Focus',
  FallbackStrategy.pileFocus: 'Pile Focus',
};

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = AppScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Text(
                'Fallback personality',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Used by the clone when it has no relevant data.',
                style: TextStyle(color: Colors.black54),
              ),
            ),
            const SizedBox(height: 8),
            RadioGroup<FallbackStrategy>(
              groupValue: notifier.fallback,
              onChanged: (v) {
                if (v != null) notifier.setFallback(v);
              },
              child: Column(
                children: [
                  for (final entry in _fallbackLabels.entries)
                    RadioListTile<FallbackStrategy>(
                      title: Text(entry.value),
                      value: entry.key,
                    ),
                ],
              ),
            ),
            const Divider(height: 32),
            FilledButton.tonal(
              style: FilledButton.styleFrom(foregroundColor: Colors.red),
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
