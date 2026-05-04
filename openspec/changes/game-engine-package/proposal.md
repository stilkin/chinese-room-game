## Why

The game engine is the foundation of Clone Wars — all game logic, the clone AI brain, and narration live here. It must exist before any app (mobile, web, server) can be built. Building it as a pure Dart package with no Flutter dependency ensures it's testable standalone and reusable across all targets.

## What Changes

- Create `packages/game_engine/` as a pure Dart package within the pub workspace
- Implement board representation using 2D signed byte arrays, generic across game types
- Implement Connect Four rules (legal moves, win/draw detection, drop mechanics)
- Add symmetry canonicalization: left/right mirror normalization, perspective flip (always store from side-to-move), loss inversion (store losses as opponent wins)
- Implement Zobrist hashing for O(1) exact-match board lookup, incrementally updatable per move
- Implement Connect Four diffusion kernel (influence spreading along 4 winning directions, 2-3 steps) producing influence maps for fuzzy similarity
- Add diffused influence map comparison via Hamming distance
- Implement two-scalar pre-filter (total_material, material_balance) with adaptive widening to reduce search space before full comparison
- Implement move weighting: wins > draws > losses, fewer moves to win preferred
- Implement basic factual clone narration (e.g. "move from game #5", "no data — playing randomly")
- Define game state data model with outcome/moves_to_end backfilling on game completion
- Implement cold-start fallback personalities for Connect Four (random, middle-focus, edge-focus, pile-focus)

## Capabilities

### New Capabilities

- `board-representation`: 2D Int8 array board model, generic across game types (Connect Four, Chess, Go, Othello)
- `connect-four-rules`: Connect Four game rules — legal move generation, piece dropping, win/draw detection
- `canonicalization`: Symmetry normalization at write time — mirror, perspective flip, loss inversion
- `zobrist-hashing`: Zobrist hash computation and incremental update for exact-match board lookup
- `diffusion-engine`: Diffusion kernel interface and Connect Four implementation — produces influence maps from board states
- `similarity-search`: Pre-filtering (total_material, material_balance with adaptive widening), diffused map comparison via Hamming distance, candidate ranking
- `clone-brain`: Move selection pipeline — search, weight, select — plus cold-start fallback personalities
- `narration`: Basic factual narration text generation for clone decisions

### Modified Capabilities

(none — greenfield project)

## Impact

- New package at `packages/game_engine/` with its own `pubspec.yaml`
- Root `pubspec.yaml` updated to include the package in the pub workspace
- No external dependencies beyond Dart SDK — all algorithms are custom
- Defines the public API that `apps/mobile/`, `apps/web/`, and `server/` will depend on
