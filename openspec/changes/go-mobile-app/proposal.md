# Go mobile app

## Why

`go-engine-foundation` adds Go to the engine package but leaves the mobile app shipping Connect Four. This change cuts the app over to 13×13 Go: new board widget, new tap interaction, new capture animation, new persistence shape, and the removal of all Connect Four user-facing surface area. Connect Four code stays in the engine package as a multi-game regression case but disappears from the user's experience.

We ship with `chaotic` (random legal) as the only fallback personality. The Go-specific personality ladder is held back to a deferred change after we've played enough real games to know which behaviours are worth ladder-ing.

## What Changes

- **Board widget**: replace the Connect Four slot/gravity widget with an intersection-grid widget. Tap a free intersection to place a stone there. Pass via a dedicated button (header or footer of the game screen).
- **Capture animation**: when a placement removes opposing stones, animate them out (fade or shrink). Simpler than CF's gravity drop — instant removal is acceptable for the first cut.
- **Game over UX**: two consecutive passes (or "I want to score now") triggers the post-game screen with the area score and winner.
- **Settings**: drop all Connect Four-specific personality copy. Slider stays in place but only `chaotic` populated for now (one-position slider until change 3 fills the ladder).
- **DB migration**: bump schema. Connect Four data is incompatible game-state shape — fresh start. Document this; users see a clean slate the first time they launch the new build.
- **Connect Four UI removal**: drop CF screens, routes, the column-tap interaction, the gravity-drop animation, CF-specific narration templates, and all `apps/mobile/lib/src/widgets/board_painter.dart` CF-specific code. Engine package keeps `ConnectFourRules` for tests; the mobile app no longer imports or uses it.
- **Narration vocabulary**: tune templates for Go (territory, capture, group, influence) and remove CF-specific phrases ("column 4", "drop", "stack").
- **App boots straight into Go.** No game picker. The 13×13 board is the only thing the user sees on game-screen.

## Impact

- Heavy churn in `apps/mobile/lib/src/widgets/` (board widget rewritten).
- `apps/mobile/lib/src/screens/game_screen.dart`: tap interaction, pass button, capture animation hook.
- `apps/mobile/lib/src/state/game_notifier.dart`: switch underlying `GameRules` from `ConnectFourRules` to `GoRules(size: 13)`.
- `apps/mobile/lib/src/db/database_service.dart`: schema bump (v4); `onUpgrade` from v3 wipes `game_states` and `games` tables (CF data is incompatible); fresh installs go straight to v4.
- `apps/mobile/lib/src/screens/settings_screen.dart`: slider reduced to one entry (`Chaotic`); CF-specific blurbs removed.
- `apps/mobile/lib/src/db/database_service.dart`: `_kUserFacingFallbacks` reduces to just `random`; `_kDefaultFallback = random`.
- `apps/mobile/test/`: widget/notifier/persistence tests rewritten for Go.
- New file: `apps/mobile/lib/src/widgets/go_board.dart` (intersection-grid widget).
- Deleted/retired: `apps/mobile/lib/src/widgets/board_painter.dart` (CF gravity drop), CF-specific narration templates.
- Engine package: untouched. `ConnectFourRules` continues to live there as a regression case.
- Spec capabilities updated: `game-screen`, `settings-screen`, `clone-brain` (cold-start fallback list reduces to chaotic), `game-persistence` (schema v4), `start-screen`.
