## MODIFIED Requirements

### Requirement: Winner-POV storage at backfill
At game end, every row of the just-finished game SHALL be stored with a single, game-wide perspective convention: the winner's pieces SHALL be `+1` in the stored `board` and the loser's pieces SHALL be `-1`. Implementation:

- **Player wins**: rows are stored as-is (display perspective; player pieces already `+1`).
- **Bot wins**: every row of the game is replaced by `invertState(s, kernel)` at backfill time, which flips the board's perspective, recomputes the **diffused image** (Int8List, quantized) on the flipped board, flips `materialBalance`, and preserves `movePlayed`, `ply`, `gameId`, `outcome`, and `movesToEnd`.
- **Draws**: rows are stored as-is (display perspective; no winner to align to).

After backfill, the DB invariant holds: every stored row's `outcome=+1` corresponds to a position where the winner just moved, and every `outcome=-1` corresponds to where the loser just moved.

#### Scenario: invertState recomputes the diffused image
- **WHEN** `invertState(state, kernel)` is invoked
- **THEN** the result's `diffusedImage` SHALL be `quantizeInfluenceMap(kernel.diffuse(flipPerspective(state.board)))`
- **AND** the result's `board` SHALL be `flipPerspective(state.board)`
- **AND** `materialBalance` SHALL be sign-flipped
- **AND** `movePlayed`, `ply`, `gameId`, `outcome`, `movesToEnd` SHALL be preserved unchanged

(Existing scenarios for player-won-as-is, bot-won-flipped, draw-as-is, outcome-meaning-across-rows are retained from the prior spec — they don't reference the diffused-bit-hash specifically and survive the change unchanged.)

### Requirement: Four-query search at read time
At every move decision, the bot SHALL run **four** independent searches against the stored data, with appropriate perspective and mirror transforms applied to the query, and combine the results:

- **Query A**: query board is `flipPerspective(currentDisplayBoard)`. Diffuse and quantize. Search via `searchSimilar`. Filter to `outcome=+1` rows. Sign `+1`. No move-untransform.
- **Query A mirror**: query board is `mirrorBoard(flipPerspective(currentDisplayBoard))`. Same retrieval. Filter to `outcome=+1`. Sign `+1`. Move-untransform: `c → cols - 1 - c` (game-specific). Image-untransform: left-right flip of the diffused image.
- **Query B**: query board is `currentDisplayBoard` unchanged. Same retrieval. Filter to `outcome=-1`. Sign `-1`. No move-untransform.
- **Query B mirror**: query board is `mirrorBoard(currentDisplayBoard)`. Same retrieval. Filter to `outcome=-1`. Sign `-1`. Same mirror untransforms as `Q_A mirror`.

Cross-side rows (Q_A's `outcome=-1`, Q_B's `outcome=+1`, etc.) SHALL be ignored — they describe the opponent's behavior, not the bot's.

#### Scenario: All four queries fire each turn
- **WHEN** the bot makes a move decision and the log has at least one completed game's data
- **THEN** the brain SHALL invoke `searchSimilar` four times, once per query, against the same `completedStates` candidate pool

#### Scenario: Mirror-query candidates carry untransform functions
- **WHEN** a candidate is returned from a mirror query
- **THEN** the candidate's diffused image SHALL be mirrored before contributing to the heatmap, and the candidate's `movePlayed` SHALL be mirrored before being surfaced to narration

#### Scenario: Cross-side filtering is enforced
- **WHEN** the four queries return their results
- **THEN** the brain SHALL keep only `outcome=+1` rows from `Q_A` and `Q_A mirror`, and only `outcome=-1` rows from `Q_B` and `Q_B mirror`; cross-side rows SHALL be discarded

### Requirement: Distance-weighted heatmap accumulation (replaces Hamming-distance vote)
Each candidate's weight SHALL be computed as:
```
weight = (1 / (1 + movesToEnd)) × (1 / (1 + l1Distance))
```
Weights SHALL be always positive, regardless of the originating query. `l1Distance` is the matcher's L1 distance over Int8 diffused images.

The aggregation step is delegated to `InfluenceOverlayStrategy` (see `move-selection` spec): each candidate contributes `weight × candidate.diffusedImage` (mirrored if from a mirror query) to a single board-shaped signed heatmap. The candidate image's *natural sign* carries the win/loss lesson — winner-mover candidates have positive territory at their mover's cells (push the heatmap up there → "play here"), loser-mover candidates have negative territory there (push the heatmap down there → "avoid here"). An explicit sign multiplier on the weight would double-count and invert the loss signal, so it is intentionally omitted.

The legal move with the highest heatmap score (via `MoveScorer`) is selected. If the highest score is `≤ 0`, the brain falls back instead.

(Cross-references the move-selection spec for the heatmap accumulation and scoring details.)

#### Scenario: Closer match contributes more weight
- **WHEN** two candidates with the same `outcome` and `movesToEnd` differ in `l1Distance`
- **THEN** the candidate with smaller `l1Distance` SHALL contribute a larger-magnitude term to the heatmap

#### Scenario: All-losing chosen move routes to fallback
- **WHEN** the chosen move's heatmap score is `≤ 0`
- **THEN** the brain SHALL invoke the configured fallback strategy and report `usedFallback=true` with `narration=DecisionContext.allLosing`

## REMOVED Requirements

### Requirement: Two-query search at read time
**Reason**: Replaced by the four-query variant above. The two-query design covered winner-POV but not left/right symmetry; with image-distance retrieval, mirror queries are cheap and useful. Left/right symmetry is recovered without re-introducing write-time mirror canonicalization.
**Migration**: Callers running two queries upgrade to four; mirror queries require explicit move-untransform and image-untransform handling. Stored data is unchanged (the storage convention was already mirror-blind).
