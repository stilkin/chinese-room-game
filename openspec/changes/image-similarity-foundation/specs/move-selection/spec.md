## REMOVED Requirements

### Requirement: Vote-by-move strategy
**Reason**: Per-column voting collapses spatially-rich candidate evidence into one number per legal column. The candidates' diffused maps carry where on the board the winning trajectory was concentrated; the heatmap-overlay strategy preserves that signal. Vote-by-move was a stepping stone; influence-overlay was always the planned destination (it's been specced and stubbed since the engine was built).
**Migration**: Connect Four's `MoveSelectionStrategy` switches from `VoteByMoveStrategy` to `InfluenceOverlayStrategy`. The engine no longer ships any vote-by-move implementation.

### Requirement: Influence overlay strategy
**Reason**: This requirement existed but described an unimplemented future design. It's being replaced (in this change) with a more specific, implemented version below.
**Migration**: The interface stays — `MoveSelectionStrategy.selectMove(candidates, legalMoves, currentBoard)` — but its concrete behavior is now spelled out and tied to `MoveScorer`.

## ADDED Requirements

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

### Requirement: Cold-start fallback personalities (carried forward)
The system SHALL retain the four fallback personalities from the existing implementation: random, middle-focus, edge-focus, pile-focus. These fire when:
- The brain has no candidates with `outcome != null`, OR
- The four-query retrieval produces zero merged candidates, OR
- `InfluenceOverlayStrategy.selectMove` returns `null`, OR
- The chosen move's heatmap score is `≤ 0` (the all-losing guard).

#### Scenario: No candidates triggers fallback
- **WHEN** the four-query retrieval merges to an empty candidate list
- **THEN** the system SHALL invoke the configured fallback strategy and report `usedFallback=true`

#### Scenario: All-losing post-overlay routes to fallback
- **WHEN** every legal move's heatmap score is `≤ 0`
- **THEN** the system SHALL invoke the fallback and produce the `allLosing` narration
