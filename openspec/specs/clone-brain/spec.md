## Purpose
Defines the clone's move-decision pipeline and fallback behaviour.
## Requirements
### Requirement: Decision pipeline
On the clone's turn, the brain SHALL run the four-query retrieval defined in the canonicalization spec, filter candidates by outcome (`Q_A` and `Q_A_mirror` → `outcome=+1` only; `Q_B` and `Q_B_mirror` → `outcome=-1` only), assign each surviving candidate a positive distance-weighted weight and a per-query move/image untransform, and pass the merged weighted-candidate list to `InfluenceOverlayStrategy`. The strategy accumulates a single signed heatmap (the candidate image's natural sign carries the win/loss lesson) and selects the highest-scoring legal move via the per-game `MoveScorer`.

States with null `outcome` (rows from the in-progress current game, not yet backfilled) SHALL be excluded from retrieval.

#### Scenario: In-progress states excluded
- **WHEN** the in-memory `GameLog` contains states from the current ongoing game (null `outcome`)
- **THEN** the brain SHALL exclude them from the candidate set passed to retrieval

#### Scenario: Four query results merged before delegation
- **WHEN** the four queries return candidate sets with sizes `Na`, `Na_m`, `Nb`, `Nb_m`
- **THEN** the brain SHALL merge them into a single `WeightedCandidate` list of size `Na + Na_m + Nb + Nb_m` (post outcome-filter), with mirror-query candidates carrying their `untransformImage` and `untransformMove` functions, before invoking `InfluenceOverlayStrategy.selectMove`

#### Scenario: All-losing guard
- **WHEN** the strategy returns a move whose heatmap score is `≤ 0`
- **THEN** the brain SHALL invoke the configured fallback strategy instead and produce `allLosing` narration

### Requirement: Cold-start fallback personalities

The system SHALL support fallback strategies that fire when the clone has no relevant data (no candidates found, all candidates fall outside the prefilter window, or the all-losing guard rejects the chosen move). For Connect Four, the engine SHALL provide the following fallback strategies:

- `random` — pick a uniformly random legal column. *User-facing label: "Chaotic".*
- `middleFocus` — pick the legal column closest to the middle. *Benchmark-only; not surfaced via configuration.*
- `pileFocus` — pick the legal column with the highest pile of pieces (any colour); tie-break by closeness to middle. *User-facing label: "Stacker". Default for new installs.*
- `ownPileAdjacent` — pick a column adjacent to the tallest stack of own (`+1`) pieces; tie-break by closeness to middle. *User-facing label: "Builder".*
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

_(Note: the `edgeFocus` scenario from the prior `Cold-start fallback personalities` requirement is implicitly removed by the modified content above. Migration: any persisted value not in the user-facing set (including legacy `edgeFocus` and benchmark-only `middleFocus`) SHALL be silently mapped to `pileFocus` at the persistence layer.)_

### Requirement: Distance-weighted candidate weighting
Each candidate's weight SHALL be:
```text
weight = (1 / (1 + movesToEnd)) × (1 / (1 + l1Distance))
```
Weights SHALL be always positive, regardless of the originating query. `movesToEnd` is from the candidate's stored row. `l1Distance` is the matcher's distance for that candidate (Int8 L1 over the diffused images). The win/loss lesson is carried by the candidate image's natural sign (winner-mover candidates have positive territory at their mover's cells; loser-mover candidates have negative territory there) — a sign multiplier on the weight would double-count and invert the loss signal.

#### Scenario: Closer match contributes more weight
- **WHEN** two candidates with the same `movesToEnd` differ in L1 distance
- **THEN** the candidate with smaller distance SHALL have a larger weight

#### Scenario: Faster path contributes more weight
- **WHEN** two candidates with the same L1 distance differ in `movesToEnd`
- **THEN** the candidate with smaller `movesToEnd` SHALL have a larger weight

#### Scenario: Loss candidate carries its lesson via image sign, not weight sign
- **WHEN** a candidate originates from `Q_B` or `Q_B_mirror` (a loser-mover row)
- **THEN** its weight SHALL still be positive
- **AND** its diffused image (which has negative territory at the mover's cells) SHALL be the part that pushes the heatmap *down* on those cells when accumulated

### Requirement: Move-untransform on mirror-query candidates
Candidates retrieved via mirror queries (`Q_A_mirror`, `Q_B_mirror`) SHALL have their stored `diffusedImage` mirrored before being added to the heatmap, and their `movePlayed` value SHALL be mirrored before being surfaced to narration. For Connect Four, the mirror is `c → cols - 1 - c` for column moves and a left-right flip on the image's row-major layout.

#### Scenario: Mirror-query image aligns with query coordinate frame
- **WHEN** a candidate from `Q_A_mirror` contributes its diffused image to the heatmap
- **THEN** the image SHALL be left-right flipped before accumulation, so its territories align with the un-mirrored query's coordinate frame

#### Scenario: Mirror-query move played reflects to query frame
- **WHEN** a candidate from `Q_A_mirror` reports `movePlayed = 1` (column 1)
- **AND** the board has 7 columns
- **THEN** the move surfaced to narration SHALL be column `5` (= `7 - 1 - 1`)

