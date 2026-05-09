## Purpose
Defines how piece influence spreads across the board into a diffused image used for similarity matching.
## Requirements
### Requirement: DiffusionKernel interface
The system SHALL define a `DiffusionKernel` interface that takes a board and a step count, and returns an influence map (2D double array of the same dimensions as the board).

#### Scenario: Kernel returns correct dimensions
- **WHEN** a diffusion kernel is applied to a 7x6 board
- **THEN** the returned influence map SHALL be 7x6

#### Scenario: Empty board produces zero influence
- **WHEN** a diffusion kernel is applied to an empty board
- **THEN** all influence map values SHALL be 0.0

### Requirement: Connect Four diffusion spreads along winning directions
The Connect Four diffusion kernel SHALL spread each piece's value along the four winning directions: horizontal, vertical, ascending diagonal, and descending diagonal. Influence SHALL attenuate with distance from the source piece.

#### Scenario: Single piece radiates in four directions
- **WHEN** a board has one piece at (row=0, col=3) and diffusion is applied
- **THEN** the influence map SHALL have non-zero values extending horizontally, vertically, and diagonally from (0, 3), attenuating with distance

#### Scenario: Opponent pieces produce negative influence
- **WHEN** an opponent piece (value -1) is on the board
- **THEN** its diffused influence SHALL be negative, spreading along the same directions

#### Scenario: Multiple diffusion steps increase spread
- **WHEN** diffusion is applied with 2 steps vs 1 step
- **THEN** the 2-step map SHALL have non-zero values at greater distances from pieces

### Requirement: Diffusion depth is 2-3 steps
The system SHALL apply the diffusion kernel for 2-3 iterative steps. The exact step count SHALL be configurable per game type.

#### Scenario: Default Connect Four diffusion steps
- **WHEN** Connect Four diffusion is applied without override
- **THEN** it SHALL use 2 steps

### Requirement: Influence map quantizes to Int8 image
The system SHALL convert the diffused influence map (a `List<List<double>>`) to a row-major `Int8List` via `quantizeInfluenceMap`: each cell value is rounded and clamped to the signed-byte range `[-128, 127]`. The resulting image is stored alongside each `GameState` as its `diffusedImage` and is the input to L1 distance retrieval.

#### Scenario: Identical boards produce identical images
- **WHEN** two identical boards are diffused and quantized
- **THEN** the resulting `Int8List` images SHALL be byte-for-byte equal

#### Scenario: Similar boards produce small L1 distances
- **WHEN** two boards differ by one piece placement
- **THEN** the L1 distance between their diffused images SHALL be small relative to the total cell count

#### Scenario: Out-of-range values clamp to byte bounds
- **WHEN** an influence map cell holds a value outside `[-128, 127]`
- **THEN** `quantizeInfluenceMap` SHALL clamp it to the bound rather than overflow

