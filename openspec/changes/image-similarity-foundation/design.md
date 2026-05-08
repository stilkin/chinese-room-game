## Context

We're swapping out the matcher and the move selector simultaneously because they share an underlying representation. Today both use the diffused-bit-hash. After this change, both use the quantized diffused image. Doing them in lockstep keeps storage clean (one representation per row, not two during a transition).

The change is scoped to **Connect Four only**. The interfaces it introduces (`CandidateFilter`, `MoveScorer`) are game-agnostic, but their implementations and the design choices around quantization assume Connect Four's value range. Chess and Go are explicit non-goals.

The self-play benchmark added in `d1e69e7` is the success gate: the new pipeline must match or exceed the bit-hash baseline (~80% trainee win rate vs middle-focus coach over 200 games, two seeds) before we declare the change done.

## Resolved design questions

### 1. Why drop the bit-hash entirely instead of keeping it as a Stage-1 filter?

Past discussion proposed a **coarse-to-fine** pipeline: bit-hash + Hamming as a cheap broad filter, then raw-board Hamming as a tiebreaker. We considered this and rejected it for our scale.

- At low thousands of stored rows, single-pass L1 over Int8 vectors is microseconds. There is no performance pressure that justifies a two-stage pipeline.
- Two representations per row is more storage and more code for no measurable benefit at our scale.
- The two-stage pipeline mixes two distance metrics that measure different things (perceptual structure vs exact piece positions), making weight-tuning ambiguous.

If retrieval ever becomes a bottleneck (Go at 19×19 with hundreds of thousands of rows), we can add a coarse stage then. Until then, brute-force L1 is correct.

### 2. Why L1 and not L2 / SSIM / cosine?

L1 is the simplest interpretable distance over signed-byte images:

- Cheap (subtract, abs, accumulate — one branchless inner loop).
- Linear in cell-magnitude differences. A queen swap (under chess piece values) creates ~9 units of disagreement per affected cell; a pawn swap creates ~1. The metric scales with strategic importance directly. L2 amplifies large deviations quadratically — sometimes useful, often noisy.
- Already aligned with our quantized Int8 representation: `(a - b).abs()` over Int8 fits in 16-bit accumulators easily.
- Trivial to swap out later if the benchmark ever shows L2/SSIM wins by enough to justify the complexity.

SSIM is overkill for our cell counts and adds a windowing parameter. Cosine distance is built for high-dimensional sparse vectors; our images are dense and low-dimensional.

### 3. Why store the quantized diffused image, not the raw float map?

- Storage: 42 bytes vs 336 bytes per row (8× saving).
- Distance compute: Int8 L1 is ~4× faster than Float64 L1 (vectorizable on most CPUs even without SIMD intrinsics).
- Precision loss: for Connect Four, influence values stay in roughly `[-5, 5]` after 2 diffusion steps with attenuation 0.5; rounding to Int8 loses well under 1 unit per cell, dominated by the diffusion approximation itself. Negligible for retrieval ranking.

The bit-hash already discarded *far* more precision than Int8 quantization does and the system worked. Int8 is conservatively lossy.

### 4. Pre-filter: per-game, not universal.

The current pre-filter uses `totalMaterial ±2` and `materialBalance ±2`. For Connect Four this is the same as `ply ±2` (each move adds one piece, no captures). For chess this is a meaningful filter (captures change material; balance changes with trade quality). For Go it'd be a fairly weak filter (stones change slowly).

Rather than overload one filter to fit all games, we expose `CandidateFilter` as a `GameRules` member:

```dart
abstract class CandidateFilter {
  bool matches(GameState query, GameState candidate);
}

abstract class GameRules {
  CandidateFilter prefilter(GameState query);
  // ...
}
```

Connect Four returns a filter on `ply ±2`. Adaptive widening (the "double the window until ≥5 candidates" loop) stays in `searchSimilar` as a generic loop — it asks the filter to produce a wider variant on each iteration.

```dart
abstract class CandidateFilter {
  bool matches(GameState candidate);
  CandidateFilter widened();  // returns a more permissive filter for the next iteration
}
```

Connect Four's filter doubles its ply window each call to `widened()`. Other games can plug in their own widening strategy.

### 5. Move scoring: per-game, not universal.

Connect Four: a move is a column. The "resulting position" is the cell where gravity drops the piece — `(landing_row, col)`. Score = `heatmap[landing_row][col]`.

Chess (eventual): a move has a from-square, a to-square, and a piece type. Plausible scores: `heatmap[to] - heatmap[from]`, weighted by piece value, with capture bonuses. Different game, different scorer.

Rather than try to define a universal scoring function now, we abstract it:

```dart
abstract class MoveScorer {
  double scoreMove(int move, Board currentBoard, List<List<double>> heatmap);
}

abstract class GameRules {
  MoveScorer get moveScorer;
  // ...
}
```

`InfluenceOverlayStrategy` calls `rules.moveScorer.scoreMove(move, board, heatmap)` for each legal move and picks the highest. This pushes all game-specific move geometry into the scorer.

### 6. Multi-query retrieval: 4 queries, with move-untransform

Today's two-query split (Q_A flipped, Q_B unchanged) handles the winner-POV storage convention. We extend it to 4 to also exploit left/right symmetry — without re-introducing write-time mirror canonicalization (which had subtle correctness bugs and was removed in `winner-pov-foundation`).

Mirror at query time is much less invasive than mirror at write time:

```
Q_A         = flipPerspective(query)
Q_A_mirror  = mirror(flipPerspective(query))
Q_B         = query
Q_B_mirror  = mirror(query)
```

Each query produces candidates, each candidate carries:
- The candidate `GameState` (with its diffused image and `movePlayed`).
- An L1 distance.
- A **sign** (+1 for Q_A and Q_A_mirror, -1 for Q_B and Q_B_mirror).
- A **move-untransform** function (identity for non-mirror queries, `c → cols-1-c` for mirror queries on Connect Four).

When a candidate feeds the heatmap, its diffused image is mirrored (if the query was a mirror query) before being added — so the territory aligns with the *query's* coordinate frame. Its `movePlayed` value is also untransformed via the per-query function for narration purposes (the heatmap doesn't directly need movePlayed, but narration does).

The cross-side rows policy from `winner-pov-foundation` carries forward: from Q_A and Q_A_mirror we keep only `outcome=+1` rows; from Q_B and Q_B_mirror we keep only `outcome=-1` rows. The cross rows describe the opponent's behavior, not the bot's, and are ignored.

### 7. Heatmap aggregation

Single signed heatmap, board-shaped, accumulating contributions from all four query results:

```
weight = sign × (1 / (1 + movesToEnd)) × (1 / (1 + l1Distance))
heatmap += weight * (mirroredIfNeeded(candidate.diffusedImage))
```

After all candidates are summed in, each legal move is scored via `rules.moveScorer.scoreMove(move, currentBoard, heatmap)`. Highest score wins.

Sanity gate: if the highest score is `≤ 0`, route to fallback (the data points to a losing-flavoured choice). Same logic as today's net-weight ≤ 0 guard.

### 8. Schema migration

Schema v2 → v3, destructive. Same approach as winner-pov-foundation:

```sql
-- onUpgrade if oldVersion < 3:
DROP TABLE IF EXISTS game_states;
CREATE TABLE game_states (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id TEXT NOT NULL,
  ply INTEGER NOT NULL,
  move_played INTEGER NOT NULL,
  diffused_image BLOB NOT NULL,        -- was diffused_hash
  board BLOB NOT NULL,
  rows INTEGER NOT NULL,
  cols INTEGER NOT NULL,
  total_material INTEGER NOT NULL,
  material_balance INTEGER NOT NULL,
  outcome INTEGER,
  moves_to_end INTEGER
);
CREATE INDEX idx_game_states_game_id ON game_states(game_id);
CREATE INDEX idx_game_states_filter ON game_states(total_material, material_balance);
DELETE FROM games;
```

`total_material` and `material_balance` indices stay — useful for future per-game filters that want them, and the cost is negligible.

`onCreate` for fresh installs uses the v3 schema directly.

### 9. Narration

Stays mostly intact. The brain still reports a "best candidate" for narration. The framework (`DecisionContext.fuzzyMatch`, `multipleCandidates`, `fallbackUsed`, `allLosing`) doesn't reference Hamming — it speaks in match counts and game ids — so it carries forward unchanged.

One subtle update: the "best candidate" framing under the heatmap model is fuzzier (the chosen move is informed by all candidates summed into a heatmap, not by one specific top-ranked candidate). For narration purposes, we report the lowest-L1-distance candidate that contributed positively to the chosen move's heatmap value. Approximation, but good enough for one-line narration.

## Engine API after refactor (target end state)

**Lives:**
- `Board`, `flipPerspective`, `mirrorBoard` — primitives.
- `DiffusionKernel`, `ConnectFourDiffusion`, `quantizeInfluenceMap` — perceptual matching foundation.
- `GameRules`, `ConnectFourRules` — game-specific. Now exposes `CandidateFilter` and `MoveScorer`.
- `CandidateFilter` (with `widened()`), `ConnectFourFilter`.
- `MoveScorer`, `ConnectFourMoveScorer`.
- `GameLog`, `GameLog.replaceStatesForGame` — in-memory store.
- `searchSimilar(queryDiffusedImage, prefilter, candidates)` — L1-ranked.
- `MoveSelectionStrategy`, `InfluenceOverlayStrategy` — accumulates heatmap, scores legal moves.
- `CloneBrain` — orchestrates four-query retrieval, heatmap accumulation, move scoring.
- `invertState(GameState, DiffusionKernel)` — same role; recomputes the diffused image instead of the bit-hash.

**Goes:**
- `influenceMapToBitHash` (in `diffusion.dart`).
- `GameState.diffusedHash` (renamed and retyped).
- `VoteByMoveStrategy`.
- `searchSimilar`'s `queryDiffusedHash` parameter, replaced by `queryDiffusedImage`.

## Performance budget

For Connect Four (42 cells, ~thousands of stored rows):

- One L1 distance pass = 42 subtractions, abs, accumulate ≈ ~50ns on commodity hardware.
- Four queries × ~1000 candidates surviving the prefilter = ~200μs of distance compute per move.
- Heatmap accumulation: 4 queries × top ~50 candidates × 42 cells = ~8400 multiply-adds ≈ ~50μs.
- Move scoring: 7 legal moves × heatmap lookup = ~7 lookups, ~1μs.

Total per-move budget: well under a millisecond. Same order as today's bit-hash matcher.

For chess (64 cells) and Go (361 cells) the per-row distance grows linearly; nothing else changes. Go at 50k rows × 4 queries × 361 cells = ~70M ops per move, still well under a second. We don't need ANN structures for any of the planned games.

## Risks

1. **Behavioral regression vs bit-hash baseline.** Mitigation: self-play benchmark gates the change. If the new pipeline doesn't match the baseline, we investigate before merging — possibilities include quantization being too lossy, the heatmap aggregation washing out signal that vote-by-column captured better, or the four-query retrieval over-broadening the candidate set.
2. **Mirror-untransform bugs.** Possibly the trickiest bit — getting the mirror direction right for both the candidate's diffused image *and* its `movePlayed`. Mitigation: explicit unit tests that synthesize a known-mirror-of-known game and verify the heatmap aligns with the query's coordinate frame.
3. **Heatmap normalization.** Net weight ≤ 0 → fallback is the same guard as today. But heatmap values are a different scale than vote sums; the threshold may need tuning. Mitigation: keep the threshold at 0 (sign-based, scale-free) and trust the benchmark to catch over- or under-triggering.
4. **Quantization saturation in chess.** Influence values for chess (king radiates 20, queen 9, attenuated over 2 steps) may overflow Int8. Out of scope for this change but called out — when chess arrives, that game's `GameRules` will need to specify a quantization scale, or we introduce a Float32 variant gated per-game.

## Out of scope

- Chess, Go, Othello.
- Coarse-to-fine retrieval (Stage 1 perceptual hash → Stage 2 raw board).
- Approximate-nearest-neighbor structures (HNSW, k-d trees, locality-sensitive hashing).
- Real-valued influence map storage (Float32 / Float64). We're committing to Int8 for Connect Four.
- Per-game distance metric configuration. L1 is the only metric.
- Heatmap visualization / debug overlay. Useful future work; not load-bearing.
