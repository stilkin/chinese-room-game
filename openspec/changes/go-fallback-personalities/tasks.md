## 1. Engine: enum churn

- [ ] 1.1 In `packages/game_engine/lib/src/clone_brain.dart`, extend `FallbackStrategy` with: `goStarPoints`, `goHugger`, `goContact`, `goGreedyArea`. Append to the enum (don't reorder; preserves stable serialised names for the existing CF values).
- [ ] 1.2 In `_fallbackMove`, add four new cases. Each delegates to a private helper.
- [ ] 1.3 Implement `_goStarPointWeight(int r, int c, int size)` returning the static 0–3 weight per the design table. Single function, used by all four Go personalities.
- [ ] 1.4 Implement `_goStarPointMove(List<int> legalMoves, GoRules rules)`: score each legal move by `_goStarPointWeight`, pick max, random tie-break.
- [ ] 1.5 Implement `_goHuggerMove`: score = count of 4-adjacent friendly stones. Tie-break: Star-point weight, then random.
- [ ] 1.6 Implement `_goContactMove`: score = count of 4-adjacent enemy stones. Tie-break: Star-point weight, then random.
- [ ] 1.7 Implement `_goNeighbourOfStoneCandidates(Board)`: return `Set<int>` of empty cells with at least one 4-orthogonal-adjacent stone (any colour). Used only by Greedy.
- [ ] 1.8 Implement `_goGreedyAreaMove(List<int> legalMoves, GoRules rules)`: intersect `legalMoves` with `_goNeighbourOfStoneCandidates`. If empty, fall through to `_goStarPointMove`. Else, for each candidate, `applyMove` then call `rules.areaScore(trial)` and pick by `(own − opponent)`. Tie-break: Star-point weight, then random.
- [ ] 1.9 In each Go-mode helper, `assert(rules is GoRules)` at entry — defensive fence; the slider construction already prevents wrong-game routing.

## 2. Engine: tests

- [ ] 2.1 `_goStarPointWeight` table tests: tengen (6,6) → 3, hoshi (3,3) → 3, 3rd line (3,7) → 2, edge (0,5) → 1, 2nd line (1,5) → 0. Spot-check four corners + tengen + each "ring".
- [ ] 2.2 Star-point fallback group: empty board → tengen (or random hoshi under fixed seed); board with one move at tengen → some other star point.
- [ ] 2.3 Hugger fallback group: empty board → behaves identically to Star-point; one own stone at (6,6) → picks one of (5,6), (7,6), (6,5), (6,7); two own stones in a row → picks the cell that touches both.
- [ ] 2.4 Contact fallback group: empty board → Star-point behaviour; one enemy stone at (6,6) → picks one of its four neighbours; mixed board with friendly and enemy stones — confirms it picks the enemy-adjacent placement, not the friendly-adjacent one.
- [ ] 2.5 Greedy fallback group: empty board → Star-point behaviour (prefilter empty); constructed mid-game position where one move captures 3 stones — confirm Greedy picks the capturing move (largest area swing); position where prefilter returns ~10 cells — confirm only those are evaluated (instrument via test-only counter or observe via deterministic non-prefilter cell).
- [ ] 2.6 `dart format && dart analyze && dart test` clean in `packages/game_engine/`.

## 3. Engine: benchmark CLI

- [ ] 3.1 Add a `bin/go_personality_round_robin.dart` (or extend the existing Go self-play benchmark) that accepts tokens `chaotic`, `gostar`, `gohugger`, `gocontact`, `gogreedy` for both coach and trainee.
- [ ] 3.2 Round-robin gate runner: 50 games per direction × 10 pairings × 2 alternation directions = 1000 games. Print aggregate-wins-per-personality.
- [ ] 3.3 Help comment block lists the supported tokens and example invocations.

## 4. Engine: behavioural sanity benchmark (gate)

- [ ] 4.1 Run the round-robin with seed 42, 50 games per direction.
- [ ] 4.2 Record the aggregate-wins ranking in this tasks file.
- [ ] 4.3 Apply the slider-position-swap rule from design.md if observed strength contradicts paper expectation by more than one adjacent swap. Document any swaps.

## 5. Mobile: persistence

- [ ] 5.1 In `apps/mobile/lib/src/db/database_service.dart`, update `_kUserFacingFallbacks` to `{random, goStarPoints, goHugger, goContact, goGreedyArea}`.
- [ ] 5.2 Update `_kDefaultFallback` to `goHugger`.
- [ ] 5.3 No schema bump needed (still v5; coercion happens at read time in `loadFallback`).
- [ ] 5.4 Persistence tests: round-trip across the five new user-facing values; legacy `pileFocus` / `ownPileAdjacent` / `greedyConnect` / `greedyConnectDefense` / `middleFocus` / `edgeFocus` (raw insert) → `goHugger`; default-on-empty is `goHugger`.

## 6. Mobile: settings UI (slider restored)

- [ ] 6.1 Convert `SettingsScreen` from `StatelessWidget` back to `StatefulWidget`. Slider's local drag state lives in `_SettingsScreenState`, not in `AppScope` — confirm `initState` reads only from `widget` and from `AppScope.of(context)` *inside* `build` to avoid the prior `initState` lookup crash.
- [ ] 6.2 `_kSliderLevels` becomes the five Go entries: Chaotic, Star-point, Hugger (default), Contact, Greedy. Default index `_kDefaultSliderIndex = 2`.
- [ ] 6.3 Replace the static `Text` with `Slider(divisions: 4, min: 0, max: 4)` plus live-updating name (display font) + blurb (body font) below.
- [ ] 6.4 Persist on `onChangeEnd` via `notifier.setFallback(...)`.
- [ ] 6.5 `_initialPosition` falls back to `_kDefaultSliderIndex` (Hugger) if the persisted value is somehow off-list.
- [ ] 6.6 Brand-styled with the moonlit-goban palette (cinnabar accent, ivory text, board-panel surface) — match the existing settings aesthetic.

## 7. Mobile: notifier default

- [ ] 7.1 No code change required: `main.dart` already bootstraps the brain via `db.loadFallback()`, which now returns `goHugger` by default.
- [ ] 7.2 Update `apps/mobile/test/game_notifier_test.dart` only if any test asserts on the literal default fallback (likely a test that expected `FallbackStrategy.random` after the Go cutover). Switch to `goHugger`.

## 8. Verification

- [ ] 8.1 `dart format && dart analyze && dart test` clean in `packages/game_engine/`.
- [ ] 8.2 `flutter analyze && flutter test` clean in `apps/mobile/`.
- [ ] 8.3 Pre-commit hook passes.
- [ ] 8.4 Manual smoke on device:
  - Install over the previous build. Open Settings — confirm a real `Slider` widget with five rungs appears, defaulting to Hugger.
  - Drag through all five positions; confirm name + blurb update live; close and reopen Settings to verify persistence.
  - Delete all logs, then start a fresh game with each of Star-point / Hugger / Contact / Greedy selected (forces the fallback path); play 10 plies; confirm the personality is recognisable: Star-point opens at hoshi, Hugger sticks stones together, Contact responds adjacent to your stones, Greedy plays where territory swings.
  - Confirm the early-game double-pass rate drops vs the `random`-only Go cutover (informally — fewer "0–0 phantom games" in the first three games before the brain has data).

## 9. Archive

- [ ] 9.1 After ship + smoke, move `openspec/changes/go-fallback-personalities/` to `openspec/changes/archive/<date>-go-fallback-personalities/` per the project's archive convention.
