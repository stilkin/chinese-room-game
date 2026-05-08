## MODIFIED Requirements

### Requirement: Decision pipeline
On the clone's turn, the brain SHALL run the four-query retrieval defined in the canonicalization spec, filter candidates by outcome (`Q_A` and `Q_A_mirror` → `outcome=+1` only; `Q_B` and `Q_B_mirror` → `outcome=-1` only), assign each surviving candidate a sign-aware distance-weighted weight and a per-query move/image untransform, and pass the merged weighted-candidate list to `InfluenceOverlayStrategy`. The strategy accumulates a single signed heatmap and selects the highest-scoring legal move via the per-game `MoveScorer`.

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

## ADDED Requirements

### Requirement: Sign-aware distance-weighted candidate weighting
Each candidate's weight SHALL be:
```
weight = sign × (1 / (1 + movesToEnd)) × (1 / (1 + l1Distance))
```
Where `sign` is `+1` for candidates from `Q_A` and `Q_A_mirror`, and `-1` for candidates from `Q_B` and `Q_B_mirror`. `movesToEnd` is from the candidate's stored row. `l1Distance` is the matcher's distance for that candidate (Int8 L1 over the diffused images).

#### Scenario: Closer match contributes more weight
- **WHEN** two candidates with the same sign and `movesToEnd` differ in L1 distance
- **THEN** the candidate with smaller distance SHALL have a larger absolute weight

#### Scenario: Faster path contributes more weight
- **WHEN** two candidates with the same sign and L1 distance differ in `movesToEnd`
- **THEN** the candidate with smaller `movesToEnd` SHALL have a larger absolute weight

#### Scenario: Loss candidate contributes negative weight
- **WHEN** a candidate originates from `Q_B` or `Q_B_mirror`
- **THEN** its weight SHALL be negative

### Requirement: Move-untransform on mirror-query candidates
Candidates retrieved via mirror queries (`Q_A_mirror`, `Q_B_mirror`) SHALL have their stored `diffusedImage` mirrored before being added to the heatmap, and their `movePlayed` value SHALL be mirrored before being surfaced to narration. For Connect Four, the mirror is `c → cols - 1 - c` for column moves and a left-right flip on the image's row-major layout.

#### Scenario: Mirror-query image aligns with query coordinate frame
- **WHEN** a candidate from `Q_A_mirror` contributes its diffused image to the heatmap
- **THEN** the image SHALL be left-right flipped before accumulation, so its territories align with the un-mirrored query's coordinate frame

#### Scenario: Mirror-query move played reflects to query frame
- **WHEN** a candidate from `Q_A_mirror` reports `movePlayed = 1` (column 1)
- **AND** the board has 7 columns
- **THEN** the move surfaced to narration SHALL be column `5` (= `7 - 1 - 1`)
