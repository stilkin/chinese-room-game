import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_engine/game_engine.dart';
import 'package:pi_ying/src/app_scope.dart';
import 'package:pi_ying/src/db/database_service.dart';
import 'package:pi_ying/src/screens/start_screen.dart';
import 'package:pi_ying/src/state/game_notifier.dart';
import 'package:pi_ying/src/widgets/area_history_strip.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Initialises the global `databaseFactory` reference so the
    // DatabaseService default constructor doesn't throw. We never call
    // `init()`, so no native sqlite3 lookup is actually performed.
    sqfliteFfiInit();
  });

  testWidgets('tap on strip pushes /history', (tester) async {
    // Build a notifier without booting its DB: the start screen only reads
    // already-initialised fields (`recentGames`, `gamesPlayed`, …), and the
    // tap handler doesn't touch the DB. We never call `init()`, so no
    // sqlite3-via-FFI symbol resolution is attempted from flutter_tester.
    final rules = GoRules(size: 13);
    final log = GameLog();
    final brain = CloneBrain(rules: rules, log: log);
    final notifier = GameNotifier(
      rules: rules,
      log: log,
      brain: brain,
      db: DatabaseService.withFactory(databaseFactoryFfi),
    );

    Route<dynamic>? observed;
    await tester.pumpWidget(
      AppScope(
        notifier: notifier,
        child: MaterialApp(
          home: const StartScreen(),
          navigatorObservers: [
            _ObservingNavigatorObserver((r) => observed = r),
          ],
          routes: {
            '/history': (_) => const Scaffold(body: Text('history-target')),
          },
        ),
      ),
    );

    await tester.tap(find.byType(AreaHistoryStrip), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(observed?.settings.name, '/history');
  });
}

class _ObservingNavigatorObserver extends NavigatorObserver {
  final void Function(Route<dynamic>) onPush;
  _ObservingNavigatorObserver(this.onPush);
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == '/history') onPush(route);
  }
}
