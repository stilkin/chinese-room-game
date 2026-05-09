## REMOVED Requirements

### Requirement: Move selection delegates to game-specific strategy
**Reason**: Subsumed by `Decision pipeline` (post-image-similarity), which already states that the brain delegates to the game's `MoveSelectionStrategy` (specifically `InfluenceOverlayStrategy` for Connect Four). The legacy requirement also referenced `vote-by-move`, which no longer exists.
**Migration**: None — `Decision pipeline` covers the delegation contract.
