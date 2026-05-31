## Why

Two adjacent UX gaps surfaced after the Go cutover and the agree-to-pass nudge:

1. **The post-game screen says "You win!" or "Clone wins!" — and that's it.** Whether you won by 50 tiles or by half a tile reads the same. For a game where the win margin is the only signal of "how close was that?", flattening the outcome to a binary verdict throws away the most interesting information of the play session.

2. **The home screen's `LAST GAMES` row of dots tells you "5 wins, 2 losses lately" but says nothing about *trend*.** Are your wins getting tighter as the clone learns? Did that streak of losses come from blowouts or near-misses? The dots can't show it.

This change makes per-game *area scores* a first-class persisted artefact and surfaces them in two places: a one-line score readout on the post-game screen, and a vertically-stacked proportion-bar history strip on the home screen that replaces the existing dot row. Per-game area scores are also a future-fuel signal — once we've got them on disk we could weight CBR retrieval by win margin, A/B-test fallback strength via average margin shifts, etc. — but the immediate motivation is just letting the player *see* their own progression.

## What Changes

- **Schema bump (v5 → v6)**: add `player_area INTEGER` and `clone_area INTEGER` columns to the `games` table. Both nullable. Existing v5 rows migrate forward with NULLs (no destructive wipe — we keep history). Resigned games leave the columns NULL by design (no real area was contested).
- **End-of-game persistence**: when a Go game terminates via two passes (or a single pass + the clone's agree-to-pass override), `_endGame` SHALL compute `rules.areaScore(_displayBoard)` and persist `(player_area, clone_area)` against the `games` row. CF games (no `areaScore` concept) continue to leave the columns NULL — no harm.
- **Resign path**: the `resign` flow already sets `outcome = -1` and scrubs `game_states`. It SHALL NOT compute or persist area; the columns stay NULL. The widget renders these as a "DNF" muted-grey row.
- **Post-game area readout**: the post-game screen SHALL show a small "AREA YOU X · CLONE Y" line below the verdict, computed live from the final board (works on resign too — `_displayBoard` survives `resign`). One conditional skip: if both areas are zero (resign on an empty board), suppress the line.
- **`AreaHistoryStrip` widget** (new): replaces `RecentGamesStrip` on the start screen. Each completed game is one ~2px-tall row:
  - **Bar middle**: ivory (player area) ÷ near-black (clone area), proportions of total area.
  - **Endcaps** (small ~3px squares on each end): the colour of the *winning* side — ivory if you won, near-black if the clone won, cream-amber for a draw, muted-grey for DNF/resign. Endcap colour disambiguates the outcome when the proportion bar is near 50/50.
  - **DNF rows**: solid muted-grey line, no proportion split, no endcaps.
- **Home-screen reorder**: `logo + tagline → "Your clone" stats box → New Game / Resume buttons → LAST GAMES strip` filling the bottom. The strip is hard-capped at the **most recent 100** games for now (no scrolling); top of strip = newest game.
- **Persistence read path**: `DatabaseService.loadRecentGames(limit)` (replacing or extending `loadRecentOutcomes`) SHALL return a typed list of `({int outcome, int? playerArea, int? cloneArea})` records, ordered most-recent-first.

## Capabilities

### New Capabilities

(none — the new strip widget extends an existing `start-screen` requirement)

### Modified Capabilities

- `game-persistence`: schema gains two nullable columns; `loadRecentOutcomes` becomes `loadRecentGames` returning area data alongside outcome.
- `post-game-screen`: outcome line is joined by a one-line area readout (suppressed when both areas are zero).
- `start-screen`: the LAST GAMES surface changes from a dot row (`RecentGamesStrip`) to a stacked proportion-bar strip (`AreaHistoryStrip`). Most-recent-on-top, hard cap of 100 rows.

## Impact

- `apps/mobile/lib/src/db/database_service.dart`
  - `_kSchemaVersion` 5 → 6; `onUpgrade` adds an `if (oldVersion < 6)` branch that runs `ALTER TABLE games ADD COLUMN player_area INTEGER`, `ALTER TABLE games ADD COLUMN clone_area INTEGER`. Non-destructive — existing rows keep their outcome and ply data; only the new columns start as NULL.
  - `onCreate` updated for fresh installs.
  - New `updateGameAreaScore(gameId, playerArea, cloneArea)` method.
  - `loadRecentOutcomes` → `loadRecentGames` (returns the typed-record list above). Old method deleted.
- `apps/mobile/lib/src/state/game_notifier.dart`
  - `_recentOutcomes` field replaced with `_recentGames` of the new record type; getter renamed.
  - `_endGame` (or wherever `db.updateGameOutcome` is called for completed Go games) computes area and writes it.
  - `resign` unchanged — explicitly does not write area.
- `apps/mobile/lib/src/widgets/recent_games_strip.dart` → deleted, replaced by:
- `apps/mobile/lib/src/widgets/area_history_strip.dart` (new)
- `apps/mobile/lib/src/screens/start_screen.dart`: switch widget; reorder so the strip fills the bottom.
- `apps/mobile/lib/src/screens/post_game_screen.dart`: add the area-readout line.
- `apps/mobile/test/database_service_test.dart`
  - v5 → v6 migration test (insert v5-shape row → upgrade → confirm columns added, NULL on legacy rows).
  - `updateGameAreaScore` round-trip.
  - `loadRecentGames` orders most-recent-first; resigned-row areas surface as nulls.
- `apps/mobile/test/game_notifier_test.dart`: existing assertions about `recentOutcomes` migrate to the new field shape.
- `apps/mobile/test/widgets/area_history_strip_test.dart` (new): golden-ish layout test — confirm the strip paints proportion + endcap correctly for each of {win, loss, draw, DNF}.
- **No engine changes.** `GoRules.areaScore` is already exposed and has a public signature.
- **No spec migration risk** for users: existing rows keep their data; schema migration is additive.
