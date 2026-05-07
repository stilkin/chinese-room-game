## 1. App Setup

- [x] 1.1 Create `apps/mobile/` Flutter project with `flutter create`
- [x] 1.2 Update `pubspec.yaml`: add `game_engine` path dependency, `sqflite`, `path_provider`
- [x] 1.3 Update root `pubspec.yaml` to include `apps/mobile/` in the pub workspace
- [x] 1.4 Verify `flutter analyze` and `flutter test` run cleanly on the empty app

## 2. SQLite Persistence

- [x] 2.1 Create `DatabaseService` class: initialize SQLite database, create `game_states`, `games`, and `clone_config` tables
- [x] 2.2 Implement `insertGameState()`: write a single GameState row with board as byte blob
- [x] 2.3 Implement `loadAllGameStates()`: bulk read all rows, deserialize boards from blobs into engine GameState objects
- [x] 2.4 Implement `backfillOutcomes()`: update outcome and moves_to_end for all states in a completed game (per-side outcome flip; explicit inverted-row insertion intentionally omitted — the engine's per-move perspective canonicalization already produces both POVs)
- [x] 2.5 Implement `insertGame()` and `updateGameOutcome()` for the games table
- [x] 2.6 Implement `getGamesPlayedCount()`: return total completed games
- [x] 2.7 Implement `loadCloneConfig()` and `saveCloneConfig()` for fallback personality setting
- [x] 2.8 Implement `deleteAllData()`: drop all game states, games, and reset clone config
- [x] 2.9 Write tests: insert/load round-trip, backfill correctness, board blob round-trip, delete all

## 3. Game State Management

- [x] 3.1 Create `GameNotifier` extending `ChangeNotifier`: holds current board, turn, outcome, narration, game_id
- [x] 3.2 Implement `startNewGame()`: reset board, create game record, set player turn
- [x] 3.3 Implement `playerMove(column)`: validate legal move, apply to board via engine, canonicalize and persist state, check win/draw, switch to clone turn
- [x] 3.4 Implement `cloneTurn()`: invoke clone brain search, apply selected move, persist state, update narration, check win/draw, switch to player turn
- [x] 3.5 Implement `endGame()`: backfill outcomes in database, update game record (no separate inverted-state insertion — see 2.4)
- [x] 3.6 Wire `DatabaseService` into `GameNotifier`: load all states on init, persist on each move
- [x] 3.7 Write tests: turn alternation, game lifecycle, outcome detection triggers endGame

## 4. Start Screen

- [x] 4.1 Create `StartScreen` widget: app title/branding area
- [x] 4.2 Add "New Game" button that calls `GameNotifier.startNewGame()` and navigates to `/game`
- [x] 4.3 Add "Settings" button that navigates to `/settings`
- [x] 4.4 Display games-played count from `DatabaseService.getGamesPlayedCount()`

## 5. Game Screen

- [x] 5.1 Create `BoardPainter` (CustomPainter): draw 7×6 grid with empty cells, player pieces, and clone pieces in distinct colors
- [x] 5.2 Implement tap-to-column mapping: convert touch coordinates to column index (0-6)
- [x] 5.3 Create `GameScreen` widget: board painter, tap handler calling `GameNotifier.playerMove()`, ignore taps during clone turn or on full columns
- [x] 5.4 Add narration display area: prominently show `GameNotifier.narration` text below/above the board
- [x] 5.5 Add turn indicator: display whose turn it is (player or "Clone is thinking...")
- [x] 5.6 Wire game-end detection: navigate to `/post-game` when `GameNotifier.outcome` is set

## 6. Post-Game Screen

- [x] 6.1 Create `PostGameScreen` widget: display outcome text ("You win!" / "Clone wins!" / "Draw!")
- [x] 6.2 Display clone's last narration as "final thought"
- [x] 6.3 Display updated total games-played count
- [x] 6.4 Add "Play Again" button: calls `startNewGame()` and navigates to `/game`
- [x] 6.5 Add "Home" button: navigates to `/` (start screen)

## 7. Settings Screen

- [x] 7.1 Create `SettingsScreen` widget with back navigation
- [x] 7.2 Add fallback personality picker (dropdown or radio): Random, Middle Focus, Edge Focus, Pile Focus
- [x] 7.3 Wire picker to `DatabaseService.saveCloneConfig()` — persist selection, default to Random
- [x] 7.4 Add "Delete All Game Logs" button with confirmation dialog
- [x] 7.5 Wire delete to `DatabaseService.deleteAllData()` and clear in-memory GameLog

## 8. Navigation & App Shell

- [x] 8.1 Set up `MaterialApp` with named routes: `/`, `/game`, `/post-game`, `/settings`
- [x] 8.2 Wire `GameNotifier` as app-level state via `ListenableBuilder` or provider pattern (used `InheritedNotifier` via `AppScope`)
- [x] 8.3 Initialize `DatabaseService` and bulk-load game states before showing start screen

## 9. Integration

- [ ] 9.1 Manual test: play a full game against the clone, verify narration appears, post-game shows correct outcome
- [ ] 9.2 Manual test: change fallback personality in settings, start a new game with empty data, verify fallback is used
- [ ] 9.3 Manual test: delete all game logs, verify clone resets and games-played count is 0
- [ ] 9.4 Manual test: close and reopen the app, verify game data persists and clone remembers past games
- [x] 9.5 Run `flutter analyze` clean, all automated tests pass (19 mobile tests + 91 engine tests)
