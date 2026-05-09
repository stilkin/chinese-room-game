## REMOVED Requirements

### Requirement: Two-scalar pre-filter
**Reason**: Pre-filtering is now per-game via `CandidateFilter`. The universal `totalMaterial`/`materialBalance` filter is replaced by game-specific filters; for Connect Four the natural filter is ply-count window (which equals the old material window for Connect Four specifically, but the abstraction matters for chess and Go).
**Migration**: Existing call sites that passed `queryTotalMaterial` and `queryMaterialBalance` to `searchSimilar` now pass a `CandidateFilter` instead. `GameRules.prefilter(query)` returns the filter for the active game.

### Requirement: Adaptive widening
**Reason**: Widening logic stays — but the *shape* of widening is now game-specific (the filter returns its own widened variant). The mechanism survives; the implementation moves into the filter.
**Migration**: `searchSimilar` still drives the widening loop, but each iteration calls `filter.widened()` to get a more permissive filter.

### Requirement: Ranking by Hamming distance
**Reason**: Hamming distance over a thresholded bit-hash discards the diffused map's gradient information. With the storage-per-row cost now well-understood, switching to L1 distance over the quantized diffused image preserves magnitude (a queen swap and a pawn swap produce different distance contributions, matching the project's piece-value spacing intent).
**Migration**: Stored rows now carry `diffused_image` (Int8List, one byte per cell) instead of `diffused_hash` (packed bit-hash). The matcher computes `l1Distance(query, candidate)` instead of `hammingDistance(query, candidate)`.

## ADDED Requirements

### Requirement: Per-game candidate pre-filter
The system SHALL pre-filter candidate states using a game-specific `CandidateFilter` returned by `GameRules.prefilter(query)`. The filter exposes two methods: `bool matches(GameState candidate)` decides whether a candidate passes; `CandidateFilter widened()` returns a strictly more permissive filter for adaptive widening.

#### Scenario: Connect Four uses ply-window filter
- **WHEN** the active game is Connect Four and the prefilter is requested with a query at ply 8
- **THEN** the returned filter SHALL accept candidates with ply in `[6, 10]` (window of `±2` by default) and reject the rest

#### Scenario: Filter widens monotonically
- **WHEN** `widened()` is called on a filter
- **THEN** the returned filter SHALL accept every candidate the previous filter accepted, plus at least some candidates the previous filter rejected (when such candidates exist in the data)

#### Scenario: Adaptive widening loop
- **WHEN** `searchSimilar` is invoked and the initial filter passes fewer than `minCandidates` candidates
- **THEN** the search SHALL replace the filter with `filter.widened()` and re-filter
- **AND** the search SHALL repeat until at least `minCandidates` candidates pass or `maxWidens` rounds have elapsed
- **AND** if `maxWidens` rounds pass without enough candidates, the search SHALL fall through and use the entire candidate pool

### Requirement: L1 distance over quantized diffused images
The system SHALL rank candidates by L1 distance between their stored `diffusedImage` (Int8List) and the query's diffused image. L1 distance is `sum_i |a[i] - b[i]|` over all `i` in `[0, length)`. Lower distance means higher similarity.

#### Scenario: Identical images have zero distance
- **WHEN** the query and candidate have byte-equal `diffusedImage` values
- **THEN** the L1 distance SHALL be `0`

#### Scenario: Single-cell magnitude difference
- **WHEN** the query and candidate differ in exactly one cell, by magnitude `k` (e.g. query has `5` and candidate has `-3` → magnitude `8`)
- **THEN** the L1 distance SHALL be `k`

#### Scenario: Rank lower distances first
- **WHEN** candidate A has L1 distance 12 and candidate B has L1 distance 30
- **THEN** the search SHALL return A before B

### Requirement: Quantized diffused image is the stored fingerprint
The system SHALL produce each row's matching fingerprint by diffusing the row's board (via the game's `DiffusionKernel`), then quantizing the resulting real-valued influence map to `Int8List` via `quantizeInfluenceMap`. Quantization rounds each cell to the nearest integer and clamps to `[-128, 127]`.

#### Scenario: Fingerprint length matches board cell count
- **WHEN** a board with `r × c` cells is diffused and quantized
- **THEN** the resulting `Int8List` SHALL have length `r × c`

#### Scenario: Empty board has zero fingerprint
- **WHEN** the input board is all zeros
- **THEN** the resulting fingerprint SHALL be all zeros (length `r × c`)

#### Scenario: Quantization clamps out-of-range values
- **WHEN** an influence cell has value `200.0`
- **THEN** the quantized value SHALL be `127` (Int8 max)
- **AND** when an influence cell has value `-150.0`, the quantized value SHALL be `-128` (Int8 min)
