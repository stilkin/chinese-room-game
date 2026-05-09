## Purpose
Defines how the clone retrieves past states similar to the current position via L1 distance over diffused images.
## Requirements
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

