## 1. Persistence: ongoing-game queries and atomic delete

- [ ] 1.1 Add `Future<String?> findOngoingGame()` to `DatabaseService` — `SELECT game_id FROM games WHERE outcome IS NULL ORDER BY started_at DESC LIMIT 1`, returns null when empty
- [ ] 1.2 Add `Future<List<GameState>> loadStatesForGame(String gameId)` to `DatabaseService` — `SELECT * FROM game_states WHERE game_id = ? ORDER BY ply ASC`, hydrates via the existing `_rowToGameState`
- [ ] 1.3 Add `Future<void> deleteGame(String gameId)` to `DatabaseService` — single SQLite transaction: `DELETE FROM game_states WHERE game_id = ?` then `DELETE FROM games WHERE game_id = ?`
- [ ] 1.4 Tests in `database_service_test.dart`: `findOngoingGame` empty/single/finished-only/mixed cases; `loadStatesForGame` ordering and round-trip; `deleteGame` removes both tables atomically; `deleteGame` is a no-op on missing id

## 2. Notifier: resume entry point and single-slot startNewGame

- [ ] 2.1 Add `bool _hasOngoingGame` (and `bool get hasOngoingGame`) to `GameNotifier`. Refresh on `init()` (via `findOngoingGame`), and on `_endGame`, `startNewGame`, `deleteAllData`, `resumeLastGame` (where the answer is known locally)
- [ ] 2.2 Update `startNewGame()`: if `_hasOngoingGame`, call `db.deleteGame(_currentOngoingGameId)` first so single-slot is preserved. The caller (start-screen UI) is responsible for the confirmation dialog
- [ ] 2.3 Add `Future<void> resumeLastGame()` — `findOngoingGame` → `loadStatesForGame` → start from `Board(rules.rows, rules.cols)`, replay each via `rules.applyMove(displayBoard, state.movePlayed, state.side)`, then set `_gameId`, `_ply = states.length`, `_currentSide = (_ply.isEven ? 1 : -1)`, `_outcome = null`, `_narration = ''`, `_isCloneThinking = false`, `notifyListeners()`
- [ ] 2.4 Wrap the replay in try/catch — on any failure (empty load, applyMove throws), call `db.deleteGame(badId)`, refresh `_hasOngoingGame`, rethrow so the UI can surface a snackbar
- [ ] 2.5 Tests: resume reproduces the display board after N moves, sets the right side parity, doesn't duplicate persisted rows; `startNewGame` with an existing ongoing game wipes the prior records (verify via `findOngoingGame` returning the new id and the prior state count being 0); corrupt/missing-states case clears the orphan and signals failure

## 3. Start screen UI

- [ ] 3.1 Show a Resume button below New Game when `notifier.hasOngoingGame`
- [ ] 3.2 On Resume tap: `await notifier.resumeLastGame()`, then push `/game`. On exception, show a snackbar (`ScaffoldMessenger.of(context).showSnackBar`) and remain on start
- [ ] 3.3 On New Game tap with `hasOngoingGame == true`: show an `AlertDialog` ("Discard your unfinished game?"). Only call `startNewGame` + push on confirm
- [ ] 3.4 Tests: pump start screen with `hasOngoingGame=false` (Resume hidden, New Game flows directly); pump with `hasOngoingGame=true` (Resume visible, tapping New Game shows the dialog)

## 4. Verification

- [ ] 4.1 `flutter analyze` and `flutter test` pass in `apps/mobile/`
- [ ] 4.2 Manual smoke on device: start a game, navigate Home, kill the app, relaunch — Resume appears, tapping it restores the board exactly as it was, gameplay continues to a normal end + backfill (and loss-inversion if the player wins)
- [ ] 4.3 Manual smoke: with an ongoing game, tap New Game — confirm dialog appears; cancel keeps you on start; confirm starts fresh and the prior game is gone from the DB (no inert rows accumulate)
