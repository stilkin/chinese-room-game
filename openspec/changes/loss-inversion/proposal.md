## Why

The clone learns almost nothing from the player's wins. With per-move perspective canonicalization, the player's stored states sit in `+canonical` space while the clone queries in `−canonical` space — they never match. In sparse-data regimes (early games, where the player tends to win), the clone falls back constantly because its own past states are losses (zero-weighted). The `canonicalization` spec already requires loss inversion; we never implemented it.

## What Changes

- Add a public engine helper `invertState(GameState, ZobristTable, DiffusionKernel) → GameState` that produces a perspective-twin: re-canonicalized from the opposite side's POV (full pipeline: mirror + perspective flip), recomputed Zobrist + diffused-bit hashes, flipped `side` and `materialBalance`, preserved `movePlayed` / `ply` / `gameId` / `outcome` / `movesToEnd`.
- Apply inversion **at backfill time**, **only on the winning player's states** of **player-won games**. When the bot wins, no inversion happens — the clone's own states already live in bot-POV space with `outcome=+1`. When the player wins, the player's states are replaced in place by their inversions: side flips from `+1` to `−1`, the canonical board lands in bot-POV space, and the outcome stays `+1` (the inverted state represents "winning trajectory, refiled under the bot's POV").
- Mobile app's `GameNotifier._endGame` orchestrates this — invokes `invertState` on each player-side row of the just-finished game and replaces the rows in both the in-memory `GameLog` and SQLite when the player wins.
- Refine the existing `canonicalization` "Loss inversion" requirement to match this semantic: per-state, at backfill, only winning side of a player-won game.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `canonicalization`: refine the existing "Loss inversion" requirement — inversion is per-state, happens at backfill time, applied only to the winning side of a player-won game, and is exposed via a public engine helper that re-canonicalizes through the full pipeline.

## Impact

- `packages/game_engine/lib/src/canonicalize.dart` — add `invertState` helper.
- `packages/game_engine/lib/game_engine.dart` — re-export the helper.
- `apps/mobile/lib/src/state/game_notifier.dart::_endGame` — when `winner == 1`, walk the game's player-side states, replace each with its `invertState` output (in-memory log) and delete-then-reinsert in SQLite within a transaction.
- `apps/mobile/lib/src/db/database_service.dart` — small additions: a per-game-side query and a per-game-side delete to support the in-place replacement.
- Tests: engine unit tests for `invertState` (round-trip, hash recomputation, side/balance flip, fixed point under double-inversion); a behavioral test that a clone fed only player-won games picks moves consistent with the player's winning strategy.
- Storage: **no row count growth** on average — same number of rows per game as today. No schema change.
- No breaking API changes for callers that don't opt in.
