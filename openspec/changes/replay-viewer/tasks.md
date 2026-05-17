## 1. Persistence: extended `RecentGame` + replay loader

- [x] 1.1 In `apps/mobile/lib/src/db/database_service.dart`, extend the `RecentGame` typedef with `String gameId`, `int startedAt`, `int totalMoves`.
- [x] 1.2 Update `loadRecentGames` to select `game_id, started_at, total_moves` alongside the existing columns and surface them in the returned records.
- [x] 1.3 Add a `ReplayFrame` typedef `({Board board, int movePlayed})`.
- [x] 1.4 Add `Future<List<ReplayFrame>> loadGameForReplay(String gameId)` — queries `game_states` for the given game, ordered by ply ASC, returns boards + moves.
- [x] 1.5 Persistence tests:
  - Extended `RecentGame` round-trip (round-trip an inserted game; confirm `gameId`, `startedAt`, `totalMoves` surface correctly).
  - `loadGameForReplay` order (ply ASC), correct frame count, board blobs decode.
  - `loadGameForReplay` on a non-existent gameId returns an empty list.

## 2. Engine reuse: board inversion at load time

- [x] 2.1 No engine changes. **Correction during implementation: used `flipPerspective(Board)` from `canonicalize.dart`, not `invertState`** — `invertState` takes a `GameState` and requires a `DiffusionKernel`, recomputing the diffused image we don't need. Both are exported via the engine barrel.
- [x] 2.2 Document the inversion rule in `loadGameForReplay`'s dartdoc: caller's responsibility (the replay screen does it once with the game's outcome).

## 3. `GoBoard`: read-only flag

**Decision during implementation: SKIPPED — `GoBoard.onTap` is already nullable.** Not passing it (i.e. `GoBoard(board: ..., lastMoveRow: ..., lastMoveCol: ...)`) makes the board read-only with no additional code. The proposal's `readOnly: bool` flag would have been dead weight.

- [x] 3.1 ~~Add `final bool readOnly` to the constructor~~ — superseded; existing `onTap = null` is sufficient.
- [x] 3.2 ~~Suppress the tap handler~~ — handled by the existing `if (cb == null) return;` short-circuit at `go_board.dart:64`.
- [x] 3.3 ~~Test: read-only board ignores taps~~ — covered indirectly: replay tests pass with no `onTap`, no move is emitted.

## 4. Strip painter extraction

- [x] 4.1 Lift the per-row painting helper out of `area_history_strip.dart` into a top-level function (e.g. `paintAreaHistoryRow(Canvas, Rect, RecentGame)`) so the history list rows can call it.
- [x] 4.2 `AreaHistoryStrip`'s painter delegates to the new helper for each row — no visual change.
- [x] 4.3 Existing strip tests stay green (helper extraction is pure refactor).

## 5. Replay controller

- [x] 5.1 New file `apps/mobile/lib/src/state/replay_controller.dart`. `ChangeNotifier` with:
  - `int ply`, `double speedFactor`, `bool isPlaying`, `bool isAtStart`, `bool isAtEnd`.
  - `jumpToStart`, `jumpToEnd`, `stepBack`, `stepForward`, `seek(int)`.
  - `togglePlay`, `cycleSpeed` (1× → 2× → 4× → 1×; if playing, restart ticker at the new tempo).
  - `Board boardAtCurrentPly()` and `int? lastMoveAtCurrentPly()` (returns null at `ply == 0`).
  - `Timer.periodic` play loop pauses when `ply == totalPlies`; disposes on `dispose()`.
- [x] 5.2 Tempos in code constants: `_kBaseTickMs = 600`; effective tick = `_kBaseTickMs / speedFactor`.
- [x] 5.3 Tests (`apps/mobile/test/state/replay_controller_test.dart`):
  - `ply` starts at `totalPlies` (the screen initialises it; controller default is 0 but the screen jumps to end on first build — test the constructor with `initialPly`).
  - `stepForward` / `stepBack` clamp at bounds.
  - `togglePlay` advances ply on each tick (fake async / `pumpAndSettle`).
  - `cycleSpeed` rotates 1→2→4→1; ticker tempo updates mid-play.
  - `jumpToStart` and `jumpToEnd` stop playback.

## 6. History screen

- [x] 6.1 New file `apps/mobile/lib/src/screens/history_screen.dart`. Reads `notifier.recentGames`.
- [x] 6.2 Empty state when list is empty: centred `Text("No completed games yet.", style: bodyMedium, color: onSurfaceMuted)`.
- [x] 6.3 `ListView.separated` of game rows. Per-row layout: date (formatted from `startedAt`), outcome chip (W / L / D / RES), move count, area split string ("84 : 76" or "—"), and a thin proportion-bar painter (reuse `paintAreaHistoryRow` from §4.1).
- [x] 6.4 Row tap → `Navigator.pushNamed(context, '/replay', arguments: recentGame)`.
- [x] 6.5 Wire route in `main.dart`: `'/history': (ctx) => const HistoryScreen()`.
- [x] 6.6 Tests (`apps/mobile/test/screens/history_screen_test.dart`):
  - Renders one row per game; rows show date + outcome chip + move count + area split.
  - Empty state when `recentGames` is empty.
  - Tap on a row navigates to `/replay` with the row's `RecentGame` as arguments.

## 7. Replay screen

- [x] 7.1 New file `apps/mobile/lib/src/screens/replay_screen.dart`. Receives a `RecentGame` via route arguments.
- [x] 7.2 `initState`: load frames via `db.loadGameForReplay(game.gameId)`; if `game.outcome == -1`, invert each frame's board for display; build the `ReplayController` with `initialPly: totalPlies` (opens at the final state, paused).
- [x] 7.3 Loading indicator while frames are in-flight (the small spinner avoids a blank frame on slow devices).
- [x] 7.4 Wire route in `main.dart`: `'/replay': (ctx) => ReplayScreen(game: ModalRoute.of(ctx)!.settings.arguments as RecentGame)`.
- [x] 7.5 Layout per design.md:
  - AppBar with outcome verdict ("YOU WIN" / "CLONE WINS" / "DRAW" / "GAME OVER") and a back arrow.
  - Area readout line below the appBar (suppressed when either area is null).
  - `GoBoard(...)` (no `readOnly` flag — see §3 above; omitting `onTap` makes it read-only) showing `controller.boardAtCurrentPly()` and `controller.lastMoveAtCurrentPly()`.
  - "Move N / Total" text, with "(pass)" appended when the current ply is a pass move.
  - `Slider(min: 0, max: totalPlies.toDouble(), value: controller.ply.toDouble(), onChanged: (v) => controller.seek(v.round()))`.
  - VCR row: five `IconButton`s — `⏮ ⏴ ⏯ ⏵ ⏭`. `⏯` toggles between play/pause icons based on `controller.isPlaying`.
  - Speed chip: small `OutlinedButton` showing `1×` / `2×` / `4×`, taps cycle.
- [x] 7.6 Tests (`apps/mobile/test/screens/replay_screen_test.dart`):
  - Opens at final ply; slider at max; play button shows ▶ icon.
  - Tapping `⏮` moves slider to 0; tapping `⏵` advances by one ply.
  - Tapping `⏯` starts auto-play; after one tempo tick the slider has advanced.
  - Pass ply shows "(pass)" annotation in the move counter and no last-move ring.
  - Bot-won game (`outcome == -1`) renders player stones as ivory at every ply (assert via painted-rect inspection from the GoBoard tests we already have).
  - `readOnly` GoBoard ignores taps.

## 8. Start screen: tappable strip

- [x] 8.1 In `apps/mobile/lib/src/screens/start_screen.dart`, wrap the existing `AreaHistoryStrip` in a `GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => Navigator.pushNamed(context, '/history'))`.
- [x] 8.2 Optional: a faint Material splash with `InkWell` instead of `GestureDetector` if the strip area benefits from tap feedback. Pick one; document the call.
- [x] 8.3 Test: tapping the strip widget pushes `/history`.

## 9. Verification

- [x] 9.1 `cd packages/game_engine && dart format . && dart analyze && dart test` clean (no engine changes; regression).
- [x] 9.2 `cd apps/mobile && flutter analyze && flutter test` clean.
- [x] 9.3 `flutter build apk --debug` succeeds.
- [x] 9.4 `npx openspec validate replay-viewer --strict` clean.
- [ ] 9.5 Manual on-device smoke:
  - Tap the home-screen strip → History screen lists my games most-recent-first.
  - Tap a player-won game → Replay opens at final board; `⏮` rewinds; `⏯` plays; speed chip cycles 1×/2×/4×.
  - Tap a bot-won game → my stones still render as ivory throughout the replay.
  - Tap a resigned game → no AREA line, header says "RESIGNED", slider still scrubs through the actual moves played.
  - Scrub the slider — captures un-capture correctly going backwards.
  - Pass plies show "(pass)" annotation and no last-move ring.
  - Empty install: tap strip → History shows "No completed games yet."

## 10. Archive

- [ ] 10.1 After ship + smoke confirms, move `openspec/changes/replay-viewer/` to `openspec/changes/archive/<date>-replay-viewer/`.
