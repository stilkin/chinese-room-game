## Context

Pi-Ying needs a shared game engine that implements the full clone AI pipeline: store board states, find similar positions, weight by outcome, select a move, and narrate the decision. This is a greenfield pure Dart package at `packages/game_engine/` — no existing code, no Flutter dependency.

The engine must be game-agnostic in its core (storage, similarity, weighting, narration) while allowing game-specific modules (rules, diffusion kernels) to be plugged in. Connect Four is the first game; Othello, Chess, and Go follow later.

## Goals / Non-Goals

**Goals:**
- Implement the full clone decision pipeline for Connect Four
- Design interfaces that generalize to future games without modification to core logic
- Keep the package pure Dart — no Flutter, no external dependencies beyond Dart SDK
- Make every component independently testable with `dart test`

**Non-Goals:**
- Persistence / SQLite (lives in the mobile app layer, not the engine)
- Network sync, user accounts, matchmaking (Phase 3)
- Diffusion kernels for games other than Connect Four (Phase 4)
- Performance optimization beyond what brute-force provides (unnecessary at this scale)
- UI, rendering, or animations

## Decisions

### Game abstraction via abstract `GameRules` class

Each game implements a `GameRules` interface providing: board dimensions, legal moves, apply move, check win/draw, piece values, and a `DiffusionKernel`. The clone brain, similarity search, canonicalization, and narration all operate on `GameRules` — they never reference Connect Four directly.

*Alternative: no abstraction, just build Connect Four directly.* Rejected because the proposal lists 4 future games and the interfaces are simple enough that abstracting now costs almost nothing.

### Board as `List<List<int>>` backed by flat data

Boards are 2D `List<List<int>>` for readability at the API layer. Internally, operations that need performance (hashing, diffusion) work on a flat `Int8List` view. This avoids boxing overhead for bulk operations while keeping the public API intuitive.

*Alternative: flat array everywhere.* Rejected — 2D indexing is clearer for game rules (row, col) and the conversion cost is negligible for these board sizes.

### Zobrist table seeded from game type string

The Zobrist random table is generated from a deterministic PRNG seeded with the game type name. This ensures consistent hashes across sessions without storing the table. Each `(piece_value, row, col)` combination maps to a random 64-bit int. The hash of a board is XOR of all occupied entries — incrementally updatable when a move is applied.

*Alternative: precomputed constant tables.* Rejected — deterministic seeding achieves the same result without maintaining large literal tables per game type.

### Diffusion kernel as a game-provided function

Each `GameRules` provides a `DiffusionKernel` that takes a board and returns an influence map (2D double array). The kernel defines how piece values spread — along winning lines for Connect Four, along legal move paths for chess, etc. 2-3 application steps. The engine calls it identically regardless of game type.

The diffused map is converted to a perceptual-style bit hash for storage and Hamming distance comparison.

*Alternative: a generic spatial diffusion with configurable parameters.* Rejected — game diffusion patterns are fundamentally different (directional for Connect Four, piece-specific for chess, spatial for Go). A generic kernel would be either too simple or too complex.

### Two-scalar pre-filter with adaptive widening

Before computing diffusion similarity, candidate states are filtered by `(total_material, material_balance)` — both computable in O(board_size) from piece values. Starting window is ±2 on each axis; if fewer than 5 candidates remain, the window doubles iteratively until enough candidates are found or the full database is searched.

This generalizes across all game types because the board representation already encodes piece values (±1 for Connect Four/Go/Othello, weighted for Chess).

*Alternative: ply-count filtering.* Rejected after discussion — ply count is too restrictive early on (cold start) and doesn't generalize to Go where similar positions occur at very different move numbers.

### Canonicalization at write time, not query time

All states are canonicalized before storage:
1. Mirror normalization — compare left-half vs right-half Zobrist hash, flip if needed
2. Perspective — always store from side-to-move's perspective
3. Inversion — losses are stored as wins from the opponent's perspective (negate board, swap side)

This means every game produces data for both sides, and queries only need to canonicalize the current board once.

*Alternative: canonicalize at query time across all symmetries.* Rejected — stores one canonical form instead of querying N symmetry variants. Simpler and faster.

### Game-specific move selection strategies

Move selection — how to go from weighted candidates to a chosen move — is part of the `GameRules` interface. Two strategies are defined:

**Vote-by-move** (Connect Four, Othello): Candidates each suggest a specific move. Weights are aggregated per move. The move with the highest total weight wins. Works well when the move space is small (7 columns for Connect Four) and multiple candidates naturally converge on the same moves.

**Influence overlay** (Go, Chess): When the move space is large (361 intersections for Go), candidates rarely suggest the exact same move. Instead, the top N candidates' diffusion maps are weighted by outcome/efficiency and averaged into a **target influence map** — a heat map of "where good things happen." Each legal move is scored by its value in the target map. The move in the hottest region wins. This captures spatial clustering: three candidates playing *near* each other in a good region produce one strong signal instead of three weak ones.

Connect Four implements vote-by-move. The influence overlay interface is defined but only implemented for future games.

*Alternative: always use vote-by-move.* Rejected — for Go with 200+ legal moves, candidates almost never agree on an exact intersection. Spatial clustering of strategic intent is lost. The influence overlay recovers it cheaply (one lookup per legal move in the target map).

*Alternative: compute full diffusion per candidate move to evaluate resulting positions.* Rejected — too expensive for large boards (200 diffusion computations per Go turn). Looking up each legal move's value in the pre-averaged target map achieves the same effect with a single averaging pass plus O(legal_moves) lookups.

### Narration as template selection, not generation

Narration picks from a set of factual templates based on the decision context (exact match found, fuzzy match, multiple candidates, no data, all-losing data). Templates reference concrete data: game ID, move count, outcome. No LLM or generative text.

*Alternative: freeform text generation.* Rejected — deterministic templates are testable and predictable. Flavor text is a later enhancement.

## Risks / Trade-offs

**[Hamming distance on diffused hashes may not capture strategic similarity well enough]** → Validate empirically once Connect Four is playable. The diffusion kernel quality matters more than the distance metric. If Hamming proves too coarse, cosine similarity on the raw influence map is a drop-in replacement.

**[Adaptive widening could degenerate to full scan on cold start]** → Acceptable. With few stored states, a full scan is cheap. The pre-filter's value grows with data volume.

**[Abstracting for multiple games before building one risks over-engineering]** → Mitigated by keeping interfaces minimal. `GameRules` has ~6 methods. If the abstraction proves wrong for Chess/Go, it's cheap to refactor a small interface.

**[Deterministic PRNG for Zobrist tables ties hash quality to seed/algorithm choice]** → Use a well-known algorithm (e.g., SplitMix64). Hash collisions are astronomically unlikely for these board sizes regardless.
