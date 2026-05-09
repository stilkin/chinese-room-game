## MODIFIED Requirements

### Requirement: Cold-start fallback personalities

The system SHALL support fallback strategies that fire when the clone has no relevant data (no candidates found, all candidates fall outside the prefilter window, or the all-losing guard rejects the chosen move). For Connect Four, the engine SHALL provide the following fallback strategies:

- `random` — pick a uniformly random legal column. *User-facing label: "Chaotic".*
- `middleFocus` — pick the legal column closest to the middle. *Benchmark-only; not surfaced via configuration.*
- `pileFocus` — pick the legal column with the highest pile of pieces (any colour); tie-break by closeness to middle. *User-facing label: "Stacker".*
- `ownPileAdjacent` — pick a column adjacent to the tallest stack of own (`+1`) pieces; tie-break by closeness to middle. *User-facing label: "Builder". Default for new installs.*
- `greedyConnect` — for each legal column, simulate dropping an own piece, score the column by the maximum length of contiguous own pieces through the resulting cell across the four standard axes; pick the highest-scoring column with mid-distance tie-break. *User-facing label: "Connector".*
- `greedyConnectDefense` — if the opponent has any move that produces a length-4 own-colour run for them on their next turn, play the most central such column to block; otherwise behave as `greedyConnect`. *User-facing label: "Sentinel".*

The strategy `edgeFocus` is removed.

#### Scenario: No candidates triggers fallback
- **WHEN** the clone has no candidates that meet the search threshold
- **THEN** the system SHALL use the configured fallback strategy

#### Scenario: Random fallback (Chaotic)
- **WHEN** the fallback strategy is `random`
- **THEN** the bot SHALL pick a uniformly random legal column

#### Scenario: Middle-focus fallback (benchmark only)
- **WHEN** the fallback strategy is `middleFocus`
- **THEN** the bot SHALL pick the legal column closest to the middle (`cols ~/ 2`)
- **AND** this strategy SHALL NOT be selectable via the user-facing settings UI

#### Scenario: Pile-focus fallback (Stacker)
- **WHEN** the fallback strategy is `pileFocus`
- **THEN** the bot SHALL pick the legal column with the highest count of non-empty cells, breaking ties by closeness to the middle column

#### Scenario: Builder fallback on empty board
- **WHEN** the fallback strategy is `ownPileAdjacent`
- **AND** the board contains no own (`+1`) pieces
- **THEN** the bot SHALL pick the middle column (or the legal column closest to the middle if it is full)

#### Scenario: Builder fallback with a single own pile
- **WHEN** the fallback strategy is `ownPileAdjacent`
- **AND** there is a single column `c*` with the most own pieces
- **THEN** the bot SHALL pick whichever of `c*-1`, `c*+1` is legal and closer to the middle (`mid`)
- **AND** if both adjacent columns are equidistant from `mid` and legal, the bot SHALL pick one uniformly at random (using the `CloneBrain`'s seeded `Random` instance, so behaviour remains reproducible under a fixed seed)

#### Scenario: Builder fallback with tied own piles
- **WHEN** the fallback strategy is `ownPileAdjacent`
- **AND** multiple columns are tied for the most own pieces
- **THEN** the bot SHALL select the tied column closest to `mid` as `c*`, then apply the adjacent-column rule

#### Scenario: Connector fallback extends a chain
- **WHEN** the fallback strategy is `greedyConnect`
- **AND** dropping an own piece in column `c` would yield the longest contiguous own-colour run through the new cell across all four standard axes (horizontal, vertical, diagonal-NE, diagonal-NW)
- **THEN** the bot SHALL pick column `c`, breaking ties by closeness to `mid`

#### Scenario: Sentinel fallback blocks a winning move
- **WHEN** the fallback strategy is `greedyConnectDefense`
- **AND** at least one column exists where the opponent dropping a piece would create a contiguous opponent run of length 4 or more
- **THEN** the bot SHALL pick the most central such "must-block" column

#### Scenario: Sentinel fallback with no immediate threat
- **WHEN** the fallback strategy is `greedyConnectDefense`
- **AND** no column allows the opponent to create a length-4 run on their next move
- **THEN** the bot SHALL behave identically to `greedyConnect`

## REMOVED Requirements

### Requirement: Edge-focus fallback
**Reason**: Edge-focus is a known weak strategy for Connect Four (corners are weak), has no narrative purpose, and was not used by the benchmark. It is removed entirely from the engine.
**Migration**: any persisted `edgeFocus` config value SHALL be silently mapped to `ownPileAdjacent` at the persistence layer.
