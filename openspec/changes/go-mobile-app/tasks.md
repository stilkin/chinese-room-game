## 1. Mobile: switch GameRules

- [x] 1.1 In `apps/mobile/lib/src/state/game_notifier.dart`, change the `GameRules` instance from `ConnectFourRules()` to `GoRules(size: 13)`. (Done in `main.dart:18` — the notifier itself stays generic.)
- [x] 1.2 Remove any remaining hard-coded `7` (cols) / `6` (rows) constants in mobile code; rely on `rules.rows` / `rules.cols`. (Notifier was already correct; tests updated to `Board(13, 13)`.)
- [x] 1.3 Wire the pass action through `GameNotifier.pass()`.

## 2. Mobile: GoBoard widget

- [x] 2.1 New file `apps/mobile/lib/src/widgets/go_board.dart`.
- [x] 2.2 Render a 13×13 intersection grid via a `CustomPainter`. Lines, star points (3-3, 3-6, 3-9, 6-3, 6-6, 6-9, 9-3, 9-6, 9-9).
- [x] 2.3 Render stones as filled circles at intersections. Player (red) and clone (yellow), sized to `cell * 0.45`.
- [x] 2.4 Last-move highlight: small ring at the most recent placement.
- [x] 2.5 Tap handler: convert (x, y) to nearest intersection within a `cell * 0.4` hit radius; reject taps further out. Legality filtered by `GameNotifier.playerMove` upstream.
- [ ] 2.6 Capture-animation hook: stones fade over 150ms. **Skipped per design.md** — proposal explicitly allows instant removal for v1; revisit if it feels visually abrupt on device.
- [x] 2.7 `shouldRepaint => true` (consistent with the simpler-is-better lesson from CF).

## 3. Mobile: GameScreen wiring

- [x] 3.1 In `apps/mobile/lib/src/screens/game_screen.dart`, replace the CF board widget with `GoBoard`.
- [x] 3.2 Add a Pass button to the footer area. Disable while the clone is thinking.
- [x] 3.3 On two consecutive passes (or other terminal condition), navigate to the post-game screen with the area score and winner. (`_postGameNavScheduled` latch + 1.2s delay survives the rewrite.)
- [x] 3.4 Update narration display: phrasing reads naturally for Go. (No work — engine narration in `narration.dart` was already game-neutral.)
- [x] 3.5 Remove all `column` / `drop` / `stack` vocabulary from mobile copy. (Only the start-screen tagline needed updating.)

## 4. Mobile: settings simplification

- [x] 4.1 In `apps/mobile/lib/src/screens/settings_screen.dart`, reduce `_kSliderLevels` to a single entry: `(strategy: random, name: 'Chaotic', blurb: 'plays anywhere legal.')`.
- [x] 4.2 In `apps/mobile/lib/src/db/database_service.dart`, set `_kUserFacingFallbacks = {random}` and `_kDefaultFallback = random`.
- [x] 4.3 Persistence: any persisted value not in `{random}` (e.g. legacy `pileFocus`, `ownPileAdjacent`) coerces to `random`.
- [x] 4.4 Existing slider widget code: **replaced with a static label** (Flutter `Slider` can't render with `divisions: 0`). Restored to a real slider when the personality ladder lands in `go-fallback-personalities`.

## 5. Mobile: schema migration

- [x] 5.1 In `apps/mobile/lib/src/db/database_service.dart`, bump `_kSchemaVersion` to `4`.
- [x] 5.2 `onUpgrade` for `oldVersion < 4`: drop `game_states`, drop `games`, recreate empty at v4 (column shapes unchanged; only blob sizes differ).
- [x] 5.3 `onCreate` for v4 unchanged from v3.
- [x] 5.4 Settings preserved across the migration (separate `clone_config` table; not touched).

## 6. Mobile: retire Connect Four UI

- [x] 6.1 Delete `apps/mobile/lib/src/widgets/board_painter.dart` (the CF gravity-drop board).
- [x] 6.2 Remove any CF imports from `apps/mobile/lib/`. (`main.dart` was the only consumer.)
- [x] 6.3 Remove CF-specific narration templates from mobile copy (engine narration stays). (No-op — none existed.)
- [x] 6.4 Remove CF-specific tests; replace with Go equivalents. (Deleted `board_painter_test.dart`; rewrote `game_notifier_test.dart` and `database_service_test.dart`; added `go_board_test.dart`.)

## 7. Engine: moveDescription helper

- [ ] 7.1 In `packages/game_engine/lib/src/game_rules.dart`, add `String moveDescription(int move)` to `GameRules`. Default returns `move.toString()`.
- [ ] 7.2 `ConnectFourRules.moveDescription(c) => 'column $c'`.
- [ ] 7.3 `GoRules.moveDescription(move) => move == passMove ? 'pass' : <coord-string for that intersection>`.
- [ ] 7.4 Mobile narration consumes `rules.moveDescription(...)` rather than hard-coded phrasing.

**Section 7 is deferred / out of scope.** Survey of `narration.dart` and `apps/mobile/lib/` confirmed no consumer surfaces move-specific phrasing today; adding the helper would be speculative. The hook can be added when an actual consumer arrives (e.g. richer narration templates in `go-fallback-personalities`).

## 8. Tests

- [x] 8.1 New `apps/mobile/test/go_board_test.dart`: tap-to-intersection conversion (within hit radius, outside hit radius, edge cases). 7 tests.
- [x] 8.2 Update `apps/mobile/test/game_notifier_test.dart`: replaced CF-shaped scenarios with Go-shaped ones (place at intersections, pass, illegal-move rejection, persistence, settings round-trip).
- [x] 8.3 Update `apps/mobile/test/database_service_test.dart`: `Board(13, 13)` everywhere; fallback coercion tests updated to assert that non-user-facing values now map to `random`.
- [x] 8.4 Delete obsolete CF-specific mobile tests (the engine still tests `ConnectFourRules`).

## 9. Verification

- [x] 9.1 `flutter analyze` clean.
- [x] 9.2 `flutter test` clean (34 tests pass).
- [x] 9.3 Build APK: `flutter build apk --debug` succeeds.
- [ ] 9.4 Manual smoke on device: place a stone, capture an opposing stone, pass, two-pass terminates, post-game shows area score, settings shows just "Chaotic", restart preserves the choice, narration reads naturally, resume mid-game works.
