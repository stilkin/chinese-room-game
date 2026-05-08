## 1. Engine: drop Zobrist & mirror canonicalization

- [x] 1.1 Delete `packages/game_engine/lib/src/zobrist.dart` (whole file: `ZobristTable`, `SplitMix64`).
- [x] 1.2 Remove `export 'src/zobrist.dart';` from `packages/game_engine/lib/game_engine.dart`.
- [x] 1.3 In `packages/game_engine/lib/src/canonicalize.dart`, drop `mirror`, `_shouldMirror`, `canonicalize`, and `CanonicalResult`. Keep only `flipPerspective`. Remove the `import 'zobrist.dart';`.
- [x] 1.4 Engine analyzer remains clean after deletions (callers updated in subsequent phases).

## 2. Engine: simplify GameState

- [x] 2.1 Remove `zobristHash` and `side` fields from `GameState` in `packages/game_engine/lib/src/game_state.dart` (constructor + class definition).
- [x] 2.2 `GameLog` and `replaceStatesForGame` unchanged.

## 3. Engine: simplify createState + invertState

- [x] 3.1 Update `CloneBrain.createState` in `packages/game_engine/lib/src/clone_brain.dart`: drop `side` parameter. Don't canonicalize. Just diffuse the input board, compute `totalMaterial`/`materialBalance`, build the `GameState` directly.
- [x] 3.2 Drop `_zobristTable` field, `zobristTable` getter, the `ZobristTable.forGame(rules)` initializer, and the `dart:math` `Random` import-related code (Random stays — used for fallback).
- [x] 3.3 Update `invertState` in `canonicalize.dart` to drop the `ZobristTable` parameter; just `flipPerspective(board)`, recompute `diffusedHash`, flip `materialBalance`, preserve metadata.

## 4. Engine: simplify searchSimilar

- [x] 4.1 In `packages/game_engine/lib/src/similarity.dart`, drop the `queryZobristHash` parameter and the exact-match loop.
- [x] 4.2 Remove `SimilarityResult.isExactMatch` field. Update the constructor accordingly.

## 5. Engine: two-query selectMove + sign-aware weighting

- [x] 5.1 Rewrite `CloneBrain.selectMove` to run two searches: Query A on `flipPerspective(currentBoard)`, Query B on `currentBoard`. Filter A to `outcome=+1` rows (positive weight); filter B to `outcome=-1` rows (negative weight).
- [x] 5.2 Extract a private `_searchOnce(Board query, List<GameState> candidates) → List<SimilarityResult>` helper inside `CloneBrain` that diffuses + bit-hashes + computes material + calls `searchSimilar`.
- [x] 5.3 Update `_weightCandidate` (or replace with `_weight(SimilarityResult, {required int sign})`) to compute `sign × (1/(1+movesToEnd)) × (1/(1+hammingDistance))`.
- [x] 5.4 After calling `rules.moveSelectionStrategy.selectMove`, look up the selected column's net weight; if `≤ 0`, route to `_fallbackDecision`.
- [x] 5.5 Update `_buildNarration`: drop the `exactMatch` branch (unreachable — no Zobrist) and `invertedData` branch (not used). Build narration from the merged Query A + Query B match counts.

## 6. Engine: narration cleanup

- [x] 6.1 In `packages/game_engine/lib/src/narration.dart`, drop the `exactMatch` and `invertedData` cases from `DecisionContext` enum and the matching switch arms in `narrate(...)`.

## 7. Engine: tests

- [x] 7.1 In `packages/game_engine/test/canonicalize_test.dart`, drop the `mirror`, `flipPerspective`, `canonicalize` test groups for the removed functions. Keep `flipPerspective`'s test (function still exists). Update the `invertState` group: drop `ZobristTable` from setup, drop the Zobrist-hash equivalence test, keep flip-side, materialBalance-flip, metadata-preservation, double-inversion-identity, diffused-hash-recompute.
- [x] 7.2 In `packages/game_engine/test/behavioral_test.dart`, drop the "mirror-image games produce identical canonical states" test. Rewrite the "Loss inversion" group as **"Winner-POV storage"**:
  - Player-won game synthesis: assert all rows store the display board as-is (player=+1, clone=-1 in `board.flat`); `outcome=+1` on even plies, `-1` on odd plies.
  - Bot-won game synthesis + whole-game flip via `replaceStatesForGame`: assert all rows have flipped boards (clone=+1, player=-1); `outcome=+1` on odd plies (clone moves), `-1` on even plies (player moves).
  - Behavioral: with mixed bot-won and player-won data in the log, the bot's `selectMove` returns a non-fallback decision that incorporates both positive and negative weights (no specific move asserted; just `usedFallback=false` and `candidatesFound > 0`).
- [x] 7.3 Run `dart analyze` and `dart test` in `packages/game_engine/`; both clean.

## 8. Mobile: schema migration + storage policy flip

- [x] 8.1 In `apps/mobile/lib/src/db/database_service.dart`, bump `_kSchemaVersion` to 2. Update `OpenDatabaseOptions.onCreate` to use the v2 schema (no `zobrist_hash`, no `side`). Add an `onUpgrade` that, on `oldVersion < 2`, drops `game_states`, recreates it with the v2 shape and indices, and clears the `games` table. Do not touch `clone_config`.
- [x] 8.2 Update `_gameStateColumns(GameState s)` and `_rowToGameState(...)` to drop the removed columns/fields.
- [x] 8.3 Rewrite `backfillStates` to use ply parity: `UPDATE game_states SET outcome = CASE WHEN (ply % 2) = 0 THEN ? ELSE ? END, moves_to_end = ? - ply WHERE game_id = ?`. Parameters: `(outcomeForEvenPly, -outcomeForEvenPly, totalMoves, gameId)` where `outcomeForEvenPly` is the outcome from the player's POV (player moves on even plies).
- [x] 8.4 In `apps/mobile/lib/src/state/game_notifier.dart`, flip the `_endGame` invert trigger to `winner == -1`. Rename `_invertCurrentGameToBotPerspective` → `_invertCurrentGameToWinnerPerspective`. Drop the `side` parameter from `_brain.createState` calls (since it's gone).
- [x] 8.5 Verify `_brain.createState(...)` call sites in the notifier still compile (no `side` parameter).

## 9. Mobile: tests

- [x] 9.1 In `apps/mobile/test/database_service_test.dart`: drop `side` from the `_state(...)` test helper. Drop assertions on `zobrist_hash`. Update the backfill test to verify ply-parity-based outcome assignment. Keep `replaceAllStatesForGameAtomic` test.
- [x] 9.2 In `apps/mobile/test/game_notifier_test.dart`: update the player-won game test — now expects rows stored AS-IS (no flip); even plies have `outcome=+1` and player pieces in `board.flat`; odd plies have `outcome=-1` and clone pieces. Add a new "bot-won game" test: feed seed data so the bot can force a win, verify rows have flipped boards (clone pieces=+1) with `outcome=+1` on odd plies.
- [x] 9.3 Run `flutter analyze` and `flutter test` in `apps/mobile/`; both clean (parallel + serial).

## 10. Verification

- [x] 10.1 `dart analyze` and `dart test` clean in `packages/game_engine/`.
- [x] 10.2 `flutter analyze` and `flutter test` clean in `apps/mobile/`.
- [x] 10.3 Pre-commit hook passes.
- [x] 10.4 Manual smoke on device:
  - Install over old install. Confirm DB migration runs without error and old games are gone (settings preserved).
  - Play and lose 2–3 games (bot wins). Verify subsequent games' clone narration leaves fallback faster than under prior scheme.
  - Play and win 2–3 games (player wins). Same observation.
