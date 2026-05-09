import 'package:flutter/material.dart';
import 'package:game_engine/game_engine.dart';

import '../app_scope.dart';
import '../state/game_notifier.dart';
import '../theme.dart';
import '../widgets/board_painter.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  GameNotifier? _notifier;

  // Drop-animation state.
  late final AnimationController _dropController;
  int _animatedMoveCounter = 0; // last move counter the animation ran for
  bool _isDropAnimating = false;
  bool _postGameNavScheduled = false;

  void _onChange() {
    if (!mounted) return;
    final n = _notifier;
    if (n == null) return;
    // Trigger drop animation when a new move arrives.
    if (n.moveCounter != _animatedMoveCounter && n.lastMoveRow >= 0) {
      _animatedMoveCounter = n.moveCounter;
      _isDropAnimating = true;
      _dropController.forward(from: 0).whenComplete(() {
        if (!mounted) return;
        setState(() => _isDropAnimating = false);
      });
    }
    // Latch so subsequent notifyListeners() calls (narration update,
    // isCloneThinking flips, etc.) don't enqueue a second navigation.
    if (n.outcome != null && !_postGameNavScheduled) {
      _postGameNavScheduled = true;
      // Brief pause on the game screen so the player sees the winning chip
      // and the highlight before navigating to post-game.
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/post-game');
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _dropController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = AppScope.of(context);
    if (next != _notifier) {
      _notifier?.removeListener(_onChange);
      next.addListener(_onChange);
      _notifier = next;
      // Sync the move counter so a fresh game (or resume) doesn't replay an
      // animation for moves that happened off-screen.
      _animatedMoveCounter = next.moveCounter;
    }
  }

  @override
  void dispose() {
    _dropController.dispose();
    _notifier?.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = _notifier!;
    final cols = notifier.rules.cols;
    final rows = notifier.rules.rows;
    final rules = notifier.rules;
    final winningCells = (rules is ConnectFourRules && notifier.outcome != null)
        ? rules.findWinningCells(notifier.displayBoard)
        : null;

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
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final cellSize = cellSizeFor(width, cols);
                  final height = cellSize * rows;
                  final size = Size(width, height);
                  return GestureDetector(
                    onTapUp: (details) {
                      // Block taps while a chip is mid-drop or it's not the
                      // player's turn — prevents stacking animations and
                      // double-fires.
                      if (_isDropAnimating ||
                          notifier.isCloneThinking ||
                          notifier.outcome != null) {
                        return;
                      }
                      final col = columnFromTap(
                        details.localPosition,
                        size,
                        cols,
                      );
                      if (col != null) notifier.playerMove(col);
                    },
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: Stack(
                        children: [
                          // Static board — exclude the most recent chip while
                          // its drop animation is running so we don't see two
                          // chips at the same cell.
                          CustomPaint(
                            size: size,
                            painter: BoardPainter(
                              notifier.displayBoard,
                              excludeRow: _isDropAnimating
                                  ? notifier.lastMoveRow
                                  : null,
                              excludeCol: _isDropAnimating
                                  ? notifier.lastMoveCol
                                  : null,
                              winningCells: winningCells,
                            ),
                          ),
                          // Animated chip falling into place.
                          if (_isDropAnimating)
                            AnimatedBuilder(
                              animation: _dropController,
                              builder: (context, _) {
                                return CustomPaint(
                                  size: size,
                                  painter: _DropOverlayPainter(
                                    progress: Curves.easeIn.transform(
                                      _dropController.value,
                                    ),
                                    landingRow: notifier.lastMoveRow,
                                    col: notifier.lastMoveCol,
                                    side: notifier.lastMoveSide,
                                    cellSize: cellSize,
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
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
    // Stroke only the two slanted sides; the bottom edge sits flush against
    // the bubble's top border, where the bubble already has a 2px outline.
    final sidesOnly = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height);
    canvas.drawPath(sidesOnly, stroke);
  }

  @override
  bool shouldRepaint(_BubbleTailPainter oldDelegate) => false;
}

/// Renders the in-flight chip falling from above the board down to its
/// landing cell. The static board (passed to BoardPainter) is rendered with
/// that cell excluded while this overlay is active, so there's never a
/// double-chip.
class _DropOverlayPainter extends CustomPainter {
  final double progress; // 0..1
  final int landingRow;
  final int col;
  final int side;
  final double cellSize;

  _DropOverlayPainter({
    required this.progress,
    required this.landingRow,
    required this.col,
    required this.side,
    required this.cellSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (landingRow < 0) return;
    final radius = cellSize * 0.4;
    // Start above the top of the board — chip should appear to fall from
    // off-screen, into row 0, and continue down to the landing row.
    final cx = col * cellSize + cellSize / 2;
    final startCy = -cellSize / 2;
    final endCy = landingRow * cellSize + cellSize / 2;
    final cy = startCy + (endCy - startCy) * progress;
    BoardPainter.paintFloatingChip(canvas, Offset(cx, cy), radius, side);
  }

  @override
  bool shouldRepaint(_DropOverlayPainter old) =>
      old.progress != progress ||
      old.landingRow != landingRow ||
      old.col != col ||
      old.side != side;
}
