import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../db/database_service.dart';
import '../theme.dart';

const double _kRowHeight = 3.0;
const double _kRowGap = 1.0;
const double _kEndcapWidth = 3.0;

// Stones-on-board colours, mirrored from go_board.dart so the strip reads as
// "your stones vs the clone's" without the user needing a legend.
const Color _kPlayerColour = PiYingTheme.onSurface; // ivory
const Color _kCloneColour = Color(0xFF0E0E14); // near-black
const Color _kDrawColour = PiYingTheme.lineColor; // cream-amber
const Color _kDnfColour = PiYingTheme.onSurfaceMuted;

/// Vertical strip of completed-game proportion bars. Each row is one game,
/// most-recent at the top. The bar's left/right split shows the player vs
/// clone area share; small endcaps on each side carry the winner's colour
/// to disambiguate near-50/50 rows.
///
/// `games` is taken as-is — caller is responsible for the most-recent-first
/// ordering and the 100-row cap (the loader does both).
class AreaHistoryStrip extends StatelessWidget {
  final List<RecentGame> games;

  const AreaHistoryStrip({super.key, required this.games});

  static double heightFor(int rowCount) =>
      rowCount == 0 ? 0 : rowCount * _kRowHeight + (rowCount - 1) * _kRowGap;

  @override
  Widget build(BuildContext context) {
    if (games.isEmpty) {
      return Center(
        child: Text(
          'no games yet',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      height: heightFor(games.length),
      child: CustomPaint(
        painter: AreaHistoryPainter(games),
        size: Size.infinite,
      ),
    );
  }
}

@visibleForTesting
typedef PaintedRect = ({Rect rect, Color color});

class AreaHistoryPainter extends CustomPainter {
  final List<RecentGame> games;

  /// Test-only sink so widget tests can assert "row 0 has these rects" without
  /// golden-file pixel comparisons. Populated on each `paint` call.
  @visibleForTesting
  final List<PaintedRect> drawnRects = [];

  AreaHistoryPainter(this.games);

  @override
  void paint(Canvas canvas, Size size) {
    drawnRects.clear();
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < games.length; i++) {
      final top = i * (_kRowHeight + _kRowGap);
      _paintRow(canvas, paint, size.width, top, games[i]);
    }
  }

  void _paintRow(
    Canvas canvas,
    Paint paint,
    double width,
    double top,
    RecentGame game,
  ) {
    if (game.playerArea == null || game.cloneArea == null) {
      // DNF / resigned / pre-v6 legacy: solid muted bar, no endcaps.
      _fill(
        canvas,
        paint,
        Rect.fromLTWH(0, top, width, _kRowHeight),
        _kDnfColour,
      );
      return;
    }
    final endcapColour = switch (game.outcome) {
      1 => _kPlayerColour,
      -1 => _kCloneColour,
      _ => _kDrawColour,
    };
    // Left endcap.
    _fill(
      canvas,
      paint,
      Rect.fromLTWH(0, top, _kEndcapWidth, _kRowHeight),
      endcapColour,
    );
    // Right endcap.
    _fill(
      canvas,
      paint,
      Rect.fromLTWH(width - _kEndcapWidth, top, _kEndcapWidth, _kRowHeight),
      endcapColour,
    );
    // Proportion bar between the endcaps.
    final barLeft = _kEndcapWidth;
    final barWidth = width - 2 * _kEndcapWidth;
    if (barWidth <= 0) return;
    final total = game.playerArea! + game.cloneArea!;
    final playerFraction = total == 0 ? 0.5 : game.playerArea! / total;
    final playerWidth = barWidth * playerFraction;
    _fill(
      canvas,
      paint,
      Rect.fromLTWH(barLeft, top, playerWidth, _kRowHeight),
      _kPlayerColour,
    );
    _fill(
      canvas,
      paint,
      Rect.fromLTWH(
        barLeft + playerWidth,
        top,
        barWidth - playerWidth,
        _kRowHeight,
      ),
      _kCloneColour,
    );
  }

  void _fill(Canvas canvas, Paint paint, Rect rect, Color color) {
    paint.color = color;
    canvas.drawRect(rect, paint);
    drawnRects.add((rect: rect, color: color));
  }

  @override
  bool shouldRepaint(AreaHistoryPainter old) => !listEquals(old.games, games);
}
