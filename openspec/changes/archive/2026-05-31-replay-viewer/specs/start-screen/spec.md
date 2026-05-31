## MODIFIED Requirements

### Requirement: Recent games strip shows per-game area proportions

The start screen SHALL display recent completed games as a vertical strip of horizontal proportion bars, one bar per game, ordered most-recent-on-top. Each bar's interior SHALL show the player's area (ivory) and the clone's area (near-black) as a left-to-right proportion of the total area; each bar SHALL have small endcaps on both ends coloured to match the winning side. The strip SHALL be hard-capped at the most recent 100 completed games. **The strip SHALL be a tap target: tapping anywhere on the strip's painted region SHALL navigate to the History screen.**

#### Scenario: Player wins by a wide margin
- **WHEN** a completed game's `playerArea / (playerArea + cloneArea)` is 0.85
- **THEN** the corresponding row SHALL render with ~85% ivory and ~15% near-black
- **AND** both endcaps SHALL be ivory

#### Scenario: Clone wins by a small margin
- **WHEN** a completed game's `playerArea / (playerArea + cloneArea)` is 0.48
- **THEN** the corresponding row SHALL render with ~48% ivory and ~52% near-black
- **AND** both endcaps SHALL be near-black

#### Scenario: Draw
- **WHEN** a completed game ends with `outcome == 0`
- **THEN** both endcaps SHALL be cream-amber (the line colour)

#### Scenario: Resigned / DNF / legacy games render as muted rows
- **WHEN** a row has `playerArea == null` or `cloneArea == null` (resigned, pre-v6, or any other path that leaves area NULL)
- **THEN** the row SHALL render as a solid muted-grey bar with no proportion split and no endcaps

#### Scenario: At most 100 rows
- **WHEN** the database has more than 100 completed games
- **THEN** the strip SHALL render only the most recent 100

#### Scenario: Most recent on top
- **WHEN** the strip is shown
- **THEN** the topmost row SHALL correspond to the most-recently-completed game

#### Scenario: Tap opens history screen
- **WHEN** the player taps anywhere on the strip's painted region
- **THEN** the app SHALL navigate to the History screen
- **AND** this SHALL hold even on a fresh install (zero rows): the tap on the empty painted region SHALL still navigate, and the History screen SHALL show its empty state
