## Design

### Personality definitions (Connect Four)

All five personalities operate on a `Board` and a list of legal columns, return a single column. Conventions: `mid = cols ~/ 2` (column 3 on a 7-wide board); "own" colour means `+1` on the board, since the clone is always the side-to-move when the fallback fires.

#### 1. Chaotic — `FallbackStrategy.random`

Pick a uniformly random legal column. Unchanged from today.

#### 2. Stacker — `FallbackStrategy.pileFocus` (existing)

For each legal column, count non-empty cells (any colour). Pick the column with the highest count. Tie-break: closest to `mid`. Unchanged from today; only the user-facing label changes.

#### 3. Builder — `FallbackStrategy.ownPileAdjacent` (NEW)

Goal: build *your own* structure rather than just stacking.

- Find the column `c*` with the tallest stack of *own* (+1) pieces. If multiple columns are tied, pick the one closest to `mid`.
- If `c*` has zero own pieces (e.g. very early game, opponent has been alternating), fall back to `mid`.
- Candidate adjacent columns: `c* - 1` and `c* + 1`. Pick the one closest to `mid`. If both are equidistant from `mid`, pick one uniformly at random (mirror-symmetric, so the choice has no expected effect on benchmark outcomes; randomness avoids hard-coding a side bias).
- If the chosen adjacent column is full or off-board, try the other adjacent column. If both are unplayable, fall back to `mid`. If `mid` is unplayable, pick the legal column closest to `mid`.

#### 4. Connector — `FallbackStrategy.greedyConnect` (NEW)

One-ply offensive lookahead.

- For each legal column `c`:
  - Determine the row `r` where a dropped own piece would land (Connect Four gravity).
  - Compute the longest contiguous run of own pieces (treating the new piece as `+1`) through `(r, c)` along each of four axes: horizontal, vertical, diagonal-NE, diagonal-NW. Take the maximum across the four axes — this is the column's score.
- Pick the column with the highest score. Tie-break: closest to `mid`.

A length-4 run is a winning move; the personality plays it because it's the local maximum. We don't add explicit win-detection logic — it falls out of the score function for free.

#### 5. Sentinel — `FallbackStrategy.greedyConnectDefense` (NEW)

Connector + one-step defensive block.

- For each legal column `c`, simulate the *opponent* dropping a `-1` piece at `(r, c)`. Compute the longest opponent run through `(r, c)` (same scoring as Connector but for `-1`). If the score is `>= 4`, mark `c` as a "block-here-or-lose" column.
- If at least one such column exists, pick the one closest to `mid` (we can only block one; the rest are unblockable forced losses, but blocking the most central is the best heuristic for the spirit of the game).
- Otherwise, run Connector logic.

We deliberately do **not** block 3-in-a-rows that aren't yet winning. That edges into "actually trying to win" territory and breaks the "weak heuristic personality" framing.

### Engine API

Single switch in `CloneBrain._fallbackMove`. No new abstractions; per the prime directive, three small private methods on `CloneBrain` (`_builderMove`, `_connectorMove`, `_sentinelMove`) feed off the existing `Board` API. If/when game #2 forces a generic personality framework, we extract then.

```dart
enum FallbackStrategy {
  random,
  middleFocus,           // benchmark-only; never set via UI
  pileFocus,             // user-facing label "Stacker"
  ownPileAdjacent,       // user-facing label "Builder" (default)
  greedyConnect,         // user-facing label "Connector"
  greedyConnectDefense,  // user-facing label "Sentinel"
}
```

The `edgeFocus` value is **removed** — not deprecated. Removing it forces every call site (including the benchmark CLI) to update; any legacy persisted `edgeFocus` string is handled at the `loadFallback` layer (mapped to `pileFocus`, the same default new installs get).

### UI: discrete slider

Flutter `Slider` with `divisions: 4`, value range 0–4. The slider value indexes into a fixed list of `(strategy, name, blurb)` tuples, in the canonical order:

```text
0 — Chaotic   — "plays anywhere. no plan."
1 — Builder   — "builds next to its own pieces."
2 — Stacker   — "stacks the tallest pile."        ← default
3 — Connector — "plays for longer chains."
4 — Sentinel  — "plays for chains. blocks losses."
```

The original ordering put Builder at position 2 as the default, but the head-to-head round-robin gate (see "Benchmark validation gate" below) showed Stacker beating Builder on Connect Four — Stacker tracks the centre column (canonical-best opening) while Builder deliberately moves *away* from centre. Slider positions 2 and 3 were swapped to match observed strength, and the default moved to Stacker so the cold-start clone is at least mid-strength.

Big name above the slider in display font (Press Start 2P), the one-line blurb below in body font (VT323). Live update as the user drags. Persists on slider release (no separate Save button — same pattern as the current radio).

### Default flow

- New install: `loadFallback` returns `pileFocus` (Stacker — no row in `clone_config`).
- Existing install with stored `random`/`pileFocus`/`ownPileAdjacent`/`greedyConnect`/`greedyConnectDefense`: that exact value is honoured.
- Existing install with stored `edgeFocus` or `middleFocus` (or any other non-user-facing value): silently mapped to `pileFocus`. No upgrade UI; user discovers the new slider on next visit to settings.

### Benchmark validation gate (before ship)

The self-play benchmark already exists. Add CLI tokens for the three new personalities and use it for a sanity round-robin:

```bash
# trainee always uses the case-based brain;
# coach uses one of the user-facing personalities. 200 games, two seeds.
dart run bin/self_play_benchmark.dart 200 42 chaotic
dart run bin/self_play_benchmark.dart 200 42 stacker
dart run bin/self_play_benchmark.dart 200 42 builder
dart run bin/self_play_benchmark.dart 200 42 connector
dart run bin/self_play_benchmark.dart 200 42 sentinel
```

Then a head-to-head round-robin of the four user-facing personalities (no learning, both sides use the same kind of bot but with different fallback strategies, ~50 games each pairing, both seeds).

**Pass criterion**: in the round-robin, ranking from best to worst SHALL be Sentinel ≥ Connector ≥ Builder ≥ Stacker ≥ Chaotic. Strict-> is preferred but ties between adjacent personalities are tolerable. If the ordering inverts (e.g. Builder beats Connector), revisit the personality before shipping.

### Risks & decision points

1. **Builder degeneracy.** With no own pieces (true at the very first move of the very first game ever), Builder must default somewhere. Centre column is the canonical choice. *Decision*: hard-code `mid` as the empty-board choice; documented behaviour, single line of code.
2. **Sentinel giving the game away early.** A "blocks all 4-in-a-rows" personality played as the cold-start fallback for the first ~10 games risks the player feeling like they're playing a normal bot, not their nascent clone. The whole product gimmick relies on the clone *learning from you*. *Decision*: ship it, but the slider default is **Stacker** (level 2/4 after the round-robin reorder), not Sentinel — the player has to opt into the strongest personality. Prevents accidental over-strong cold-start.
3. **Slider ordering wrong.** If Connector loses to Stacker in head-to-head, the slider's "complexity" axis lies. *Decision*: benchmark gate before ship (above). If a bot doesn't earn its slider position, fix or reorder.
4. **No abstraction for "personality" yet.** Three new private methods on `CloneBrain` is a slight smell, but extracting a `Personality` interface now would be premature given Connect Four is the only game. *Decision*: defer extraction until game #2 forces it. (See Build Phases section of CLAUDE.md.)

5. **Builder randomness in the equidistant case.** The two adjacent columns of `c*` may both be equidistant from `mid` when `c*` is the centre column itself. Picking randomly between them avoids hard-coded side bias but introduces non-determinism into the fallback path. *Decision*: acceptable — the existing `random` fallback is already non-deterministic, and the parent `CloneBrain` already carries a seeded `Random` we can reuse, so reproducible benchmark runs remain possible by passing a fixed seed.
