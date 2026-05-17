## Why

After `go-fallback-personalities` shipped (v0.2.0), on-device play and the round-robin gate revealed two of the five personalities were genuinely weak in ways that didn't match their intended role:

- **Hugger** (max friendly orthogonal-neighbour count) produced overconcentrated "dumpling shape" — orthogonally-tight stones that share liberties and cover overlapping territory. Lost 0/100 to Chaotic in the original gate (11% aggregate). Visually disengaging; the bot's shape was clearly weak.
- **Chaotic** (pure uniform-random over the full legal-move list) scattered stones across the 13×13 board so thinly they got individually claimed or ignored, producing low-interaction games that ended in lopsided territory swings.

Both personalities are kept (the slider needs five rungs and the "weak baseline + tactical" slot is real), but they're reworked with Go-correct heuristics:

- **Hugger → Diamond**: scores by `diagonal-friendly − orthogonal-friendly` (option (b) from design.md discussion). Actively seeks ponnuki / kosumi shapes and penalises dumpling clusters. In the new gate Diamond rose from worst (11%) to second-best (77%) — significantly stronger because diagonal-extending stones cover disjoint territory.
- **Chaotic → Wanderer**: same `random` enum value, but in Go mode the move pool is pre-filtered to empty cells within Manhattan-2 of any stone. Concentrates random plays where action is happening so they actually interact. Empty board falls through to Star-point (cold-start opener). CF random unchanged.

The round-robin gate (50 games/dir, seed 42) confirmed the reshuffle and drove the slider order. The default went back to **Star-point** (encouraging first impression at ~30% win-rate, recognizable Go openings, contemplative aesthetic) rather than the new slider-mid Contact.

## What Changes

### Engine

- **Rename** `FallbackStrategy.goHugger` → `FallbackStrategy.goDiamond`. Legacy persisted `goHugger` strings no longer match any enum value and coerce to the default at the persistence layer.
- **Replace** the Hugger scoring (`friendly orthogonal-neighbour count`) with Diamond scoring (`diagonal-friendly count − orthogonal-friendly count`). The minus actively penalises dumpling-shape orthogonal adjacency; the diagonal-friendly score rewards kosumi / ponnuki extensions. Tie-break pyramid (Star-point weight → seeded random) is unchanged.
- **In Go mode**, `FallbackStrategy.random` SHALL route to a new "Wanderer" behaviour: empty placement cells within Manhattan-2 of any stone, uniformly random within that pool. Empty board (no stones) → falls through to Star-point. CF random retains uniform-random over the full legal list.
- **Generalise** the Greedy prefilter helper to a parametric `_goCellsNearStones(board, maxDistance)` shared by Greedy (`maxDistance = 1`) and Wanderer (`maxDistance = 2`).
- **Hoist** the 4-orthogonal and 4-diagonal offset tables (`_kOrthogonalOffsets`, `_kDiagonalOffsets`) to module scope so each Go personality can reuse them.
- **Extract** a shared `_pickFromScored` helper that does the "primary-score → Star-point weight → random survivor pick" tie-break, used by Diamond, Contact, and Greedy.
- **Engine tests**: rewrite the Hugger test group as a Diamond group with new assertions (picks diagonal-of-tengen, avoids orthogonal-adjacent, picks shared diagonal between two stones). Add a Wanderer test group (Manhattan-2 prefilter respected, empty board falls through, pass excluded).
- **Round-robin CLI**: token rename `chaotic` → `wanderer`, `gohugger` → `diamond` in `bin/go_personality_round_robin.dart`.

### Mobile

- **Slider reorder** per the new gate: `Wanderer → Star-point (default, position 1) → Contact → Diamond → Greedy`. The default keeps its strategy (`goStarPoints`) but its slider position moves from 2 → 1 because Diamond climbed into the second-strongest seat.
- **Labels**: "Chaotic" → "Wanderer", "Hugger" → "Diamond". New blurbs: "plays randomly near existing stones" and "plays in ponnuki-like diamond shapes."
- **Default-slider index**: `_kDefaultSliderIndex = 1` (was 2).
- **Persistence**: `_kUserFacingFallbacks` swaps `goHugger` → `goDiamond`. Legacy `goHugger` strings (from before the rename) silently coerce to `goStarPoints` (the Go-mode default) on read. `_kDefaultFallback` stays at `goStarPoints`.

### Gate result (round-robin, 50 games/dir, seed 42, 2000 games total)

```text
gogreedy     337  (84% win rate)
diamond      306  (77%)
gocontact    202  (51%)
gostar       119  (30%)
wanderer      34   (9%)
```

Pairwise strict ordering: Wanderer < Star-point < Contact < Diamond < Greedy. Slider matches observed strength.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `clone-brain`: the Go-mode subset of the **Cold-start fallback personalities** requirement is rewritten — `goHugger` becomes `goDiamond` with diagonal-minus-orthogonal scoring; `random` in Go mode gains the Manhattan-2 prefilter (Wanderer behaviour).
- `settings-screen`: the **Fallback personality picker** requirement is rewritten — labels updated ("Chaotic"→"Wanderer", "Hugger"→"Diamond"), slider order changed to match the new gate ranking, default moves from slider-position-2 to slider-position-1 (still `goStarPoints` strategy).

## Impact

- `packages/game_engine/lib/src/clone_brain.dart`
  - Enum: `goHugger` → `goDiamond`.
  - New constants: `_kOrthogonalOffsets`, `_kDiagonalOffsets`.
  - New helpers: `_goWandererMove`, `_pickByDiamondScore`, `_pickByOrthogonalNeighbour`, `_pickFromScored`. The renamed `_goDiamondMove` calls `_pickByDiamondScore`; `_goContactMove` calls `_pickByOrthogonalNeighbour`.
  - `_goNeighbourOfStoneCandidates(board)` → `_goCellsNearStones(board, maxDistance)` (parametric). Greedy's callsite passes `maxDistance: 1`.
  - In `_fallbackMove`, the `random` case detects `rules is GoRules` and routes to `_goWandererMove`.
- `packages/game_engine/test/clone_brain_test.dart` — Hugger group rewritten as Diamond; new Wanderer group; updated assertions.
- `packages/game_engine/bin/go_personality_round_robin.dart` — token map updated to `wanderer`, `diamond`.
- `apps/mobile/lib/src/screens/settings_screen.dart` — `_kSliderLevels` reordered, labels and blurbs updated, `_kDefaultSliderIndex = 1`.
- `apps/mobile/lib/src/db/database_service.dart` — `_kUserFacingFallbacks` swaps `goHugger` → `goDiamond`. Legacy-coercion docstring updated. Default stays `goStarPoints`.
- `apps/mobile/test/database_service_test.dart` — round-trip set includes `goDiamond`; legacy-coercion test exercises both `edgeFocus` and `goHugger`.
- `apps/mobile/test/game_notifier_test.dart` — `setFallback(goHugger)` → `setFallback(goDiamond)`.
- **No schema change.** Coercion happens at the persistence read layer.
- **Migration**: legacy users on Hugger (pre-rework, slider position 0) land on Star-point default after upgrade — their persisted `goHugger` string doesn't match any enum value, falls through to default. Users on Chaotic (pure-random) keep the `random` strategy, which now does Wanderer in Go mode. Star-point / Contact / Greedy users are unaffected.
