## Context

The `canonicalization` spec already requires loss inversion ("every lost game stored as a won game from the opponent's perspective"), but the engine code never implemented it. During mobile-app planning we explicitly chose to skip it on the (incorrect) assumption that per-move perspective canonicalization already covered both POVs in the same canonical space.

It does not. The player's stored canonical board has the player's pieces as `+1`; the clone's query canonicalizes the same display board with `side=−1`, which negates → different Zobrist hash, no match. Cold-start games are mostly fallback even when the player has built up history.

## Goals / Non-Goals

**Goals:**
- Make the player's wins available to the clone's case-based search.
- Keep the engine's API surface minimal — one new public function.
- Keep storage cost flat (no doubled row count).
- Reuse the existing canonicalize pipeline so the inverted state is mirror-canonical from the bot's POV.

**Non-Goals:**
- No retroactive inversion of existing stored data. New games will be inverted; old data won't.
- No change to the search/weighting logic. Inverted states are normal `GameState` rows in the log.
- No new persistence schema. We use existing tables and existing insert/delete APIs.
- No async / background work. Inversion runs synchronously at game-end.
- No inversion of bot-won games. Clone's states already live in bot-POV space.

## Decisions

### Inversion at backfill, not at write time

We keep the per-move write path simple — store the mover's POV state as today. At game end, if the player won, replace each player-side row with its inversion. Keep the bot-win path untouched.

*Alternative: write a twin per move (the original v1 of this proposal).* Rejected — doubled row count, asymmetric query coverage (only twin matches mattered for the bot, originals were dead weight), and a subtle mirror-consistency edge case. Backfill-time inversion is cleaner: one row per move, deterministic outcome, full canonical pipeline run on the inverted result.

### Invert every row of player-won games (not just the winning side)

When the player wins, we rewrite the whole game as if the bot played it: the player rows become the bot's *winning* trajectory and the clone rows become the opponent's *losing* trajectory. Every row of the game stays consistent — same side conventions, same outcome semantics, same canonical perspective.

*Alternative considered: invert only the winning player's rows, leaving the clone's losing rows in place.* Rejected. The argument for the asymmetric scheme was Zobrist-specific: clone rows are weight-zero under the current outcome-based weighting, so inverting them produces no behavioral difference. But that's a contingent property of today's matching system, not a long-term invariant — once we sunset Zobrist for perceptual / diffusion-image matching, "weight-zero in -canonical space" stops being a useful frame, and the asymmetric storage just looks like dead code. Full inversion gives a cleaner, more uniform data model that survives the matching-system rewrite.

When the bot wins, no inversion happens — the standard per-side backfill has already produced the right shape (bot rows: side=-1 outcome=+1; player rows: side=+1 outcome=-1).

### `invertState` re-runs the full canonicalize pipeline

```
GameState invertState(GameState s, ZobristTable table, DiffusionKernel kernel) {
  // 1. Recover a representative of the displayed board (modulo mirror).
  final afterMirror = s.side == 1 ? s.board : flipPerspective(s.board);

  // 2. Canonicalize from the OPPOSITE side's POV — mirror + perspective.
  final canonical = canonicalize(afterMirror, -s.side, table);

  // 3. Recompute the diffused-bit hash on the new canonical.
  final influence = kernel.diffuse(canonical.board);
  final diffusedHash = influenceMapToBitHash(influence);

  return GameState(
    board: canonical.board,
    zobristHash: canonical.zobristHash,
    diffusedHash: diffusedHash,
    movePlayed: s.movePlayed,
    ply: s.ply,
    side: -s.side,
    gameId: s.gameId,
    totalMaterial: s.totalMaterial,
    materialBalance: -s.materialBalance,
    outcome: s.outcome,        // preserved; see "Outcome semantics" below
    movesToEnd: s.movesToEnd,
  );
}
```

Step 1 recovers a board representative from the canonical equivalence class — either the displayed board or its mirror, both work because canonicalize is mirror-idempotent.

Step 2 re-canonicalizes from the opposite POV. This is the key: because we go through `canonicalize` (not just bit-flip the input), the mirror choice is correctly recomputed for the negated board. Whatever a fresh query at an equivalent displayed board would land on — that's exactly what the inverted canonical equals.

Step 3 recomputes the diffused hash on the new canonical. Diffusion is sign-sensitive (the threshold flips on negation) and mirror-sensitive (mirror flips column positions), so neither bit-inversion nor a clever shortcut is sound. Recompute. It's a few hundred ops for Connect Four — trivial.

### Outcome semantics — preserved per row, not flipped

`invertState` preserves each row's `outcome` field as-is. After standard backfill, a player-win game has player rows at `outcome=+1` and clone rows at `outcome=-1`. After full-game inversion, player rows are `side=-1, outcome=+1` and clone rows are `side=+1, outcome=-1` — the outcome label still tracks "did the side stored in this row's `side` field win?", consistent with the standard backfill convention.

So under full-game inversion, the `outcome ↔ side` correspondence remains the natural one: a row with `outcome=+1` represents "the side recorded here won this game." No semantic shift, no special interpretation — the game is just stored with sides swapped end-to-end.

The bot's weighting reads `outcome` directly without consulting `side`, so existing weighting code is unaffected.

### Backfill ordering: standard outcomes first, then invert

`GameLog.backfillGame` keeps its current behavior — sets `outcome` and `movesToEnd` per-side. After it runs, `_endGame` checks the winner. If the player won, it walks **every** row of the just-finished game, calls `invertState` on each, and atomically swaps them in both the in-memory log and the database.

*Alternative: do the inversion inside `backfillGame`.* Rejected — `GameLog` doesn't know about `ZobristTable` or the diffusion kernel, and forcing it to would couple the engine's data model to its hashing/diffusion infrastructure. Orchestration in the notifier keeps `GameLog` a dumb container.

### DB inversion is a single game-scoped delete-then-bulk-insert

The inverted row's `board` blob, Zobrist hash, diffused-hash blob, side, and `materialBalance` all change. Per-row UPDATE for that many columns is just as costly as a delete-then-insert, and the latter reuses the existing column-builder (`_gameStateColumns`). The notifier produces the full set of inverted rows up front, then `replaceAllStatesForGameAtomic(gameId, replacements)` does one game-scoped DELETE plus N inserts inside one SQLite transaction so the swap is atomic.

## Risks / Trade-offs

**[Hash recompute on inversion]** → A few hundred extra ops per inverted row, only at backfill, only on player-won games. Negligible.

**[Old data lacks inversion]** → Games stored before this lands won't get inverted retroactively. Acceptable: the MVP hasn't shipped widely; new games naturally fill in.

**[Backfill is no longer write-time-only]** → Originally we said "canonicalization happens at write time, never at query time." Backfill-time inversion technically rewrites stored canonicals at game-end. This is a deliberate exception — distinct from query-time canonicalization, which still doesn't happen.

## Migration Plan

No user-facing migration needed. First ship that includes this change starts inverting at the next player-won game. Existing data is unchanged. "Delete All Game Logs" still works.
