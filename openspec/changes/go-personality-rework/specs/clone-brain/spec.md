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

- `random` — for Go this is the **"Wanderer"** behaviour: empty placement cells within Manhattan-2 of any stone, picked uniformly at random within that pool. Empty board (no stones) → falls through to `goStarPoints`. The brain layer filters `passMove` from the pool before the strategy receives it (unless the opponent just passed). *User-facing label: "Wanderer".*
- `goStarPoints` — score each legal placement by a static per-cell weight (3 at hoshi/tengen, 2 on the 3rd/4th lines, 1 on the 1st line and the centre cross, 0 elsewhere); pick max with random tie-break. *User-facing label: "Star-point". Default for Go installs.*
- `goDiamond` — score each legal placement by `(diagonal-friendly count) − (orthogonal-friendly count)`, where the diagonals are the 4 cells at distance |dr|=|dc|=1 and orthogonals are the 4 cells at |dr|+|dc|=1. The minus actively penalises dumpling shape; positive scores reward kosumi / ponnuki extensions. Tie-break: Star-point weight, then random. *User-facing label: "Diamond".* (Replaces the prior `goHugger` strategy; legacy persisted `goHugger` strings coerce to the default.)
- `goContact` — score each legal placement by its count of 4-orthogonal-adjacent enemy (`-1`) stones; same tie-break as `goDiamond`. *User-facing label: "Contact".*
- `goGreedyArea` — for each candidate placement (empty cells with at least one 4-orthogonal-adjacent stone of any colour — i.e., `_goCellsNearStones(board, 1)`; falls through to `goStarPoints` if the candidate set is empty), apply the move and compute the resulting Chinese-style area-score differential `(own_area − opponent_area)`; pick the differential-maximising move with Star-point weight tie-break, then random. *User-facing label: "Greedy".*

The Go-mode strategies (`goStarPoints`, `goDiamond`, `goContact`, `goGreedyArea`) SHALL NOT be selectable via the user-facing settings UI when `gameType != 'go'`. The CF-mode strategies SHALL NOT be selectable via the user-facing settings UI when `gameType == 'go'`. The `random` strategy is cross-game; its behaviour varies by `GameRules` subtype (Wanderer for Go, uniform-random for CF).

#### Scenario: Wanderer fallback on empty Go board
- **WHEN** the fallback strategy is `random`
- **AND** the active rules are `GoRules`
- **AND** the board contains no stones
- **THEN** the prefilter set is empty
- **AND** the bot SHALL fall through to `goStarPoints` behaviour

#### Scenario: Wanderer fallback respects Manhattan-2 prefilter
- **WHEN** the fallback strategy is `random`
- **AND** the active rules are `GoRules`
- **AND** the board has at least one stone
- **THEN** the chosen cell SHALL be an empty placement at Manhattan-distance ≤ 2 from at least one stone
- **AND** the chosen cell SHALL NOT be `passMove` unless the opponent has just passed

#### Scenario: CF random fallback is unchanged
- **WHEN** the fallback strategy is `random`
- **AND** the active rules are `ConnectFourRules`
- **THEN** the bot SHALL pick uniformly at random from the brain's filtered candidate set (column moves, pass-not-applicable)

#### Scenario: Diamond fallback prefers a kosumi over a dumpling
- **WHEN** the fallback strategy is `goDiamond`
- **AND** the board has exactly one own (`+1`) stone at intersection `(r, c)`
- **THEN** the bot SHALL pick one of the 4 diagonals `(r±1, c±1)` (score `+1`)
- **AND** the bot SHALL NOT pick any of the 4 orthogonals `(r±1, c)` or `(r, c±1)` (score `−1`)

#### Scenario: Diamond fallback completes a shared-diagonal cell
- **WHEN** the fallback strategy is `goDiamond`
- **AND** two own stones exist at intersections diagonally separated by Manhattan-distance 2 (e.g., (5,5) and (7,7))
- **THEN** the cell at their shared centre (e.g., (6,6)) SHALL have score `+2` (diagonal to both, orthogonal to neither)
- **AND** the bot SHALL pick that shared cell (no other cell scores higher)

#### Scenario: Diamond fallback on empty Go board
- **WHEN** the fallback strategy is `goDiamond`
- **AND** the board contains no own (`+1`) pieces
- **THEN** the score is uniformly zero
- **AND** the Star-point weight tie-break SHALL produce a star-point opener

_(Note: the requirement's scenarios from the pre-rework go-fallback-personalities change that mentioned `goHugger` and the prior "Random fallback (Chaotic)" / "Hugger fallback" scenarios are superseded by the scenarios above. Legacy persisted values not in the user-facing set for the active game SHALL be silently mapped to the default at the persistence layer: `pileFocus` (Stacker) for CF mode, `goStarPoints` (Star-point) for Go mode.)_
