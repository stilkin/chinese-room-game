## ADDED Requirements

### Requirement: Human always plays first
The player SHALL always be player 1 (positive piece values) and take the first turn in every game.

#### Scenario: New game starts
- **WHEN** a new game begins
- **THEN** it SHALL be the player's turn with an empty board

### Requirement: Alternating turns
Turns SHALL alternate between the player and the clone. The player acts via tap input; the clone acts automatically via the clone brain.

#### Scenario: After player move
- **WHEN** the player places a piece
- **THEN** the clone SHALL take its turn automatically

#### Scenario: After clone move
- **WHEN** the clone places a piece and the game is not over
- **THEN** it SHALL become the player's turn

### Requirement: Clone turn triggers brain search
On the clone's turn, the app SHALL invoke the clone brain's move selection, which searches the game log, weights candidates, selects a move, and produces narration.

#### Scenario: Clone has data
- **WHEN** the clone's turn arrives and the game log has relevant states
- **THEN** the clone brain SHALL search, select a weighted move, and return narration

#### Scenario: Clone has no data
- **WHEN** the clone's turn arrives and no relevant states exist
- **THEN** the clone brain SHALL use the configured fallback personality and return fallback narration

### Requirement: Game lifecycle creates a game record
The app SHALL create a new game record when a game starts and update it with the outcome when the game ends.

#### Scenario: New game record
- **WHEN** the player starts a new game
- **THEN** a new game record SHALL be created with a unique game_id

#### Scenario: Game completion
- **WHEN** a game ends (win or draw)
- **THEN** the game record SHALL be updated with the outcome and total moves

### Requirement: State managed via ChangeNotifier
A single GameNotifier SHALL own the current game state (board, turn, outcome, narration). UI screens SHALL rebuild in response to notifications.

#### Scenario: Board update triggers rebuild
- **WHEN** a piece is placed on the board
- **THEN** the GameNotifier SHALL notify listeners and the game screen SHALL reflect the updated board
