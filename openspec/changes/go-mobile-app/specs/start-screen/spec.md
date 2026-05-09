## MODIFIED Requirements

### Requirement: Start screen launches the active game directly
The start screen SHALL launch directly into the active game (Go) when the user taps `New Game`. There SHALL NOT be a game picker.

#### Scenario: New Game starts a Go game
- **WHEN** the user taps `New Game` from the start screen
- **THEN** the app SHALL navigate to the game screen with a fresh 13×13 Go log

#### Scenario: Resume continues an in-progress Go game
- **WHEN** an in-progress Go game exists in persistence
- **THEN** the start screen SHALL surface a `Resume` action that navigates to the game screen with the persisted log
