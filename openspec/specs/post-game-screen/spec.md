## ADDED Requirements

### Requirement: Outcome display
The post-game screen SHALL display the game outcome: "You win!", "Clone wins!", or "Draw!"

#### Scenario: Player won
- **WHEN** the player won the game
- **THEN** the screen SHALL display "You win!"

#### Scenario: Clone won
- **WHEN** the clone won the game
- **THEN** the screen SHALL display "Clone wins!"

#### Scenario: Draw
- **WHEN** the game ended in a draw
- **THEN** the screen SHALL display "Draw!"

### Requirement: Clone final thought
The post-game screen SHALL display the clone's narration for its last move as a "final thought."

#### Scenario: Clone's last narration shown
- **WHEN** the post-game screen is displayed
- **THEN** the clone's narration from its last move in the game SHALL be visible

### Requirement: Total games played
The post-game screen SHALL display the updated total number of completed games.

#### Scenario: Games count incremented
- **WHEN** the post-game screen is shown after the player's 10th game
- **THEN** the total games played SHALL display "10"

### Requirement: Play again navigation
The post-game screen SHALL have a "Play Again" button that starts a new game.

#### Scenario: Tap play again
- **WHEN** the player taps "Play Again"
- **THEN** the app SHALL navigate to the game screen with a fresh empty board

### Requirement: Back to home navigation
The post-game screen SHALL have a "Home" button that returns to the start screen.

#### Scenario: Tap home
- **WHEN** the player taps "Home"
- **THEN** the app SHALL navigate to the route `/` (the start screen)
