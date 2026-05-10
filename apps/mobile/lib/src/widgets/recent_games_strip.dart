import 'package:flutter/material.dart';

import '../theme.dart';

/// Horizontal strip rendering one cell per past game outcome:
///   +1 (player won)  → cinnabar (the brand accent — your wins should pop)
///   -1 (clone won)   → muted cream (loss reads quieter than win)
///    0 (draw)        → outline grey
///
/// Layout: cells fill the strip's width left-to-right, oldest on the left.
/// More games → narrower cells. With ≤ ~120 games on a phone the cells are
/// distinct blocks; beyond that they degrade to thin lines.
class RecentGamesStrip extends StatelessWidget {
  final List<int> outcomes;
  final double height;

  const RecentGamesStrip({super.key, required this.outcomes, this.height = 28});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: PiYingTheme.surfaceLow,
        border: Border.all(color: PiYingTheme.outline, width: 2),
      ),
      child: outcomes.isEmpty
          ? Center(
              child: Text(
                'no games yet',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          : CustomPaint(painter: _StripPainter(outcomes), size: Size.infinite),
    );
  }
}

class _StripPainter extends CustomPainter {
  final List<int> outcomes;
  _StripPainter(this.outcomes);

  @override
  void paint(Canvas canvas, Size size) {
    if (outcomes.isEmpty) return;
    final cellWidth = size.width / outcomes.length;
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < outcomes.length; i++) {
      paint.color = _colorFor(outcomes[i]);
      final left = i * cellWidth;
      // Always at least 1 logical pixel wide so very long histories don't
      // disappear into background gaps.
      final w = cellWidth < 1 ? 1.0 : cellWidth;
      canvas.drawRect(Rect.fromLTWH(left, 0, w, size.height), paint);
    }
  }

  Color _colorFor(int outcome) {
    if (outcome == 1) return PiYingTheme.cinnabar;
    if (outcome == -1) return PiYingTheme.onSurfaceMuted;
    return PiYingTheme.outline;
  }

  @override
  bool shouldRepaint(_StripPainter old) => old.outcomes != outcomes;
}
