## Why

The game engine provides the clone brain, but players need an actual app to play against it. The mobile app is the first playable surface — it validates whether the core loop (play, learn, narrate) is fun before investing in online features or additional games.

## What Changes

- Create `apps/mobile/` Flutter app within the pub workspace
- Implement start screen with new game button, settings button, and games-played count
- Implement game screen with Connect Four board (CustomPainter), tap-to-drop interaction, clone narration display, and turn indicator
- Implement post-game screen showing outcome, clone's final thought, total games played, and play again / back to home navigation
- Implement settings screen with fallback personality picker (switchable between games) and delete-all-game-logs button (clone reset)
- Implement SQLite persistence via sqflite — store game states as they're created, load all into memory on startup for clone brain search
- Wire up game_engine package for rules, clone brain, and narration
- State management via ChangeNotifier

## Capabilities

### New Capabilities

- `start-screen`: Home screen with new game entry point, settings navigation, and games-played summary
- `game-screen`: Connect Four gameplay — board rendering, tap input, piece dropping, clone turn with narration, win/draw detection and transition to post-game
- `post-game-screen`: Game outcome display, clone final thought, stats, and navigation (play again / home)
- `settings-screen`: Fallback personality picker and delete-all-game-logs (clone reset)
- `game-persistence`: SQLite storage of game states via sqflite — write on each move, bulk load on startup, delete all for reset
- `game-flow`: Turn management, game lifecycle (new game → play → end → backfill outcomes), ChangeNotifier state management

### Modified Capabilities

(none — greenfield project)

## Impact

- New Flutter app at `apps/mobile/` with its own `pubspec.yaml`
- Dependencies: `game_engine` (path), `sqflite`, `path_provider`
- Root `pubspec.yaml` updated to include `apps/mobile/` in the pub workspace
- Targets Android and iOS from a single codebase
