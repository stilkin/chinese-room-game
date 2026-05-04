## ADDED Requirements

### Requirement: Start screen displays games played count
The start screen SHALL display the total number of completed games.

#### Scenario: No games played yet
- **WHEN** the app launches for the first time
- **THEN** the start screen SHALL display "0 games played"

#### Scenario: Games exist
- **WHEN** the player has completed 47 games
- **THEN** the start screen SHALL display "47 games played"

### Requirement: New game button starts a game
The start screen SHALL have a "New Game" button that navigates to the game screen and starts a fresh Connect Four game.

#### Scenario: Tap new game
- **WHEN** the player taps "New Game"
- **THEN** the app SHALL navigate to the game screen with an empty board and the player's turn

### Requirement: Settings button navigates to settings
The start screen SHALL have a "Settings" button that navigates to the settings screen.

#### Scenario: Tap settings
- **WHEN** the player taps "Settings"
- **THEN** the app SHALL navigate to the settings screen
