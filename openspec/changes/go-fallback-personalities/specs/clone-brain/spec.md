## MODIFIED Requirements

### Requirement: Cold-start fallback personalities

The system SHALL support fallback strategies that fire when the clone has no relevant data (no candidates found, all candidates fall outside the prefilter window, or the all-losing guard rejects the chosen move). The set of available strategies is game-aware: each game exposes a subset via the user-facing settings UI; other strategies remain selectable in the engine for benchmark and regression use.

For Connect Four (`ConnectFourRules`), the engine SHALL provide:

- `random` — uniformly random legal column. *User-facing label: "Chaotic".*
- `middleFocus` — legal column closest to the middle. *Benchmark-only.*
- `pileFocus` — legal column with the highest pile of pieces; mid-distance tie-break. *User-facing label: "Stacker".*
- `ownPileAdjacent` — column adjacent to the tallest stack of own pieces. *User-facing label: "Builder".*
- `greedyConnect` — score by max-direction run length through the dropped piece. *User-facing label: "Connector".*
- `greedyConnectDefense` — block opponent length-4 runs, else `greedyConnect`. *User-facing label: "Sentinel".*

For Go (`GoRules`), the engine SHALL provide:

- `random` — uniformly random legal placement. *User-facing label: "Chaotic".* (Same enum value as CF; distinct user-facing semantics — pass moves are excluded from the candidate pool by the brain layer before the fallback receives the legal-moves list.)
- `goStarPoints` — score each legal placement by a static per-cell weight (3 at hoshi/tengen, 2 on the 3rd/4th lines, 1 on the 1st line and the centre cross, 0 elsewhere); pick max with random tie-break. *User-facing label: "Star-point".*
- `goHugger` — score each legal placement by its count of 4-orthogonal-adjacent friendly (`+1`) stones; pick max with Star-point weight as secondary tie-break, then random. *User-facing label: "Hugger". Default for Go installs.*
- `goContact` — score each legal placement by its count of 4-orthogonal-adjacent enemy (`-1`) stones; same tie-break as `goHugger`. *User-facing label: "Contact".*
- `goGreedyArea` — for each candidate placement (empty cells with at least one 4-orthogonal-adjacent stone of any colour; falls through to Star-point if the candidate set is empty), apply the move and compute the resulting Chinese-style area-score differential `(own_area − opponent_area)`; pick the differential-maximising move with Star-point weight tie-break, then random. *User-facing label: "Greedy".*

The Go-mode strategies SHALL NOT be selectable via the user-facing settings UI when `gameType != 'go'`. The CF-mode strategies SHALL NOT be selectable via the user-facing settings UI when `gameType == 'go'`.

#### Scenario: No candidates triggers fallback
- **WHEN** the clone has no candidates that meet the search threshold
- **THEN** the system SHALL use the configured fallback strategy

#### Scenario: Random fallback (Chaotic)
- **WHEN** the fallback strategy is `random`
- **THEN** the bot SHALL pick a uniformly random legal move from the brain's filtered candidate set (which excludes `passMove` for Go unless the opponent just passed)

#### Scenario: Star-point fallback on empty Go board
- **WHEN** the fallback strategy is `goStarPoints`
- **AND** the board is empty
- **THEN** the bot SHALL pick one of the cells with the maximum static weight (the nine 13×13 hoshi positions) uniformly at random

#### Scenario: Star-point fallback prefers third-line over second-line
- **WHEN** the fallback strategy is `goStarPoints`
- **AND** all hoshi cells are occupied
- **THEN** the bot SHALL pick a 3rd/4th-line cell over a 2nd-line cell

#### Scenario: Hugger fallback on empty Go board
- **WHEN** the fallback strategy is `goHugger`
- **AND** the board contains no own (`+1`) pieces
- **THEN** the friendly-neighbour score is uniformly zero
- **AND** the Star-point weight tie-break SHALL produce a star-point opener

#### Scenario: Hugger fallback adjacent to own stone
- **WHEN** the fallback strategy is `goHugger`
- **AND** there is exactly one own (`+1`) stone on the board at intersection `(r, c)`
- **THEN** the bot SHALL pick one of the legal 4-orthogonal-adjacent cells of `(r, c)`

#### Scenario: Hugger fallback connects two own stones
- **WHEN** the fallback strategy is `goHugger`
- **AND** there are two own (`+1`) stones with exactly one shared 4-orthogonal-adjacent empty cell that is legal
- **THEN** the bot SHALL pick that shared cell (score = 2, strictly higher than any other empty cell's score)

#### Scenario: Contact fallback adjacent to enemy stone
- **WHEN** the fallback strategy is `goContact`
- **AND** there is at least one enemy (`-1`) stone on the board
- **THEN** the bot SHALL pick a legal 4-orthogonal-adjacent cell of the enemy stone with the highest enemy-neighbour count

#### Scenario: Contact fallback ignores own stones
- **WHEN** the fallback strategy is `goContact`
- **AND** the board has both own and enemy stones
- **THEN** the bot SHALL pick the move adjacent to the most enemy stones, regardless of any friendly-neighbour count

#### Scenario: Greedy area fallback prefilter
- **WHEN** the fallback strategy is `goGreedyArea`
- **AND** the board has at least one stone
- **THEN** the bot SHALL evaluate only candidates that are empty intersections with at least one 4-orthogonal-adjacent stone of any colour
- **AND** the bot SHALL NOT evaluate empty intersections more than 1 step removed from any stone

#### Scenario: Greedy area fallback on empty board
- **WHEN** the fallback strategy is `goGreedyArea`
- **AND** the board has no stones
- **THEN** the candidate set SHALL be empty
- **AND** the bot SHALL fall through to `goStarPoints` behaviour

#### Scenario: Greedy area fallback maximises territory differential
- **WHEN** the fallback strategy is `goGreedyArea`
- **AND** the candidate set has at least one move
- **THEN** the bot SHALL pick the candidate that maximises `(own_area − opponent_area)` after applying the move, where `own_area` and `opponent_area` are returned by `GoRules.areaScore` on the post-move board

_(Note: legacy persisted values not in the user-facing set for the active game SHALL be silently mapped to the default at the persistence layer: `pileFocus` (Stacker) for CF mode, `goHugger` (Hugger) for Go mode.)_
