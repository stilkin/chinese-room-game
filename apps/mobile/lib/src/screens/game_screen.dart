import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../state/game_notifier.dart';
import '../theme.dart';
import '../widgets/go_board.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  GameNotifier? _notifier;
  // Latch so the post-game navigation fires once even if `notifyListeners`
  // is invoked again before we've navigated away (narration update,
  // isCloneThinking flips, etc.).
  bool _postGameNavScheduled = false;

  void _onChange() {
    if (!mounted) return;
    final n = _notifier;
    if (n == null) return;
    if (n.outcome != null && !_postGameNavScheduled) {
      _postGameNavScheduled = true;
      // Brief pause on the game screen so the player sees the final board
      // and last-move ring before navigating to post-game.
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/post-game');
      });
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
    final canTap = !notifier.isCloneThinking && notifier.outcome == null;

    return Scaffold(
      appBar: AppBar(title: const Text('PI-YING')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusBanner(
                isCloneThinking: notifier.isCloneThinking,
                outcome: notifier.outcome,
              ),
              const SizedBox(height: 12),
              AspectRatio(
                aspectRatio: 1,
                child: GoBoard(
                  board: notifier.displayBoard,
                  lastMoveRow: notifier.lastMoveRow,
                  lastMoveCol: notifier.lastMoveCol,
                  onTap: canTap ? notifier.playerMove : null,
                ),
              ),
              const SizedBox(height: 16),
              _PassButton(onPressed: canTap ? notifier.pass : null),
              const SizedBox(height: 16),
              _NarrationBubble(
                text: notifier.narration.isEmpty ? '...' : notifier.narration,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Status banner above the board: cyan "YOUR TURN", muted "CLONE THINKING…",
/// or amber "GAME OVER". Press Start 2P, all caps, retro vibe.
class _StatusBanner extends StatelessWidget {
  final bool isCloneThinking;
  final int? outcome;

  const _StatusBanner({required this.isCloneThinking, required this.outcome});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final (label, color) = outcome != null
        ? ('GAME OVER', PiYingTheme.amber)
        : isCloneThinking
        ? ('CLONE THINKING…', PiYingTheme.onSurfaceMuted)
        : ('YOUR TURN', PiYingTheme.cyan);
    return Center(
      child: Text(
        label,
        style: textTheme.titleSmall?.copyWith(color: color, letterSpacing: 2),
      ),
    );
  }
}

class _PassButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const _PassButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: PiYingTheme.outline, width: 2),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
        child: const Text('PASS', style: TextStyle(letterSpacing: 2)),
      ),
    );
  }
}

/// Speech-bubble for the clone's narration. Sharp 2px outline matching the
/// theme, with a small triangular tail pointing up at the board so it reads
/// as "the clone said this about the move it just played."
class _NarrationBubble extends StatelessWidget {
  final String text;
  const _NarrationBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: PiYingTheme.surfaceLow,
            border: Border.all(color: PiYingTheme.outline, width: 2),
          ),
          constraints: const BoxConstraints(minHeight: 80),
          child: Text(text, style: textTheme.bodyMedium),
        ),
        // Tail — a pixel-y notch pointing up to the board.
        Positioned(
          top: -8,
          left: 28,
          child: CustomPaint(
            size: const Size(16, 8),
            painter: _BubbleTailPainter(),
          ),
        ),
      ],
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = PiYingTheme.surfaceLow;
    final stroke = Paint()
      ..color = PiYingTheme.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, fill);
    final sidesOnly = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height);
    canvas.drawPath(sidesOnly, stroke);
  }

  @override
  bool shouldRepaint(_BubbleTailPainter oldDelegate) => false;
}
