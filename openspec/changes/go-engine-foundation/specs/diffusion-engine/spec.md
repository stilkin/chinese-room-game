## ADDED Requirements

### Requirement: Go diffusion spreads along orthogonal lines
The Go diffusion kernel SHALL spread each stone's value along the four orthogonal directions (north, south, east, west). Influence SHALL attenuate with distance from the source stone. Diagonal neighbours SHALL NOT receive direct influence — Go's connectivity is 4-neighbour, and diagonal leakage would over-claim corner regions.

#### Scenario: Single stone radiates orthogonally
- **WHEN** a board has one stone at `(r=6, c=6)` on a 13×13 Go board and diffusion is applied
- **THEN** the influence map SHALL have non-zero values along row 6 and column 6, attenuating with distance
- **AND** diagonal cells (e.g. `(5, 5)`, `(7, 7)`) SHALL receive zero direct contribution from that stone

#### Scenario: Opposing stones produce negative influence
- **WHEN** an opposing stone (value `-1`) is on the board
- **THEN** its diffused influence SHALL be negative, spreading along the same four orthogonal directions

### Requirement: Default Go diffusion depth is 2 steps
The Go diffusion kernel SHALL apply for 2 iterative steps by default, matching the Connect Four kernel's depth. The exact step count remains configurable per construction.

#### Scenario: Default Go diffusion uses 2 steps
- **WHEN** `GoDiffusionKernel().diffuse(board)` is called without override
- **THEN** the kernel SHALL apply 2 steps
