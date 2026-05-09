## ADDED Requirements

### Requirement: Game states stored to SQLite on each move
The app SHALL write each new game state to SQLite immediately after it is created during play. The state SHALL include all fields from the engine's GameState model.

#### Scenario: Player makes a move
- **WHEN** the player drops a piece
- **THEN** the canonical game state SHALL be written to the game_states table

#### Scenario: Clone makes a move
- **WHEN** the clone plays a move
- **THEN** the canonical game state SHALL be written to the game_states table

### Requirement: Outcome backfill on game end
The app SHALL update all game states for the completed game with outcome and moves_to_end when the game ends. Inverted (opponent-perspective) states SHALL also be created and stored.

#### Scenario: Game ends in a win
- **WHEN** a game ends
- **THEN** all states for that game SHALL have outcome and moves_to_end updated in SQLite, and inverted states SHALL be inserted

### Requirement: Bulk load on startup
The app SHALL load all game states from SQLite into the engine's in-memory GameLog on app startup.

#### Scenario: App launches with existing data
- **WHEN** the app starts and the database has 500 game states
- **THEN** all 500 states SHALL be loaded into the in-memory GameLog before the start screen appears

#### Scenario: App launches with empty database
- **WHEN** the app starts for the first time
- **THEN** the in-memory GameLog SHALL be empty and the app SHALL proceed normally

### Requirement: Board stored as byte blob
The app SHALL store the canonical board as a raw byte blob (Int8List) in SQLite, not as JSON or text.

#### Scenario: Board round-trip
- **WHEN** a board is stored and then loaded
- **THEN** the loaded board SHALL be identical to the original
