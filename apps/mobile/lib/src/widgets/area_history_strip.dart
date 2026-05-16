import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../db/database_service.dart';
import '../theme.dart';

const double _kMaxRowHeight = 5.0;
const double _kMinRowHeight = 1.5;
const double _kEndcapWidth = 3.0;
// Transparent margin between an endcap and the proportion bar — keeps the
// endcap visually distinct from the bar instead of bleeding into it.
const double _kEndcapInnerGap = 1.5;
// Rows-to-height mapping: at or below this many games we paint at max
// height; at or above the strip's hard cap (100) we paint at min height.
const int _kRowsAtMaxHeight = 10;
const int _kRowsAtMinHeight = 100;

// Stones-on-board colours, mirrored from go_board.dart so the strip reads as
// "your stones vs the clone's" without the user needing a legend.
const Color _kPlayerColour = PiYingTheme.onSurface; // ivory
const Color _kCloneColour = Color(0xFF0E0E14); // near-black
const Color _kDrawColour = PiYingTheme.lineColor; // cream-amber
const Color _kDnfColour = PiYingTheme.onSurfaceMuted;

/// Returns the per-row height to use when there are [rowCount] games. Caps
/// at [_kMaxRowHeight] for small counts (≤ 10) and shrinks linearly toward
/// [_kMinRowHeight] for the hard-cap (100 games), so the strip stays visible
/// across the full range.
double rowHeightFor(int rowCount) {
  if (rowCount <= _kRowsAtMaxHeight) return _kMaxRowHeight;
  if (rowCount >= _kRowsAtMinHeight) return _kMinRowHeight;
  final t =
      (rowCount - _kRowsAtMaxHeight) / (_kRowsAtMinHeight - _kRowsAtMaxHeight);
  return _kMaxRowHeight - t * (_kMaxRowHeight - _kMinRowHeight);
}

// Gap between rows scales with row height — at 5px rows a 1px gap reads
// clean; at 1.5px rows the gap collapses to roughly a third so adjacent
// rows remain distinguishable without merging.
double _rowGapFor(double rowHeight) => rowHeight * 0.3;

/// Vertical strip of completed-game proportion bars. Each row is one game,
/// most-recent at the top. The bar's left/right split shows the player vs
/// clone area share; small endcaps on each side carry the winner's colour
/// to disambiguate near-50/50 rows. Resigned / legacy rows render as a
/// shorter muted bar (no endcaps) so they read as "no real outcome".
///
/// `games` is taken as-is — caller is responsible for the most-recent-first
/// ordering and the 100-row cap (the loader does both).
class AreaHistoryStrip extends StatelessWidget {
  final List<RecentGame> games;

  const AreaHistoryStrip({super.key, required this.games});

  static double heightFor(int rowCount) {
    if (rowCount == 0) return 0;
    final h = rowHeightFor(rowCount);
    final gap = _rowGapFor(h);
    return rowCount * h + (rowCount - 1) * gap;
  }

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

/// Paints one history row into [rect] on [canvas] using [paint].
///
/// Resigned / legacy rows (null area) render as a muted bar limited to the
/// inner span between the endcap slots — the endcap slots stay transparent,
/// so DNF rows are visually shorter than scored games. Scored rows fill the
/// whole [rect]: winner-coloured endcaps at the edges, then a small
/// transparent gap, then the ivory/near-black proportion bar in the middle.
///
/// If [drawnRects] is supplied, every fill is appended to it — used by widget
/// tests to inspect paint output without golden-file comparison.
void paintAreaHistoryRow(
  Canvas canvas,
  Paint paint,
  Rect rect,
  RecentGame game, {
  List<PaintedRect>? drawnRects,
  double endcapWidth = _kEndcapWidth,
  double endcapInnerGap = _kEndcapInnerGap,
}) {
  void fill(Rect r, Color color) {
    paint.color = color;
    canvas.drawRect(r, paint);
    drawnRects?.add((rect: r, color: color));
  }

  // The proportion-bar slot (between the two endcaps + their inner gaps).
  final barLeft = rect.left + endcapWidth + endcapInnerGap;
  final barRight = rect.right - endcapWidth - endcapInnerGap;
  final barWidth = barRight - barLeft;

  if (game.playerArea == null || game.cloneArea == null) {
    // DNF / resigned / pre-v6 legacy: muted bar over the proportion-bar slot
    // only. Endcap slots stay transparent so the row reads as visually
    // shorter than a real scored game.
    if (barWidth > 0) {
      fill(
        Rect.fromLTWH(barLeft, rect.top, barWidth, rect.height),
        _kDnfColour,
      );
    }
    return;
  }
  final endcapColour = switch (game.outcome) {
    1 => _kPlayerColour,
    -1 => _kCloneColour,
    _ => _kDrawColour,
  };
  fill(
    Rect.fromLTWH(rect.left, rect.top, endcapWidth, rect.height),
    endcapColour,
  );
  fill(
    Rect.fromLTWH(rect.right - endcapWidth, rect.top, endcapWidth, rect.height),
    endcapColour,
  );
  if (barWidth <= 0) return;
  final total = game.playerArea! + game.cloneArea!;
  final playerFraction = total == 0 ? 0.5 : game.playerArea! / total;
  final playerWidth = barWidth * playerFraction;
  fill(
    Rect.fromLTWH(barLeft, rect.top, playerWidth, rect.height),
    _kPlayerColour,
  );
  fill(
    Rect.fromLTWH(
      barLeft + playerWidth,
      rect.top,
      barWidth - playerWidth,
      rect.height,
    ),
    _kCloneColour,
  );
}

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
    final rowHeight = rowHeightFor(games.length);
    final rowGap = _rowGapFor(rowHeight);
    for (var i = 0; i < games.length; i++) {
      final top = i * (rowHeight + rowGap);
      paintAreaHistoryRow(
        canvas,
        paint,
        Rect.fromLTWH(0, top, size.width, rowHeight),
        games[i],
        drawnRects: drawnRects,
      );
    }
  }

  @override
  bool shouldRepaint(AreaHistoryPainter old) => !listEquals(old.games, games);
}
