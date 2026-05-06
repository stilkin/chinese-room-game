## 1. Package Setup

- [x] 1.1 Create `packages/game_engine/` with `pubspec.yaml` (pure Dart, no Flutter dependency)
- [x] 1.2 Create root `pubspec.yaml` with pub workspace referencing `packages/game_engine/`
- [x] 1.3 Create `lib/game_engine.dart` barrel file and `lib/src/` directory structure
- [x] 1.4 Verify `dart analyze` and `dart test` run cleanly on empty package

## 2. Board Representation

- [x] 2.1 Implement `Board` class: 2D `List<List<int>>` with configurable dimensions, Int8List flat view
- [x] 2.2 Implement `GameRules` abstract class: board dimensions, legal moves, apply move, check win/draw, piece values, diffusion kernel, move selection strategy
- [x] 2.3 Write tests: board creation, flat view round-trip, dimension validation

## 3. Connect Four Rules

- [x] 3.1 Implement `ConnectFourRules` extending `GameRules`: 7x6 board, gravity-based drop, legal move generation
- [x] 3.2 Implement win detection (horizontal, vertical, both diagonals)
- [x] 3.3 Implement draw detection (full board, no winner)
- [x] 3.4 Write tests: legal moves on empty/partial/full boards, drop mechanics, all win directions, draw

## 4. Zobrist Hashing

- [x] 4.1 Implement deterministic PRNG (SplitMix64) seeded from game type string
- [x] 4.2 Implement Zobrist table generation: `(piece_value, row, col) → int64`
- [x] 4.3 Implement full board hash computation (XOR of occupied entries)
- [x] 4.4 Implement incremental hash update on move application
- [x] 4.5 Write tests: determinism, empty board=0, incremental vs full recomputation, different game types produce different tables

## 5. Canonicalization

- [x] 5.1 Implement mirror normalization: compare left/right half hashes, flip if needed
- [x] 5.2 Implement perspective normalization: negate piece values so side-to-move is positive
- [x] 5.3 Implement loss inversion: generate opponent-perspective states with outcome=win
- [x] 5.4 Implement canonical pipeline: mirror → perspective → Zobrist recompute
- [x] 5.5 Write tests: mirror symmetry produces same canonical form, perspective flip, loss inversion doubles data, canonical form is idempotent

## 6. Diffusion Engine

- [x] 6.1 Define `DiffusionKernel` interface: board → influence map (2D doubles), configurable step count
- [x] 6.2 Implement Connect Four kernel: spread along horizontal, vertical, both diagonals with attenuation
- [x] 6.3 Implement iterative diffusion (apply kernel 2 steps by default)
- [x] 6.4 Implement influence map → perceptual bit hash conversion
- [x] 6.5 Write tests: empty board → zero influence, single piece spreads in 4 directions, opponent pieces produce negative influence, identical boards → identical hashes

## 7. Similarity Search

- [x] 7.1 Implement `total_material` and `material_balance` computation from board
- [x] 7.2 Implement two-scalar pre-filter with configurable initial window (default ±2)
- [x] 7.3 Implement adaptive widening: double window when <5 candidates, stop at full scan
- [x] 7.4 Implement Hamming distance comparison on diffused bit hashes
- [x] 7.5 Implement search pipeline: exact Zobrist match first, then pre-filter → diffusion ranking
- [x] 7.6 Write tests: filter excludes distant states, widening triggers correctly, exact match ranks first, Hamming ordering

## 8. Move Selection Strategies

- [x] 8.1 Define `MoveSelectionStrategy` interface: takes weighted candidates + legal moves, returns chosen move
- [x] 8.2 Implement vote-by-move strategy: aggregate weights per move, select highest, tie-break by best individual weight
- [x] 8.3 Define influence overlay strategy interface: weighted-average candidate diffusion maps into target map, score legal moves by target map lookup
- [x] 8.4 Wire vote-by-move into `ConnectFourRules` as its move selection strategy
- [x] 8.5 Write tests: vote aggregation, single candidate, tie-breaking, influence overlay target map averaging, move scoring from target map

## 9. Clone Brain

- [x] 9.1 Implement `GameState` data model: canonical_board, zobrist_hash, diffused_hash, move_played, side, game_id, outcome, moves_to_end
- [x] 9.2 Implement `GameLog` in-memory store with add/query/backfill operations
- [x] 9.3 Implement outcome backfilling: set outcome and moves_to_end for all states in a completed game
- [x] 9.4 Implement move weighting: outcome score × efficiency score
- [x] 9.5 Implement fallback strategies: random, middle_focus, edge_focus, pile_focus for Connect Four
- [x] 9.6 Implement `CloneBrain.selectMove()`: search → weight → delegate to game's move selection strategy → narrate
- [x] 9.7 Write tests: weighting prefers wins over draws, fast wins over slow wins, strategy delegation, fallback triggers on empty data

## 10. Narration

- [x] 10.1 Implement narration template selection based on decision context (exact match, fuzzy match, multiple candidates, inverted data, fallback, all-losing)
- [x] 10.2 Implement template interpolation with concrete data (game ID, move count, outcome)
- [x] 10.3 Write tests: each decision context produces appropriate narration string, narration is never empty

## 11. Integration

- [x] 11.1 Wire full pipeline: rules → canonicalize → store → search → weight → select (via strategy) → narrate
- [x] 11.2 Write integration test: play a short Connect Four game, store states, query clone for a move, verify narration
- [x] 11.3 Run `dart analyze` clean, all tests pass
