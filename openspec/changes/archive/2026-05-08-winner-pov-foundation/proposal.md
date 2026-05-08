## Why

The just-shipped `loss-inversion` change exposed sharp edges in the engine's storage model:

1. **Per-row perspective canonicalization** splits the data into two parallel hash spaces (`+POV` and `-POV`), so loss data sits in a space the bot's query can't reach. We worked around this with full-game inversion at backfill — but that's a workaround, not a model.
2. **Mirror canonicalization** exists primarily to make Zobrist exact-matching catch mirror-equivalent boards. It has known bugs (mirror-replay correctness in `movePlayed`) and adds complexity without clear long-term value.
3. **Zobrist** is on its way out: the project's long-term matching strategy is perceptual diffusion-image overlay, which doesn't need exact-match hashing. The existing fuzzy-match tier (Hamming distance on diffused-bit hashes) already handles realistic similarity.

The desired foundation, clarified through user discussion, is much simpler:

- **Winner is `+1`, everywhere in the DB.** Decide perspective once per game (at game end), apply uniformly to all rows of that game.
- **Search runs twice at read time** — one query in each perspective transform — to access both winning and losing trajectories.
- **No mirror canonicalization. No Zobrist. No `side` column.** Three layers of complexity removed.

This refactor is mostly *deletion*. It generalizes cleanly to other two-player signed-piece games (Chess, Go, Othello, Checkers) and is forward-compatible with the eventual diffusion-image overlay matching.

## What Changes

- **Delete** `packages/game_engine/lib/src/zobrist.dart` (`ZobristTable`, `SplitMix64`).
- **Delete** mirror canonicalization (`mirror`, `_shouldMirror`) and the `canonicalize` wrapper / `CanonicalResult` struct from `canonicalize.dart`. Keep `flipPerspective` and a slimmer `invertState`.
- **Drop** `GameState.zobristHash` and `GameState.side` fields. Drop the corresponding `zobrist_hash` and `side` columns from the `game_states` table (schema bump 1 → 2, destructive migration — wipes old rows).
- **Replace** per-row perspective canonicalization with **per-game winner-POV transform at backfill**: player won → store as-is; bot won → flip every row (the existing whole-game inversion, just triggered on the opposite outcome); draws → store as-is.
- **Replace** single-query `selectMove` with **two-query search**: Query A on `flipPerspective(currentBoard)` (matches bot-won games' rows; use `outcome=+1` rows as positive-weight candidates), Query B on `currentBoard` (matches player-won games' rows; use `outcome=-1` rows as negative-weight candidates).
- **Update weighting**: fold Hamming distance into the candidate weight (closer matches contribute more); use sign-aware weights so losses subtract from a column's vote.
- **Slim** `searchSimilar`: drop the `queryZobristHash` parameter and exact-match tier; the function becomes pure fuzzy match.
- **Slim** narration: drop `DecisionContext.exactMatch` (unreachable without Zobrist) and `DecisionContext.invertedData` (not in use after refactor).
- **Update** the mobile notifier: trigger `_invertCurrentGame...` on `winner == -1` (bot won) instead of `winner == 1`. Rename to reflect winner-POV semantics.
- **Update** `db.backfillStates` to derive a row's outcome from ply parity (even ply = player mover, odd ply = clone mover) since `side` is gone.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `canonicalization`: extensive overhaul. The "Mirror normalization", "Perspective normalization", and "Loss inversion" requirements all collapse into a single new "Winner-POV storage" requirement plus a "Two-query search" requirement and a "Sign-aware distance-weighted vote" requirement. The "Canonicalization happens at write time" requirement survives in spirit (storage policy is applied at backfill, not at read time).

## Impact

- `packages/game_engine/lib/src/zobrist.dart` — deleted.
- `packages/game_engine/lib/src/canonicalize.dart` — drops `mirror`, `_shouldMirror`, `canonicalize`, `CanonicalResult`. `invertState` simplifies (no `ZobristTable` parameter).
- `packages/game_engine/lib/src/game_state.dart` — `GameState` loses `zobristHash` and `side` fields.
- `packages/game_engine/lib/src/clone_brain.dart` — drops `_zobristTable`/`zobristTable`. `createState` no longer canonicalizes (display board stored as-is, just diffuse + compute material). `selectMove` runs two queries with sign-aware weighting. `_buildNarration` simplified.
- `packages/game_engine/lib/src/similarity.dart` — drops `queryZobristHash` parameter and exact-match loop. `SimilarityResult.isExactMatch` removed.
- `packages/game_engine/lib/src/narration.dart` — drops two unreachable `DecisionContext` cases.
- `packages/game_engine/lib/game_engine.dart` — drops the `src/zobrist.dart` export.
- `apps/mobile/lib/src/db/database_service.dart` — schema v2 with destructive migration. Drops two columns. `backfillStates` rewritten to use ply parity.
- `apps/mobile/lib/src/state/game_notifier.dart` — `_endGame` invert trigger flips. Helper renamed.
- Tests: `canonicalize_test.dart`, `behavioral_test.dart`, `database_service_test.dart`, `game_notifier_test.dart` all churn; net test count similar.
- **Storage**: net column drop (`zobrist_hash` int + `side` int per row → ~16 bytes per row saved).
- **Migration**: destructive — `game_states` table is wiped on bump from schema v1 to v2. The `games` table is also cleared so games-played counter starts fresh. Acceptable: MVP hasn't shipped widely; old data is incompatible with new semantics anyway.
- **Behavioral**: subsumes loss-inversion; bot now learns from both wins (positive weight) and losses (negative weight); mirror-replay correctness bug eliminated.
