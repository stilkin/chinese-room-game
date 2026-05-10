## Why

The Go cutover (`go-mobile-app`) shipped with a stub fallback set: only `random` (Chaotic) is exposed via Settings. The slider widget was even replaced with a static label since there's only one entry to show. That was a deliberate "park it" decision so the Go cutover could ship without bikeshedding the personality ladder, but the cold-start experience now is "your clone plays uniformly random Go" — which is exactly the disengaging first impression the CF personality slider was originally introduced to fix.

This change introduces a **Go-shaped personality ladder** in the same spirit as the CF version, restores the Settings slider as a real `Slider` widget, and picks a default that gives the cold-start clone a recognisable Go-ish feel without making it feel like a "real" bot. The personalities all read only the current `Board`; none of them do tree search, lookahead beyond one ply, or use the diffusion kernel. Per the prime directive, simplicity over cleverness.

A secondary problem the change solves: the engine smoke benchmark for `go-engine-foundation` showed games ending via early double-pass when the heatmap signal is weak (the chosen move's score falls to the pass-floor of `0.01`, no offence is found, both sides pass into a 0–0 area score). With a stronger fallback as the *default*, more cold-start games will reach a real territory outcome instead of a dud double-pass.

## What Changes

- **Add** four new engine fallback strategies (Go-specific by construction):
  - `goStarPoints` — labelled **"Star-point"**: per-cell static weight table (3rd/4th line ≫ 2nd line ≫ tengen ≫ rest); score each legal placement by its weight, pick max with random tie-break. Empty-board friendly (plays a 4-4 or 3-3 like a Go textbook).
  - `goHugger` — labelled **"Hugger"**: score each legal placement by its count of 4-adjacent friendly stones; pick max, tie-break by Star-point weight, then random. Empty board → plays Star-point (no friendlies to hug).
  - `goContact` — labelled **"Contact"**: same shape as Hugger but counting **enemy** 4-neighbours; produces an aggressive, in-your-face style. Empty board → plays Star-point.
  - `goGreedyArea` — labelled **"Greedy"**: one-ply lookahead over a *prefiltered* candidate set (empty cells within Manhattan distance 1 of any stone). For each candidate, apply, run `GoRules.areaScore` on the resulting board, pick the move that maximises (own_area − opponent_area). Empty board (no stones, so prefilter is empty) → plays Star-point. Tie-break by Star-point weight, then random.
- **Restore** the Settings slider as a real `Slider(divisions: 4, min: 0, max: 4)` widget, replacing the static one-entry `Text` block from the Go cutover.
- **Rebrand** the existing CF-shaped fallback values in the engine: kept for `ConnectFourRules` regression coverage but **never** surfaced via the Go-mode slider. The user-facing fallback set for `gameType == 'go'` is exactly the five Go-mode values.
- **Default**: **Hugger**. Mirrors the CF pattern (default = middle of slider, recognisable shape-builder). It responds to its own stones, produces coherent shapes, and isn't strong enough to feel like a "real bot" on the first impression.
- **Migrate** persisted config: any stored value not in the Go user-facing set (including legacy `pileFocus`, `ownPileAdjacent`, `greedyConnect`, `greedyConnectDefense`, the prior CF defaults) is silently mapped to `goHugger` on read. (Already mostly handled by the Go cutover's coercion to `random`; this change tightens the default to `goHugger`.)
- **Validate ordering via benchmark** before ship: round-robin among the five Go personalities. Expected ordering (passivity → engagement / strength): `Chaotic ≤ Star-point ≤ Hugger ≤ Contact ≤ Greedy`. If observed strength contradicts the expected ladder by more than one position, swap slider positions to match (precedent: the CF round-robin swapped Builder and Stacker).

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `clone-brain`: the **Cold-start fallback personalities** requirement gains four Go-mode strategies. The CF strategies survive in the enum but are explicitly documented as never surfaced for `gameType == 'go'`.
- `settings-screen`: the **Fallback personality picker** requirement is rewritten. The static one-line `Text` from the Go cutover is replaced with a 5-step slider. The default changes from `random` (Chaotic) to `goHugger` (Hugger).

## Impact

- `packages/game_engine/lib/src/clone_brain.dart` — `FallbackStrategy` enum gains four new values: `goStarPoints`, `goHugger`, `goContact`, `goGreedyArea`. `_fallbackMove` switch grows four new cases. New private helpers: `_goStarPointWeight(int r, int c, int size)`, `_goHuggerMove`, `_goContactMove`, `_goGreedyAreaMove`, `_goNeighbourOfStoneCandidates(Board)`. The Go-specific helpers assert the underlying `rules is GoRules` for clarity.
- `packages/game_engine/lib/src/games/go.dart` — public API of `GoRules.areaScore(Board)` is already exposed (used by the running tally). No changes here unless an `intersect(...)` helper is needed for the prefilter; even that lives in `clone_brain.dart` since it's fallback-internal.
- `packages/game_engine/test/clone_brain_test.dart` — new unit tests: empty-board behaviour for each Go fallback, Hugger picks correct neighbour, Contact picks correct enemy-neighbour, Greedy prefilter excludes far-from-stones cells, Greedy picks territory-maximising move on a constructed mid-game board.
- `packages/game_engine/bin/go_self_play_benchmark.dart` *(or extend the existing one)* — accepts the new tokens (`gostar`, `gohugger`, `gocontact`, `gogreedy`) and runs the round-robin gate. If it doesn't already have a Go mode, add one in this change.
- `apps/mobile/lib/src/db/database_service.dart` — `_kUserFacingFallbacks` becomes `{random, goStarPoints, goHugger, goContact, goGreedyArea}`. `_kDefaultFallback` becomes `goHugger`. `loadFallback`'s coercion logic already handles unknown values gracefully.
- `apps/mobile/lib/src/screens/settings_screen.dart` — restored to a `StatefulWidget` with a `Slider(divisions: 4)` + live-updating name/blurb text, mirroring the CF pattern. `_kSliderLevels` becomes the five Go-mode entries; `_kDefaultSliderIndex = 2` (Hugger).
- `apps/mobile/lib/src/state/game_notifier.dart` — no code change required. `main.dart` already bootstraps the brain via `db.loadFallback()`; the new default flows through automatically.
- `apps/mobile/test/database_service_test.dart` — round-trip tests for the four new values; legacy-mapping test (`pileFocus` → `goHugger`); default-on-empty is `goHugger`.
- `apps/mobile/test/game_notifier_test.dart` — minor: any test asserting the literal default fallback updates from `random` to `goHugger`. Test scenarios using `random` for "stay-out-of-the-way" determinism are left as-is (random is still a user-facing value).
- **Storage**: no schema change. `clone_config` value column already stores arbitrary text.
- **Migration**: non-destructive. Existing user choice is honoured if it's still valid (only `random` carries over from the Go cutover); legacy CF values silently become `goHugger`.
- **Behavioural**: cold-start games feel more deliberate. The strongest fallback (Greedy) is recognisably stronger than the weakest (Chaotic) but still beatable and clearly *not* minimax — the clone-as-shadow gimmick stays intact.
