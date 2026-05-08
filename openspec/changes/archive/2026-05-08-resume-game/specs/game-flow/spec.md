## ADDED Requirements

### Requirement: Resume rebuilds state from persisted moves
The `GameNotifier` SHALL expose a `resumeLastGame()` entry point that reconstructs the display board, ply counter, current side, and game id from the ongoing game's persisted `game_states` rows. Rehydration SHALL replay moves via `GameRules.applyMove` rather than reading the stored canonical boards, since the stored boards are from each mover's perspective and not directly the display board.

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
- **THEN** the standard end-of-game flow SHALL run, backfilling outcomes per side and applying loss-inversion when the player wins

### Requirement: Single-slot enforcement when starting new games
The `GameNotifier`'s `startNewGame` flow SHALL ensure at most one ongoing game exists. When invoked while an ongoing game already exists, the prior game's persisted records SHALL be deleted before the new game is created. The caller SHALL ensure user confirmation has been obtained before calling `startNewGame` in this state (the start-screen UI shows the dialog; `PostGameScreen`'s "Play Again" never triggers this path because the prior game is no longer ongoing by the time it ran).

#### Scenario: New game replaces the prior ongoing game
- **WHEN** `startNewGame` is called and an ongoing game exists
- **THEN** the prior game's records SHALL be deleted (single transaction) before the new `games` row is inserted, so the database holds exactly one ongoing game afterward
