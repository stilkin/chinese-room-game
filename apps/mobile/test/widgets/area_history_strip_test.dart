import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_ying/src/db/database_service.dart';
import 'package:pi_ying/src/theme.dart';
import 'package:pi_ying/src/widgets/area_history_strip.dart';

const _kPlayer = PiYingTheme.onSurface;
const _kClone = Color(0xFF0E0E14);
const _kDraw = PiYingTheme.lineColor;
const _kDnf = PiYingTheme.onSurfaceMuted;

RecentGame _game({
  required int outcome,
  required int? playerArea,
  required int? cloneArea,
  String gameId = 'g',
  int startedAt = 0,
  int totalMoves = 0,
}) => (
  gameId: gameId,
  startedAt: startedAt,
  totalMoves: totalMoves,
  outcome: outcome,
  playerArea: playerArea,
  cloneArea: cloneArea,
);

/// Pumps the strip at a fixed width so the painter's rects are predictable.
Future<AreaHistoryPainter> _pumpStrip(
  WidgetTester tester,
  List<RecentGame> games, {
  double width = 200,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: AreaHistoryStrip(games: games),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  // Multiple CustomPaint widgets exist in the tree (Material chrome uses
  // them internally). Walk descendants of AreaHistoryStrip to find ours.
  final paintWidgets = tester.widgetList<CustomPaint>(
    find.descendant(
      of: find.byType(AreaHistoryStrip),
      matching: find.byType(CustomPaint),
    ),
  );
  return paintWidgets
      .map((p) => p.painter)
      .whereType<AreaHistoryPainter>()
      .single;
}

void main() {
  testWidgets('empty list renders the placeholder', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AreaHistoryStrip(games: [])),
      ),
    );
    expect(find.text('no games yet'), findsOneWidget);
  });

  // Geometry constants mirrored from area_history_strip.dart so the
  // assertions stay readable. If those move, this file moves with them.
  const endcapWidth = 3.0;
  const endcapInnerGap = 1.5;
  const stripWidth = 200.0;
  const barWidth = stripWidth - 2 * endcapWidth - 2 * endcapInnerGap; // 191.0

  testWidgets('player win: ivory endcaps + ivory-leaning bar', (tester) async {
    final painter = await _pumpStrip(tester, [
      _game(outcome: 1, playerArea: 80, cloneArea: 20),
    ]);
    final colours = painter.drawnRects.map((r) => r.color).toList();
    // Two endcap rects + two proportion rects = 4 fills total per row.
    expect(painter.drawnRects, hasLength(4));
    expect(colours.where((c) => c == _kPlayer).length, 3); // 2 endcaps + bar
    expect(colours.where((c) => c == _kClone).length, 1);
    final playerBarRect = painter.drawnRects.firstWhere(
      (r) => r.color == _kPlayer && r.rect.width > endcapWidth,
    );
    expect(playerBarRect.rect.width, closeTo(0.8 * barWidth, 0.001));
  });

  testWidgets('clone win: dark endcaps', (tester) async {
    final painter = await _pumpStrip(tester, [
      _game(outcome: -1, playerArea: 30, cloneArea: 90),
    ]);
    final endcaps = painter.drawnRects
        .where((r) => r.rect.width == endcapWidth)
        .toList();
    expect(endcaps, hasLength(2));
    expect(endcaps.every((r) => r.color == _kClone), isTrue);
  });

  testWidgets('draw: cream-amber endcaps, 50/50 bar', (tester) async {
    final painter = await _pumpStrip(tester, [
      _game(outcome: 0, playerArea: 50, cloneArea: 50),
    ]);
    final endcaps = painter.drawnRects
        .where((r) => r.rect.width == endcapWidth)
        .toList();
    expect(endcaps.every((r) => r.color == _kDraw), isTrue);
    final playerBar = painter.drawnRects.firstWhere((r) => r.color == _kPlayer);
    final cloneBar = painter.drawnRects.firstWhere((r) => r.color == _kClone);
    expect(playerBar.rect.width, closeTo(cloneBar.rect.width, 0.001));
  });

  testWidgets('DNF / null area: muted bar limited to inner width, no endcaps', (
    tester,
  ) async {
    final painter = await _pumpStrip(tester, [
      _game(outcome: -1, playerArea: null, cloneArea: null),
    ]);
    expect(painter.drawnRects, hasLength(1));
    expect(painter.drawnRects.first.color, _kDnf);
    // Limited to the proportion-bar slot — endcap zones stay transparent.
    expect(painter.drawnRects.first.rect.width, closeTo(barWidth, 0.001));
    expect(
      painter.drawnRects.first.rect.left,
      closeTo(endcapWidth + endcapInnerGap, 0.001),
    );
  });

  testWidgets('multi-row strip stacks top-down', (tester) async {
    final painter = await _pumpStrip(tester, [
      _game(outcome: 1, playerArea: 60, cloneArea: 40),
      _game(outcome: -1, playerArea: 30, cloneArea: 70),
      _game(outcome: -1, playerArea: null, cloneArea: null),
    ]);
    // 3 rows × varying rect counts (4, 4, 1) = 9 rects total.
    expect(painter.drawnRects, hasLength(9));
    // ≤10 games → max row height 5.0 with gap 1.5, so tops are 0, 6.5, 13.
    final tops = painter.drawnRects.map((r) => r.rect.top).toSet().toList()
      ..sort();
    expect(tops, [0.0, 6.5, 13.0]);
  });

  test('rowHeightFor scales smoothly from max to min', () {
    expect(rowHeightFor(0), 5.0);
    expect(rowHeightFor(10), 5.0);
    expect(rowHeightFor(100), 1.5);
    expect(rowHeightFor(150), 1.5);
    // Linearly between: at midpoint (55 games) ≈ midpoint between max and min.
    expect(rowHeightFor(55), closeTo((5.0 + 1.5) / 2, 0.05));
  });
}
