# go-rules Specification

## Purpose
TBD - created by archiving change go-engine-foundation. Update Purpose after archive.
## Requirements
### Requirement: Configurable board size
The system SHALL provide a `GoRules` implementation of `GameRules` whose constructor accepts a `size` parameter defaulting to `13`. Cell coordinates range over `[0, size)` for both rows and columns.

#### Scenario: Default size is 13
- **WHEN** `GoRules()` is constructed without arguments
- **THEN** `rows` SHALL equal `13` AND `cols` SHALL equal `13`

#### Scenario: 9 and 19 are also valid
- **WHEN** `GoRules(size: 9)` or `GoRules(size: 19)` is constructed
- **THEN** the resulting board dimensions SHALL match the requested size

### Requirement: Move encoding includes a pass sentinel
The system SHALL encode moves as non-negative integers. Integers `0..size*size-1` SHALL represent intersection indices in row-major order: `intersection(r, c) = r * size + c`. The integer `size*size` SHALL be the **pass** sentinel.

#### Scenario: Pass sentinel is one beyond the last intersection
- **WHEN** `GoRules(size: 13)` is constructed
- **THEN** `passMove` SHALL equal `169`

#### Scenario: Pass is always legal
- **WHEN** `legalMoves(board)` is called for any board state
- **THEN** the returned list SHALL include `passMove`

### Requirement: Legal-move generation excludes suicide and ko
The system SHALL include an empty intersection in `legalMoves` only if placing a stone there does not result in self-suicide and does not violate simple ko (recreating the immediately-previous board state).

#### Scenario: Suicide is illegal
- **WHEN** an empty intersection has no liberties after placement and would not capture any opposing group
- **THEN** that intersection SHALL NOT appear in `legalMoves`

#### Scenario: Suicide that captures is legal
- **WHEN** placement at an intersection would have zero liberties on its own group, but also captures at least one opposing group
- **THEN** that intersection SHALL appear in `legalMoves` and the placement SHALL execute the capture

#### Scenario: Simple ko is rejected
- **WHEN** a placement would produce a board byte-equal to the board immediately before the opponent's previous move
- **THEN** that intersection SHALL NOT appear in `legalMoves`

### Requirement: Captures resolve on placement
The system SHALL, after each non-pass placement, identify every adjacent opposing group with zero liberties and remove it from the board before evaluating the placing player's own group's liberties.

#### Scenario: Surrounding an opponent stone captures it
- **WHEN** a stone is placed such that an adjacent opposing single stone now has zero liberties
- **THEN** that opposing stone SHALL be removed

#### Scenario: Multi-stone group capture
- **WHEN** a stone is placed such that an adjacent opposing group of three connected stones now has zero liberties
- **THEN** all three stones SHALL be removed

### Requirement: Two consecutive passes terminate the game
The system SHALL report `isTerminal(log) == true` when the most recent two moves in the log were both `passMove`, regardless of board state. The system SHALL also terminate when no non-pass legal moves remain (degenerate case).

#### Scenario: Two passes end the game
- **WHEN** the last two recorded moves are `passMove` and `passMove`
- **THEN** `isTerminal(log)` SHALL return `true`

#### Scenario: One pass does not end the game
- **WHEN** the most recent move was `passMove` but the move before it was an intersection placement
- **THEN** `isTerminal(log)` SHALL return `false`

### Requirement: Final outcome uses Chinese-style area scoring
The system SHALL compute the final outcome by summing each side's stones on the board plus empty intersections whose connected region neighbours only that side's stones (territory). The side with the higher total SHALL win; equal totals SHALL be reported as a draw.

#### Scenario: White stones plus surrounded empties beat black
- **WHEN** white has 50 area points (stones + own territory) and black has 49
- **THEN** `finalOutcome(log)` SHALL return `+1`

#### Scenario: Equal area scores draw
- **WHEN** both sides have identical area totals
- **THEN** `finalOutcome(log)` SHALL return `0`

#### Scenario: Empties touching both colours score for neither
- **WHEN** an empty connected region neighbours both white and black stones
- **THEN** that region SHALL contribute zero to either total

### Requirement: Go diffusion kernel and per-game retrieval helpers
`GoRules` SHALL provide a `GoDiffusionKernel`, a `GoFilter` prefilter, and a `GoMoveScorer` so that the existing CBR pipeline (four-query retrieval, L1 over diffused images, heatmap accumulation) operates on Go data without modification.

#### Scenario: GoFilter widens by doubling the window
- **WHEN** a `GoFilter` with window `4` is `widened()`
- **THEN** the result SHALL accept candidates within a window of `8`

#### Scenario: Pass move scores at a small fixed value
- **WHEN** `GoMoveScorer.scoreMove(passMove, board, heatmap)` is called
- **THEN** it SHALL return `0.01`, regardless of heatmap content

#### Scenario: Intersection move scores from heatmap
- **WHEN** `GoMoveScorer.scoreMove(move, board, heatmap)` is called for a non-pass `move`
- **THEN** it SHALL return `heatmap[move ~/ size][move % size]`

