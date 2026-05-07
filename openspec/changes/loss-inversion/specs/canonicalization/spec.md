## MODIFIED Requirements

### Requirement: Loss inversion
The engine SHALL provide a public helper `invertState` that produces a new `GameState` for the opposite side. The helper SHALL re-canonicalize through the full pipeline (mirror + perspective from the opposite side's POV), recompute Zobrist and diffused-bit hashes, flip `side` and `materialBalance`, and preserve `movePlayed`, `ply`, `gameId`, `outcome`, and `movesToEnd`. Stores using the engine SHALL invoke the helper at backfill time on the winning player's states of player-won games, replacing those states in place. Bot-won games SHALL NOT be inverted — the clone's existing states already live in bot-POV space.

#### Scenario: Inversion targets the opposite side
- **WHEN** `invertState` is called on a state with `side=1`
- **THEN** the returned state SHALL have `side=-1`

#### Scenario: Inversion is a fixed point under double application
- **WHEN** `invertState` is called twice on the same input state
- **THEN** the resulting state's `board`, `zobristHash`, `diffusedHash`, `side`, and `materialBalance` SHALL equal the original's

#### Scenario: Inversion re-runs the full canonicalize pipeline
- **WHEN** `invertState` is called on a canonical state whose negation lies on the opposite mirror polarity
- **THEN** the returned state's canonical board SHALL match what `canonicalize(displayBoard, -side)` would produce for an equivalent display board, including any mirror normalization

#### Scenario: Inversion preserves move metadata
- **WHEN** `invertState` is called
- **THEN** the returned state SHALL have the same `movePlayed`, `ply`, `gameId`, `outcome`, and `movesToEnd` as the input

#### Scenario: Inversion flips materialBalance sign
- **WHEN** `invertState` is called on a state with `materialBalance=2`
- **THEN** the returned state SHALL have `materialBalance=-2`

#### Scenario: Backfill inverts player's states when player wins
- **WHEN** a game ends with the player winning and the in-memory log contains both player-side and clone-side states for that game
- **THEN** after backfill, the player-side rows SHALL be replaced with their `invertState` outputs (now `side=-1`, canonical from bot-POV, `outcome=+1` preserved), and the clone-side rows SHALL retain their post-backfill values without inversion

#### Scenario: Backfill leaves bot-won games unchanged
- **WHEN** a game ends with the bot winning
- **THEN** the standard per-side outcome flip SHALL apply but no inversion SHALL run; the clone's states are already in bot-POV space with `outcome=+1`

#### Scenario: Outcome attribution after inversion
- **WHEN** an inverted state is read by the clone's weighting logic
- **THEN** `outcome=+1` on a state with `side=-1` SHALL be interpreted as a winning trajectory from the canonical mover's POV (i.e., useful for the bot)
