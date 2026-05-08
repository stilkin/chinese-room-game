import 'package:flutter/material.dart';

import '../app_scope.dart';

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = AppScope.of(context);
    return ListenableBuilder(
      listenable: notifier,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Pi-Ying',
                    style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Connect Four against a learning clone',
                    style: TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  const SizedBox(height: 48),
                  if (notifier.hasOngoingGame) ...[
                    FilledButton(
                      onPressed: () => _onResume(context),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                        child: Text('Resume', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => _onNewGame(context, confirm: true),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        child: Text('New Game'),
                      ),
                    ),
                  ] else
                    FilledButton(
                      onPressed: () => _onNewGame(context, confirm: false),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                        child: Text('New Game', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => Navigator.pushNamed(context, '/settings'),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 8,
                      ),
                      child: Text('Settings'),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    '${notifier.gamesPlayed} games played',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
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
          content: Text("Couldn't resume that game — it's been cleared."),
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
          title: const Text('Discard your unfinished game?'),
          content: const Text(
            'Starting a new game will erase your current one.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard & start'),
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
