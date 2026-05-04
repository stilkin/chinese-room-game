## ADDED Requirements

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

### Requirement: Influence map converts to bit hash
The system SHALL convert the diffused influence map to a perceptual-style bit hash suitable for Hamming distance comparison. Positive influence maps to 1-bits, non-positive maps to 0-bits.

#### Scenario: Identical boards produce identical hashes
- **WHEN** two identical boards are diffused and hashed
- **THEN** the resulting bit hashes SHALL be identical

#### Scenario: Similar boards produce similar hashes
- **WHEN** two boards differ by one piece placement
- **THEN** the Hamming distance between their diffused hashes SHALL be small relative to the total hash length
