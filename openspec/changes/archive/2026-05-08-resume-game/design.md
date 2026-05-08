## Context

Every move is already written to SQLite at the time it's played, and `games` rows are created at the start of each game with `outcome IS NULL` until the game ends. The data needed to resume an interrupted game already exists; we just have no UI path to it. The current "New Game" flow stomps over `GameNotifier` and silently abandons any ongoing game, leaving its `games` and `game_states` rows orphaned forever.

This proposal is purely an app-layer change. The engine is untouched.

## Goals / Non-Goals

**Goals:**
- One-tap recovery from app close, navigation away, or crash.
- No data loss on the resumed game — it ends with a normal backfill, contributing to clone training (and to loss inversion when the player wins).
- Zero new persistence — reuse what's already on disk.
- Single-slot policy: at most one ongoing game at a time, no inert orphans.

**Non-Goals:**
- No game-history browser. Multiple concurrent games is out of scope; if Chess later wants it, that's a separate proposal.
- No "save and continue later" affordance during gameplay — the app is already auto-saving every move.
- No cloud sync, no cross-device resume.
- No automatic cleanup of stray inert rows from earlier app versions. The first time a user starts a game in this version, any pre-existing ongoing game is treated as the slot occupant and either resumed or wiped via the new flow.

## Decisions

### Single-slot ongoing-game policy

At any moment, at most one `games` row has `outcome IS NULL`. Starting a new game while an ongoing one exists prompts the user to confirm; on confirm, the prior game is **deleted** (cascading to its `game_states`) before the new one is created. This keeps the schema invariant simple and the DB lean — no orphan rows.

*Alternative: list all ongoing games and let the user pick.* Rejected — UI complexity for a casual game, and the casual mobile usage pattern doesn't warrant it.

*Alternative: keep abandoned games as inert rows (the prior version of this proposal).* Rejected — accumulates DB cruft over time and forces the start screen to define "most recent" semantics. Single-slot is cleaner.

### Rehydration via move replay

To resume game `G`:
1. Load `G`'s `GameState` rows from SQLite, ordered by `ply ASC`.
2. Start from `Board(rules.rows, rules.cols)` and apply each move via `rules.applyMove(displayBoard, state.movePlayed, state.side)`. This rebuilds the *display* board (player pieces `+1`, clone pieces `-1`).
3. Set `_gameId = G`, `_ply = states.length`, `_currentSide = (_ply.isEven ? 1 : -1)`, `_outcome = null`, `_narration = ''`, `_isCloneThinking = false`.
4. Replay does **not** call `_brain.createState` or `db.insertGameState` — the states are already on disk and in the in-memory `GameLog` from startup `init`. Re-inserting would duplicate.

*Why not reuse the stored canonical board instead of replaying moves?* The stored boards are canonicalized from each mover's POV (negated for clone moves, possibly mirrored). We don't store a `wasMirrored` flag, so we can't deterministically recover the display board from a single canonical alone. `movePlayed` + `applyMove` is a few microseconds for Connect Four and avoids storing extra columns.

### "New Game" with an ongoing game shows a confirm-and-delete

Tapping "New Game" when `findOngoingGame()` is non-null prompts: "You have an unfinished game. Starting a new one will discard it. Continue?" with Cancel / Discard & Start. On confirm, `db.deleteGame(prevGameId)` runs (a transaction that deletes the `games` row and its `game_states` rows), then `startNewGame()` proceeds as normal. Cancel keeps the user on the start screen.

*Alternative: silent overwrite (current behavior).* Rejected — the user just learned about Resume; surprise abandonment is worse than a one-tap confirm.

*Alternative: silent overwrite without delete (leave inert rows).* Rejected — see "Single-slot ongoing-game policy."

### `hasOngoingGame` is a `GameNotifier` getter, refreshed on lifecycle events

The start screen reads `notifier.hasOngoingGame` to decide whether to show Resume and whether to confirm on New Game. The notifier refreshes this cache on `init` (via `findOngoingGame`), and on `_endGame`, `startNewGame`, and `deleteAllData` (where the answer is known without a query). Re-querying SQLite on every start-screen build would be unnecessary I/O.

### Failure handling on resume

If `loadStatesForGame` returns an empty list, or if any `applyMove` during replay throws (corrupt persisted move column, schema drift), `resumeLastGame` SHALL catch the failure, call `db.deleteGame` on the bad row, refresh `hasOngoingGame`, and surface the failure to the caller (which shows a snackbar and stays on the start screen). Cheap and rare.

## Risks / Trade-offs

**[Replay drift across game-rule changes]** → If we ever amend `rules.applyMove` semantics for an existing game, an old persisted game's replay could land on a different board. Connect Four is unlikely to change. → Mitigation: a per-game `gameType` column would let us version-gate replay; not worth it for MVP since we have one game.

**[Single-slot is too restrictive for some games]** → Chess and Go players in the wild often run concurrent games. → Acceptable for MVP. When we add those games, revisit with a multi-slot proposal — schema is forward-compatible (we'd just allow more than one `outcome IS NULL` row).

**[Loss-inversion + resume interaction]** → A resumed game's pre-resume player moves are already in the log as side=+1 stored canonical (no inversion yet). When the resumed game ends with the player winning, `_endGame` walks all of the game's player-side rows and inverts them — including the pre-resume ones. Invariant holds. No special handling needed.

**[Edge case: app exits during the confirm-and-delete]** → If the user taps Discard but the app crashes between `deleteGame` and `insertGame`, we end up with no ongoing game and no leftover. That's fine — the user starts a fresh game next launch. The transactional delete keeps DB consistency.

## Migration Plan

No migration needed. Existing data already has the necessary rows. First boot after this ships will surface "Resume" if any ongoing game exists; otherwise the start screen is unchanged.
