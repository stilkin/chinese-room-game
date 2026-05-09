# Design — Go engine foundation

## Goal

A working `Go(size: 13)` game module in the engine package that plugs into the existing CBR pipeline (four-query retrieval, L1 over diffused images, heatmap accumulation, all-losing fallback) with no changes to that pipeline.

## Board representation

- `Board` is reused as-is: 2D `Int8List` with `-1/0/+1` cells. Row-major. `size × size`.
- No piece weighting (Go is uniform); the kernel does the heavy lifting.

## Move encoding

- Integers `0..size*size-1` are intersection indices in row-major order. `intersection(r, c) = r * size + c`.
- Integer `size*size` is the **pass** sentinel. Choosing this constant rather than `-1` keeps move ints non-negative everywhere (some engine code treats `move ≥ 0` as a precondition).
- `legalMoves(Board)` always includes the pass sentinel — passing is always legal in Go.

## Captures and liberties

- After a placement, scan the four neighbours of the placed stone. For each neighbouring opposing-colour group, run a flood-fill to count liberties; if zero, remove the group.
- Then check the placed stone's own group for liberties; if zero (and no opposing capture happened), the move is illegal (suicide).
- Implementation: a single `_captureAdjacentEnemyGroups(board, r, c, side)` helper followed by a `_isSelfSuicide(board, r, c, side)` check. Both use the same flood-fill walker.

## Ko

- Single-stone simple ko: track the immediately-previous board hash (a cheap integer hash over the cell array). A move that would recreate that hash is illegal.
- We do **not** implement positional superko (recreate any prior position) — simple ko is sufficient for almost all play and avoids storing the full game history of board hashes.
- Ko state is part of `GameState` for retrieval purposes? **No.** Ko is a transient legality check, not a retrieval signal. Stored states retain their `board` + `diffusedImage` only.

## Game termination

- Connect Four ends when `checkWinner(Board)` returns non-null. That signature is insufficient for Go (two-pass termination depends on move history, not the board alone).
- **Interface change**: extend `GameRules` with `bool isTerminal(GameLog)` returning true when the game is over. Default implementation delegates to `checkWinner(currentBoard)`. Go overrides: terminal when the last two moves were both `pass` (or the board is filled — degenerate case).
- Add `int finalOutcome(GameLog) → +1/-1/0` called once when `isTerminal` first returns true. For Connect Four, derives from `checkWinner`. For Go, runs area scoring.

## Area scoring (Chinese-style)

- Count `+1` stones + empty intersections fully surrounded by `+1`-only neighbours (transitively) → `whiteScore`. Same for `-1` → `blackScore`.
- Empties that touch both colours' regions (dame) are unscored.
- No komi for now (a half-point handicap to the second player). Easy to add later via a constant offset.
- Ties → `0`. The half-point of komi exists in real Go specifically to avoid ties; without komi we just accept that ties are possible.

## Diffusion kernel

- `GoDiffusionKernel`: each stone radiates positive (or negative) influence along the four orthogonal directions (no diagonals — Go's connectivity is 4-neighbour). Influence attenuates by `0.5` per step.
- 2 steps deep, matching the Connect Four kernel's depth. Empirical tuning may push to 3 if the smoke benchmark suggests under-spreading.
- Why not include diagonals? In Go, diagonally-adjacent stones are *not* connected; territorial influence follows orthogonal connectivity. A diagonal-leaking kernel would over-claim corners.
- Why orthogonal-line spread (Connect-Four-like) rather than radial-spatial? Radial spreads influence into shapes that don't match how Go territory actually works — Go territory grows along board lines. Lines preserve the right anisotropy.

## Prefilter

- `GoFilter`: same shape as `ConnectFourFilter`. Stores a query move-count, accepts candidates whose move-count differs by at most `window` (initial = 4, doubles on `widened()`). Move-count is a strong proxy for stage-of-game on Go.
- `maxCandidateL1Distance` for Go: starting guess `120` (twice Connect Four's `60`, scaled roughly with cell count). Empirical tuning expected.

## Move scorer

- `GoMoveScorer.scoreMove(move, currentBoard, heatmap)`:
  - If `move == passSentinel`: return a small fixed score (`0.01`). This sits below any positive heatmap region (so the brain plays placements when influence is positive somewhere) but above the all-losing threshold (so the brain *passes* rather than falling back to chaotic when every placement has negative score — which is the natural late-game state when our territory is settled).
  - Else: `move` is an intersection. Return `heatmap[r][c]` where `(r, c) = (move ~/ size, move % size)`.
  - Illegal placements never reach the scorer (they're filtered upstream).

## Open questions (defer to playtest)

1. **Pass score = 0.01** — this is a guess. Might need tuning based on whether the bot passes too eagerly or too late. Adjust after the first real games.
2. **Diffusion depth** — 2 steps is the Connect Four parallel. Go territory propagates further along open lines; 3 might serve better. Smoke benchmark numbers will tell us.
3. **L1 ceiling = 120** — pure scaling guess. Tune from observed retrieval distances.
4. **Komi** — skip for now. Add as a constant offset to `whiteScore` (not `blackScore`) when the rules feel imbalanced.

## Alternatives considered

- **Radial Gaussian kernel** — more isotropic but doesn't match Go's line-based connectivity. Would over-claim corners. Rejected.
- **Track full positional superko history** — correct but expensive (per-game list of N board hashes). Simple ko handles ~99% of cases. Rejected for now; can swap in later if needed.
- **Japanese-style territory scoring (only counts surrounded empties)** — more nuanced but introduces dead-stone disambiguation, which is a UI/UX problem. Chinese area scoring is mechanically simpler and a reasonable approximation for AI training. Use Chinese for now.
- **`move = -1` for pass** — would force every "is move ≥ 0" check to special-case it. Using `size*size` keeps moves non-negative throughout. Cheaper.

## Connect Four impact

- `ConnectFourRules.isTerminal(log) => checkWinner(log.currentBoard) != null` — three-line method.
- `ConnectFourRules.finalOutcome(log) => checkWinner(log.currentBoard)!` — same.
- Existing tests unaffected.

## Smoke benchmark

- `bin/go_smoke_benchmark.dart`: 10 self-play games on 9×9 (cheaper than 13×13 for a smoke pass), seed 42, fresh log. Confirm:
  - Game terminates (eventually two passes are chosen).
  - Final score is in a sane range.
  - Retrieval doesn't crash.
- This is **not** a strength benchmark. Real strength benchmarking happens after a few hundred games, post-shipping.
