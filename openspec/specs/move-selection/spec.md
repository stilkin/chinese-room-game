## ADDED Requirements

### Requirement: Move selection strategy is game-specific
The `GameRules` interface SHALL include a `MoveSelectionStrategy` that defines how weighted candidates are converted into a chosen move. Each game provides its own strategy.

#### Scenario: Connect Four uses vote-by-move
- **WHEN** the clone brain selects a move for Connect Four
- **THEN** it SHALL use the vote-by-move strategy

#### Scenario: Strategy is provided by GameRules
- **WHEN** a new game type is added
- **THEN** it SHALL specify its move selection strategy as part of the GameRules implementation

### Requirement: Vote-by-move strategy
The vote-by-move strategy SHALL aggregate candidate weights by the move they suggest. The move with the highest total aggregated weight SHALL be selected. This strategy is suited for games with small move spaces.

#### Scenario: Aggregation across candidates
- **WHEN** 3 candidates suggest column 3 (weights 0.8, 0.7, 0.6) and 1 candidate suggests column 4 (weight 0.9)
- **THEN** column 3 SHALL be selected (aggregated weight 2.1 > 0.9)

#### Scenario: Single candidate
- **WHEN** only one candidate state passes similarity search
- **THEN** the move from that candidate SHALL be selected

#### Scenario: Tie-breaking
- **WHEN** two moves have equal aggregated weight
- **THEN** the move from the candidate with the highest individual weight SHALL be selected

### Requirement: Influence overlay strategy
The influence overlay strategy SHALL combine multiple candidates' diffusion maps into a target influence map by computing a weighted average (weighted by each candidate's outcome/efficiency score). Each legal move SHALL be scored by looking up its position's value in the target influence map. The legal move with the highest target influence value SHALL be selected.

#### Scenario: Target map from multiple candidates
- **WHEN** 3 candidates with different diffusion maps and weights are combined
- **THEN** the target influence map SHALL be the weighted average of their diffusion maps

#### Scenario: Move scored by target map value
- **WHEN** the target influence map has value 0.8 at position (4,3) and 0.3 at position (10,10)
- **THEN** a legal move at (4,3) SHALL score higher than a legal move at (10,10)

#### Scenario: Spatial clustering captured
- **WHEN** 3 candidates played at nearby positions (4,3), (4,4), and (5,3) in a good region
- **THEN** the target influence map SHALL have a hot spot in that region, and a legal move within that region SHALL be preferred

#### Scenario: No candidates falls through to fallback
- **WHEN** no candidates are found for influence overlay
- **THEN** the clone brain SHALL use the configured fallback strategy
