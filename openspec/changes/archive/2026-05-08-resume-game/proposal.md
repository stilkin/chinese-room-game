## Why

If a player closes the app mid-game (or the device crashes, or they navigate Home and start something else), there's no way to come back to that game. State is lost, and the partial game record sits orphaned in SQLite forever — including all its `game_states` rows, none of which feed the clone since they're never backfilled. A "Resume" affordance closes this loop. Every move is already written to disk, so we have everything we need.

## What Changes

- **Single-slot ongoing-game policy.** At any moment the app holds at most one ongoing game (a `games` row with `outcome IS NULL`). Suitable for Connect Four — multiple concurrent games is a Chess.com / lichess pattern, not a casual mobile one.
- Surface a "Resume" button on the start screen when an ongoing game exists. When none does, the button is hidden and the start screen is unchanged for fresh installs.
- Tapping "New Game" while an ongoing game exists prompts a confirmation. On confirm, the prior game is **deleted** (its `games` row and all its `game_states` rows in a single transaction) before the fresh game starts. No inert rows accumulate.
- "Resume" rehydrates the `GameNotifier` from the persisted move history of the most recent ongoing game: replay moves chronologically into the display board, restore `_gameId`, `_ply`, `_currentSide`, then continue play normally. Backfill on the resumed game's eventual end runs as it always did (and its outcome flows into clone training as usual — and through the new loss-inversion path if the player wins).
- Add a `game-flow` requirement for the rehydration entry point and a `game-persistence` requirement for the ongoing-game query and the cascading delete. Update `start-screen` to surface the Resume button and the New-Game confirmation flow.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `start-screen`: add the Resume button (visible only when an ongoing game exists) and the New-Game-with-confirm-and-delete flow.
- `game-flow`: add a "resume from persisted state" lifecycle entry point.
- `game-persistence`: add a "find the ongoing game" query and a "delete a game and its states" cascading delete.

## Impact

- `apps/mobile/lib/src/db/database_service.dart` — new methods: `findOngoingGame()` returns the `gameId` of the single ongoing game (or null); `loadStatesForGame(gameId)` returns its moves in chronological order; `deleteGame(gameId)` removes the `games` row and all its `game_states` rows in a single transaction. No schema change.
- `apps/mobile/lib/src/state/game_notifier.dart` — new `resumeLastGame()` method that replays persisted moves; `startNewGame()` is updated to call `db.deleteGame` on the prior ongoing game (if any) before creating the new one. New `bool get hasOngoingGame` getter, refreshed on `init`, `_endGame`, `startNewGame`, `deleteAllData`.
- `apps/mobile/lib/src/screens/start_screen.dart` — conditional Resume button; New Game confirmation dialog when an ongoing game exists.
- New tests: `findOngoingGame` cases, replay correctness, `startNewGame`-with-existing-ongoing wipes the prior game.
- **Ordering note:** spec deltas target `start-screen`, `game-flow`, and `game-persistence`, which currently live in the active `mobile-app` change (not yet synced to `openspec/specs/`). Apply order: archive `mobile-app` first → apply `loss-inversion` → apply `resume-game`. No code dependency on archival, only OpenSpec metadata.
- No engine changes. No new dependencies.
