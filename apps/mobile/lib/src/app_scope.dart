import 'package:flutter/widgets.dart';

import 'state/game_notifier.dart';

class AppScope extends InheritedNotifier<GameNotifier> {
  const AppScope({
    super.key,
    required GameNotifier super.notifier,
    required super.child,
  });

  static GameNotifier of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope found in widget tree');
    return scope!.notifier!;
  }
}
