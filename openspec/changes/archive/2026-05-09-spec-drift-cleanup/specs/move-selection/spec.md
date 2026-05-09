## MODIFIED Requirements

### Requirement: Move selection strategy is game-specific
The `GameRules` interface SHALL include a `MoveSelectionStrategy` that defines how weighted candidates are converted into a chosen move. Each game provides its own strategy. For Connect Four, the strategy is `InfluenceOverlayStrategy(ConnectFourMoveScorer())`.

#### Scenario: Connect Four uses InfluenceOverlay
- **WHEN** the clone brain selects a move for Connect Four
- **THEN** it SHALL use `InfluenceOverlayStrategy` paired with `ConnectFourMoveScorer`

#### Scenario: Strategy is provided by GameRules
- **WHEN** a new game type is added
- **THEN** it SHALL specify its move selection strategy as part of the GameRules implementation

## REMOVED Requirements

### Requirement: Cold-start fallback personalities (carried forward)
**Reason**: Duplicate. The authoritative requirement for fallback personalities lives in `clone-brain/spec.md` (`Cold-start fallback personalities`), updated by the `fallback-personalities-slider` change to the slider personalities (Chaotic, Builder, Stacker, Connector, Sentinel). The `move-selection` copy still listed the pre-slider set including `edge-focus` and was a contradiction, not a cross-reference.
**Migration**: None — the canonical fallback list is the one in `clone-brain/spec.md`.
