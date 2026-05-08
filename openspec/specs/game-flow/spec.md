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

### Requirement: Resume rebuilds state from persisted moves
The `GameNotifier` SHALL expose a `resumeLastGame()` entry point that reconstructs the display board, ply counter, current side, and game id from the ongoing game's persisted `game_states` rows. Rehydration SHALL replay moves via `GameRules.applyMove` rather than reading the stored canonical boards.

#### Scenario: Resume rebuilds the display board
- **WHEN** `resumeLastGame()` is called and the ongoing game has 5 stored moves
- **THEN** `displayBoard` SHALL contain those 5 pieces in their played positions, `ply` SHALL be 5, and `currentSide` SHALL reflect whose turn comes next (player if even ply count, clone otherwise)

#### Scenario: Resume sets game id
- **WHEN** `resumeLastGame()` is called for a game with id `G`
- **THEN** `gameId` SHALL be `G` so subsequent moves and the eventual backfill attribute to the same game

#### Scenario: Resume does not duplicate persistence
- **WHEN** `resumeLastGame()` replays moves
- **THEN** the brain's `createState` and `DatabaseService.insertGameState` SHALL NOT be called for the replayed moves; the in-memory `GameLog` already contains them from the startup load

#### Scenario: Resumed game ends normally
- **WHEN** the player or clone makes a winning move after resume
- **THEN** the standard end-of-game flow SHALL run, backfilling outcomes and applying winner-POV inversion when the bot wins

### Requirement: Single-slot enforcement when starting new games
The `GameNotifier`'s `startNewGame` flow SHALL ensure at most one ongoing game exists. When invoked while an ongoing game already exists, the prior game's persisted records SHALL be deleted before the new game is created. The caller SHALL ensure user confirmation has been obtained before calling `startNewGame` in this state.

#### Scenario: New game replaces the prior ongoing game
- **WHEN** `startNewGame` is called and an ongoing game exists
- **THEN** the prior game's records SHALL be deleted (single transaction) before the new `games` row is inserted, so the database holds exactly one ongoing game afterward
