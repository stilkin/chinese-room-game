## Purpose
Defines the local storage schema and read/write contract for completed games.
## Requirements
### Requirement: Game states stored to SQLite on each move
The app SHALL write each new game state to SQLite immediately after it is created during play. The state SHALL include all fields from the engine's GameState model.

#### Scenario: Player makes a move
- **WHEN** the player drops a piece
- **THEN** the canonical game state SHALL be written to the game_states table

#### Scenario: Clone makes a move
- **WHEN** the clone plays a move
- **THEN** the canonical game state SHALL be written to the game_states table

### Requirement: Outcome backfill on game end
The app SHALL update all stored rows for the completed game with `outcome` (per row, derived from ply parity and the winner) and `moves_to_end`. The perspective alignment for the finished game (winner-POV whole-game flip on bot wins, store-as-is on player wins or draws) SHALL be applied at backfill time as defined in the canonicalization spec.

#### Scenario: Game ends in a win
- **WHEN** a game ends with a winner
- **THEN** every row of that game SHALL have `outcome` set in SQLite (even-ply rows take the player-side outcome, odd-ply rows take its negation) and `moves_to_end` set to `total_moves - ply`, and the winner-POV alignment SHALL be persisted (rows replaced with their inverted form on a bot win)

#### Scenario: Game ends in a draw
- **WHEN** a game ends in a draw
- **THEN** every row of that game SHALL have `outcome=0` and `moves_to_end` set; rows SHALL remain in display perspective (no flip)

### Requirement: Bulk load on startup
The app SHALL load all game states from SQLite into the engine's in-memory GameLog on app startup.

#### Scenario: App launches with existing data
- **WHEN** the app starts and the database has 500 game states
- **THEN** all 500 states SHALL be loaded into the in-memory GameLog before the start screen appears

#### Scenario: App launches with empty database
- **WHEN** the app starts for the first time
- **THEN** the in-memory GameLog SHALL be empty and the app SHALL proceed normally

### Requirement: Board stored as byte blob
The app SHALL store both the canonical board (`board` BLOB) and the quantized diffused image (`diffused_image` BLOB) as raw byte blobs (Int8List) in SQLite, not as JSON or text.

#### Scenario: Board round-trip
- **WHEN** a board is stored and then loaded
- **THEN** the loaded board SHALL be byte-identical to the original

#### Scenario: Diffused image round-trip
- **WHEN** a `diffusedImage` Int8List is stored and then loaded
- **THEN** the loaded image SHALL be byte-identical to the original (length matches `rows × cols`; every cell value preserved within Int8 range)

### Requirement: Query for the ongoing game
`DatabaseService` SHALL expose a method to find the ongoing game (the single `games` row with `outcome IS NULL`, given the single-slot policy). The method SHALL return the game id when one exists and a null marker when none does.

#### Scenario: No ongoing games
- **WHEN** the method is called and every `games` row has a non-null `outcome`
- **THEN** it SHALL return null

#### Scenario: Single ongoing game
- **WHEN** exactly one `games` row has `outcome IS NULL`
- **THEN** the method SHALL return that row's `game_id`

#### Scenario: Defensive behavior with multiple ongoing rows
- **WHEN** more than one `games` row has `outcome IS NULL`
- **THEN** the method SHALL return the most recent by `started_at`

### Requirement: Load states for one game
`DatabaseService` SHALL expose a method to load all `game_states` rows for a given `game_id`, ordered by `ply ASC`, so the notifier can replay them.

#### Scenario: Load returns chronological moves
- **WHEN** the method is called with the id of a game that has 4 stored moves at plies 0..3
- **THEN** it SHALL return 4 `GameState` instances in plies 0..3 order

### Requirement: Delete a game and its states atomically
`DatabaseService` SHALL expose a method that removes a `games` row and all its `game_states` rows in a single SQLite transaction.

#### Scenario: Delete removes both tables
- **WHEN** the method is called with a game id whose `games` row exists and has 6 corresponding `game_states` rows
- **THEN** all 7 rows SHALL be removed and the operation SHALL be atomic

#### Scenario: Delete is a no-op on missing id
- **WHEN** the method is called with a game id that no longer exists
- **THEN** the call SHALL succeed with zero rows affected

### Requirement: Schema v3 stores diffused images, not bit-hashes
The `game_states` table SHALL include a `diffused_image BLOB NOT NULL` column. This replaces the v2 schema's `diffused_hash BLOB NOT NULL` column. Schema bump from v2 to v3 SHALL drop and recreate `game_states` with the new shape, and SHALL clear the `games` table. Existing v1 → v2 migration logic SHALL remain in place for legacy upgrades that may still hit it.

#### Scenario: Fresh install creates v3 schema directly
- **WHEN** a fresh install opens the database
- **THEN** `game_states` SHALL be created with the `diffused_image BLOB NOT NULL` column and no `diffused_hash` column

#### Scenario: Upgrade from v2 wipes game_states
- **WHEN** the database is opened with `oldVersion = 2` and `newVersion = 3`
- **THEN** `game_states` SHALL be dropped and recreated with the v3 shape, and the `games` table SHALL be cleared (`DELETE FROM games`); `clone_config` SHALL NOT be touched

#### Scenario: V3 schema preserves indices
- **WHEN** `game_states` is created at v3
- **THEN** the table SHALL have `idx_game_states_game_id` on `game_id` and `idx_game_states_filter` on `(total_material, material_balance)` for compatibility with future per-game filters

