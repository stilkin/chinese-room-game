## 1. Engine: representation swap (bit-hash → quantized image)

- [x] 1.1 In `packages/game_engine/lib/src/diffusion.dart`, delete `influenceMapToBitHash`. Add `quantizeInfluenceMap(List<List<double>>) → Int8List`: row-major flatten, `clamp(round(v), -128, 127)` per cell.
- [x] 1.2 In `packages/game_engine/lib/src/game_state.dart`, replace `final List<int> diffusedHash` with `final Int8List diffusedImage`. Update constructor, exports.
- [x] 1.3 In `packages/game_engine/lib/src/clone_brain.dart`, update `createState` to populate `diffusedImage` via `quantizeInfluenceMap(rules.diffusionKernel.diffuse(board))`.
- [x] 1.4 In `packages/game_engine/lib/src/canonicalize.dart`, update `invertState` to recompute the diffused image (not bit-hash) on the flipped board. Add `Board mirrorBoard(Board)` helper (left/right column flip).
- [x] 1.5 Engine analyzer clean after representation swap. Tests will be churned in step 7.

## 2. Engine: L1 distance + per-game pre-filter

- [x] 2.1 In `packages/game_engine/lib/src/similarity.dart`, replace `hammingDistance` with `int l1Distance(Int8List a, Int8List b)`: sum of `(a[i] - b[i]).abs()`.
- [x] 2.2 Define `abstract class CandidateFilter { bool matches(GameState candidate); CandidateFilter widened(); }` in `similarity.dart`.
- [x] 2.3 Rewrite `searchSimilar` to take `(queryDiffusedImage: Int8List, prefilter: CandidateFilter, candidates: List<GameState>, {minCandidates = 5, maxWidens = 8})`. Loop: filter candidates by `prefilter.matches`, if too few then `prefilter = prefilter.widened()` and retry; up to `maxWidens` rounds, then fall through to all candidates. Compute L1 distance for the survivors, sort ascending.
- [x] 2.4 `SimilarityResult` field `int distance` stays — semantically just changes from Hamming to L1.

## 3. Engine: GameRules surface for filter + scorer

- [x] 3.1 In `packages/game_engine/lib/src/game_rules.dart`, add abstract members: `CandidateFilter prefilter(GameState query)`, `MoveScorer get moveScorer`.
- [x] 3.2 In `packages/game_engine/lib/src/move_selection.dart`, define `abstract class MoveScorer { double scoreMove(int move, Board currentBoard, List<List<double>> heatmap); }`.
- [x] 3.3 In `packages/game_engine/lib/src/games/connect_four.dart`, implement `ConnectFourFilter`: stores a query ply, doubles the window on `widened()`, accepts candidates whose ply differs from query ply by at most the window. Implement `ConnectFourMoveScorer`: for a column move, compute the gravity landing row given `currentBoard`, return `heatmap[landing_row][col]`. Wire both up via `prefilter` and `moveScorer` getters.
- [x] 3.4 Also expose them in `game_engine.dart` if needed (probably already covered by `move_selection.dart` and `similarity.dart` exports).

## 4. Engine: InfluenceOverlayStrategy implementation

- [x] 4.1 In `packages/game_engine/lib/src/move_selection.dart`, replace the abstract `InfluenceOverlayStrategy` stub with a concrete class. Constructor takes a `MoveScorer`.
- [x] 4.2 `selectMove(List<WeightedCandidate>, List<int> legalMoves, Board currentBoard) → int?`: build a `List<List<double>>` heatmap shaped like the board, accumulate `weight × dequantize(candidate.diffusedImage)` per cell across all candidates. (Dequantize: `Int8` → `double` straight cast, since we didn't use a scale factor.) For each legal move, call `scorer.scoreMove`. Return the move with the highest score; null if no candidates or no legal moves.
- [x] 4.3 Delete `VoteByMoveStrategy`. Update `ConnectFourRules.moveSelectionStrategy` to return `InfluenceOverlayStrategy(ConnectFourMoveScorer())`.

## 5. Engine: four-query retrieval + heatmap pipeline in CloneBrain

- [x] 5.1 In `packages/game_engine/lib/src/clone_brain.dart`, rewrite `selectMove(currentBoard, side)`:
  - Get `legal` and `completed` (states with outcome). If `completed.isEmpty` → fallback.
  - Run four queries via a helper `_queryOnce(Board queryBoard, {required int sign, required int Function(int) untransformMove, required Int8List Function(Int8List) untransformImage, required int requiredOutcome})`. Each returns `List<WeightedCandidate>`:
    - Diffuse query board, quantize.
    - Build prefilter from a synthetic query `GameState`.
    - Call `searchSimilar`.
    - Filter results to `outcome == requiredOutcome`.
    - For each result, build a `WeightedCandidate` with `weight = (1/(1+movesToEnd)) × (1/(1+l1Distance))` and an "image to add to heatmap" = `untransformImage(state.diffusedImage)`. (Sign on the weight was removed during implementation — the candidate image's natural sign carries the win/loss lesson.)
    - The four invocations:
    - `_queryOnce(flipPerspective(currentBoard), untransformMove: identity, untransformImage: identity, requiredOutcome: 1)`
    - `_queryOnce(mirrorBoard(flipPerspective(currentBoard)), untransformMove: cf-mirror, untransformImage: cf-mirror, requiredOutcome: 1)`
    - `_queryOnce(currentBoard, untransformMove: identity, untransformImage: identity, requiredOutcome: -1)`
    - `_queryOnce(mirrorBoard(currentBoard), untransformMove: cf-mirror, untransformImage: cf-mirror, requiredOutcome: -1)`
  - Merge all `WeightedCandidate` lists.
  - If empty → fallback.
  - Pass to `rules.moveSelectionStrategy.selectMove(allCandidates, legal, currentBoard)`.
  - Score the chosen move via the heatmap; if score ≤ 0 → fallback (with `allLosing` narration).
  - Return decision.
- [x] 5.2 Drop the existing `_searchOnce` helper, `_weightFor`, and the two-query `selectMove` body.
- [x] 5.3 `_buildNarration` simplification: still drives off match counts (positives vs negatives). No mention of Hamming or distance numbers in narration text — those weren't surfaced before either, so this is purely an internal tidy.

## 6. Engine: cleanup + exports

- [x] 6.1 Remove `VoteByMoveStrategy` from `packages/game_engine/lib/game_engine.dart` exports (it's gone).
- [x] 6.2 Verify `game_engine.dart` exports include any new public types (`CandidateFilter`, `MoveScorer` if not already covered transitively).
- [x] 6.3 `dart format` clean. `dart analyze` clean.

## 7. Engine: tests

- [x] 7.1 In `packages/game_engine/test/`, replace `similarity_test.dart`'s Hamming-related tests with L1 tests. Cover: identical images → distance 0, single-cell-difference of magnitude `k` → distance `k`, sign-flip on every cell on a fully-occupied board → maximum distance.
- [x] 7.2 Prefilter tests added (folded into `connect_four_test.dart` `ConnectFourFilter` group): accepts within ply window, rejects outside, `widened()` returns a strictly more permissive filter.
- [x] 7.3 Move-scorer tests added (folded into `connect_four_test.dart` `ConnectFourMoveScorer` group): computes the gravity landing row correctly, returns the heatmap value at that cell, returns sentinel for illegal columns.
- [x] 7.4 Update `move_selection_test.dart`: `InfluenceOverlayStrategy` accumulates correctly across multiple candidates, returns the highest-scoring legal move, returns null on empty inputs.
- [x] 7.5 Update `canonicalize_test.dart`: `invertState` now recomputes the diffused image (not bit-hash). Verify double-inversion is identity (boards equal byte-for-byte; diffused images byte-for-byte equal).
- [x] 7.6 Rewrite the "Winner-POV storage" / "Behavioral" tests in `behavioral_test.dart` to assert against the new pipeline: with synthetic mixed bot-won and player-won data, `selectMove` picks a non-fallback move; with only losing data, falls back; mirror-only data still produces a useful decision (sanity-check that the mirror queries fire).
- [x] 7.7 Run `dart test`; all green.

## 8. Mobile: schema migration

- [x] 8.1 In `apps/mobile/lib/src/db/database_service.dart`, bump `_kSchemaVersion` to 3.
- [x] 8.2 Update `OpenDatabaseOptions.onCreate` to use the v3 schema (`diffused_image BLOB` in place of `diffused_hash BLOB`).
- [x] 8.3 Add `onUpgrade` for `oldVersion < 3`: drop and recreate `game_states` with the v3 shape and indices, clear the `games` table. Existing v2 logic for `oldVersion < 2` stays for fresh-install paths that may still go via that route.
- [x] 8.4 Update `_gameStateColumns` and `_rowToGameState` to read/write `diffused_image` (Int8List blob).

## 9. Mobile: GameNotifier sanity sweep

- [x] 9.1 In `apps/mobile/lib/src/state/game_notifier.dart`, verify all `GameState` field references compile under the new typing (`diffusedImage` instead of `diffusedHash`). The notifier shouldn't directly read either field, so this is mostly a no-op — but check.
- [x] 9.2 Run `flutter analyze`. Clean.

## 10. Mobile: tests

- [x] 10.1 Update `apps/mobile/test/database_service_test.dart`: assertions on `diffused_hash` → `diffused_image`. Verify the v3 schema (column list, no `diffused_hash`).
- [x] 10.2 Run `flutter test`. All green (modulo the known sqflite-ffi + widget-tester flakiness from `winner-pov-foundation`).

## 11. Behavioral validation against benchmark

- [x] 11.1 Run `dart run bin/self_play_benchmark.dart 200 42 middle` from `packages/game_engine/`. Recorded: second-half win rate 82% (well above gate).
- [x] 11.2 Run `dart run bin/self_play_benchmark.dart 200 99 middle`. Recorded: second-half win rate 94%.
- [x] 11.3 Compare to the bit-hash baseline (~67% → ~80% on the same seeds, captured in `d1e69e7` commit message). New pipeline meets or exceeds the baseline on both seeds.
- [x] 11.4 Decision gate: both seeds well above the 75% second-half threshold.
- [x] 11.5 Benchmark passed; change shipped.

## 12. Manual smoke on device

- [x] 12.1 Install over the previous build. Confirm DB migration wipes old games (settings preserved).
- [x] 12.2 Play 5–10 games. Confirm clone responses are sensible, narrations make sense, no crashes.
- [x] 12.3 Resume mid-game still works.

## 13. Spec sync at archive

- [ ] 13.1 Sync delta specs into `openspec/specs/` at archive time:
  - `similarity-search/spec.md` — full rewrite.
  - `move-selection/spec.md` — InfluenceOverlay promoted, VoteByMove removed.
  - `clone-brain/spec.md` — pipeline change.
  - `canonicalization/spec.md` — two-query → four-query; invertState targets the diffused image.
  - `game-persistence/spec.md` — schema v3 mention.
- [ ] 13.2 Update `openspec/config.yaml` if any architectural language drifts (e.g., "diffused-bit-hash" mentions become "quantized diffused image"). _(config.yaml already updated in PR #1 review pass; canonical specs still pending archive.)_

## 14. Pre-commit + commit

- [x] 14.1 `dart format`, `dart analyze` (engine) clean.
- [x] 14.2 `flutter analyze`, `flutter test` (mobile) clean.
- [x] 14.3 Commit per phase or as one squashed change — match the project's existing rhythm (winner-pov-foundation went in as one commit; resume-game also one).
