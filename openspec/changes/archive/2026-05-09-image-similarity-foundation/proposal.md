## Why

The current matcher uses a **diffused-bit-hash + Hamming distance** signature: each board's diffused influence map is thresholded to one bit per cell ("is this cell's influence positive?"), and similarity is the popcount of XOR between two such hashes. This was deliberately chosen for compactness and CPU cheapness when the project's data scale was uncertain.

Now we know the scale: low thousands of stored states for Connect Four, well within real-valued image-distance budgets. The bit-hash threshold throws away two real signals:

1. **Magnitude.** A barely-positive cell (one piece three squares away) hashes the same as a heavily-contested cell. The diffused map's *gradient* — the very thing diffusion was designed to produce — is collapsed to a single bit.
2. **Pos/zero/neg distinction.** Empty wasteland and opponent territory both hash to `0`. The bot can't distinguish "nobody cares about this cell" from "the opponent dominates it."

This matters more than it sounds, because the project has been carrying piece-value spacing (chess: 1/3/3/5/9/20) on the assumption that "losing a queen creates a much larger pixel intensity change than losing a pawn." Under the bit-hash that's *only true during diffusion* — the spacing gets re-binarized into the same one-bit-per-cell representation before matching, so a queen swap and a pawn swap can produce identical bit-hashes. Switching to a real-valued distance metric makes the spacing argument actually pay off.

In the same direction: per-column voting collapses spatially-rich candidate evidence into one number per legal column. The candidates' diffused maps carry *where on the board the winning trajectory was concentrated* — that signal is also discarded today.

This change moves both halves of the pipeline up a level of expressiveness:

- **Retrieval**: store the quantized diffused image (Int8 per cell) per row; rank candidates by **L1 distance** over those images. No bit-hash, no Hamming.
- **Move selection**: graduate from `VoteByMoveStrategy` (sum weights per move column) to `InfluenceOverlayStrategy` (sum weighted candidate diffused maps into a single signed heatmap, then look up each legal move's resulting position in that heatmap, pick the highest).

Both pieces have always been on the project's roadmap — `InfluenceOverlayStrategy` is a stub class today, with a spec requirement already written — and PROJECT.md frames boards as "tiny grayscale images" in anticipation of this exact direction. We are finally landing the design the project has been written around.

## What Changes

### Matcher

- **Replace** `GameState.diffusedHash` (`List<int>` packed bit-hash) with `GameState.diffusedImage` (`Int8List`, one signed byte per board cell). Quantization: `clamp(round(influence_value), -128, 127)`. For Connect Four's piece values of ±1 with 2 diffusion steps at 0.5 attenuation, influence values stay comfortably inside Int8 range; no scale factor needed. Documented as a CF assumption; chess will need a per-game scale.
- **Replace** `searchSimilar`'s Hamming distance with **L1 distance** over the quantized diffused images: `sum(|a[i] - b[i]|)`.
- **Add** a per-game `CandidateFilter` that decides which stored rows pass the pre-filter. Connect Four's filter uses ply-count window (`±2`, doubling on insufficient candidates). The current `totalMaterial`/`materialBalance` window stays available but is now just one possible filter implementation, not the universal one.
- **Drop** the diffused-bit-hash entirely. `influenceMapToBitHash` is removed. The diffusion kernel still produces a real-valued influence map; we now quantize it to Int8 and store that instead of the bit-hash.

### Move selection

- **Replace** `VoteByMoveStrategy` (sum weights per move column) with `InfluenceOverlayStrategy` (already specced and stubbed). It accumulates each candidate's quantized diffused map into a single board-shaped `Float64List` heatmap, scaled by the candidate's signed weight, then asks a per-game `MoveScorer` to score each legal move against that heatmap. Highest score wins.
- **Add** a per-game `MoveScorer` interface. Connect Four's implementation looks up the heatmap value at the cell where a piece would land in the chosen column (gravity-aware).
- The "all-losing" guard (post-vote net weight ≤ 0 → fallback) is preserved: if the highest-scoring legal move has net heatmap value ≤ 0, route to the fallback strategy.

### Multi-query retrieval

- Today's brain runs two queries (winner-POV split: `flipPerspective(query)` and `query` unchanged). With image-distance retrieval, **add mirror queries** for left/right symmetry. Total: **four queries per turn**:
  - `Q_A` = `flipPerspective(query)` — bot-won candidates (positive weight)
  - `Q_A_mirror` = `mirror(flipPerspective(query))` — same, mirrored
  - `Q_B` = `query` unchanged — player-won candidates (negative weight)
  - `Q_B_mirror` = `mirror(query)` — same, mirrored
- Mirror queries require a **move-untransform** when their candidates feed the heatmap: a candidate matched via the mirror query has its `movePlayed` value mirrored before its diffused map is added to the heatmap (so territories and moves both align with the query's coordinate system). Sign-flip transforms don't change `movePlayed`; mirror does. Mirror for Connect Four: `c → cols - 1 - c`.
- The **two-query** requirement in `canonicalization/spec.md` upgrades to **four-query** (two perspectives × two mirror states).

### Storage

- Schema bump 2 → 3. Destructive migration: drop `game_states`, recreate with `diffused_image BLOB` replacing `diffused_hash BLOB`. Acceptable per the precedent set by `winner-pov-foundation` — MVP hasn't shipped widely; old bit-hash data isn't comparable under the new metric anyway.
- Storage cost per row goes from 8 bytes (one packed `Int64` for 42 bits) to 42 bytes (one `Int8` per cell). Negligible.

### Engine surface

- `searchSimilar` signature changes: takes `queryDiffusedImage: Int8List`, `prefilter: CandidateFilter`, returns `List<SimilarityResult>` ranked by L1 distance.
- `CloneBrain.selectMove` rewrites to: 4 queries → merge candidates → accumulate signed heatmap → ask `rules.moveScorer` for the best legal move → fallback if net score ≤ 0.
- `GameRules` gains `CandidateFilter prefilter(GameState query)` and `MoveScorer get moveScorer`.
- `invertState` updates to recompute the diffused image (not the bit-hash) on the flipped board.
- The existing `flipPerspective(Board)` stays. Add a new `mirrorBoard(Board)` helper.

## Capabilities

### New Capabilities

(none — `InfluenceOverlayStrategy` exists in spec; this is its first implementation)

### Modified Capabilities

- `similarity-search`: full rewrite. Bit-hash + Hamming → quantized image + L1. Pre-filter becomes per-game.
- `move-selection`: `VoteByMoveStrategy` requirement removed; `InfluenceOverlayStrategy` requirement promoted to the default and made concrete.
- `clone-brain`: decision pipeline updates from two-query to four-query; vote step becomes heatmap accumulation; per-game `MoveScorer` is invoked.
- `canonicalization`: two-query requirement upgrades to four-query (mirror added). `invertState` operates on `diffusedImage`, not `diffusedHash`.
- `game-persistence`: schema v3 (column rename `diffused_hash` → `diffused_image`, type stays BLOB but content is per-cell quantized).

## Impact

- `packages/game_engine/lib/src/game_state.dart` — `diffusedHash` → `diffusedImage` (Int8List). Field rename, type change.
- `packages/game_engine/lib/src/diffusion.dart` — `influenceMapToBitHash` deleted. Add `quantizeInfluenceMap(List<List<double>>) → Int8List` helper.
- `packages/game_engine/lib/src/canonicalize.dart` — `invertState` recomputes the diffused image instead of the bit-hash. Add `mirrorBoard(Board)` helper. (`flipPerspective` unchanged.)
- `packages/game_engine/lib/src/similarity.dart` — full rewrite. New `l1Distance(Int8List, Int8List) → int`. `searchSimilar` takes `queryDiffusedImage: Int8List`, `prefilter: CandidateFilter`, ranks by L1. `CandidateFilter` interface added here (or under a new file — see design.md).
- `packages/game_engine/lib/src/game_rules.dart` — adds `CandidateFilter prefilter(GameState query)` and `MoveScorer get moveScorer` abstract members.
- `packages/game_engine/lib/src/games/connect_four.dart` — implements both: `ConnectFourFilter` (ply-count window) and `ConnectFourMoveScorer` (gravity-aware landing-cell lookup).
- `packages/game_engine/lib/src/move_selection.dart` — drop `VoteByMoveStrategy`. `InfluenceOverlayStrategy` becomes a concrete class with `selectMove` taking a heatmap and a `MoveScorer`. Add `MoveScorer` interface here.
- `packages/game_engine/lib/src/clone_brain.dart` — `selectMove` rewrites to four-query + heatmap accumulation. Helper `_searchOnce(query, mirror, sign, candidates)` runs one of the four queries and returns weighted results with the appropriate move-untransform applied. `_buildNarration` simplified — no Hamming-based framing.
- `apps/mobile/lib/src/db/database_service.dart` — schema bump 2 → 3. Destructive migration. `_gameStateColumns` and `_rowToGameState` updated to read/write `diffused_image` blob.
- `apps/mobile/lib/src/state/game_notifier.dart` — minimal: depends only on engine API, which mostly stays shape-compatible.
- Tests: `similarity_test.dart`, `behavioral_test.dart`, `database_service_test.dart`, `move_selection_test.dart` all churn. New tests for `CandidateFilter`, `MoveScorer`, heatmap accumulation.
- **Storage cost per row**: ~+34 bytes (8 → 42 bytes for the diffused image blob, plus a few bytes column metadata). At 1000 stored rows: ~34 KB. Trivially fine.
- **Migration**: destructive — `game_states` wiped on bump from schema v2 to v3. The `games` table is also cleared so games-played counter resets. Same precedent as `winner-pov-foundation`.
- **Behavioral**: per the self-play benchmark (200 games, middle-focus coach, two seeds), the current bit-hash + vote system reaches ~80% trainee win rate. The success criterion for this change is *the new pipeline matches or exceeds the bit-hash baseline on the same benchmark*. If it doesn't, we have evidence that bit-hash-level granularity was sufficient and we should reconsider before chess/go arrive — that's the whole reason we built the benchmark first.
