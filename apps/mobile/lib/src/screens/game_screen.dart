import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../state/game_notifier.dart';
import '../widgets/board_painter.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  GameNotifier? _notifier;

  void _onChange() {
    if (!mounted) return;
    if (_notifier?.outcome != null) {
      Navigator.pushReplacementNamed(context, '/post-game');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = AppScope.of(context);
    if (next != _notifier) {
      _notifier?.removeListener(_onChange);
      next.addListener(_onChange);
      _notifier = next;
    }
  }

  @override
  void dispose() {
    _notifier?.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = _notifier!;
    final cols = notifier.rules.cols;
    final rows = notifier.rules.rows;

    return Scaffold(
      appBar: AppBar(title: const Text('Pi-Ying')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                notifier.isCloneThinking
                    ? 'Clone is thinking…'
                    : (notifier.outcome == null ? 'Your turn' : 'Game over'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final cellSize = width / cols;
                  final height = cellSize * rows;
                  final size = Size(width, height);
                  return GestureDetector(
                    onTapUp: (details) {
                      final col = columnFromTap(
                        details.localPosition,
                        size,
                        cols,
                      );
                      if (col != null) notifier.playerMove(col);
                    },
                    child: CustomPaint(
                      size: size,
                      painter: BoardPainter(notifier.displayBoard),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                constraints: const BoxConstraints(minHeight: 80),
                child: Text(
                  notifier.narration.isEmpty
                      ? 'The clone is silent. Make your move.'
                      : notifier.narration,
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
