## Design

### Personality definitions (Go, 13×13)

All five personalities operate on a `Board` and a `List<int>` of legal placement moves (pass already filtered out by the caller; if `passMove` is the only legal move, the brain returns it without entering the fallback path). They return a single intersection-int `r * size + c`. Conventions: own colour is `+1`; the fallback fires when the clone is the side-to-move, so own-piece checks are always `board.get(r,c) == 1`.

#### 1. Chaotic — `FallbackStrategy.random`

Pick a uniformly random legal placement. Unchanged from today. Selectable for both CF and Go — the only cross-game personality.

#### 2. Star-point — `FallbackStrategy.goStarPoints` (NEW)

Static board-position weights, ignoring the opponent and even own stones. Score function:

```text
weight(r, c) =
  3   if r ∈ {3, 6, 9} AND c ∈ {3, 6, 9}      # the nine 13×13 hoshi (incl. tengen)
  2   if r ∈ {2, 3, 9, 10} OR c ∈ {2, 3, 9, 10}   # 3rd & 4th lines (territorial framework)
  1   if r == 0 OR r == 12 OR c == 0 OR c == 12 OR r == 6 OR c == 6  # 1st line + centre cross
  0   otherwise (interior 2nd-line and inner-cross-but-not-tengen cells)
```

Pick the legal placement with the highest weight; tie-break uniformly at random (using the brain's seeded `Random`). Plays "textbook openings" for the first ~10 moves, then drifts because the weights ignore everything but cell coordinates. The exact weight table is deliberately rough — we don't need a Go primer's worth of values; we need a recognisable shape.

#### 3. Hugger — `FallbackStrategy.goHugger` (NEW, default)

Score each legal placement by its count of 4-orthogonal-adjacent **friendly** (`+1`) stones (not diagonal — Go's connection notion is orthogonal). Pick max with a two-tier tie-break:

1. Star-point weight (§2 table) as secondary score.
2. Random among the survivors.

Empty board (no friendlies anywhere): the score is uniformly zero, so Star-point weight dominates → Hugger plays a star-point opener. No empty-board edge case to special-case in code; the tie-break pyramid handles it.

This is the default. Mirrors CF's "Stacker is default" pattern (default = middle of slider, recognisable shape-builder). Produces "thick, dumpling-shaped" play — bad pro-level Go, but coherent and recognisable to a beginner.

#### 4. Contact — `FallbackStrategy.goContact` (NEW)

Same shape as Hugger, but counting **enemy** (`-1`) 4-neighbours. Picks the move that touches the most opponent stones. Aggressive, in-your-face style. Tie-break: Star-point weight, then random.

Empty board / no enemy stones: score is uniformly zero, Star-point weight dominates → opens at a star point. The first response (after the player's first move) plays right next to the player's stone, which sells the personality immediately.

#### 5. Greedy — `FallbackStrategy.goGreedyArea` (NEW)

One-ply territory lookahead with a **diffusion-style prefilter** to keep cost tractable.

**Prefilter**: candidate cells = empty intersections that have at least one 4-orthogonal-adjacent stone (any colour). A 13×13 mid-game position typically has ~30–50 such cells; without the prefilter, Greedy would do up to 168 area-score evaluations per turn. With it, ~3× cheaper. The prefilter implicitly forbids opening new frameworks far from existing stones — Greedy is a "plays where the action is" personality, not a "founds new colonies" personality. This is acknowledged in the proposal and is the simplest way to keep cost predictable on a phone.

**Empty board**: prefilter returns the empty set. Falls through to Star-point (no candidates to evaluate, but Star-point still picks a sensible opener).

**Scoring**: for each candidate move:
1. `trial = rules.applyMove(board, move, +1)` — applies the placement *and* runs Go's capture rules; the resulting board is what `areaScore` will see.
2. `score = trial.ownArea − trial.opponentArea` where `(ownArea, opponentArea) = rules.areaScore(trial)` (Chinese-style territory: own stones + empty intersections surrounded only by own colour). The differential is what wins games.

Pick the candidate with the highest differential. Tie-break: Star-point weight (a placed stone in an emptier area scores the same as one in a contested area in early game; Star-point gives sensible bias), then random.

**Cost**: ~50 area-score calls × 13×13 board × O(N) flood fill ≈ tens of thousands of cell visits per turn. On modern phones this is well under one frame; even doubling the prefilter to 2-step neighbourhood would be fine. We start at 1-step.

### Engine API

Single switch in `CloneBrain._fallbackMove`. No new abstractions. Per the prime directive, four small private methods on `CloneBrain` (`_goHuggerMove`, `_goContactMove`, `_goGreedyAreaMove`, `_goStarPointMove`), plus a shared helper `_goStarPointWeight(int r, int c, int size)` and `_goNeighbourOfStoneCandidates(Board)`. All assume `rules is GoRules` and assert it; the CF-mode call paths never reach these cases by construction (the slider only offers Go values when `gameType == 'go'`).

```dart
enum FallbackStrategy {
  random,
  middleFocus,
  pileFocus,
  ownPileAdjacent,
  greedyConnect,
  greedyConnectDefense,
  // Go-mode personalities. Selectable only when rules is GoRules.
  goStarPoints,
  goHugger,
  goContact,
  goGreedyArea,
}
```

We do **not** split the enum into per-game enums or extract a `Personality` interface. Two games with disjoint personality sets is just below the threshold where abstraction pays off; the switch stays flat. If/when game #3 forces it, we extract then.

### UI: discrete slider (restored)

Flutter `Slider` with `divisions: 4`, value range 0–4. Mirror of the CF slider that shipped earlier. The slider value indexes into a fixed Go-mode list of `(strategy, name, blurb)` tuples:

```text
0 — Chaotic    — "plays anywhere legal."
1 — Star-point — "favours classic opening points."
2 — Hugger     — "extends its own shapes."          ← default
3 — Contact    — "plays right at your stones."
4 — Greedy     — "tries to maximise its territory."
```

Big name in display font, the one-line blurb below in body font. Live update as the user drags. Persists on `onChangeEnd` (no Save button — same pattern as CF).

The current Settings screen is a `StatelessWidget` with a static `Text`; this change converts it back to a `StatefulWidget` so the slider can hold transient drag state. (We *did* once go `StatelessWidget` to fix an `initState` crash; the slider's local state lives in the widget itself, not in `AppScope`, so the original crash doesn't recur.)

### Default flow

- New install: `loadFallback` returns `goHugger` (no row in `clone_config`).
- Existing install with stored `random` (the Go cutover's default): honoured.
- Existing install with stored CF-shaped values (`pileFocus`, `ownPileAdjacent`, `greedyConnect`, `greedyConnectDefense`, `middleFocus`, `edgeFocus`, etc.): silently mapped to `goHugger`. The CF cutover already coerced these to `random`, so realistically the only stored values in the wild after this change ships are `random` and the four new Go values.

### Benchmark validation gate (before ship)

The Go self-play benchmark machinery from `go-engine-foundation` is the basis. Add CLI tokens for the new personalities and run a round-robin:

```bash
dart run bin/go_personality_round_robin.dart 50 42  # 50 games per direction, seed 42
```

Round-robin pairs every Go personality against every other (10 pairings × 50 games × 2 alternation directions = 1000 games total). Output: aggregate-wins-per-personality.

**Pass criterion**: ranking from best to worst SHALL be `Greedy ≥ Contact ≥ Hugger ≥ Star-point ≥ Chaotic`, with at most one adjacent-position swap tolerated. If two-or-more swaps appear (e.g. Star-point beating Contact AND Hugger), revisit the personality before shipping. If Greedy isn't strictly strongest, that's a red flag — the prefilter or the area-score scoring may be buggy.

Bind the gate to the slider order: if the round-robin says, e.g., Hugger > Contact, swap their slider positions. Slider order should reflect observed strength, not paper-design strength. Default at slider position 2 (Hugger by current plan; whatever lands there after the swap, if any).

### Risks & decision points

1. **Greedy prefilter cuts off new-framework openings.** Acknowledged in the proposal. Mitigation: the empty-board fallthrough to Star-point handles the very-first-move case. A bot that "always plays where stones already are" is fine for a *fallback* — fallbacks are intentionally weak. *Decision*: ship 1-step prefilter; bump to 2-step only if device benchmark feels too slow or if Greedy gets stuck.
2. **Star-point weight table is ad-hoc.** No principled basis for the exact 0/1/2/3 values; just "vaguely matches Go opening theory". *Decision*: ship as-is; tune only if the round-robin shows Star-point ranked outside expectation. The whole point is to provide a static lookup; precision doesn't matter for a fallback.
3. **Default = Hugger overrides legacy `random`.** Existing players who deliberately picked `random` (Chaotic) on the Go cutover will keep that choice. Existing players whose stored value got coerced to `random` (CF-mode legacy values) will be coerced *again* to `goHugger`. *Decision*: acceptable — the Go cutover was a deliberately-quiet wipe with `random` as the placeholder; promoting them to `goHugger` is an upgrade, not a regression.
4. **Slider widget churn.** The Go cutover removed the slider; this change brings it back. Trivial code, but it does mean a third UI revision in a short window. *Decision*: take the hit; the static-Text was always documented as temporary.
5. **Greedy compute on low-end devices.** ~50 area-score evaluations per turn × ~169 cell visits each ≈ 8.5K cell visits per turn. Fine on a 2020-era phone; possibly noticeable on a 2017-era phone. *Decision*: don't pre-optimise; ship and measure. If a real device shows lag, drop the prefilter from "1-step" to "1-step but capped at K candidates" or memoise the empty-region flood fill across iterations.
6. **All-personalities-pass deadlock.** If a personality only ever picks `passMove` (it shouldn't, since pass is excluded from the candidate list before the fallback), and the opponent also passes, the game ends 0–0. The Go cutover already filters pass out of the brain's `legalMoves` unless the opponent just passed; we inherit that filter for free here. *Decision*: no extra logic needed; the brain layer already guards this.
