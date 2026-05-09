## 1. Mobile: switch GameRules

- [ ] 1.1 In `apps/mobile/lib/src/state/game_notifier.dart`, change the `GameRules` instance from `ConnectFourRules()` to `GoRules(size: 13)`.
- [ ] 1.2 Remove any remaining hard-coded `7` (cols) / `6` (rows) constants in mobile code; rely on `rules.rows` / `rules.cols`.
- [ ] 1.3 Wire the pass action through `GameNotifier.pass()`.

## 2. Mobile: GoBoard widget

- [ ] 2.1 New file `apps/mobile/lib/src/widgets/go_board.dart`.
- [ ] 2.2 Render a 13×13 intersection grid via a `CustomPainter`. Lines, star points (4-4, 7-7, 10-10 plus mirror points and centre).
- [ ] 2.3 Render stones as filled circles at intersections. White and black, sized to ~0.45 × cell.
- [ ] 2.4 Last-move highlight: small ring or mark on the most recent placement.
- [ ] 2.5 Tap handler: convert (x, y) to nearest intersection within a `cell * 0.4` hit radius; reject taps further out. Reject taps on non-legal intersections.
- [ ] 2.6 Capture-animation hook: when `GameNotifier` reports captured cells for the most recent move, fade those cells over 150ms.
- [ ] 2.7 `shouldRepaint => true` (consistent with the simpler-is-better lesson from CF).

## 3. Mobile: GameScreen wiring

- [ ] 3.1 In `apps/mobile/lib/src/screens/game_screen.dart`, replace the CF board widget with `GoBoard`.
- [ ] 3.2 Add a Pass button to the footer area. Disable while the clone is thinking.
- [ ] 3.3 On two consecutive passes (or other terminal condition), navigate to the post-game screen with the area score and winner.
- [ ] 3.4 Update narration display: phrasing reads naturally for Go.
- [ ] 3.5 Remove all `column` / `drop` / `stack` vocabulary from mobile copy.

## 4. Mobile: settings simplification

- [ ] 4.1 In `apps/mobile/lib/src/screens/settings_screen.dart`, reduce `_kSliderLevels` to a single entry: `(strategy: random, name: 'Chaotic', blurb: 'Plays anywhere legal.')`.
- [ ] 4.2 In `apps/mobile/lib/src/db/database_service.dart`, set `_kUserFacingFallbacks = {'random'}` and `_kDefaultFallback = 'random'`.
- [ ] 4.3 Persistence: any persisted value not in `{'random'}` (e.g. legacy `pileFocus`, `ownPileAdjacent`) coerces to `random`.
- [ ] 4.4 Existing slider widget code continues to work; just receives a one-element list.

## 5. Mobile: schema migration

- [ ] 5.1 In `apps/mobile/lib/src/db/database_service.dart`, bump `_kSchemaVersion` to `4`.
- [ ] 5.2 `onUpgrade` for `oldVersion < 4`: drop `game_states`, drop `games`, recreate empty at v4 (column shapes unchanged; only blob sizes differ).
- [ ] 5.3 `onCreate` for v4 unchanged from v3.
- [ ] 5.4 Settings preserved across the migration (separate table; not touched).

## 6. Mobile: retire Connect Four UI

- [ ] 6.1 Delete `apps/mobile/lib/src/widgets/board_painter.dart` (the CF gravity-drop board).
- [ ] 6.2 Remove any CF imports from `apps/mobile/lib/`.
- [ ] 6.3 Remove CF-specific narration templates from mobile copy (engine narration stays).
- [ ] 6.4 Remove CF-specific tests; replace with Go equivalents.

## 7. Engine: moveDescription helper

- [ ] 7.1 In `packages/game_engine/lib/src/game_rules.dart`, add `String moveDescription(int move)` to `GameRules`. Default returns `move.toString()`.
- [ ] 7.2 `ConnectFourRules.moveDescription(c) => 'column $c'`.
- [ ] 7.3 `GoRules.moveDescription(move) => move == passMove ? 'pass' : <coord-string for that intersection>`.
- [ ] 7.4 Mobile narration consumes `rules.moveDescription(...)` rather than hard-coded phrasing.

## 8. Tests

- [ ] 8.1 New `apps/mobile/test/go_board_test.dart`: tap-to-place, illegal-tap rejection, last-move highlight, capture animation hook.
- [ ] 8.2 Update `apps/mobile/test/game_notifier_test.dart`: replace CF-shaped scenarios with Go-shaped ones (place at a couple of intersections, pass, two-pass termination triggers post-game).
- [ ] 8.3 Update `apps/mobile/test/database_service_test.dart`: v4 schema; v3-to-v4 upgrade clears tables; round-trip a Go-shaped `GameState`.
- [ ] 8.4 Delete obsolete CF-specific mobile tests (the engine still tests `ConnectFourRules`).

## 9. Verification

- [ ] 9.1 `flutter analyze` clean.
- [ ] 9.2 `flutter test` clean.
- [ ] 9.3 Build APK; install on device.
- [ ] 9.4 Manual smoke: place a stone, capture an opposing single stone, pass, two-pass terminates, post-game shows area score, settings slider has one entry, restart preserves the (single) fallback choice, narration reads naturally.
