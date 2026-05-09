## Purpose
Defines how a weighted candidate set produces a chosen legal move via heatmap accumulation and scoring.
## Requirements
### Requirement: Move selection strategy is game-specific
The `GameRules` interface SHALL include a `MoveSelectionStrategy` that defines how weighted candidates are converted into a chosen move. Each game provides its own strategy. For Connect Four, the strategy is `InfluenceOverlayStrategy(ConnectFourMoveScorer())`.

#### Scenario: Connect Four uses InfluenceOverlay
- **WHEN** the clone brain selects a move for Connect Four
- **THEN** it SHALL use `InfluenceOverlayStrategy` paired with `ConnectFourMoveScorer`

#### Scenario: Strategy is provided by GameRules
- **WHEN** a new game type is added
- **THEN** it SHALL specify its move selection strategy as part of the GameRules implementation

### Requirement: Influence overlay strategy is the primary move-selection strategy
The `InfluenceOverlayStrategy` SHALL accumulate weighted candidate diffused images into a single board-shaped real-valued heatmap, then ask a per-game `MoveScorer` to score each legal move against that heatmap. The legal move with the highest score SHALL be selected. Candidates with zero weight contribute nothing.

The accumulation rule is:
```
heatmap[r][c] = sum over candidates of (
  candidate.weight × (candidate.diffusedImage[r * cols + c] as double)
)
```

#### Scenario: Single positive candidate produces a positive heatmap
- **WHEN** one candidate with weight `+0.5` and a non-zero diffused image is provided
- **THEN** every cell of the heatmap SHALL equal `0.5 × candidate.diffusedImage[cell]` (cast to double)

#### Scenario: Negative candidate subtracts from the heatmap
- **WHEN** a candidate with weight `-0.3` is added on top of an existing heatmap
- **THEN** each cell SHALL be reduced by `0.3 × candidate.diffusedImage[cell]`

#### Scenario: Move selection picks the highest-scoring legal move
- **WHEN** the heatmap is built and the scorer returns scores `{col 0: 1.2, col 1: -0.4, col 2: 3.1, col 3: 2.7}` for legal moves
- **THEN** column `2` SHALL be selected

#### Scenario: Empty inputs return null
- **WHEN** the candidate list is empty or the legal-move list is empty
- **THEN** `selectMove` SHALL return `null` (the caller routes to fallback)

### Requirement: MoveScorer abstraction
The `MoveScorer` interface SHALL define `double scoreMove(int move, Board currentBoard, List<List<double>> heatmap)`. Each game provides its own implementation via `GameRules.moveScorer`.

#### Scenario: Connect Four scorer uses gravity-aware landing cell
- **WHEN** `ConnectFourMoveScorer.scoreMove` is called for column `c` on a board where the lowest empty row in column `c` is `r`
- **THEN** the score SHALL equal `heatmap[r][c]`

#### Scenario: Scorer for a full column returns negative infinity
- **WHEN** `ConnectFourMoveScorer.scoreMove` is called for a column with no empty rows
- **THEN** the score SHALL be `-double.infinity` (a sentinel ensuring the move is never picked)

