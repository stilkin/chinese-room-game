## Context

The engine accumulated three layers of write-time data transformation, each with its own justification:
- **Mirror canonicalization** to make Zobrist exact-match see mirror-equivalent positions as identical.
- **Perspective canonicalization** to "always store from the side-to-move's POV" so a single hash space holds both sides' moves.
- **Loss inversion** (just shipped) to bring player wins into the bot's hash space when the per-row perspective canonicalization had separated them.

In practice the layers compose into something hard to reason about: the `outcome` field's semantics shift under inversion; `movePlayed` is in display column space but the canonical board may be mirrored relative to it (latent correctness bug); the bot's queries see only one of two parallel hash spaces.

User-driven discussion identified the simpler model: **per-game perspective at write time, all rows aligned to the winner's POV**, with read-time perspective transforms recovering both perspectives. No mirror normalization. No Zobrist. The bit-hash from diffusion already gives a robust fuzzy similarity signal — that's the only matcher we need.

This is mostly deletion. The engine gets smaller; the data model gets one invariant ("winner is +1 everywhere") instead of three layered transformations.

## Goals / Non-Goals

**Goals:**
- Single write-time invariant: in every stored game, the winner's pieces are `+1`, the loser's are `-1`. Sequential rows of a game form a coherent narrative — same color always belongs to the winner.
- Single read-time pattern: two queries (one per perspective transform of the current board), sign-aware weighted voting.
- Drop Zobrist entirely; the diffused-bit-hash distance is the only matcher.
- Drop mirror canonicalization; mirror equivalence is deferred (recoverable at query time later if needed).
- Bot learns from both wins (positive weight) and losses (negative weight) without per-row inversion gymnastics.
- Generalizes to other two-player signed-piece games (Chess, Go, Othello, Checkers) without engine changes.

**Non-Goals:**
- No retroactive migration of existing data. Schema v1 → v2 wipes `game_states` and `games`. The MVP hasn't shipped widely; the cost is acceptable.
- No mirror equivalence in this change. Mirror is a future optimization (extra query-time mirror-flip search if it materially helps).
- No opponent modeling. The "cross-side" rows (Query A's outcome=-1 = player's losing-game moves; Query B's outcome=+1 = player's winning moves) are ignored at the matcher level. Future opportunity.
- No diffusion-image overlay matching. This refactor makes us forward-compatible with it but doesn't implement it.
- No look-ahead / minimax. Out of scope.

## Decisions

### Per-game winner-POV storage at backfill time

At game end, decide perspective once for the whole game and apply it to every row:
- **Player wins** → store as-is (display board has player=+1, clone=-1; player is the winner so winner=+1 already).
- **Bot wins** → invert every row (`flipPerspective(board)`, `materialBalance` flips sign, hashes recompute). After the flip, bot's pieces become +1 in storage; bot is the winner so winner=+1 holds.
- **Draws** → store as-is (no winner; arbitrary perspective, default to display POV).

Outcome and `moves_to_end` are set by the standard backfill *before* the bot-won-game flip. After the flip, the post-flip rows naturally have:
- Even-ply rows (originally player moves) → `outcome=-1` (player lost). After flip: still `outcome=-1`, board has player=-1 (loser=-1 ✓).
- Odd-ply rows (originally clone moves) → `outcome=+1` (clone won). After flip: still `outcome=+1`, board has clone=+1 (winner=+1 ✓).

Invariant verified: rows with `outcome=+1` have winner-just-moved (winner pieces are +1 in board); rows with `outcome=-1` have loser-just-moved (loser pieces are -1 in board).

*Alternative considered: per-row perspective canonicalization (the current scheme).* Rejected — it splits data into two parallel hash spaces, making cross-perspective lookup require workarounds like loss-inversion. The user's per-game framing is materially simpler.

*Alternative considered: twin storage (store every game twice, one per POV).* Rejected — 2× storage cost without gaining anything over per-game POV + two-query read.

### Drop Zobrist entirely

`ZobristTable`, `SplitMix64`, the `entryFor`/`hashBoard` helpers, the `_shouldMirror` predicate (which used `entryFor` for its halving hash), the `zobrist_hash` column, the `zobristHash` field on `GameState`, the `queryZobristHash` parameter, and the exact-match tier in `searchSimilar` — all gone.

The diffused-bit-hash + Hamming distance is the sole matcher. Two boards that produce the same bit-hash but differ in subtle non-influence-bearing cells will be treated as identical, which is fine — they're functionally equivalent at the diffusion-pattern level. Exact equality of arbitrary state is not a goal.

*Alternative considered: keep Zobrist as a fast pre-filter for exact matches.* Rejected — adds a code path with no clear benefit. At MVP scale (low thousands of rows), full fuzzy scan is microseconds; the optimization isn't earning its complexity.

### Drop mirror canonicalization

Without Zobrist's exact-match requirement, the case for mirror canonicalization weakens significantly. Diffused-bit-hashes of mirror-equivalent boards are *not* the same (diffusion is position-aware), so mirror equivalence never came for free in fuzzy match — it relied on canonical mirror collapsing both into the same stored representation.

Without mirror canonicalization, two mirror-equivalent positions match each other only weakly (high Hamming distance). The data efficiency cost is real: roughly 2× the data needed before the bot finds patterns common to mirrored positions. At human-play scale (tens of games), this is acceptable.

If it materially hurts the bot in practice, we can recover mirror-equivalence at query time (search both `currentBoard` and `mirror(currentBoard)`). Defer until measurement says we need it.

*Why not keep mirror?* The mirror-replay bug (`movePlayed` in display column space possibly disagreeing with stored canonical's mirror polarity) is a real correctness issue that complicates reasoning. Removing the source eliminates the bug.

### Drop the `side` column

Under winner-POV storage, the row's mover identity (winner vs loser) is fully captured by `outcome`:
- `outcome=+1` → winner just moved (in winner-POV, the +1 pieces moved).
- `outcome=-1` → loser just moved.

The previous semantic of `side` (the original mover's display side) is no longer meaningful — every game has been transformed to a single perspective at write time. Drop the field and the column.

This also drops some `backfillStates` complexity: instead of `CASE WHEN side = 1 THEN ? ELSE ?`, we use ply parity (`CASE WHEN (ply % 2) = 0 THEN ? ELSE ?`) since the player always moves on even plies and the clone on odd plies. Same outcome, simpler SQL.

### Two-query search at read time

The bot's query at the current display board needs to reach all rows where the bot was the mover. Under winner-POV storage:

- **Bot-won games** have the bot's rows stored with bot=+1 in board. The bot's display has bot=-1. Mismatch. To match, the bot must transform its query: `flipPerspective(currentBoard)` flips bot's pieces to +1. **Query A** uses this flipped query. Within bot-won games, the bot's own rows have `outcome=+1` (winner moved) — those are the candidates we want. Filter to `outcome=+1`.

- **Player-won games** have the bot's rows stored with bot=-1 in board (no flip applied). The bot's display also has bot=-1. Match without transform. **Query B** uses `currentBoard` unchanged. Within player-won games, the bot's rows have `outcome=-1` (loser moved). Filter to `outcome=-1`.

So:
- Query A → outcome=+1 rows = "bot played X here and won" → positive weight.
- Query B → outcome=-1 rows = "bot played X here and lost" → negative weight.

The cross-side rows (Query A's outcome=-1 rows = player's losing moves from bot-won games; Query B's outcome=+1 rows = player's winning moves from player-won games) describe the opponent's behavior, not the bot's. Their interpretation requires opponent modeling; defer.

Both queries run independently and feed the same vote. Two diffusions per query at MVP scale = sub-millisecond. Negligible.

*Alternative considered: drop perspective canonicalization entirely (store in display space, query 4× including mirror flips).* Equivalent in semantics, slightly more invasive. Per-game winner-POV is the chosen framing — it gives a meaningful invariant ("winner is +1") that aids both readability and forward compatibility with diffusion-image overlay matching.

### Sign-aware distance-weighted vote

Each candidate's weight composes three factors:

```
weight = sign × (1 / (1 + movesToEnd)) × (1 / (1 + hammingDistance))
```

- `sign`: +1 for Query A's positive candidates, -1 for Query B's negative candidates.
- `1/(1+movesToEnd)`: existing efficiency factor — closer-to-end states matter more.
- `1/(1+hammingDistance)`: new similarity factor — closer matches contribute more. Was previously discarded.

`VoteByMoveStrategy` sums per move column. Negative weights compose: a column with `+0.3` from one positive candidate and `-0.5` from a negative candidate has net `-0.2` — strongly avoided.

**Degenerate case**: if every candidate move column has net negative weight (the bot is in a losing-flavored position), `VoteByMoveStrategy` would still pick the "least bad" column. We add a guard in `selectMove`: if the post-vote best column's weight is `≤ 0`, route to the fallback strategy instead. The signal is "all options look bad; ignore the data and play heuristic."

### `invertState` and the helper plumbing

Engine-side `invertState` simplifies — no `ZobristTable` parameter, no Zobrist hash recompute. Just `flipPerspective(board)` + recompute diffused-bit-hash + flip materialBalance + preserve metadata.

`GameLog.replaceStatesForGame` and `db.replaceAllStatesForGameAtomic` (added in loss-inversion) survive unchanged — they're general-purpose helpers, just triggered on a different game outcome (bot won vs. player won).

The mobile notifier's `_invertCurrentGameToBotPerspective` renames to `_invertCurrentGameToWinnerPerspective` and changes its trigger condition (`winner == -1` instead of `winner == 1`).

### Schema migration: destructive

Existing rows under per-row perspective canonicalization are incompatible with the new winner-POV convention — the stored `board` blobs are in mixed perspectives that the new search can't interpret coherently.

Schema bump v1 → v2:
- DROP and recreate `game_states` (no `zobrist_hash`, no `side`).
- DELETE all rows in `games` (so the games-played counter resets).
- Preserve `clone_config` (settings).

The user has one device install. After this lands, on first launch the migration wipes prior games; settings (fallback strategy) survive.

*Alternative considered: in-place transform of existing rows (read-old, transform, write-new).* Rejected — it's not clear what "the right transform" of a per-row-canonicalized game is, since `side` was carrying information that we can't fully reconstruct without the original display boards. Wiping is honest.

### Narration changes

`narrate(DecisionContext.exactMatch, ...)` becomes unreachable (no exact-match tier); drop the case. `DecisionContext.invertedData` was already unused at the call sites (we never set narration to that context); drop. `narrate` simplifies to `fuzzyMatch / multipleCandidates / fallbackUsed / allLosing`.

The `_buildNarration` decision tree updates to reflect the two-query results. With the new sign-aware vote, the "all losing" branch fires when the post-vote best is `≤ 0` (the new fallback condition).

## Risks / Trade-offs

**[Destructive migration]** → On v1 → v2 upgrade, all existing game data is lost. → Acceptable: MVP not yet shipped widely; the user's single test install is fine to reset. Settings preserved.

**[Mirror equivalence dropped]** → Without mirror normalization (and without query-time mirror search), two strategically-equivalent mirrored positions don't match each other in the matcher. → Mitigation: ~2× data needed before patterns emerge across mirrors. At human-play scale, tolerable. Recover later via query-time mirror search if measurement justifies.

**[Cross-side rows ignored]** → The matcher gives access to "what the opponent did in similar positions" (Query A's outcome=-1, Query B's outcome=+1) but we currently filter those out. → Acceptable: opponent modeling has unclear semantics for direct move selection. Available for future work.

**[Negative weights confusing]** → `VoteByMoveStrategy` was designed for additive positive weights. With negatives, "least negative wins" is a behavior that may not match intuition. → Mitigation: explicit guard for "all negative" routes to fallback, so the bot doesn't pick a column it expects to lose with.

**[Diffused-bit-hash collisions]** → Without Zobrist as the exact-match tier, two genuinely different positions with identical bit-hashes are treated identically. → Acceptable: at the bit-hash resolution we're using (one bit per cell, sign of influence), collisions correspond to functionally-similar positions. The diffused-bit-hash is itself a fuzzy signal; treating it as "fuzzy enough" is correct.

**[Loss-inversion code we just shipped becomes redundant]** → `invertState` and `replaceStatesForGame` survive but are now used differently (bot wins, not player wins). The trigger and intent flip. → Acceptable: the helpers are general-purpose; only the wiring changes.

## Migration Plan

Single coordinated change. On the user's device:
1. Build & install the new APK.
2. App launches, sqflite migration fires (`onUpgrade` from v1 to v2): drops/recreates `game_states`, deletes `games`. Preserves `clone_config` (fallback strategy).
3. User starts a new game. Storage uses winner-POV convention. Bot uses two-query search.

No data preservation needed. No staged rollout.
