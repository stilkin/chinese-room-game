## ADDED Requirements

### Requirement: Board is a 2D signed integer array
The system SHALL represent all game boards as `List<List<int>>` where values are signed integers. Zero represents an empty cell. Positive values represent the current player's pieces, negative values represent the opponent's pieces.

#### Scenario: Empty Connect Four board
- **WHEN** a new Connect Four board is created
- **THEN** it SHALL be 7 columns by 6 rows with all cells set to 0

#### Scenario: Chess board piece values
- **WHEN** a chess board is represented
- **THEN** piece values SHALL be: pawn=1, knight=3, bishop=3, rook=5, queen=9, king=20, with negative values for opponent pieces

### Requirement: Board dimensions are game-defined
The system SHALL allow each game type to define its own board dimensions via the `GameRules` interface.

#### Scenario: Different game board sizes
- **WHEN** the engine creates boards for different games
- **THEN** Connect Four SHALL be 7x6, Othello 8x8, Chess 8x8, Go 19x19

### Requirement: Board supports flat view for bulk operations
The system SHALL provide an `Int8List` flat view of the board for use in hashing, diffusion, and comparison operations.

#### Scenario: Flat view matches 2D layout
- **WHEN** a board with known values is converted to its flat view
- **THEN** the flat view SHALL contain the same values in row-major order
