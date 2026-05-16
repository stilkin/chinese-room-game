import 'package:flutter/material.dart';
import 'package:game_engine/game_engine.dart';

import 'src/app_scope.dart';
import 'src/db/database_service.dart';
import 'src/screens/game_screen.dart';
import 'src/screens/history_screen.dart';
import 'src/screens/post_game_screen.dart';
import 'src/screens/replay_screen.dart';
import 'src/screens/settings_screen.dart';
import 'src/screens/start_screen.dart';
import 'src/state/game_notifier.dart';
import 'src/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = DatabaseService();
  await db.init();

  final rules = GoRules(size: 13);
  final log = GameLog();
  final fallback = await db.loadFallback();
  final brain = CloneBrain(rules: rules, log: log, fallback: fallback);
  final notifier = GameNotifier(rules: rules, log: log, brain: brain, db: db);
  await notifier.init();

  runApp(PiYingApp(notifier: notifier));
}

class PiYingApp extends StatelessWidget {
  final GameNotifier notifier;

  const PiYingApp({super.key, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return AppScope(
      notifier: notifier,
      child: MaterialApp(
        title: 'Pi-Ying',
        theme: PiYingTheme.build(),
        initialRoute: '/',
        routes: {
          '/': (_) => const StartScreen(),
          '/game': (_) => const GameScreen(),
          '/post-game': (_) => const PostGameScreen(),
          '/settings': (_) => const SettingsScreen(),
          '/history': (_) => const HistoryScreen(),
        },
        onGenerateRoute: (settings) {
          if (settings.name == '/replay') {
            final game = settings.arguments! as RecentGame;
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => ReplayScreen(game: game),
            );
          }
          return null;
        },
      ),
    );
  }
}
