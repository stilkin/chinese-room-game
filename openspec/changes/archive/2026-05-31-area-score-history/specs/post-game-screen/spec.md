## ADDED Requirements

### Requirement: Area-score readout

The post-game screen SHALL display the final Chinese-style area score for both sides on a single line below the W/L verdict, computed live from `GoRules.areaScore(notifier.displayBoard)`. The line SHALL be suppressed when the active game's rules are not `GoRules` or when both areas are zero (e.g., resign on an empty board).

#### Scenario: Two-pass Go game shows area
- **WHEN** a Go game ends via two consecutive passes and the post-game screen is displayed
- **THEN** the screen SHALL display "AREA  ·  YOU X  ·  CLONE Y" using the player's and clone's areas

#### Scenario: Resign on a non-empty board shows area
- **WHEN** the player resigns after stones have been placed
- **THEN** the post-game screen SHALL display the area readout computed from the live board at resign time
- **AND** the persisted `games` row's `player_area` / `clone_area` SHALL still be NULL (the readout is computed; not loaded)

#### Scenario: Resign on an empty board suppresses the line
- **WHEN** the player resigns before any stones have been placed
- **AND** both `score.white` and `score.black` are zero
- **THEN** the post-game screen SHALL NOT render the area line

#### Scenario: Non-Go game suppresses the line
- **WHEN** the active rules are not `GoRules`
- **THEN** the post-game screen SHALL NOT render the area line
