import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_engine/game_engine.dart';
import 'package:pi_ying/src/db/database_service.dart';
import 'package:pi_ying/src/screens/replay_screen.dart';

/// Builds a board with [stones] applied. Each stone is `(row, col, side)`.
Board _board(List<({int r, int c, int side})> stones) {
  final b = Board(13, 13);
  for (final s in stones) {
    b.set(s.r, s.c, s.side);
  }
  return b;
}

ReplayFrame _frame(Board board, int movePlayed) =>
    (board: board, movePlayed: movePlayed);

RecentGame _summary({
  String gameId = 'g1',
  int outcome = 1,
  int? playerArea = 84,
  int? cloneArea = 76,
  int totalMoves = 3,
}) => (
  gameId: gameId,
  startedAt: 0,
  totalMoves: totalMoves,
  outcome: outcome,
  playerArea: playerArea,
  cloneArea: cloneArea,
);

Widget _wrap(RecentGame game, List<ReplayFrame> frames) => MaterialApp(
  home: ReplayScreen(game: game, frames: frames),
);

void main() {
  testWidgets('opens paused at final ply', (tester) async {
    final frames = [
      _frame(_board([(r: 6, c: 6, side: 1)]), 6 * 13 + 6),
      _frame(
        _board([(r: 6, c: 6, side: 1), (r: 6, c: 7, side: -1)]),
        6 * 13 + 7,
      ),
      _frame(
        _board([
          (r: 6, c: 6, side: 1),
          (r: 6, c: 7, side: -1),
          (r: 7, c: 6, side: 1),
        ]),
        7 * 13 + 6,
      ),
    ];
    await tester.pumpWidget(_wrap(_summary(), frames));
    expect(find.text('YOU WIN'), findsOneWidget);
    expect(find.text('Move 3 / 3'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.text('AREA  ·  YOU 84  ·  CLONE 76'), findsOneWidget);
  });

  testWidgets('jump-to-start moves slider to 0', (tester) async {
    final frames = [
      _frame(_board([(r: 0, c: 0, side: 1)]), 0),
      _frame(_board([(r: 0, c: 0, side: 1), (r: 0, c: 1, side: -1)]), 1),
    ];
    await tester.pumpWidget(
      _wrap(_summary(totalMoves: 2, playerArea: null, cloneArea: null), frames),
    );
    expect(find.text('Move 2 / 2'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.skip_previous));
    await tester.pump();
    expect(find.text('Move 0 / 2'), findsOneWidget);
  });

  testWidgets('step-forward / step-back walk one ply', (tester) async {
    final frames = [
      _frame(_board([(r: 0, c: 0, side: 1)]), 0),
      _frame(_board([(r: 0, c: 0, side: 1), (r: 0, c: 1, side: -1)]), 1),
      _frame(
        _board([
          (r: 0, c: 0, side: 1),
          (r: 0, c: 1, side: -1),
          (r: 0, c: 2, side: 1),
        ]),
        2,
      ),
    ];
    await tester.pumpWidget(
      _wrap(_summary(totalMoves: 3, playerArea: null, cloneArea: null), frames),
    );
    await tester.tap(find.byIcon(Icons.skip_previous));
    await tester.pump();
    expect(find.text('Move 0 / 3'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    expect(find.text('Move 1 / 3'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    expect(find.text('Move 2 / 3'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();
    expect(find.text('Move 1 / 3'), findsOneWidget);
  });

  testWidgets('pass ply annotated', (tester) async {
    final stone = _board([(r: 6, c: 6, side: 1)]);
    final frames = [
      _frame(stone, 6 * 13 + 6),
      _frame(stone, 13 * 13), // pass: board unchanged
    ];
    await tester.pumpWidget(
      _wrap(_summary(totalMoves: 2, playerArea: null, cloneArea: null), frames),
    );
    expect(find.text('Move 2 / 2 (pass)'), findsOneWidget);
  });

  testWidgets('speed row shows ½×..4× and tapping selects directly', (
    tester,
  ) async {
    final frames = [
      _frame(_board([(r: 0, c: 0, side: 1)]), 0),
    ];
    await tester.pumpWidget(
      _wrap(_summary(totalMoves: 1, playerArea: null, cloneArea: null), frames),
    );
    for (final label in const ['½×', '1×', '2×', '3×', '4×']) {
      expect(find.text(label), findsOneWidget);
    }
    // Tap ½× — slow it down.
    await tester.tap(find.text('½×'));
    await tester.pump();
    // Tap 4× to fast-forward.
    await tester.tap(find.text('4×'));
    await tester.pump();
    // Back to 1×.
    await tester.tap(find.text('1×'));
    await tester.pump();
    // All five buttons still rendered (active state is visual, not text).
    for (final label in const ['½×', '1×', '2×', '3×', '4×']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('verdict reads "CLONE WINS" for bot-won games', (tester) async {
    final frames = [
      _frame(_board([(r: 0, c: 0, side: 1)]), 0),
    ];
    await tester.pumpWidget(
      _wrap(
        _summary(outcome: -1, totalMoves: 1, playerArea: 50, cloneArea: 50),
        frames,
      ),
    );
    expect(find.text('CLONE WINS'), findsOneWidget);
  });

  testWidgets('area readout suppressed when areas are null (resigned game)', (
    tester,
  ) async {
    final frames = [
      _frame(_board([(r: 0, c: 0, side: 1)]), 0),
    ];
    await tester.pumpWidget(
      _wrap(
        _summary(outcome: -1, totalMoves: 1, playerArea: null, cloneArea: null),
        frames,
      ),
    );
    expect(find.textContaining('AREA'), findsNothing);
  });
}
