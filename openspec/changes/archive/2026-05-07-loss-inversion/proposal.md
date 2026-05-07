## Why

The clone learns almost nothing from the player's wins. With per-move perspective canonicalization, the player's stored states sit in `+canonical` space while the clone queries in `−canonical` space — they never match. In sparse-data regimes (early games, where the player tends to win), the clone falls back constantly because its own past states are losses (zero-weighted). The `canonicalization` spec already requires loss inversion; we never implemented it.

## What Changes

- Add a public engine helper `invertState(GameState, ZobristTable, DiffusionKernel) → GameState` that produces a perspective-twin: re-canonicalized from the opposite side's POV (full pipeline: mirror + perspective flip), recomputed Zobrist + diffused-bit hashes, flipped `side` and `materialBalance`, preserved `movePlayed` / `ply` / `gameId` / `outcome` / `movesToEnd`.
- Apply inversion **at backfill time**, **on every row of player-won games** (not just the winning side). The whole game is rewritten as if the bot were the protagonist: player rows become `side=-1, outcome=+1` (the bot's winning trajectory) and clone rows become `side=+1, outcome=-1` (the opponent's losing trajectory). When the bot wins, no inversion happens — the bot is already the protagonist of its own moves, with the standard backfill having set the right per-side outcomes.
- Mobile app's `GameNotifier._endGame` orchestrates this — when the player wins, invokes `invertState` on every row of the just-finished game and replaces them atomically in both the in-memory `GameLog` and SQLite.
- Refine the existing `canonicalization` "Loss inversion" requirement to match this semantic: per-row, at backfill, every row of a player-won game.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `canonicalization`: refine the existing "Loss inversion" requirement — inversion is per-state, happens at backfill time, applied only to the winning side of a player-won game, and is exposed via a public engine helper that re-canonicalizes through the full pipeline.

## Impact

- `packages/game_engine/lib/src/canonicalize.dart` — add `invertState` helper. (Already re-exported via the existing `canonicalize.dart` export in the package barrel.)
- `packages/game_engine/lib/src/game_state.dart` — add `GameLog.replaceStatesForGame(gameId, transform)` that walks every row of a game and swaps in transformed rows.
- `apps/mobile/lib/src/state/game_notifier.dart::_endGame` — when `winner == 1`, walk every row of the just-finished game, replace each with its `invertState` output in the in-memory log, then atomically swap them in SQLite.
- `apps/mobile/lib/src/db/database_service.dart` — add `replaceAllStatesForGameAtomic(gameId, replacements)` that wraps a game-scoped delete + bulk-insert in one SQLite transaction.
- Tests: engine unit tests for `invertState` (round-trip, hash recomputation, side/balance flip, fixed point under double-inversion); a behavioral test confirming that after a player win every row of the game now lives in the bot's perspective space (winning rows + opponent-losing rows).
- Storage: **no row count growth** — same number of rows per game as today. No schema change.
- No breaking API changes for existing callers.
