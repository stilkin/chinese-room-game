## ADDED Requirements

### Requirement: Fallback personality picker
The settings screen SHALL allow the player to select a fallback personality for the clone from: Random, Middle Focus, Edge Focus, Pile Focus. The selection SHALL persist across app restarts.

#### Scenario: Change personality
- **WHEN** the player selects "Edge Focus" as the fallback personality
- **THEN** the clone SHALL use edge-focus for future games when it has no relevant data

#### Scenario: Personality persists
- **WHEN** the player selects a personality and restarts the app
- **THEN** the selected personality SHALL still be active

#### Scenario: Default personality
- **WHEN** the app is launched for the first time
- **THEN** the fallback personality SHALL default to "Random"

### Requirement: Delete all game logs
The settings screen SHALL have a "Delete All Game Logs" button that erases all stored game states and resets the clone.

#### Scenario: Delete with confirmation
- **WHEN** the player taps "Delete All Game Logs"
- **THEN** a confirmation dialog SHALL appear before deleting

#### Scenario: Confirm delete
- **WHEN** the player confirms the deletion
- **THEN** all game states SHALL be removed from SQLite, the in-memory game log SHALL be cleared, and the games-played count SHALL reset to 0

#### Scenario: Cancel delete
- **WHEN** the player cancels the deletion dialog
- **THEN** no data SHALL be deleted
