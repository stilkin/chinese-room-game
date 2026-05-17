## 1. Engine: enum rename + Diamond rescoring

- [x] 1.1 Rename `FallbackStrategy.goHugger` → `FallbackStrategy.goDiamond` in `packages/game_engine/lib/src/clone_brain.dart`. Update the switch case in `_fallbackMove`. Update the comment block describing Go-mode personalities.
- [x] 1.2 Rename `_goHuggerMove` → `_goDiamondMove`. Replace its body to call a new `_pickByDiamondScore` helper (instead of the previous `_pickByNeighbourCount`).
- [x] 1.3 Implement `_pickByDiamondScore`: for each legal placement, compute `score = (diagonal-friendly count) − (orthogonal-friendly count)`. Tie-break: Star-point weight, then random survivor.
- [x] 1.4 Extract `_pickByOrthogonalNeighbour` (renamed from `_pickByNeighbourCount`) so Contact still has its orthogonal-enemy-count behaviour. Helper signature unchanged.
- [x] 1.5 Extract a shared `_pickFromScored` helper used by both `_pickByDiamondScore` and `_pickByOrthogonalNeighbour` (and Greedy's existing pick logic if it shares the same shape). Deduplicates the "primary-score → Star-point weight → random survivor" tie-break.
- [x] 1.6 Hoist constants to module scope: `_kOrthogonalOffsets`, `_kDiagonalOffsets`. Each Go helper uses them in place of inline `const offsets = [...]` blocks.
- [x] 1.7 Update the stale "Hugger" mention in the `selectMove` `opponentJustPassed` comment to "Diamond".

## 2. Engine: Wanderer (Go-mode `random`)

- [x] 2.1 In `_fallbackMove`, the `random` case checks `if (rules is GoRules)` and routes to a new `_goWandererMove(legalMoves, board)`. CF random retains the existing uniform-random-over-legalMoves behaviour.
- [x] 2.2 Implement `_goWandererMove`: compute `_goCellsNearStones(board, 2)` (Manhattan-2 neighbourhood of any stone), intersect with placement moves (pass excluded), pick uniformly at random. Empty pool → fall through to `_pickByStarPointWeight`.
- [x] 2.3 Generalise the existing `_goNeighbourOfStoneCandidates(board)` to `_goCellsNearStones(board, int maxDistance)`. Greedy's existing callsite uses `maxDistance: 1`.

## 3. Engine: tests

- [x] 3.1 Rewrite the `Go Hugger fallback` test group as `Go Diamond fallback`. Empty board → Star-point fallthrough (unchanged). One own stone at tengen → picks one of the 4 diagonals (5,5)/(5,7)/(7,5)/(7,7), not the orthogonals. Two own stones at (5,5) and (7,7) → picks shared diagonal (6,6). Explicit "avoids dumpling shape" test: confirms an orthogonal-adjacent cell is never picked when a diagonal is available.
- [x] 3.2 Add `Go Wanderer fallback (random in Go-mode)` group: empty board → falls through to Star-point opener; chosen cell is within Manhattan-2 of an existing stone; pass move is excluded when opponent has not passed.
- [x] 3.3 `dart format && dart analyze && dart test` clean in `packages/game_engine/`.

## 4. Engine: benchmark CLI token rename

- [x] 4.1 In `bin/go_personality_round_robin.dart`, update the personality map: `chaotic` → `wanderer`, `gohugger` → `diamond`. Help comment updated accordingly.

## 5. Round-robin gate

- [x] 5.1 Run `dart run bin/go_personality_round_robin.dart 50 42` after the rework lands. Record the new aggregate ranking.
- [x] 5.2 **Aggregate ranking**:

  ```text
  gogreedy   337   (84% win rate)
  diamond    306   (77%)
  gocontact  202   (51%)
  gostar     119   (30%)
  wanderer    34   (9%)
  ```

  Pairwise strict order: Wanderer < Star-point < Contact < Diamond < Greedy. Slider matches observed strength exactly.

  Sanity-check observations:
  - Diamond jumped from 11% (as Hugger) to 77% (as Diamond) — the diagonal-minus-orthogonal scoring is the strongest fallback after Greedy.
  - Wanderer is *slightly stronger* than pure-random Chaotic against unchanged opponents (11.3% vs 8.7% on apples-to-apples), but its aggregate is lower because (a) the easy-meal Hugger is gone and (b) it loses 100/100 to Diamond.

## 6. Mobile: slider + persistence

- [x] 6.1 In `apps/mobile/lib/src/screens/settings_screen.dart`, update `_kSliderLevels` to the new order: Wanderer (`random`) → Star-point (`goStarPoints`) → Contact (`goContact`) → Diamond (`goDiamond`) → Greedy (`goGreedyArea`). Update labels and blurbs accordingly.
- [x] 6.2 `_kDefaultSliderIndex = 1` (Star-point, post-rework slider position; was 2 in the pre-rework slider).
- [x] 6.3 In `apps/mobile/lib/src/db/database_service.dart`, swap `goHugger` → `goDiamond` in `_kUserFacingFallbacks`. `_kDefaultFallback` stays `goStarPoints`. Update the docstring with the rationale.
- [x] 6.4 Persistence tests (`database_service_test.dart`): update the round-trip set (goHugger → goDiamond); add a legacy `goHugger` raw-insert test that confirms coercion to the default; default-on-empty asserts `goStarPoints`.
- [x] 6.5 Notifier test (`game_notifier_test.dart`): `setFallback(goHugger)` → `setFallback(goDiamond)`; coercion-after-greedyConnect test still asserts `goStarPoints`.

## 7. Verification

- [x] 7.1 `dart format && dart analyze && dart test` clean in `packages/game_engine/`.
- [x] 7.2 `flutter analyze && flutter test` clean in `apps/mobile/`.
- [x] 7.3 Pre-commit hook passes on the rework commit(s).
- [x] 7.4 Manual smoke on device:
  - Install over the previous (go-fallback-personalities) build. Open Settings — slider now shows Wanderer / Star-point / Contact / Diamond / Greedy; default thumb at position 1 (Star-point).
  - Drag through Diamond — confirm bot plays diagonal-of-own shapes, not dumplings.
  - Drag through Wanderer — confirm bot plays locally rather than scattering.
  - Existing-user upgrade smoke: legacy `goHugger` setting should land on Star-point default; legacy `random` setting stays on slider position 0 (now Wanderer).

## 8. Archive

- [ ] 8.1 After ship + smoke, move `openspec/changes/go-personality-rework/` to `openspec/changes/archive/<date>-go-personality-rework/`. Sequence-wise, archive `go-fallback-personalities` *first* (its specs describe the pre-rework state) then this rework (which MODIFIES on top).
