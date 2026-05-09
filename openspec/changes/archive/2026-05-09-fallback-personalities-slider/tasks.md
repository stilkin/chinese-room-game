## 1. Engine: enum churn

- [x] 1.1 In `packages/game_engine/lib/src/clone_brain.dart`, remove `edgeFocus` from `FallbackStrategy`. Add `ownPileAdjacent`, `greedyConnect`, `greedyConnectDefense`. Reorder the enum to canonical order: `random, middleFocus, pileFocus, ownPileAdjacent, greedyConnect, greedyConnectDefense`.
- [x] 1.2 In `_fallbackMove`, drop the `edgeFocus` case. Add cases for the three new values that delegate to `_builderMove`, `_connectorMove`, `_sentinelMove`.
- [x] 1.3 Implement `_builderMove(List<int> legalMoves, Board board)`: tallest own-pile column → adjacent column closest to mid, with empty/full fallbacks per the design doc.
- [x] 1.4 Implement `_connectorMove(List<int> legalMoves, Board board)`: for each legal column, gravity-resolve the row, score by max-direction run length through the resulting cell, pick max with mid-distance tie-break.
- [x] 1.5 Implement `_sentinelMove(List<int> legalMoves, Board board)`: scan opponent's potential drops for a winning (run >= 4) column; if found, block the most central; otherwise call `_connectorMove`.
- [x] 1.6 Extract a small private helper `_longestRunThrough(Board board, int row, int col, {required int side})` used by both Connector and Sentinel scoring.
- [x] 1.7 In `_builderMove`, use `_random` to pick uniformly between `c*-1` and `c*+1` when both are legal and equidistant from `mid`.

## 2. Engine: tests

- [x] 2.1 Builder fallback group (4 tests): empty board → centre, single own at col 0 → col 1, tied own piles, equidistant adjacents under seeded random.
- [x] 2.2 Connector fallback group (4 tests): empty board → centre, vertical own pair extends, horizontal own pair extends with mid-distance tie-break, length-4 winning move selected.
- [x] 2.3 Sentinel fallback group (3 tests): blocks opponent length-4, blocks even when own offence available, behaves like Connector when no threat.
- [x] 2.4 Builder equidistant tie-break covered as part of 2.1's fourth test (asserts the result is one of {2, 4} under seeded random).
- [x] 2.5 `dart format && dart analyze && dart test` clean (98 engine tests pass).

## 3. Engine: benchmark CLI tokens

- [x] 3.1 Added tokens `chaotic`, `stacker`, `builder`, `connector`, `sentinel` (plus aliases for legacy `random`, `pile`, `middle`). Dropped `edge`. Coaches now delegate to `CloneBrain.selectMove` so the engine stays the single source of truth.
- [x] 3.2 Help comment block updated; benchmark header still prints the coach kind verbatim.

## 4. Engine: behavioural sanity benchmark (gate)

- [x] 4.1–4.3 Wrote `bin/personality_round_robin.dart`. 50 games per direction, 1000 games total, seed 42.
- [x] 4.4 **Gate result** (recorded for archive):

  ```text
  Aggregate wins (50 games per direction, alternated-first):
    sentinel   348
    connector  291
    stacker    190
    builder    120
    chaotic     51
  ```

  **Inversion observed**: Stacker beats Builder (56–44 head-to-head, 70 wins difference in aggregate). Cause: in Connect Four, "stack the tallest pile" tracks the centre column (canonical-best opening); "build adjacent to own pile" deliberately moves *away* from the centre. Builder is *cognitively* more complex but *mechanically* weaker.

  **Resolution**: reorder the slider so Builder sits below Stacker. New order: `Chaotic, Builder, Stacker (default), Connector, Sentinel`. Slider remains a strength ladder. Default position 2 is now Stacker.

## 5. Mobile: persistence migration

- [x] 5.1 `loadFallback` defaults empty config to `pileFocus` (Stacker). Any persisted value not in the user-facing set (`edgeFocus`, `middleFocus`, or any unrecognised string) is silently coerced to `pileFocus`.
- [x] 5.2 No schema change needed.
- [x] 5.3 Persistence tests added: round-trip across the five user-facing values; `middleFocus` → Stacker mapping; legacy `edgeFocus` (raw insert) → Stacker; default-on-empty is Stacker.

## 6. Mobile: settings UI (slider)

- [x] 6.1 `SettingsScreen` is now a `StatefulWidget` with a `Slider(divisions: 4, min: 0, max: 4)` replacing the radio group.
- [x] 6.2 Constant `_kSliderLevels` holds the canonical ordered list of `(strategy, name, blurb)` records.
- [x] 6.3 Personality name in `displayMedium` (Press Start 2P, yellow), blurb in `bodyLarge` (VT323), centred.
- [x] 6.4 Persist on `onChangeEnd`; the displayed name/blurb update live during drag via local state.
- [x] 6.5 `_initialPosition` falls back to `_kDefaultSliderIndex` (Stacker) if the persisted value is somehow off-list.
- [x] 6.6 Removed `_fallbackLabels` map.

## 7. Mobile: notifier default

- [x] 7.1 No code change required: `main.dart` already bootstraps the brain via `db.loadFallback()`, which now returns Stacker by default. The notifier's transient pre-init `_fallback` is overwritten before any user-visible state is rendered.
- [x] 7.2 Updated four `game_notifier_test.dart` tests that previously used `edgeFocus` as a "stay-out-of-the-way" deterministic fallback. Switched them to `middleFocus` + player drops at col 0; same vertical-win shape, no functional change. Updated one test that persisted `middleFocus` to use `greedyConnect` (a user-facing value not coerced by `loadFallback`).

## 8. Verification

- [x] 8.1 `dart format && dart analyze && dart test` clean in `packages/game_engine/` (98 tests pass).
- [x] 8.2 `flutter analyze && flutter test` clean in `apps/mobile/` (36 tests pass).
- [x] 8.3 Pre-commit hook passes.
- [x] 8.4 Manual smoke on device:
  - Install over the previous build. Open Settings. Confirm the slider appears at Stacker (legacy values silently remap; fresh installs default to Stacker).
  - Drag through all five positions; confirm name + blurb update live; close and reopen Settings to verify persistence.
  - Start a fresh game with each of Builder / Connector / Sentinel selected (delete logs first to force the fallback path); play 5 plies; confirm the personality is recognisable.
