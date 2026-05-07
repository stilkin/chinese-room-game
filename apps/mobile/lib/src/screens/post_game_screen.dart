import 'package:flutter/material.dart';

import '../app_scope.dart';

class PostGameScreen extends StatelessWidget {
  const PostGameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = AppScope.of(context);
    final outcome = notifier.outcome;
    final outcomeText = switch (outcome) {
      1 => 'You win!',
      -1 => 'Clone wins!',
      0 => 'Draw!',
      _ => '',
    };

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                outcomeText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Clone\'s final thought',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  notifier.narration.isEmpty ? '…' : notifier.narration,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                '${notifier.gamesPlayed} games played',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () async {
                  await notifier.startNewGame();
                  if (context.mounted) {
                    Navigator.pushReplacementNamed(context, '/game');
                  }
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Play Again', style: TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () =>
                    Navigator.popUntil(context, ModalRoute.withName('/')),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Home'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
