## Why

Phase 2's open polish item: there's no way to **revisit a finished game**. The home-screen `AreaHistoryStrip` is a beautiful trend signal but it's purely visual — a player who notices "huh, that one was tight" has no path from glance to inspection. Every move is on disk already (`game_states` holds the full per-ply board log), so the data debt is zero; only the UI is missing.

This change adds a tappable history surface plus a self-contained replay viewer. Tapping the home-screen strip opens a **History** list of completed games; tapping a list row opens the **Replay** screen for that game — a read-only `GoBoard` driven by VCR-style controls. No new persisted data, no engine touches.

Per the prime directive: keep it simple, clean, maintainable. v1 ships the smallest viewer that's actually useful — board + slider + play/pause + step + jump. Animations, narration replay, diffused-image overlays, and coordinate labels stay deferred.

## What Changes

- **Strip becomes a button.** Wrap the existing `AreaHistoryStrip` on the start screen in a tap target that navigates to the new History screen. The strip's visual is unchanged.
- **New `/history` screen.** ListView of completed games, most-recent-first. Each row shows: date, outcome chip (W / L / D / RES), move count, area split (e.g. "84 : 76"), and the same per-row proportion-bar painter the strip already uses (`AreaHistoryPainter` extracted into a small reusable bit). Empty state: "No completed games yet."
- **New `/replay` screen.** Opens with the final-ply board state shown, paused. Renders the existing `GoBoard` widget in read-only mode (tap handler suppressed), a ply slider, a VCR control row (`⏮ ⏴ ⏯ ⏵ ⏭`), and a speed-cycling chip (`1× / 2× / 4×`). Header shows outcome verdict + area readout + "Move N / Total" with optional "(pass)" annotation when the current ply is a pass move.
- **Replay reconstruction reuses what's on disk.** Per-ply boards are read directly from `game_states`. For bot-won games (`outcome == -1`) every loaded board is unflipped via `invertState` before display, so the player's stones always render as ivory in the replay — matching live play.
- **`RecentGame` typedef gains a few fields** so the history list and the strip share one query. Existing strip code is unaffected (it ignores the new fields).
- **No new persisted data. No engine changes. No schema bump.**

## Capabilities

### New Capabilities

- `history-screen` — list of completed games, most-recent-first, tappable.
- `replay-screen` — ply-indexed playback of a completed game with VCR controls.

### Modified Capabilities

- `start-screen` — the `AreaHistoryStrip` SHALL be a tap target that navigates to `/history`.
- `game-persistence` — `RecentGame` gains `gameId`, `startedAt`, `totalMoves` so a single load powers both the strip and the history list.

## Impact

- `apps/mobile/lib/src/db/database_service.dart`
  - Extend the `RecentGame` typedef with `gameId`, `startedAt` (epoch ms `int`), `totalMoves`.
  - Update `loadRecentGames` to select & return the additional columns.
  - New method `Future<List<ReplayFrame>> loadGameForReplay(String gameId)` that returns the per-ply board + move-played for the given game, ordered by ply.
- `apps/mobile/lib/src/widgets/area_history_strip.dart`
  - Extract the per-row painter into a stand-alone helper so the History list rows can reuse the exact pixel-painted bar. Strip widget continues to use it; nothing visual changes.
- `apps/mobile/lib/src/screens/start_screen.dart`
  - Wrap the `AreaHistoryStrip` in `GestureDetector` (or `InkWell`) pushing `/history`.
- `apps/mobile/lib/src/screens/history_screen.dart` *(new)*
- `apps/mobile/lib/src/screens/replay_screen.dart` *(new)*
- `apps/mobile/lib/src/state/replay_controller.dart` *(new — local `ChangeNotifier` for the replay screen; ply, speed, isPlaying)*
- `apps/mobile/lib/src/widgets/go_board.dart`
  - Add a `bool readOnly = false` constructor flag that disables tap-to-place; default behaviour unchanged.
- `apps/mobile/lib/main.dart`
  - Register the two new named routes.
- **Tests**:
  - `database_service_test.dart`: extended `RecentGame` shape; `loadGameForReplay` returns the right plies in order and surfaces correct boards.
  - `replay_controller_test.dart` *(new)*: ply step bounds, speed cycle, play/pause behaviour, jump-to-start/end.
  - `history_screen_test.dart` *(new)*: lists games, shows empty state, tap-row navigates.
  - `replay_screen_test.dart` *(new)*: opens on final ply, VCR buttons move the slider, read-only board doesn't accept taps, inverted-board games render with player as ivory.
- **No engine changes.** `invertState` is already public.
- **No schema bump, no migration.** v6 stays v6.
