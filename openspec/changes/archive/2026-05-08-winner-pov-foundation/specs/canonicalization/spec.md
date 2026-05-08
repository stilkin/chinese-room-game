## REMOVED Requirements

### Requirement: Mirror normalization
**Reason**: Mirror canonicalization existed primarily as scaffolding for Zobrist exact-match equivalence. With Zobrist removed, mirror equivalence is recovered (if needed) at query time, not at write time.
**Migration**: Stored boards are no longer mirror-normalized. Mirror-equivalent positions don't match each other in the matcher unless query-time mirror search is added later.

### Requirement: Perspective normalization
**Reason**: Per-row perspective canonicalization split data into two parallel hash spaces, making cross-perspective lookup require workarounds. Replaced by per-game winner-POV storage at backfill time.
**Migration**: `GameState.side` field removed. Boards are stored in display perspective at write time; perspective transform applies once per game at backfill (only on bot wins).

## ADDED Requirements

### Requirement: Winner-POV storage at backfill
At game end, every row of the just-finished game SHALL be stored with a single, game-wide perspective convention: the winner's pieces SHALL be `+1` in the stored `board` and the loser's pieces SHALL be `-1`. Implementation:

- **Player wins**: rows are stored as-is (display perspective; player pieces already `+1`).
- **Bot wins**: every row of the game is replaced by `invertState(s, kernel)` at backfill time, which flips the board's perspective, recomputes the diffused-bit-hash on the flipped board, flips `materialBalance`, and preserves `movePlayed`, `ply`, `gameId`, `outcome`, and `movesToEnd`.
- **Draws**: rows are stored as-is (display perspective; no winner to align to).

After backfill, the DB invariant holds: every stored row's `outcome=+1` corresponds to a position where the winner just moved, and every `outcome=-1` corresponds to where the loser just moved.

#### Scenario: Player-won game stored as-is
- **WHEN** the player wins a game and the engine runs backfill
- **THEN** every row of that game SHALL retain its original `board` blob (display perspective preserved); even-ply rows SHALL have `outcome=+1` (player was the mover and won) and odd-ply rows SHALL have `outcome=-1` (clone was the mover and lost)

#### Scenario: Bot-won game inverted whole-game
- **WHEN** the bot wins a game and the engine runs backfill
- **THEN** every row of that game SHALL be replaced by `invertState(row, kernel)`: the stored `board` SHALL have all sign-flipped values (clone pieces become `+1`, player pieces become `-1`), `materialBalance` SHALL be sign-flipped, the diffused-bit-hash SHALL be recomputed on the flipped board, and `movePlayed`/`ply`/`gameId`/`outcome`/`movesToEnd` SHALL be preserved
- **AND** even-ply rows (originally player moves) SHALL have `outcome=-1` (player lost) and odd-ply rows (originally clone moves) SHALL have `outcome=+1` (clone won)

#### Scenario: Drawn game stored as-is
- **WHEN** a game ends in a draw
- **THEN** every row SHALL retain its original `board` blob and `outcome` SHALL be set to `0` for all rows (no winner)

#### Scenario: Outcome reflects mover-won-this-game across all stored rows
- **WHEN** any stored row is read
- **THEN** `outcome=+1` SHALL mean "the side who just moved (whose pieces are `+1` in this row's `board`) won this game"
- **AND** `outcome=-1` SHALL mean "the side who just moved (whose pieces are `+1` in this row's `board`) lost this game"
- **AND** `outcome=0` SHALL mean "this game ended in a draw"

### Requirement: Two-query search at read time
At every move decision, the bot SHALL run two independent searches against the stored data, with appropriate perspective transforms applied to the query, and combine the results:

- **Query A**: query board is `flipPerspective(currentDisplayBoard)`. Diffuse and bit-hash the flipped board. Search via `searchSimilar`. From the results, select rows with `outcome=+1` as positive-weight candidates ("the bot played this move from a similar position and won").
- **Query B**: query board is `currentDisplayBoard` unchanged. Diffuse and bit-hash. Search via `searchSimilar`. From the results, select rows with `outcome=-1` as negative-weight candidates ("the bot played this move from a similar position and lost").

Cross-side rows (Query A's `outcome=-1` rows, Query B's `outcome=+1` rows) SHALL be ignored — they describe the opponent's behavior, not the bot's.

#### Scenario: Query A finds bot-won game candidates
- **WHEN** the bot's `flipPerspective(currentBoard)` query matches stored rows
- **THEN** rows with `outcome=+1` SHALL be selected as positive-weight candidates and rows with `outcome=-1` SHALL be ignored

#### Scenario: Query B finds player-won game candidates
- **WHEN** the bot's unchanged `currentBoard` query matches stored rows
- **THEN** rows with `outcome=-1` SHALL be selected as negative-weight candidates and rows with `outcome=+1` SHALL be ignored

#### Scenario: Both queries' filtered candidates feed one vote
- **WHEN** both queries have produced their filtered candidate sets
- **THEN** the candidates SHALL be merged into a single weighted-candidate list and passed to `MoveSelectionStrategy.selectMove`

### Requirement: Sign-aware distance-weighted vote
Each candidate's weight SHALL be computed as:
```
weight = sign × (1 / (1 + movesToEnd)) × (1 / (1 + hammingDistance))
```
Where `sign` is `+1` for Query A's positive candidates and `-1` for Query B's negative candidates, `movesToEnd` is from the candidate's stored row, and `hammingDistance` is from the matcher.

`VoteByMoveStrategy` SHALL sum weights per move column (negative weights compose with positive ones to produce per-column net scores). If the post-vote best column's net weight is `≤ 0`, the brain SHALL route to the fallback strategy instead of returning the column.

#### Scenario: Closer match contributes more weight
- **WHEN** two candidates with the same outcome and movesToEnd differ in Hamming distance
- **THEN** the candidate with smaller Hamming distance SHALL have a larger absolute weight

#### Scenario: Loss candidate subtracts from a column's vote
- **WHEN** a column has both winning and losing candidates contributing
- **THEN** the column's net summed weight SHALL be the sum of positive contributions and negative contributions

#### Scenario: All-negative post-vote routes to fallback
- **WHEN** every legal move column has net weight `≤ 0` after the vote
- **THEN** the brain SHALL invoke the fallback strategy and report `usedFallback=true`

## MODIFIED Requirements

### Requirement: Canonicalization happens at write time
All perspective transformation (winner-POV alignment for bot-won games) SHALL be applied at backfill time before any subsequent query. Read-time queries SHALL apply only perspective transforms to the *query* board, never modifying stored data.

#### Scenario: Stored state is not transformed at query time
- **WHEN** a stored state is retrieved during search
- **THEN** the matcher SHALL compute distance against the stored `diffused_hash` and `board` directly, without any per-state transformation
