## Purpose
Defines Connect Four-specific rules, win detection, and per-game retrieval and scoring helpers.

## Requirements

### Requirement: Legal move generation
The system SHALL return a list of columns (0-6) that are not full as legal moves for the current position.

#### Scenario: All columns available on empty board
- **WHEN** the board is empty
- **THEN** legal moves SHALL be [0, 1, 2, 3, 4, 5, 6]

#### Scenario: Full column excluded
- **WHEN** column 3 has 6 pieces (full)
- **THEN** column 3 SHALL NOT appear in the legal moves list

#### Scenario: No legal moves on full board
- **WHEN** all columns are full
- **THEN** legal moves SHALL be an empty list

### Requirement: Piece dropping applies gravity
The system SHALL place a piece in the lowest empty row of the chosen column when a move is applied.

#### Scenario: Drop into empty column
- **WHEN** a piece is dropped into an empty column
- **THEN** it SHALL land in row 0 (bottom)

#### Scenario: Drop onto existing pieces
- **WHEN** a piece is dropped into a column with 3 existing pieces
- **THEN** it SHALL land in row 3 (on top of the stack)

### Requirement: Win detection along four directions
The system SHALL detect a win when four consecutive pieces of the same side exist horizontally, vertically, or along either diagonal.

#### Scenario: Horizontal win
- **WHEN** player 1 has four consecutive pieces in a row
- **THEN** the system SHALL report a win for player 1

#### Scenario: Vertical win
- **WHEN** player 1 has four consecutive pieces in a column
- **THEN** the system SHALL report a win for player 1

#### Scenario: Diagonal win
- **WHEN** player 1 has four consecutive pieces along a diagonal (ascending or descending)
- **THEN** the system SHALL report a win for player 1

#### Scenario: No win with three in a row
- **WHEN** the longest consecutive sequence for both players is 3
- **THEN** the system SHALL NOT report a win

### Requirement: Draw detection
The system SHALL detect a draw when the board is full and no player has won.

#### Scenario: Full board with no winner
- **WHEN** all 42 cells are occupied and no four-in-a-row exists
- **THEN** the system SHALL report a draw
