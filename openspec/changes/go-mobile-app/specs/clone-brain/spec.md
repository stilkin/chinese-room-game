## MODIFIED Requirements

### Requirement: Cold-start fallback personalities

The system SHALL support fallback strategies that fire when the clone has no relevant data (no candidates found, all candidates fall outside the prefilter window, or the all-losing guard rejects the chosen move). For the initial Go release, the user-facing set SHALL contain a single strategy:

- `random` — pick a uniformly random legal move (intersection or pass). *User-facing label: "Chaotic".*

Game-specific stronger personalities (Connect Four's `pileFocus`, `ownPileAdjacent`, `greedyConnect`, `greedyConnectDefense`, and any future Go-specific equivalents) SHALL remain available in the engine package for benchmark and research use, but SHALL NOT be selectable via the user-facing settings UI until a separate change populates the ladder for the active game.

#### Scenario: No candidates triggers fallback
- **WHEN** the clone has no candidates that meet the search threshold
- **THEN** the system SHALL use the configured fallback strategy

#### Scenario: Random fallback (Chaotic)
- **WHEN** the fallback strategy is `random`
- **THEN** the bot SHALL pick a uniformly random legal move from the legal-move list (which includes pass)

#### Scenario: Engine retains other strategies for benchmarks
- **WHEN** an engine benchmark imports `FallbackStrategy.pileFocus` (or any other Connect-Four-specific value)
- **THEN** the engine SHALL still support that strategy for offline use
- **AND** the mobile settings UI SHALL NOT expose it
