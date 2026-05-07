## 1. Engine: invertState helper

- [ ] 1.1 Add `GameState invertState(GameState s, ZobristTable table, DiffusionKernel kernel)` to `packages/game_engine/lib/src/canonicalize.dart`. Step 1: recover an "after mirror" representative (negate via `flipPerspective` if `s.side == -1`). Step 2: `canonicalize(afterMirror, -s.side, table)` — full pipeline. Step 3: re-diffuse + threshold for `diffusedHash`. Build a new `GameState` with the new board/hashes, flipped `side` and `materialBalance`, preserved `movePlayed` / `ply` / `gameId` / `outcome` / `movesToEnd`.
- [ ] 1.2 Re-export `invertState` from `packages/game_engine/lib/game_engine.dart`.
- [ ] 1.3 Unit tests in `packages/game_engine/test/canonicalize_test.dart`: side flips, materialBalance sign flips, metadata preserved, double-inversion equals original (for canonical inputs), Zobrist and diffused-bit hash recomputed correctly.

## 2. Engine: behavioral coverage

- [ ] 2.1 Add a behavioral test in `packages/game_engine/test/behavioral_test.dart`: simulate one or two player-won games, run `invertState` on the player's states (mimicking what the app would do at backfill), then have the clone query a fresh game's first move. Expect a non-fallback decision derived from the inverted player states. Compare against a control run without inversion (expect fallback).

## 3. Mobile app: backfill orchestration

- [ ] 3.1 In `apps/mobile/lib/src/db/database_service.dart`, add `Future<List<GameState>> queryStatesForGameAndSide(String gameId, int side)` and `Future<void> deleteStatesForGameAndSide(String gameId, int side)` (used together to support delete-then-reinsert).
- [ ] 3.2 In `apps/mobile/lib/src/state/game_notifier.dart::_endGame`, after the existing backfill calls, branch on `winner`. If `winner == 1` (player won): walk the in-memory log for `_gameId` rows where `side == 1`, replace each with `invertState(s, _brain.zobristTable, rules.diffusionKernel)`. Then in a single SQL transaction, query those player-side rows from SQLite, delete them, and insert their inversions.
- [ ] 3.3 Update `game_notifier_test.dart` expectations: in the player-wins test, after `_endGame`, the persisted player-side rows SHALL have `side=-1` and `outcome=+1`. In the bot-wins test, no inversion occurs (rows unchanged).

## 4. Verification

- [ ] 4.1 `dart analyze` and `dart test` pass in `packages/game_engine/`.
- [ ] 4.2 `flutter analyze` and `flutter test` pass in `apps/mobile/`.
- [ ] 4.3 Manual smoke on device: play and lose 2-3 games to the clone, then start a fresh game. The clone narration should leave fallback behind faster than before — it now has player-derived data to pull from.
