## ADDED Requirements

### Requirement: Decision pipeline
On the clone's turn, the brain SHALL run the two-query search defined in the canonicalization spec, filter candidates by outcome (Query A → outcome=+1 only, Query B → outcome=-1 only), build a sign-aware distance-weighted candidate list, and delegate to the game's `MoveSelectionStrategy`. States with null `outcome` (game still in progress, not backfilled) SHALL be excluded from move selection.

#### Scenario: In-progress states excluded
- **WHEN** the in-memory `GameLog` contains states from the current ongoing game (null `outcome`)
- **THEN** the brain SHALL exclude them from the candidate set passed to similarity search

#### Scenario: Two-query results merged before delegation
- **WHEN** Query A returns N positive-weight candidates and Query B returns M negative-weight candidates
- **THEN** the brain SHALL combine them into a single weighted-candidate list before invoking the move selection strategy

### Requirement: Move selection delegates to game-specific strategy
The clone brain SHALL pass weighted candidates to the game's `MoveSelectionStrategy` (defined in `GameRules`) to determine the final move. The brain does not implement move selection logic directly — it delegates to the strategy.

#### Scenario: Connect Four delegates to vote-by-move
- **WHEN** the clone brain has weighted candidates for a Connect Four game
- **THEN** it SHALL pass them to the vote-by-move strategy provided by ConnectFourRules

#### Scenario: Strategy receives all weighted candidates
- **WHEN** the clone brain invokes the move selection strategy
- **THEN** the strategy SHALL receive the full list of weighted candidates and the list of legal moves

### Requirement: Cold-start fallback personalities
The system SHALL support fallback strategies that fire when the clone has no relevant data (no candidates found or all below a confidence threshold). For Connect Four, the fallback strategies SHALL be: random, middle-focus, edge-focus, and pile-focus.

#### Scenario: No candidates triggers fallback
- **WHEN** similarity search returns zero candidates
- **THEN** the system SHALL use the configured fallback strategy

#### Scenario: Random fallback
- **WHEN** the fallback strategy is "random"
- **THEN** the system SHALL select uniformly from legal moves

#### Scenario: Middle-focus fallback
- **WHEN** the fallback strategy is "middle_focus"
- **THEN** the system SHALL prefer columns closer to the center (column 3)

#### Scenario: Edge-focus fallback
- **WHEN** the fallback strategy is "edge_focus"
- **THEN** the system SHALL prefer columns closer to the edges (columns 0 and 6)

#### Scenario: Pile-focus fallback
- **WHEN** the fallback strategy is "pile_focus"
- **THEN** the system SHALL prefer columns that already contain the most pieces

