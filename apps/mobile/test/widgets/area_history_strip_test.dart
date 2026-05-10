import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_ying/src/db/database_service.dart';
import 'package:pi_ying/src/theme.dart';
import 'package:pi_ying/src/widgets/area_history_strip.dart';

const _kPlayer = PiYingTheme.onSurface;
const _kClone = Color(0xFF0E0E14);
const _kDraw = PiYingTheme.lineColor;
const _kDnf = PiYingTheme.onSurfaceMuted;

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

  testWidgets('player win: ivory endcaps + ivory-leaning bar', (tester) async {
    final painter = await _pumpStrip(tester, [
      (outcome: 1, playerArea: 80, cloneArea: 20),
    ]);
    final colours = painter.drawnRects.map((r) => r.color).toList();
    // Two endcap rects + two proportion rects = 4 fills total per row.
    expect(painter.drawnRects, hasLength(4));
    expect(colours.where((c) => c == _kPlayer).length, 3); // 2 endcaps + bar
    expect(colours.where((c) => c == _kClone).length, 1);
    // Player fraction is 0.8 → bar is 80% of (200 - 6) = 155.2
    final barRects = painter.drawnRects
        .where((r) => r.rect.left >= 3 && r.rect.right <= 197)
        .toList();
    final playerBar = barRects.firstWhere((r) => r.color == _kPlayer);
    expect(playerBar.rect.width, closeTo(0.8 * (200 - 6), 0.001));
  });

  testWidgets('clone win: dark endcaps', (tester) async {
    final painter = await _pumpStrip(tester, [
      (outcome: -1, playerArea: 30, cloneArea: 90),
    ]);
    // First and last rects (the endcaps) should both be the clone colour.
    final endcaps = painter.drawnRects
        .where((r) => r.rect.width == 3.0)
        .toList();
    expect(endcaps, hasLength(2));
    expect(endcaps.every((r) => r.color == _kClone), isTrue);
  });

  testWidgets('draw: cream-amber endcaps, 50/50 bar', (tester) async {
    final painter = await _pumpStrip(tester, [
      (outcome: 0, playerArea: 50, cloneArea: 50),
    ]);
    final endcaps = painter.drawnRects
        .where((r) => r.rect.width == 3.0)
        .toList();
    expect(endcaps.every((r) => r.color == _kDraw), isTrue);
    final playerBar = painter.drawnRects.firstWhere((r) => r.color == _kPlayer);
    final cloneBar = painter.drawnRects.firstWhere((r) => r.color == _kClone);
    expect(playerBar.rect.width, closeTo(cloneBar.rect.width, 0.001));
  });

  testWidgets('DNF / null area: solid muted bar, no endcaps', (tester) async {
    final painter = await _pumpStrip(tester, [
      (outcome: -1, playerArea: null, cloneArea: null),
    ]);
    expect(painter.drawnRects, hasLength(1));
    expect(painter.drawnRects.first.color, _kDnf);
    // Spans the whole width.
    expect(painter.drawnRects.first.rect.width, 200.0);
  });

  testWidgets('multi-row strip stacks top-down', (tester) async {
    final painter = await _pumpStrip(tester, [
      (outcome: 1, playerArea: 60, cloneArea: 40),
      (outcome: -1, playerArea: 30, cloneArea: 70),
      (outcome: -1, playerArea: null, cloneArea: null),
    ]);
    // 3 rows × varying rect counts (4, 4, 1) = 9 rects total.
    expect(painter.drawnRects, hasLength(9));
    // First row near top, last row farther down.
    final tops = painter.drawnRects.map((r) => r.rect.top).toSet().toList()
      ..sort();
    expect(tops, [0.0, 4.0, 8.0]);
  });
}
