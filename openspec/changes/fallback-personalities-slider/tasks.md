## 1. Engine: enum churn

- [ ] 1.1 In `packages/game_engine/lib/src/clone_brain.dart`, remove `edgeFocus` from `FallbackStrategy`. Add `ownPileAdjacent`, `greedyConnect`, `greedyConnectDefense`. Reorder the enum to canonical order: `random, middleFocus, pileFocus, ownPileAdjacent, greedyConnect, greedyConnectDefense`.
- [ ] 1.2 In `_fallbackMove`, drop the `edgeFocus` case. Add cases for the three new values that delegate to `_builderMove`, `_connectorMove`, `_sentinelMove`.
- [ ] 1.3 Implement `_builderMove(List<int> legalMoves, Board board)`: tallest own-pile column → adjacent column closest to mid, with empty/full fallbacks per the design doc.
- [ ] 1.4 Implement `_connectorMove(List<int> legalMoves, Board board)`: for each legal column, gravity-resolve the row, score by max-direction run length through the resulting cell, pick max with mid-distance tie-break.
- [ ] 1.5 Implement `_sentinelMove(List<int> legalMoves, Board board)`: scan opponent's potential drops for a winning (run >= 4) column; if found, block the most central; otherwise call `_connectorMove`.
- [ ] 1.6 Extract a small private helper `_longestRunThrough(Board board, int row, int col, int side)` used by both Connector and Sentinel scoring. Single line of code per direction; no abstraction beyond the function itself.
- [ ] 1.7 In `_builderMove`, use `_random` (the existing `CloneBrain` field) to pick uniformly between `c*-1` and `c*+1` when both are legal and equidistant from `mid`; this keeps benchmark seeding reproducible.

## 2. Engine: tests

- [ ] 2.1 In `packages/game_engine/test/clone_brain_test.dart`, add a test group **"Builder fallback"**: empty board → centre; one own piece in column 0 → plays column 1; tied own-piles in cols 1 and 5 → picks the one nearer mid then its adjacent.
- [ ] 2.2 Add **"Connector fallback"** group: empty board → centre (no chain to extend, all columns score 1, mid-distance tie-break wins); given a horizontal pair of own pieces in cols 2 & 3 → plays col 4 (extends to length 3); given a vertical pair of own in col 0 → plays col 0.
- [ ] 2.3 Add **"Sentinel fallback"** group: opponent has 3-in-a-row open at one end (winnable next move) → Sentinel blocks the winning column; same shape but with a stronger own-offence elsewhere → still blocks (defence first); no opponent-winning move → behaves identically to Connector.
- [ ] 2.4 Add a "Builder equidistant tie-break" test: configure a `CloneBrain` with a seeded `Random`, place own pieces at the centre column, assert the chosen adjacent column over many trials is roughly 50/50 (or assert the deterministic outcome under a fixed seed — whichever is simpler).
- [ ] 2.5 Run `dart format && dart analyze && dart test` in `packages/game_engine/`. All clean.

## 3. Engine: benchmark CLI tokens

- [ ] 3.1 In `packages/game_engine/bin/self_play_benchmark.dart`, accept the new CLI tokens: `chaotic` (alias for random), `stacker` (alias for pileFocus), `builder`, `connector`, `sentinel`. Drop `edge`.
- [ ] 3.2 Print the user-facing name in the benchmark header so logs are self-describing.

## 4. Engine: behavioural sanity benchmark (gate)

- [ ] 4.1 Run `dart run bin/self_play_benchmark.dart 200 42 chaotic` and `... 99 chaotic` from `packages/game_engine/`. Record overall + second-half win rates.
- [ ] 4.2 Same for `stacker`, `builder`, `connector`, `sentinel`.
- [ ] 4.3 Run a head-to-head: each pair of (chaotic, stacker, builder, connector, sentinel) plays 100 games against each other as personality-vs-personality. Concretely: instantiate two `CloneBrain` instances with *empty* `GameLog`s (so every move falls back) and the two competing personalities; alternate first move; record win/loss/draw per pairing. Single-file ad-hoc script under `packages/game_engine/bin/personality_round_robin.dart` is fine — keep it minimal, no tests needed for the script itself.
- [ ] 4.4 **Gate**: confirm head-to-head ordering Sentinel ≥ Connector ≥ Builder ≥ Stacker ≥ Chaotic. If inverted, fix the personality before continuing. Record results in this file as a checkbox comment.

## 5. Mobile: persistence migration

- [ ] 5.1 In `apps/mobile/lib/src/db/database_service.dart`, update `loadFallback`: when the stored value parses to `edgeFocus` or `middleFocus`, return `FallbackStrategy.ownPileAdjacent` instead. Default for empty config also becomes `ownPileAdjacent`.
- [ ] 5.2 No schema change needed. Existing `clone_config` value column already stores enum-name strings.
- [ ] 5.3 In `apps/mobile/test/database_service_test.dart`, add tests: round-trip for the three new values; legacy `edgeFocus` → `ownPileAdjacent` mapping; legacy `middleFocus` → `ownPileAdjacent` mapping; default on empty config is `ownPileAdjacent`.

## 6. Mobile: settings UI (slider)

- [ ] 6.1 In `apps/mobile/lib/src/screens/settings_screen.dart`, replace the `RadioGroup<FallbackStrategy>` with a discrete `Slider` (`divisions: 4`, `min: 0`, `max: 4`).
- [ ] 6.2 Define a constant ordered list of `(FallbackStrategy, String name, String blurb)` matching the design doc.
- [ ] 6.3 Above the slider: big personality name in `displayMedium` (Press Start 2P, yellow accent). Below: one-line blurb in `bodyLarge` (VT323).
- [ ] 6.4 Persist on slider release (`onChangeEnd`), not on every drag tick. The visible name updates live as the user drags.
- [ ] 6.5 If the persisted value is somehow not in the slider's ordered list (defensive — shouldn't happen after `loadFallback` mapping), default the slider position to 2 (Builder) without overwriting storage.
- [ ] 6.6 Drop the now-unused `_kFallbackLabels` map.

## 7. Mobile: notifier default

- [ ] 7.1 In `apps/mobile/lib/src/state/game_notifier.dart`, change the cold-start fallback default from `FallbackStrategy.random` to `FallbackStrategy.ownPileAdjacent` (only the literal default in code; persisted user choice still wins).
- [ ] 7.2 In `apps/mobile/test/game_notifier_test.dart`, update any test that asserts on the literal default value of the fallback.

## 8. Verification

- [ ] 8.1 `dart format && dart analyze && dart test` clean in `packages/game_engine/`.
- [ ] 8.2 `flutter analyze && flutter test` clean in `apps/mobile/`.
- [ ] 8.3 Pre-commit hook passes.
- [ ] 8.4 Manual smoke on device:
  - Install over the previous build. Open Settings. Confirm the slider appears, defaults to Builder for a fresh install (or, on the dev's existing install, to whatever is mapped from the prior persisted value).
  - Drag through all five positions; confirm name + blurb update live; close and reopen Settings to verify persistence.
  - Start a new game with each of Builder/Connector/Sentinel selected and play 5 plies; confirm the bot's first-move-in-a-fresh-game (no clone data yet) actually exhibits the personality (Builder plays adjacent to your stack; Connector reaches for length; Sentinel blocks an obvious 3-in-a-row).
