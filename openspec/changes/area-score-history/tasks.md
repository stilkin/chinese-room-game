## 1. Persistence: schema v6

- [ ] 1.1 In `apps/mobile/lib/src/db/database_service.dart`, bump `_kSchemaVersion` 5 → 6.
- [ ] 1.2 In `onUpgrade`, add an `if (oldVersion < 6)` branch running two `ALTER TABLE games ADD COLUMN ...` statements (`player_area INTEGER`, `clone_area INTEGER`).
- [ ] 1.3 Update `onCreate` so fresh installs have the two columns.
- [ ] 1.4 New method `Future<void> updateGameAreaScore(String gameId, int playerArea, int cloneArea)`.
- [ ] 1.5 Replace `Future<List<int>> loadRecentOutcomes({int limit = ...})` with `Future<List<RecentGame>> loadRecentGames({int limit = 100})`. Add the typedef `RecentGame` at the top of the file (or in a tiny new model file if it grows).
- [ ] 1.6 Persistence tests:
  - v5 → v6 upgrade test: open DB at v5 with sample rows, reopen at v6, confirm both columns exist, legacy rows have NULL.
  - `updateGameAreaScore` round-trip.
  - `loadRecentGames` order (most-recent first), limit, and NULL surfacing for resigned games.

## 2. Notifier: persist scores on game end

- [ ] 2.1 In `GameNotifier._endGame`, after `db.updateGameOutcome(...)`, compute `(rules as GoRules).areaScore(_displayBoard)` and call `db.updateGameAreaScore`. Guarded by `if (rules is GoRules)` so CF (regression-only) doesn't trip.
- [ ] 2.2 `resign` SHALL NOT call the new method. Confirm with a test that resign leaves the columns NULL.
- [ ] 2.3 Replace `_recentOutcomes` field + getter with `_recentGames` of type `List<RecentGame>`. Update `loadOngoingGame` / cold-start paths to call `loadRecentGames` instead of `loadRecentOutcomes`.
- [ ] 2.4 Notifier tests update: replace any assertion on `recentOutcomes` shape with the new record type.

## 3. Widget: `AreaHistoryStrip`

- [ ] 3.1 New file `apps/mobile/lib/src/widgets/area_history_strip.dart`. Stateless, takes `List<RecentGame> games` (most-recent-first; widget assumes the slice is already capped).
- [ ] 3.2 Paint logic per design.md §Per-row painting:
  - DNF / null-area: solid `PiYingTheme.onSurfaceMuted` row, no endcaps.
  - Real game: ivory + near-black proportion bar between two `kEndcapWidth` endcaps.
  - Endcap colour: matches the winner (ivory / near-black / cream-amber for draw).
- [ ] 3.3 Constants inside the widget file: `kRowHeight = 3.0`, `kRowGap = 1.0`, `kEndcapWidth = 3.0`.
- [ ] 3.4 Widget test (`test/widgets/area_history_strip_test.dart`):
  - Renders the right number of rows.
  - Win row: paints ivory endcaps, ivory + dark proportion.
  - Loss row: paints dark endcaps.
  - Draw row: paints cream-amber endcaps, 50/50 split.
  - DNF row: paints solid muted bar, no endcaps.
  - (Use a `@visibleForTesting` accessor on the painter that exposes the accumulated draw calls; assert against that, not against pixel goldens.)
- [ ] 3.5 Delete `apps/mobile/lib/src/widgets/recent_games_strip.dart` and its test, if present.

## 4. Start screen: reorder + swap widget

- [ ] 4.1 In `apps/mobile/lib/src/screens/start_screen.dart`, replace `RecentGamesStrip(outcomes: notifier.recentOutcomes)` with `AreaHistoryStrip(games: notifier.recentGames)`.
- [ ] 4.2 Reorder the column children so the order is: header → stats box → buttons → `LAST GAMES` heading → `AreaHistoryStrip`. The strip fills the bottom; remove the `Spacer` between the strip and the buttons (buttons now sit *above* the strip).
- [ ] 4.3 Cap the slice handed to the widget at 100: `notifier.recentGames.take(100).toList()` (or do the cap inside the notifier — preference: notifier, so the cap is a single source of truth).

## 5. Post-game screen: area readout

- [ ] 5.1 In `apps/mobile/lib/src/screens/post_game_screen.dart`, below the verdict line, add a `Text` showing `'AREA  ·  YOU $playerArea  ·  CLONE $cloneArea'`.
- [ ] 5.2 Compute via `(rules as GoRules).areaScore(notifier.displayBoard)` — works on resign (the live board survives `resign`).
- [ ] 5.3 Suppress the line when `rules is! GoRules` or `score.white + score.black == 0` (early-resign on a near-empty board).
- [ ] 5.4 Style: `bodyMedium` size, `onSurfaceMuted` colour. Present without competing with the verdict.

## 6. Verification & ship

- [ ] 6.1 `cd packages/game_engine && dart format . && dart analyze && dart test` clean.
- [ ] 6.2 `cd apps/mobile && flutter analyze && flutter test` clean.
- [ ] 6.3 `npx openspec validate area-score-history --strict` clean.
- [ ] 6.4 Manual on-device smoke:
  - Existing v5 install → upgrade → v5 games render as muted DNF rows (because no area data persisted for them); freshly-completed v6 game renders with proportion + endcap.
  - Win a game by a wide margin: row's bar leans hard ivory, ivory endcaps.
  - Lose by a wide margin: row leans dark, dark endcaps.
  - Resign mid-game: row renders muted-grey, post-game screen shows AREA line with current board's score.
  - Two-pass game-end: row renders with both areas populated, post-game shows real numbers.
- [ ] 6.5 Build APK, install via `adb install -r ...`.
- [ ] 6.6 Single squashed commit at the end. Title: `FEAT: per-game area scores + AreaHistoryStrip on home screen`.

## 7. Archive

- [ ] 7.1 After ship + smoke confirms, move `openspec/changes/area-score-history/` to `openspec/changes/archive/<date>-area-score-history/`.
