## MODIFIED Requirements

### Requirement: Recent games loader returns per-game area and identity

The persistence layer SHALL expose a method `loadRecentGames(limit)` that returns up to `limit` completed games (rows with `outcome IS NOT NULL`), ordered most-recent-first. Each returned record SHALL include enough metadata to drive both the home-screen strip and the History list / Replay navigation:

| Field         | Type     | Source column   | Nullable |
|---------------|----------|-----------------|----------|
| `gameId`      | `String` | `game_id`       | no       |
| `startedAt`   | `int`    | `started_at`    | no       |
| `totalMoves`  | `int`    | `total_moves`   | no       |
| `outcome`     | `int`    | `outcome`       | no       |
| `playerArea`  | `int?`   | `player_area`   | yes      |
| `cloneArea`   | `int?`   | `clone_area`    | yes      |

#### Scenario: Recent games returned in newest-first order
- **WHEN** `loadRecentGames(limit: 100)` is called
- **THEN** the returned list SHALL be ordered by `started_at` descending
- **AND** the list length SHALL NOT exceed 100

#### Scenario: Resigned and legacy area columns surface as null
- **WHEN** a returned row has `player_area IS NULL` or `clone_area IS NULL` in the database
- **THEN** the corresponding `playerArea` / `cloneArea` fields SHALL be `null`
- **AND** no separate `end_reason` field is persisted in v1; the History UI uses the null-area state as the implicit "did not reach a territory verdict" signal (see `history-screen/spec.md`)

#### Scenario: In-progress games are excluded
- **WHEN** a `games` row has `outcome IS NULL`
- **THEN** it SHALL NOT appear in the returned list

## ADDED Requirements

### Requirement: Replay frame loader returns per-ply boards for a game

The persistence layer SHALL expose a method `loadGameForReplay(gameId)` that returns the per-ply replay data for a given completed game. Each frame SHALL include the stored board state and the move played at that ply. Frames SHALL be ordered by ascending ply.

#### Scenario: Loads frames in ply order
- **WHEN** `loadGameForReplay(gameId)` is called for a game with N stored plies
- **THEN** the returned list SHALL contain exactly N frames
- **AND** the frames SHALL be ordered by `ply` ascending

#### Scenario: Each frame carries board and move
- **WHEN** a frame at ply `k` is returned
- **THEN** the frame SHALL include the board state stored at ply `k`
- **AND** the frame SHALL include the `movePlayed` index for ply `k`

#### Scenario: Unknown gameId yields an empty list
- **WHEN** `loadGameForReplay(gameId)` is called with a `gameId` that has no matching rows
- **THEN** the returned list SHALL be empty

#### Scenario: Inversion is the caller's responsibility
- **WHEN** the called game has `outcome == -1` (bot won)
- **THEN** the returned boards SHALL still be in the winner-POV (sign-flipped) form as stored
- **AND** the caller (the Replay screen) SHALL apply `invertState` before display
