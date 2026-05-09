## 1. Engine: invertState helper

- [x] 1.1 Add `GameState invertState(GameState s, ZobristTable table, DiffusionKernel kernel)` to `packages/game_engine/lib/src/canonicalize.dart`. Implementation: `flipPerspective(s.board)` produces the inverted canonical board (since canonicalize's mirror choice is computed pre-flip and depends only on the input, the canonical-board pair `canonicalize(B, +s)` and `canonicalize(B, -s)` differ only by a perspective flip). Recompute `zobristHash` via `table.hashBoard` and `diffusedHash` via the kernel. Build a new `GameState` with the new board/hashes, flipped `side` and `materialBalance`, preserved `movePlayed` / `ply` / `gameId` / `outcome` / `movesToEnd`.
- [x] 1.2 No new export needed — `canonicalize.dart` is already re-exported via `packages/game_engine/lib/game_engine.dart`.
- [x] 1.3 Unit tests in `packages/game_engine/test/canonicalize_test.dart`: side flips, materialBalance sign flips, metadata preserved, double-inversion equals original (for canonical inputs), Zobrist hash matches `canonicalize(displayBoard, -side).zobristHash`, diffused-bit hash matches a fresh recompute on the inverted board.

## 2. Engine: behavioral coverage

- [x] 2.1 Add behavioral tests in `packages/game_engine/test/behavioral_test.dart`: a control test (no inversion → bot has zero winning candidates) and a post-inversion test (after full-game inversion of a synthetic player-won game, the bot's winning-candidate count equals the player's row count, the clone rows flipped sides too, and a mid-game query in the bot's POV finds the player's stacking move as a candidate).
- [x] 2.2 Add a `GameLog.replaceStatesForGame(gameId, transform)` helper in `packages/game_engine/lib/src/game_state.dart` that walks every row of a game and replaces them in place via the transform.

## 3. Mobile app: backfill orchestration

- [x] 3.1 In `apps/mobile/lib/src/db/database_service.dart`, extract `_gameStateColumns(s)` (shared by `insertGameState` and the bulk swap) and add `replaceAllStatesForGameAtomic(gameId, replacements)` which deletes every row of the game and inserts the replacements inside one transaction.
- [x] 3.2 In `apps/mobile/lib/src/state/game_notifier.dart::_endGame`, after the existing backfill calls, branch on `winner`. If `winner == 1`: call `_invertCurrentGameToBotPerspective`, which uses `log.replaceStatesForGame` to capture the inverted rows and `db.replaceAllStatesForGameAtomic` to swap them in SQLite atomically.
- [x] 3.3 Update `game_notifier_test.dart` expectations: in the player-wins test, after `_endGame`, the persisted rows SHALL split into 4 winning rows (`side=-1, outcome=+1`) and 3 losing rows (`side=+1, outcome=-1`), and the in-memory log SHALL match. In the bot-wins test, no inversion occurs — player rows stay at `side=+1, outcome=-1` and clone rows stay at `side=-1, outcome=+1`.

## 4. Verification

- [x] 4.1 `dart analyze` and `dart test` pass in `packages/game_engine/`.
- [x] 4.2 `flutter analyze` and `flutter test` pass in `apps/mobile/`.
- [x] 4.3 Manual smoke on device: play and win 2-3 games against the clone, then start a fresh game. The clone narration should leave fallback behind faster than before — it now has player-derived data to pull from.
