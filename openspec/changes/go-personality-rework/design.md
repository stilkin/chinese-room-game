## Design

### Why diamond > hugger (in Go terms)

Two own stones placed orthogonally adjacent share three liberties. They cover the same set of cells (their union of neighbours is small). In Go this is called **馬鹿形 ("dumpling shape")** — over-concentrated, inefficient, weak. The original Hugger maximised exactly this: "pick the cell with the most friendly orthogonal-neighbours" produces 2-block, 3-block, then larger dumplings.

Two own stones placed *diagonally* adjacent (a **kosumi**) share **zero** liberties — they each control their own 4 cells. The union of their neighbours is 8 cells, exactly twice as much board influence. The shape is also "thick" (hard to cut) without being inefficient. Four stones in the rotated-square arrangement form a **ponnuki**, the canonical thick-but-efficient shape in Go.

The rework's scoring formula:

```text
score(cell) = (count of side-coloured diagonal neighbours)
            − (count of side-coloured orthogonal neighbours)
```

A move adjacent to one own stone (dumpling-extending) scores `0 − 1 = −1`. A move diagonal to one own stone (kosumi-extending) scores `+1 − 0 = +1`. A move that's the centre of a partial-diamond — diagonal to two of our stones — scores `+2`. The bot strictly prefers diamond extensions over dumpling extensions, and prefers central-of-diamond cells over single-diagonal cells. Tie-break pyramid is unchanged (Star-point weight → random survivor).

### Wanderer (localised random)

Pure-random on 13×13 spreads stones so thin that adjacent-cell interactions are rare. Most "random" moves get individually claimed or ignored, producing low-information games. The localised variant — empty cells within Manhattan-2 of any stone, uniformly random within — concentrates the randomness where the action is.

Manhattan-2 is the right radius: Manhattan-1 (used by Greedy) is too narrow for "random" because it just plays right next to existing stones; Manhattan-3 starts behaving like Greedy's reach without the scoring discipline. Manhattan-2 lets Wanderer make 1-space jumps, contact moves, and diagonals — the full vocabulary of moves "close to the action" — without scoring any of them.

Empty-board fallthrough: the prefilter set is empty when no stones exist on the board, so Wanderer cascades to Star-point. This keeps the cold-start opener recognisable (hoshi) rather than a corner stone with no purpose.

### Why same enum (`random`) for Wanderer

`random` is a universal fallback concept; CF benchmark code still uses it for pure-random. We don't want to fork the enum into `random` + `goWanderer` because:

1. The slider's user-facing label is already game-aware (we show "Wanderer" in Go mode, the CF tooling never surfaces).
2. The enum-name churn would force a persistence-coercion test, a settings-screen test update, and a CF benchmark file touch — for zero functional gain.
3. The behaviour is delegated by `rules is GoRules` inside `_fallbackMove`'s `random` case. Simple type-check, no abstraction overhead.

The trade-off is a small comment in the source: "for Go this is Wanderer; for CF this is uniform-random." Acceptable.

### Slider order and default

Gate ordering: Wanderer (9%) < Star-point (30%) < Contact (51%) < Diamond (77%) < Greedy (84%). Slider position matches strict observed strength.

The default *strategy* (`goStarPoints`) is unchanged from the previous post-gate state, but its **slider position** moves from 2 → 1 because Diamond climbed into the second-strongest seat. Star-point is no longer the slider's middle position, but the previous-default-strategy heuristic ("encouraging first-impression: ~30% win-rate, recognizable openings, contemplative aesthetic") still applies.

Contact at the new slider-mid would be a defensible default for "balanced 50/50 opponent" — that was briefly the choice before this proposal's author swung back to Star-point. The trade-off was: Contact at mid is mechanically tidier (default = mid-of-slider matches CF precedent) but its tactical "rush your stones" feel is less inviting on first contact. Star-point's hoshi openers communicate "this is Go" from move 1 even when the player doesn't know the brain is fallback-driven.

### Migration

No schema bump. The persistence-layer `loadFallback` already coerces unknown strings to `_kDefaultFallback`. Legacy `goHugger` strings stored before this rework will not match any enum value (the symbol was renamed), so they fall through to `_kDefaultFallback = goStarPoints`. Users on Chaotic (`random`) keep their setting; their Go-mode behaviour silently becomes Wanderer.

The slider's *position* for existing users changes: legacy-Hugger users (slider position 0) land on Star-point (position 1) by way of the default coercion. Legacy-Chaotic users at position 1 stay at position 0 because Wanderer occupies that seat. Star-point / Contact / Greedy users are unaffected.

### Risks

1. **Diamond may be too strong.** At 77% win-rate it's close to Greedy. If on-device play feels "Diamond and Greedy are interchangeable" we may want to tune Diamond down — maybe by dropping the orthogonal-friendly subtraction (option (a) from the proposal discussion, which would weaken Diamond by ~10 win-rate points based on rough estimates). Defer until smoke feedback.
2. **Wanderer at 9% may feel "too weak"** for a slider's leftmost seat. The previous Chaotic at 27% had similar leftmost-position issues. Acceptable: the slider's leftmost seat is intentionally the weakest, and Wanderer-vs-pure-random is a slight strength upgrade against same-opponents (11.3% vs 8.7% against unchanged Star-point/Contact/Greedy).
3. **Star-point dropping from position 2 to position 1** silently moves the default thumb's screen position. Users who haven't touched the slider will see the thumb appear in a different place than they remember. Trade-off accepted for honest "slider = strength axis" semantics; the personality blurb still reads "Star-point" so the experience is consistent.
4. **No spec drift between go-fallback-personalities (pre-archive) and this rework**: this proposal's spec deltas describe the Go-mode subset after the rename + scoring change + Wanderer routing. When `go-fallback-personalities` archives first, its deltas flush into canonical specs describing `goHugger` etc; then this proposal's archive flushes the rework over the top. The canonical-spec evolution is `(pre-Go) → (post-go-fallback-personalities) → (post-this-rework)` — clean.
