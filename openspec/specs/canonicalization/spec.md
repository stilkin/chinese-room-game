## ADDED Requirements

### Requirement: Mirror normalization
The system SHALL canonicalize boards by comparing the Zobrist hash of the left half to the right half. If the left half's hash is lower, the board SHALL be mirrored horizontally before storage.

#### Scenario: Board with higher-hash left half stored as-is
- **WHEN** a board's left half has a higher Zobrist hash than the right half
- **THEN** the board SHALL be stored without mirroring

#### Scenario: Board with lower-hash left half gets mirrored
- **WHEN** a board's left half has a lower Zobrist hash than the right half
- **THEN** the board SHALL be mirrored horizontally before storage

#### Scenario: Symmetric board stored consistently
- **WHEN** a board is perfectly symmetric (left equals right)
- **THEN** the board SHALL be stored in a deterministic canonical form

### Requirement: Perspective normalization
The system SHALL always store board states from the perspective of the side to move. Piece signs SHALL be flipped if the stored state was originally from the opponent's perspective.

#### Scenario: Side-to-move perspective stored directly
- **WHEN** a board state is recorded for the side that just moved
- **THEN** piece values SHALL be negated so the next-to-move side's pieces are positive

### Requirement: Loss inversion
The engine SHALL provide a public helper `invertState` that produces a perspective-twin of a single `GameState`: re-canonicalized for the opposite side's POV (full pipeline equivalence — mirror normalization preserved, perspective flipped), Zobrist and diffused-bit hashes recomputed, `side` and `materialBalance` flipped, and `movePlayed`, `ply`, `gameId`, `outcome`, and `movesToEnd` preserved.

Stores using the engine SHALL invoke the helper at backfill time on **every row** of player-won games, replacing all rows of the just-finished game in place. The full-game inversion rewrites the game as if the bot were the protagonist: player-played rows become `side=-1, outcome=+1` (the bot's winning trajectory), and clone-played rows become `side=+1, outcome=-1` (the opponent's losing trajectory). Bot-won games SHALL NOT be inverted — the standard per-side backfill already produces the right shape.

#### Scenario: Inversion targets the opposite side
- **WHEN** `invertState` is called on a state with `side=1`
- **THEN** the returned state SHALL have `side=-1`

#### Scenario: Inversion is a fixed point under double application
- **WHEN** `invertState` is called twice on the same input state
- **THEN** the resulting state's `board`, `zobristHash`, `diffusedHash`, `side`, and `materialBalance` SHALL equal the original's

#### Scenario: Inversion produces canonical board from the opposite POV
- **WHEN** `invertState` is called on a state whose canonical board is the canonicalize-result for the original side
- **THEN** the returned state's canonical `board` SHALL equal what `canonicalize(displayBoard, -side)` would produce for an equivalent display board, and its `zobristHash` SHALL equal the recomputed hash on that board

#### Scenario: Inversion preserves move metadata
- **WHEN** `invertState` is called
- **THEN** the returned state SHALL have the same `movePlayed`, `ply`, `gameId`, `outcome`, and `movesToEnd` as the input

#### Scenario: Inversion flips materialBalance sign
- **WHEN** `invertState` is called on a state with `materialBalance=2`
- **THEN** the returned state SHALL have `materialBalance=-2`

#### Scenario: Backfill inverts every row of a player-won game
- **WHEN** a game ends with the player winning and the in-memory log contains both player-side and clone-side states for that game
- **THEN** after backfill, every row of that game SHALL be replaced with its `invertState` output: player-played rows become `side=-1, outcome=+1` (canonical from bot-POV) and clone-played rows become `side=+1, outcome=-1`

#### Scenario: Backfill leaves bot-won games unchanged
- **WHEN** a game ends with the bot winning
- **THEN** the standard per-side outcome flip SHALL apply but no inversion SHALL run; the bot's rows already sit at `side=-1, outcome=+1` and the player's rows at `side=+1, outcome=-1`

#### Scenario: Outcome attribution stays consistent with side
- **WHEN** any stored row is read by the clone's weighting logic after backfill (with or without inversion)
- **THEN** `outcome=+1` on a row SHALL always represent "the side recorded in this row's `side` field won this game," matching the standard backfill convention

### Requirement: Canonicalization happens at write time
All canonicalization (mirror, perspective, inversion) SHALL be applied before a state is stored. Query-time canonicalization SHALL only be applied to the current board being searched for.

#### Scenario: Stored state is already canonical
- **WHEN** a state is retrieved from storage
- **THEN** no further canonicalization SHALL be needed for comparison
