# Design — Go mobile app

## Goal

Cut the mobile app over from Connect Four to 13×13 Go in one user-visible change. Engine work is already done (`go-engine-foundation`); this is the UI + persistence + retire-CF work.

## Board widget

- New `GoBoard` widget rendering a 13×13 intersection grid.
- Stones rendered as filled circles at intersections (player = white, clone = black, or whichever convention reads best on our colour palette).
- Tap target = nearest intersection within a hit radius. Tapping a non-empty or otherwise-illegal intersection: brief negative haptic, no state change. Tapping a legal empty: place stone, animate any captures, hand the turn to the clone.
- Pass action: dedicated button (footer area, alongside or replacing the existing "new game" controls during play).
- Last-move highlight: small ring around the most recent placement so the user can see what the clone just did.
- Capture animation: stones being removed fade over ~150ms. Simpler than a "fly off the board" effect; readable.

## Coordinate system

- Engine indices are `(row, col)` with `row=0` at the top, `col=0` at the left.
- Widget renders the same orientation. No flip. Board is square; orientation choice doesn't matter for play, but consistency with engine-internal coordinates makes debugging easier.

## State flow

- `GameNotifier` owns the engine `GameLog` plus rendering-only state (last move, capture animation triggers, "is clone thinking" spinner).
- On user tap: `GameNotifier.placeAt(r, c)` validates legality (delegates to `GoRules.legalMoves`), applies the move, stores the resulting `GameState`, schedules the clone's response.
- On user pass: `GameNotifier.pass()` — same flow with `move = passMove`. If two consecutive passes accumulate (the user passes after the clone passed, or vice versa), `isTerminal` returns true and the post-game screen appears.

## Persistence

- Schema v4. v3 storage is Connect-Four-shaped (7×6 boards, 42-byte diffused images). Go data is 13×13 = 169-cell boards / 169-byte diffused images. The shapes are incompatible at the byte level.
- `onUpgrade` from v3 to v4: drop `game_states`, drop `games`, recreate at v4 with the same column shapes (board blob, diffused_image blob, etc. — Go just stores larger blobs in the same columns). User sees a clean slate on first launch of the new build.
- Settings (fallback choice) preserved across the migration — that's a separate table.
- v4 is **not** itself game-specific in schema — only the blob sizes change. Future games that reuse the schema (e.g. 9×9 Go in a settings option later) wouldn't need another bump.

## Settings slider

- Slider stays as a UI element to preserve muscle memory and the structure for change 3.
- Only one position populated for now: `Chaotic`. The slider effectively becomes a label until change 3 adds ladder entries.
- Alternative considered: hide the slider entirely until change 3. Rejected — leaving the UI scaffolding in place makes change 3's scope smaller (just populate the ladder, no settings-screen restructure).
- Persistence layer (`_kUserFacingFallbacks`, `_kDefaultFallback`) reduces to just `random`. The legacy slider personalities (`pileFocus`, `ownPileAdjacent`, `greedyConnect`, `greedyConnectDefense`) are now Connect-Four-only and live in the engine package; the mobile app just doesn't surface them.

## Narration

- Connect Four narration uses templates like "I've seen this column before…". Replace with Go-flavoured templates: "this region of the board has come up before", "I'm thinking about influence on the lower right", etc.
- Templates live in `packages/game_engine/lib/src/narration.dart` — general phrasing that works for any spatial game. Less game-specific is better; the more we can reuse the same templates across games, the simpler the code.
- Game-specific vocab (the word "column", the word "intersection") gets parameterised via a small `GameRules.moveDescription(int move)` helper that returns a human-readable string ("column 4" for CF, "Q14" or "the lower-right corner" for Go).

## Connect Four removal scope

- **Engine package**: keep everything. `ConnectFourRules`, `ConnectFourFilter`, `ConnectFourMoveScorer`, kernel, tests, all of it.
- **Mobile app**: remove:
  - `apps/mobile/lib/src/widgets/board_painter.dart` (CF gravity drop animation)
  - Any imports of `ConnectFourRules` from `apps/mobile/`
  - CF-specific copy in settings, post-game screen
  - The old slider personality blurbs that reference columns/stacks/etc.
- **Game picker**: there is no game picker in the current app, so nothing to remove. The app simply boots into Go now where it used to boot into Connect Four.

## Open questions (defer to first device test)

1. **White-on-light readability** — depending on the board background colour, white stones may need an outline or shadow. Decide visually.
2. **Hit radius** — too tight = misses; too loose = wrong-intersection placements. Start with `cell_size * 0.4` and adjust.
3. **Pass button placement** — header vs footer. Lean footer (close to the touch zone). Decide visually.
4. **Capture animation duration** — 150ms is a guess. Slow enough to see, fast enough not to interrupt rhythm. Adjust.

## Alternatives considered

- **Keep the game picker, add Go alongside CF** — more UI surface, two boards to maintain, no real benefit before Go's been proven on its own. Rejected.
- **Migrate CF data into Go via re-encoding** — nonsensical (different game). Rejected.
- **Animate CF-style "fly the captures off the board"** — over-engineered for v1. Fade is fine. Rejected.
- **Add a "resign" button** — nice-to-have but not needed for v1; two-pass termination + the clone's own passing covers natural game-end. Defer.
