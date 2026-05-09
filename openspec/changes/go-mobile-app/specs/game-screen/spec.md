## MODIFIED Requirements

### Requirement: Game screen renders the active game's board
The game screen SHALL render the board produced by the active `GameRules` implementation. For Go, this is a 13×13 intersection grid with stones placed at intersections; the player's stones SHALL be one colour and the clone's another, distinguishable at a glance.

#### Scenario: 13×13 intersection grid renders
- **WHEN** the game screen mounts with `GoRules(size: 13)` as the active rules
- **THEN** the board widget SHALL render 13 horizontal lines and 13 vertical lines forming the grid
- **AND** stones SHALL render as filled circles at intersection points

#### Scenario: Last move highlighted
- **WHEN** a move has just been played
- **THEN** the most recent placement SHALL be visually distinguished (ring, mark, or comparable indicator) until the next move is played

### Requirement: Tap-to-place on legal intersections
The game screen SHALL respond to tap input by placing a stone at the nearest intersection within a hit radius. Taps outside the hit radius or on non-legal intersections SHALL be rejected without modifying game state.

#### Scenario: Tap on legal empty intersection places a stone
- **WHEN** the user taps within the hit radius of an empty, legal intersection
- **THEN** a stone of the user's colour SHALL appear at that intersection AND the clone's turn SHALL begin

#### Scenario: Tap on non-legal intersection is rejected
- **WHEN** the user taps an intersection that is occupied, suicide, or ko-violating
- **THEN** game state SHALL NOT change AND the user SHALL receive negative tactile or visual feedback

### Requirement: Pass button advances the turn without placing
The game screen SHALL provide a Pass control. Activating it SHALL append a `passMove` to the game log and hand control to the clone. Two consecutive passes (across both sides) SHALL trigger the post-game screen.

#### Scenario: Pass appends pass move
- **WHEN** the user activates Pass on their turn
- **THEN** the game log's most recent move SHALL be `passMove` AND the clone's turn SHALL begin

#### Scenario: Two-pass termination shows post-game
- **WHEN** the most recent two moves in the log are both `passMove`
- **THEN** the game screen SHALL navigate to the post-game screen with the final area score and winner

### Requirement: Captured stones animate out
When a placement results in opposing-stone captures, those stones SHALL fade out over a short animation (~150ms) before the next turn begins. Capture animation SHALL NOT block clone-side response computation.

#### Scenario: Single-stone capture fades
- **WHEN** the player's placement reduces an adjacent opposing single stone's group to zero liberties
- **THEN** that stone SHALL fade out over ~150ms before the clone begins thinking
