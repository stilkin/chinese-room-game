## 1. App Setup

- [ ] 1.1 Create `apps/mobile/` Flutter project with `flutter create`
- [ ] 1.2 Update `pubspec.yaml`: add `game_engine` path dependency, `sqflite`, `path_provider`
- [ ] 1.3 Update root `pubspec.yaml` to include `apps/mobile/` in the pub workspace
- [ ] 1.4 Verify `flutter analyze` and `flutter test` run cleanly on the empty app

## 2. SQLite Persistence

- [ ] 2.1 Create `DatabaseService` class: initialize SQLite database, create `game_states`, `games`, and `clone_config` tables
- [ ] 2.2 Implement `insertGameState()`: write a single GameState row with board as byte blob
- [ ] 2.3 Implement `loadAllGameStates()`: bulk read all rows, deserialize boards from blobs into engine GameState objects
- [ ] 2.4 Implement `backfillOutcomes()`: update outcome and moves_to_end for all states in a completed game, insert inverted states
- [ ] 2.5 Implement `insertGame()` and `updateGameOutcome()` for the games table
- [ ] 2.6 Implement `getGamesPlayedCount()`: return total completed games
- [ ] 2.7 Implement `loadCloneConfig()` and `saveCloneConfig()` for fallback personality setting
- [ ] 2.8 Implement `deleteAllData()`: drop all game states, games, and reset clone config
- [ ] 2.9 Write tests: insert/load round-trip, backfill correctness, board blob round-trip, delete all

## 3. Game State Management

- [ ] 3.1 Create `GameNotifier` extending `ChangeNotifier`: holds current board, turn, outcome, narration, game_id
- [ ] 3.2 Implement `startNewGame()`: reset board, create game record, set player turn
- [ ] 3.3 Implement `playerMove(column)`: validate legal move, apply to board via engine, canonicalize and persist state, check win/draw, switch to clone turn
- [ ] 3.4 Implement `cloneTurn()`: invoke clone brain search, apply selected move, persist state, update narration, check win/draw, switch to player turn
- [ ] 3.5 Implement `endGame()`: backfill outcomes in database, create inverted states, update game record
- [ ] 3.6 Wire `DatabaseService` into `GameNotifier`: load all states on init, persist on each move
- [ ] 3.7 Write tests: turn alternation, game lifecycle, outcome detection triggers endGame

## 4. Start Screen

- [ ] 4.1 Create `StartScreen` widget: app title/branding area
- [ ] 4.2 Add "New Game" button that calls `GameNotifier.startNewGame()` and navigates to `/game`
- [ ] 4.3 Add "Settings" button that navigates to `/settings`
- [ ] 4.4 Display games-played count from `DatabaseService.getGamesPlayedCount()`

## 5. Game Screen

- [ ] 5.1 Create `BoardPainter` (CustomPainter): draw 7×6 grid with empty cells, player pieces, and clone pieces in distinct colors
- [ ] 5.2 Implement tap-to-column mapping: convert touch coordinates to column index (0-6)
- [ ] 5.3 Create `GameScreen` widget: board painter, tap handler calling `GameNotifier.playerMove()`, ignore taps during clone turn or on full columns
- [ ] 5.4 Add narration display area: prominently show `GameNotifier.narration` text below/above the board
- [ ] 5.5 Add turn indicator: display whose turn it is (player or "Clone is thinking...")
- [ ] 5.6 Wire game-end detection: navigate to `/post-game` when `GameNotifier.outcome` is set

## 6. Post-Game Screen

- [ ] 6.1 Create `PostGameScreen` widget: display outcome text ("You win!" / "Clone wins!" / "Draw!")
- [ ] 6.2 Display clone's last narration as "final thought"
- [ ] 6.3 Display updated total games-played count
- [ ] 6.4 Add "Play Again" button: calls `startNewGame()` and navigates to `/game`
- [ ] 6.5 Add "Home" button: navigates to `/` (start screen)

## 7. Settings Screen

- [ ] 7.1 Create `SettingsScreen` widget with back navigation
- [ ] 7.2 Add fallback personality picker (dropdown or radio): Random, Middle Focus, Edge Focus, Pile Focus
- [ ] 7.3 Wire picker to `DatabaseService.saveCloneConfig()` — persist selection, default to Random
- [ ] 7.4 Add "Delete All Game Logs" button with confirmation dialog
- [ ] 7.5 Wire delete to `DatabaseService.deleteAllData()` and clear in-memory GameLog

## 8. Navigation & App Shell

- [ ] 8.1 Set up `MaterialApp` with named routes: `/`, `/game`, `/post-game`, `/settings`
- [ ] 8.2 Wire `GameNotifier` as app-level state via `ListenableBuilder` or provider pattern
- [ ] 8.3 Initialize `DatabaseService` and bulk-load game states before showing start screen

## 9. Integration

- [ ] 9.1 Manual test: play a full game against the clone, verify narration appears, post-game shows correct outcome
- [ ] 9.2 Manual test: change fallback personality in settings, start a new game with empty data, verify fallback is used
- [ ] 9.3 Manual test: delete all game logs, verify clone resets and games-played count is 0
- [ ] 9.4 Manual test: close and reopen the app, verify game data persists and clone remembers past games
- [ ] 9.5 Run `flutter analyze` clean, all automated tests pass
