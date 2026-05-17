import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_ying/src/db/database_service.dart';
import 'package:pi_ying/src/screens/history_screen.dart';

RecentGame _g({
  String gameId = 'g',
  int startedAt = 0,
  int totalMoves = 0,
  int outcome = 1,
  int? playerArea,
  int? cloneArea,
}) => (
  gameId: gameId,
  startedAt: startedAt,
  totalMoves: totalMoves,
  outcome: outcome,
  playerArea: playerArea,
  cloneArea: cloneArea,
);

Widget _wrap(List<RecentGame> games, {NavigatorObserver? observer}) =>
    MaterialApp(
      home: HistoryScreen(games: games),
      navigatorObservers: observer == null ? const [] : [observer],
      routes: {'/replay': (_) => const Scaffold(body: Text('replay-target'))},
    );

void main() {
  testWidgets('empty state when no completed games', (tester) async {
    await tester.pumpWidget(_wrap(const []));
    expect(find.text('No completed games yet.'), findsOneWidget);
  });

  testWidgets('renders one row per completed game with metadata', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap([
        _g(
          gameId: 'g1',
          totalMoves: 87,
          outcome: 1,
          playerArea: 84,
          cloneArea: 76,
        ),
        _g(gameId: 'g2', totalMoves: 60, outcome: -1),
      ]),
    );
    expect(find.text('WIN'), findsOneWidget);
    expect(find.text('LOSS'), findsOneWidget);
    expect(find.text('87 moves'), findsOneWidget);
    expect(find.text('60 moves'), findsOneWidget);
    expect(find.text('84 : 76'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('tap row navigates to /replay with arguments', (tester) async {
    Route<dynamic>? observed;
    await tester.pumpWidget(
      _wrap([
        _g(
          gameId: 'g1',
          totalMoves: 42,
          outcome: 1,
          playerArea: 90,
          cloneArea: 79,
        ),
      ], observer: _ObservingNavigatorObserver((r) => observed = r)),
    );

    await tester.tap(find.text('WIN'));
    await tester.pumpAndSettle();

    expect(observed?.settings.name, '/replay');
    final args = observed!.settings.arguments;
    expect(args, isA<RecentGame>());
    expect((args! as RecentGame).gameId, 'g1');
  });
}

class _ObservingNavigatorObserver extends NavigatorObserver {
  final void Function(Route<dynamic>) onPush;
  _ObservingNavigatorObserver(this.onPush);
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == '/replay') onPush(route);
  }
}
