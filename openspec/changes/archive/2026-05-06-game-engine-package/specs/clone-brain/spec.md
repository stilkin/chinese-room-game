## ADDED Requirements

### Requirement: Move weighting by outcome and efficiency
The system SHALL weight candidate moves by outcome (win=1.0, draw=0.5, loss=0.0) and efficiency (fewer moves to end is better). The combined weight SHALL favor moves from winning games that ended quickly.

#### Scenario: Win weighted above draw
- **WHEN** one candidate has outcome=win and another has outcome=draw, both with equal similarity
- **THEN** the win candidate SHALL have a higher weight

#### Scenario: Fast win preferred over slow win
- **WHEN** two candidates both have outcome=win, one with moves_to_end=3 and the other moves_to_end=10
- **THEN** the candidate with moves_to_end=3 SHALL have a higher weight

#### Scenario: States without outcome data
- **WHEN** a candidate state has null outcome (game still in progress or not backfilled)
- **THEN** it SHALL be excluded from move selection

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

### Requirement: Outcome backfilling
The system SHALL backfill `outcome` and `moves_to_end` for all states in a game when that game ends. Outcome is from each state's side-to-move perspective: win=1, draw=0, loss=-1.

#### Scenario: Win backfill
- **WHEN** a 10-move game ends with player 1 winning
- **THEN** all states where player 1 was side-to-move SHALL have outcome=1, and moves_to_end counting down from each state's ply to 10

#### Scenario: Loss backfill with inversion
- **WHEN** a game ends in a loss
- **THEN** inverted (opponent-perspective) states SHALL be created with outcome=1
