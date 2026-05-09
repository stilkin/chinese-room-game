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
The start screen SHALL have a "New Game" button. When no ongoing game exists, tapping it SHALL navigate directly to the game screen with a fresh empty board. When an ongoing game exists, tapping it SHALL first show a confirmation dialog warning that the in-progress game will be discarded; on confirmation, the prior game's records SHALL be deleted before a fresh game is created so the database holds at most one ongoing game at a time.

#### Scenario: Tap new game with no ongoing game
- **WHEN** the player taps "New Game" and no ongoing game exists
- **THEN** the app SHALL navigate to the game screen with an empty board and the player's turn, and no confirmation dialog SHALL appear

#### Scenario: Tap new game with an ongoing game
- **WHEN** the player taps "New Game" and an ongoing game exists
- **THEN** a confirmation dialog SHALL appear warning that the in-progress game will be discarded

#### Scenario: Confirm discard
- **WHEN** the player confirms the dialog
- **THEN** the prior ongoing game's `games` row and all its `game_states` rows SHALL be deleted in a single transaction, then a fresh game SHALL start

#### Scenario: Cancel discard
- **WHEN** the player cancels the dialog
- **THEN** no records SHALL be deleted and no new game SHALL start; the player SHALL remain on the start screen

### Requirement: Settings button navigates to settings
The start screen SHALL have a "Settings" button that navigates to the settings screen.

#### Scenario: Tap settings
- **WHEN** the player taps "Settings"
- **THEN** the app SHALL navigate to the settings screen

### Requirement: Resume button surfaces the ongoing game
The start screen SHALL display a "Resume" button when the database has an ongoing game (a `games` row with `outcome IS NULL`). When no ongoing game exists, the Resume button SHALL be hidden so the start screen layout is unchanged for fresh installs.

#### Scenario: No ongoing game
- **WHEN** the start screen is shown and no ongoing game exists
- **THEN** the Resume button SHALL NOT be visible

#### Scenario: Ongoing game exists
- **WHEN** the start screen is shown and the single-slot ongoing game exists
- **THEN** the Resume button SHALL be visible

### Requirement: Resume rehydrates and navigates
Tapping Resume SHALL rehydrate the in-memory game state from the ongoing game's persisted moves and navigate to the game screen.

#### Scenario: Resume tap
- **WHEN** the player taps Resume
- **THEN** the app SHALL replay all stored moves for the ongoing game in chronological order, set the current side based on move count, then push the `/game` route

#### Scenario: Resume failure
- **WHEN** Resume fails because persisted state is corrupt or empty
- **THEN** the app SHALL delete the bad game record, surface a brief failure message, and remain on the start screen with the Resume button hidden
