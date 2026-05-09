## ADDED Requirements

### Requirement: Query for the ongoing game
`DatabaseService` SHALL expose a method to find the ongoing game (the single `games` row with `outcome IS NULL`, given the single-slot policy). The method SHALL return the game id when one exists and a null marker when none does.

#### Scenario: No ongoing games
- **WHEN** the method is called and every `games` row has a non-null `outcome`
- **THEN** it SHALL return null

#### Scenario: Single ongoing game
- **WHEN** exactly one `games` row has `outcome IS NULL`
- **THEN** the method SHALL return that row's `game_id`

#### Scenario: Defensive behavior with multiple ongoing rows
- **WHEN** more than one `games` row has `outcome IS NULL` (e.g., from a prior app version that didn't enforce single-slot)
- **THEN** the method SHALL return the most recent by `started_at`; the next "New Game" confirm-and-delete restores the single-slot invariant

### Requirement: Load states for one game
`DatabaseService` SHALL expose a method to load all `game_states` rows for a given `game_id`, ordered by `ply ASC`, so the notifier can replay them.

#### Scenario: Load returns chronological moves
- **WHEN** the method is called with the id of a game that has 4 stored moves at plies 0..3
- **THEN** it SHALL return 4 `GameState` instances in plies 0..3 order

### Requirement: Delete a game and its states atomically
`DatabaseService` SHALL expose a method that removes a `games` row and all its `game_states` rows in a single SQLite transaction, supporting the single-slot replacement and the resume-failure recovery paths.

#### Scenario: Delete removes both tables
- **WHEN** the method is called with a game id whose `games` row exists and has 6 corresponding `game_states` rows
- **THEN** all 7 rows SHALL be removed and the operation SHALL be atomic — either all succeed or all roll back

#### Scenario: Delete is a no-op on missing id
- **WHEN** the method is called with a game id that no longer exists
- **THEN** the call SHALL succeed with zero rows affected
