## ADDED Requirements

### Requirement: Per-game area score persistence

The `games` table SHALL include nullable `player_area INTEGER` and `clone_area INTEGER` columns. When a Go game completes via two consecutive passes (or a single pass plus the agree-to-pass override), the system SHALL compute Chinese-style area for both sides via `GoRules.areaScore` and persist them against the game's row. The columns SHALL remain NULL for any game that ended via resign, for any non-Go game, and for any row created prior to schema v6.

#### Scenario: Two-pass termination persists area
- **WHEN** a Go game ends via two consecutive passes
- **THEN** the system SHALL update the `games` row's `player_area` and `clone_area` to the values returned by `GoRules.areaScore` on the final board, mapped as `player_area = white` and `clone_area = black`

#### Scenario: Resign leaves area NULL
- **WHEN** the player resigns mid-game
- **THEN** the `games` row's `outcome` SHALL be set to `-1` (existing behaviour) and both `player_area` and `clone_area` SHALL remain NULL

#### Scenario: Pre-v6 games surface as legacy rows
- **WHEN** a database is upgraded from schema v5 to v6
- **THEN** existing `games` rows SHALL retain their outcome and ply data unchanged
- **AND** their `player_area` and `clone_area` columns SHALL be NULL

### Requirement: Recent games loader returns area data

`DatabaseService` SHALL expose a method that loads the most recent N completed games' outcomes alongside their persisted area scores. The method SHALL order rows newest-first and SHALL surface the area columns as nullable so callers can distinguish real-area rows from DNF / legacy rows.

#### Scenario: Order is most-recent-first
- **WHEN** the method is called and the database has 12 completed games
- **THEN** the returned list SHALL contain the games in descending `started_at` order

#### Scenario: NULL area surfaces as null record fields
- **WHEN** a row's `player_area` and `clone_area` are NULL (resigned or legacy game)
- **THEN** the corresponding record's `playerArea` and `cloneArea` SHALL be `null`

#### Scenario: Limit honoured
- **WHEN** the method is called with `limit: 100`
- **THEN** at most 100 rows SHALL be returned

## MODIFIED Requirements

### Requirement: Outcome backfill on game end

The app SHALL update all stored rows for the completed game with `outcome` (per row, derived from ply parity and the winner) and `moves_to_end`. The perspective alignment for the finished game (winner-POV whole-game flip on bot wins, store-as-is on player wins or draws) SHALL be applied at backfill time as defined in the canonicalization spec. For Go games that terminate naturally (not via resign), the `games` row SHALL additionally record `player_area` and `clone_area` per the Per-game area score persistence requirement.

#### Scenario: Game ends in a win
- **WHEN** a game ends with a winner
- **THEN** every row of that game SHALL have `outcome` set in SQLite (even-ply rows take the player-side outcome, odd-ply rows take its negation) and `moves_to_end` set to `total_moves - ply`, and the winner-POV alignment SHALL be persisted (rows replaced with their inverted form on a bot win)
- **AND** for Go games, the `games` row SHALL have `player_area` and `clone_area` populated from `GoRules.areaScore` on the final board

#### Scenario: Game ends in a draw
- **WHEN** a game ends in a draw
- **THEN** every row of that game SHALL have `outcome=0` and `moves_to_end` set; rows SHALL remain in display perspective (no flip)
- **AND** for Go games, the `games` row SHALL have `player_area` and `clone_area` populated (equal values for a true area-tie)

#### Scenario: Game ends via resign
- **WHEN** the player resigns
- **THEN** the `games` row's `outcome` SHALL be set to `-1` and `final_ply` SHALL reflect the resign-time ply
- **AND** the `game_states` rows for that game SHALL be deleted (existing behaviour — no CBR pollution from resigned positions)
- **AND** the `games` row's `player_area` and `clone_area` SHALL remain NULL
