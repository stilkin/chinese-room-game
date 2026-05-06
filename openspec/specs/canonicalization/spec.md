## ADDED Requirements

### Requirement: Mirror normalization
The system SHALL canonicalize boards by comparing the Zobrist hash of the left half to the right half. If the left half's hash is lower, the board SHALL be mirrored horizontally before storage.

#### Scenario: Board with higher-hash left half stored as-is
- **WHEN** a board's left half has a higher Zobrist hash than the right half
- **THEN** the board SHALL be stored without mirroring

#### Scenario: Board with lower-hash left half gets mirrored
- **WHEN** a board's left half has a lower Zobrist hash than the right half
- **THEN** the board SHALL be mirrored horizontally before storage

#### Scenario: Symmetric board stored consistently
- **WHEN** a board is perfectly symmetric (left equals right)
- **THEN** the board SHALL be stored in a deterministic canonical form

### Requirement: Perspective normalization
The system SHALL always store board states from the perspective of the side to move. Piece signs SHALL be flipped if the stored state was originally from the opponent's perspective.

#### Scenario: Side-to-move perspective stored directly
- **WHEN** a board state is recorded for the side that just moved
- **THEN** piece values SHALL be negated so the next-to-move side's pieces are positive

### Requirement: Loss inversion
The system SHALL store every lost game as a won game from the opponent's perspective by negating all piece values and recording a win outcome. This doubles the effective training data per game.

#### Scenario: Player loses a game
- **WHEN** a game ends in a loss for the player
- **THEN** each state SHALL also be stored with negated board values and outcome=win

#### Scenario: Inverted state is independently canonical
- **WHEN** a loss-inverted state is created
- **THEN** it SHALL undergo mirror normalization and perspective normalization independently

### Requirement: Canonicalization happens at write time
All canonicalization (mirror, perspective, inversion) SHALL be applied before a state is stored. Query-time canonicalization SHALL only be applied to the current board being searched for.

#### Scenario: Stored state is already canonical
- **WHEN** a state is retrieved from storage
- **THEN** no further canonicalization SHALL be needed for comparison
