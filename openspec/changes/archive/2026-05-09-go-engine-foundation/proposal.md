# Go engine foundation

## Why

The case-based-reasoning architecture has been validated against Connect Four, but Connect Four turns out to be a worst-case fit (sharp tactics, small state space, gravity discontinuities — see archived `image-similarity-foundation`). Go is the canonical good fit: diffusion of stone influence *is* the strategy, the state space is huge, patterns reuse heavily across games, and the strategic body of the game (territory, thickness, moyo) is exactly what a multi-step diffusion kernel models.

This change adds a Go module to the engine package only — rules, diffusion kernel, prefilter, move scorer, tests, smoke benchmark. The mobile app is **not** changed by this proposal; the next change (`go-mobile-app`) cuts the UI over.

## What Changes

- New game module `Go(size: int)` with default `size = 13`. Engine retains 9 and 19 as reachable sizes via the constructor; UI choice is a separate concern.
- Move encoding: integers `0..size*size-1` are intersection indices in row-major order; integer `size*size` is the **pass** sentinel.
- Rules: legal-move generation excluding own-suicide and ko, group-capture on placement, two-consecutive-passes terminates the game, simple Chinese-style area scoring (stones + own-surrounded empties).
- `GoDiffusionKernel`: orthogonal-line spread of stone influence (horizontal + vertical), attenuating with distance, 2 steps.
- `GoFilter`: move-count window prefilter with adaptive widening (mirrors `ConnectFourFilter`).
- `GoMoveScorer`: heatmap lookup at the candidate intersection. Pass move scores at a small fixed value so the brain only chooses to pass when no positive-scoring placement exists.
- New tests: rules edge cases (ko, suicide, multi-stone capture, snapback, two-pass termination) and a small CBR-against-itself smoke benchmark to confirm the retrieval pipeline functions on Go-shaped data.
- Connect Four code retained in the engine package as the multi-game regression case.

## Impact

- New file: `packages/game_engine/lib/src/games/go.dart`.
- New file: `packages/game_engine/test/go_test.dart`.
- New file: `packages/game_engine/bin/go_smoke_benchmark.dart`.
- Tiny extension to the `GameRules` interface for two-pass termination (board-only `checkWinner` is insufficient for Go). Connect Four implements the new method as a delegating no-op.
- New canonical capability: `go-rules`.
- Updated capability: `diffusion-engine` (Go kernel requirement added).
- **No** mobile changes. **No** DB schema changes. **No** UI changes. **No** changes to clone-brain, similarity-search, canonicalization, or game-persistence specs.
