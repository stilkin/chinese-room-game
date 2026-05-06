## ADDED Requirements

### Requirement: Deterministic hash table from game type
The system SHALL generate the Zobrist random number table from a deterministic PRNG seeded with the game type string. Each `(piece_value, row, col)` combination SHALL map to a unique random 64-bit integer.

#### Scenario: Same game type produces same table
- **WHEN** the Zobrist table is generated for "connect_four" twice
- **THEN** both tables SHALL be identical

#### Scenario: Different game types produce different tables
- **WHEN** Zobrist tables are generated for "connect_four" and "chess"
- **THEN** the tables SHALL differ

### Requirement: Board hash is XOR of occupied entries
The system SHALL compute a board's Zobrist hash as the XOR of all table entries corresponding to occupied squares on the board.

#### Scenario: Empty board hash is zero
- **WHEN** the board has no pieces
- **THEN** the Zobrist hash SHALL be 0

#### Scenario: Single piece hash
- **WHEN** a board has one piece of value +1 at position (row=0, col=3)
- **THEN** the Zobrist hash SHALL equal the table entry for (piece_value=1, row=0, col=3)

### Requirement: Incremental hash update
The system SHALL support updating the Zobrist hash incrementally when a move is applied, by XORing the table entry for the new piece's `(piece_value, row, col)`.

#### Scenario: Hash after one move
- **WHEN** a piece is placed on an empty board
- **THEN** the incrementally updated hash SHALL equal the hash computed from scratch on the resulting board

#### Scenario: Hash after multiple moves
- **WHEN** a sequence of moves is applied incrementally
- **THEN** the final incremental hash SHALL equal the full recomputation hash

### Requirement: Exact match lookup
The system SHALL use the Zobrist hash to find exact board matches in O(1) via hash map lookup.

#### Scenario: Identical board found
- **WHEN** the current board's Zobrist hash matches a stored state's hash
- **THEN** the stored state SHALL be returned as an exact match candidate

#### Scenario: No exact match
- **WHEN** no stored state has the same Zobrist hash as the current board
- **THEN** the exact match search SHALL return no results
