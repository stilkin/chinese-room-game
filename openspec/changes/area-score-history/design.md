## Design

### Schema migration (v5 → v6)

Additive only. `onUpgrade(db, oldVersion, newVersion)`:

```dart
if (oldVersion < 6) {
  await db.execute('ALTER TABLE games ADD COLUMN player_area INTEGER');
  await db.execute('ALTER TABLE games ADD COLUMN clone_area INTEGER');
}
```

`onCreate` for fresh installs gets the same two columns in its `CREATE TABLE games` statement.

Existing v5 rows surface as `playerArea: null, cloneArea: null` after the upgrade — the `AreaHistoryStrip` renders them as DNF/legacy rows (solid muted-grey). No upgrade UI; the visual change is the implicit "your old games are dimmed" effect.

`game_states` is unchanged. CBR retrieval doesn't need area; only the games-row index does.

### End-of-game persistence

`GameNotifier._endGame(int outcome)` is the single funnel where a game transitions from in-progress to completed. Right after the existing `db.updateGameOutcome(_gameId, outcome, _ply)` call, add:

```dart
if (rules is GoRules) {
  final score = (rules as GoRules).areaScore(_displayBoard);
  await db.updateGameAreaScore(_gameId, score.white, score.black);
}
```

`white` is +1, the player; `black` is -1, the clone — names match the engine's white-centric `areaScore` orientation, but at the persistence layer we map them to the player/clone semantic. New method:

```dart
Future<void> updateGameAreaScore(String gameId, int playerArea, int cloneArea) async {
  await db.update(
    'games',
    {'player_area': playerArea, 'clone_area': cloneArea},
    where: 'game_id = ?', whereArgs: [gameId],
  );
}
```

`resign` (in `GameNotifier`) does **not** call this — the columns stay NULL on resign by design. Rationale: an early-resign board is not a real territory outcome; persisting "AREA YOU 0 · CLONE 0" pollutes the history strip with misleading spans.

CF games leave the columns NULL too. CF doesn't ship in production any more, but the engine retains `ConnectFourRules` for regression coverage; the `if (rules is GoRules)` guard keeps CF safe even if it were re-surfaced.

### Read path: `loadRecentGames`

Replaces `loadRecentOutcomes`. Returns the most-recent N completed games in newest-first order.

```dart
typedef RecentGame = ({int outcome, int? playerArea, int? cloneArea});

Future<List<RecentGame>> loadRecentGames({int limit = 100}) async {
  final rows = await db.query(
    'games',
    columns: ['outcome', 'player_area', 'clone_area'],
    where: 'outcome IS NOT NULL',
    orderBy: 'started_at DESC',
    limit: limit,
  );
  return [
    for (final r in rows)
      (
        outcome: r['outcome'] as int,
        playerArea: r['player_area'] as int?,
        cloneArea: r['clone_area'] as int?,
      ),
  ];
}
```

`GameNotifier._recentOutcomes` becomes `_recentGames` of the same typed shape; the getter on the notifier is renamed accordingly.

### `AreaHistoryStrip` widget

Replaces `RecentGamesStrip`. Stateless. Inputs: `List<RecentGame> games` (already most-recent-first). Output: a `CustomPaint` that draws one row per game, top-down.

Per-row layout (left → right):

```
┌──┬──────────────────────────────┬──┐
│EC│  player area  │  clone area  │EC│
└──┴──────────────────────────────┴──┘
   ^                ^               ^
   3px endcap       proportion bar  3px endcap
```

**Constants** (defined inside the widget, not imported — the strip's geometry is local):

- `kRowHeight = 3.0` — gives a visible-but-tight visual rhythm.
- `kRowGap = 1.0` — single transparent line between rows so adjacent games don't visually merge.
- `kEndcapWidth = 3.0` — square per the row height; reads as a "frame" without dominating.
- `kCap = 100` — hard cap (caller's responsibility to slice; widget simply paints what it gets).

**Colours**:

- `playerColour = PiYingTheme.onSurface` — ivory; matches in-game player stones.
- `cloneColour = const Color(0xFF0E0E14)` — near-black; matches in-game clone stones.
- `drawColour = PiYingTheme.lineColor` — cream-amber; the existing board-line colour, semantically "neutral".
- `dnfColour = PiYingTheme.onSurfaceMuted` — already in the theme; reads as "no data".

**Per-row painting logic**:

```dart
if (game.playerArea == null) {
  // DNF / resigned / legacy: solid muted bar, no endcaps.
  fill row with dnfColour
  continue
}
final total = game.playerArea! + game.cloneArea!;
final playerFraction = total == 0 ? 0.5 : game.playerArea! / total;
// ── proportion bar (between the two endcaps) ──
fill [endcap..endcap+barWidth*playerFraction] with playerColour
fill [...rest...] with cloneColour
// ── endcaps (winner colour) ──
final endcap = switch (game.outcome) {
  1  => playerColour,
  -1 => cloneColour,
  _  => drawColour,
};
fill leftEndcap, rightEndcap with endcap
```

Edge case: a real Chinese-style 0–0 (impossible in practice on a normal-sized board, but imaginable on a 1x1) renders as a 50/50 draw line with cream-amber endcaps. Acceptable.

The widget paints into whatever `Size` the parent gives it. The start screen will hand it a `SizedBox(height: kRowHeight * games.length + kRowGap * (games.length - 1))` or similar; if the parent's height is shorter than the natural height, the widget paints what fits and silently truncates (won't happen in practice with the 100 cap and a tall scroll area).

No animations in v1. New rows just appear at top on next paint. If we want later: a 200ms slide-down for the existing rows when a new game lands, or a brief flash on the new row.

### Start-screen reorder

Old order:

```
header (icon + 皮影 + tagline)
"Your clone" stats box
LAST GAMES (RecentGamesStrip — small)
[Spacer]
New Game / Resume buttons
```

New order:

```
header (icon + 皮影 + tagline)
"Your clone" stats box
New Game / Resume buttons
LAST GAMES (AreaHistoryStrip — fills remaining space)
```

The buttons move *up* (closer to the stats box, more "above-the-fold" tappable) so the strip fills the bottom. The home screen remains a `SingleChildScrollView`. No nested scrollables.

### Post-game area readout

Below the existing W/L verdict, add a single line:

```
  AREA  ·  YOU 84  ·  CLONE 76
```

Source: `rules.areaScore(notifier.displayBoard)` for Go; absent for CF (CF games don't have territory). Render only when:

- `rules is GoRules`
- `score.white + score.black > 0` (suppress on empty/early-resign boards)

Style: `bodyMedium` weight, `onSurfaceMuted` colour — present without competing with the verdict.

### Risks & decision points

1. **Schema additive vs destructive**. We could wipe v5 → v6 (the rebrand-wipe precedent), getting rid of NULL legacy rows. Decided against: the user has built up real game history under v5, and the visual blurring of legacy rows (muted DNF lines) actually communicates "older history, less detailed" honestly. Wiping would feel hostile.
2. **Persisting on Go but not CF**. The `if (rules is GoRules)` guard reads as polymorphism leaking into the notifier. Acceptable: the notifier already has Go-specific code (pass move, area-score running tally) and CF is no longer a shipping configuration. If a third game lands later we'll either generalise (extend `GameRules` with an optional `({int p, int c})? finalScore(Board)` method) or accept the per-game guards.
3. **Endcap colour scheme**. We considered traffic-light green/red and brand cinnabar variants. Chose "winner-colour endcap" for self-consistency: a row's endcap colour matches the dominant area colour, so the winner reads at a glance even without inspecting the proportion. Cinnabar stays reserved for the in-board last-move ring and the delete-data accent.
4. **Hard cap of 100 vs unbounded**. 100 × ~4px ≈ 400px tall — tall but not absurd for a home-screen strip. Beyond 100 the marginal information is small (long-run trend doesn't change much over an extra 200 games). A future "view full history" screen with scrolling can come if real users hit the cap and care.
5. **DNF rendering**. The muted-grey solid row is honest ("no data") but visually breaks the proportion-bar pattern. Considered: skip DNF rows entirely (no row drawn at all). Rejected: skipping would let the player visually forget about resigned games, which is dishonest. The grey row keeps them in the rhythm.
6. **Test coverage of the painter**. CustomPaint widgets are notoriously awkward to test. We'll write a "paints expected colours at expected positions" test using `tester.pumpWidget` + a `Finder` of `CustomPaint`, and verify by hooking into the painter's accumulated `_drawnRects` (test-only field guarded by an `@visibleForTesting` getter). Lower-cost than golden file comparison; sufficient for "the row math is right".
