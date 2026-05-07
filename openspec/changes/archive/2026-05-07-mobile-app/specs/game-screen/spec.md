## ADDED Requirements

### Requirement: Board rendered with CustomPainter
The game screen SHALL render the Connect Four board (7 columns × 6 rows) using a CustomPainter. Empty cells, player pieces, and clone pieces SHALL be visually distinct.

#### Scenario: Empty board display
- **WHEN** a new game starts
- **THEN** the board SHALL display a 7×6 grid with all empty cells

#### Scenario: Pieces are visually distinct
- **WHEN** both player and clone have pieces on the board
- **THEN** player pieces and clone pieces SHALL be rendered in different colors

### Requirement: Tap to drop piece
The player SHALL tap a column to drop a piece. The piece SHALL land in the lowest empty row of that column.

#### Scenario: Tap valid column
- **WHEN** the player taps column 3 during their turn and column 3 is not full
- **THEN** a player piece SHALL appear in the lowest empty row of column 3

#### Scenario: Tap full column
- **WHEN** the player taps a column that is full
- **THEN** nothing SHALL happen and it SHALL remain the player's turn

#### Scenario: Tap during clone's turn
- **WHEN** the player taps the board while the clone is thinking
- **THEN** the tap SHALL be ignored

### Requirement: Clone narration display
The game screen SHALL display the clone's narration text after each clone move. The narration SHALL be prominently visible, not buried below the fold.

#### Scenario: Clone makes a move
- **WHEN** the clone selects and plays a move
- **THEN** the narration text from the clone brain SHALL be displayed on screen

#### Scenario: First move of game
- **WHEN** a new game starts and it is the player's turn
- **THEN** the narration area SHALL be empty or show a neutral message

### Requirement: Turn indicator
The game screen SHALL indicate whose turn it is (player or clone).

#### Scenario: Player's turn
- **WHEN** it is the player's turn
- **THEN** the screen SHALL indicate it is the player's turn

#### Scenario: Clone's turn
- **WHEN** it is the clone's turn
- **THEN** the screen SHALL indicate the clone is thinking

### Requirement: Game end detection navigates to post-game
The game screen SHALL detect when the game ends (win or draw) and navigate to the post-game screen.

#### Scenario: Player wins
- **WHEN** the player completes four in a row
- **THEN** the app SHALL navigate to the post-game screen with outcome "You win!"

#### Scenario: Clone wins
- **WHEN** the clone completes four in a row
- **THEN** the app SHALL navigate to the post-game screen with outcome "Clone wins!"

#### Scenario: Draw
- **WHEN** the board is full with no winner
- **THEN** the app SHALL navigate to the post-game screen with outcome "Draw!"
