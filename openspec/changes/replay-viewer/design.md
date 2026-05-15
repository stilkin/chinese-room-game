## Design

Three pieces — persistence read path, list screen, replay screen — plus a small tweak to the existing strip widget and `GoBoard`. Nothing is reused that already exists in a heavier form; nothing new is created speculatively.

### Persistence: extended `RecentGame` + `loadGameForReplay`

`RecentGame` today is the home-strip row shape. The history list needs three more bits of metadata per row (game id for navigation, started_at for display, total_moves for the move counter). We extend the typedef rather than build a parallel `GameSummary` shape — one query, one type, two callers.

```dart
typedef RecentGame = ({
  String gameId,
  int startedAt,           // epoch ms; cheaper than DateTime through the DB layer
  int totalMoves,
  int outcome,             // +1 win, 0 draw, -1 loss
  int? playerArea,
  int? cloneArea,
});
```

`loadRecentGames` already does the `WHERE outcome IS NOT NULL ORDER BY started_at DESC LIMIT ?` query — just add the three columns to the `columns:` list and to the row mapping. The strip widget ignores the new fields; no visual diff.

For replay, a single new method:

```dart
typedef ReplayFrame = ({Board board, int movePlayed});

Future<List<ReplayFrame>> loadGameForReplay(String gameId) async {
  final rows = await db.query(
    'game_states',
    columns: ['ply', 'move_played', 'board', 'rows', 'cols'],
    where: 'game_id = ?',
    whereArgs: [gameId],
    orderBy: 'ply ASC',
  );
  return [
    for (final r in rows)
      (
        board: Board.fromBlob(r['board'] as Uint8List,
                              rows: r['rows'] as int,
                              cols: r['cols'] as int),
        movePlayed: r['move_played'] as int,
      ),
  ];
}
```

The replay screen also reads the matching `games` row (for outcome + areas + total_moves) but that's already covered by the history-list query and is passed through in the route arguments — no extra DB hit.

### Board inversion for display

Winner-POV storage means a bot-won game has every stored board sign-flipped so the clone's stones are `+1` on disk. For replay we always want the player to render as ivory (`+1`) — same as live play. The fix is one line, applied once when the replay frames are received:

```dart
final framesForDisplay = (game.outcome == -1)
    ? frames.map((f) => (board: invertState(f.board), movePlayed: f.movePlayed)).toList()
    : frames;
```

`invertState` is already exported from the engine. Player-won and draw games go through untouched. (`invertState` sign-flips the cells; `movePlayed` is a position index and is unaffected by the colour flip.)

### History list screen

Stateless screen. On first build it reads the notifier's already-loaded `recentGames` slice — the home screen pays the DB cost once, both screens share it. ListView.separated, one row per game:

```
┌──────────────────────────────────────────────┐
│ May 12, 14:32        WIN    87 moves         │
│ ▌▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░▌      84 : 76         │
└──────────────────────────────────────────────┘
```

The proportion bar (the `▌▓▓░░▌` line) is a one-row `CustomPaint` reusing the same `AreaHistoryPainter` the strip uses, lifted out of `area_history_strip.dart` into a top-level helper. Rows for resigned games show `RES` chip, "—" area split, and a muted DNF bar; rows for pre-v6 legacy games (null area) render the same DNF treatment.

Empty state when `recentGames.isEmpty`: a centred muted text "No completed games yet." Nothing else.

Tap → `Navigator.push` to `/replay` with the row's `RecentGame` as arguments.

### Replay screen — controller + view

The replay screen owns one `ReplayController` (a `ChangeNotifier`) and a single `GoBoard` for rendering:

```dart
class ReplayController extends ChangeNotifier {
  ReplayController({required this.frames, required this.totalPlies});

  final List<ReplayFrame> frames;          // length == totalPlies (no empty ply 0; see below)
  final int totalPlies;

  int _ply = 0;                            // 0 = empty board, 1..totalPlies = after k-th move
  double _speedFactor = 1.0;               // 1.0 / 2.0 / 4.0
  bool _isPlaying = false;
  Timer? _ticker;

  int get ply => _ply;
  double get speedFactor => _speedFactor;
  bool get isPlaying => _isPlaying;
  bool get isAtStart => _ply == 0;
  bool get isAtEnd => _ply == totalPlies;

  Board boardAtCurrentPly() =>
      _ply == 0 ? Board.empty(rows, cols) : frames[_ply - 1].board;
  int? lastMoveAtCurrentPly() =>
      _ply == 0 ? null : frames[_ply - 1].movePlayed;

  void jumpToStart() { _stopTicker(); _ply = 0; notifyListeners(); }
  void jumpToEnd()   { _stopTicker(); _ply = totalPlies; notifyListeners(); }
  void stepBack()    { if (_ply > 0)          { _ply--; notifyListeners(); } }
  void stepForward() { if (_ply < totalPlies) { _ply++; notifyListeners(); } }
  void seek(int ply) { _ply = ply.clamp(0, totalPlies); notifyListeners(); }

  void togglePlay() { _isPlaying ? _pause() : _play(); }
  void cycleSpeed() { /* 1× → 2× → 4× → 1×; restart ticker if playing */ }

  // …play loop: Timer.periodic(600ms / speedFactor) → stepForward(); pause on end…
}
```

`ply == 0` is the pre-game empty board — needed so the user can hit `⏮` and watch from move 1. The frames list has one entry per played move; ply `k` shows the board after the k-th move.

The view tree is minimal:

```
Scaffold
  appBar: outcome verdict ("YOU WIN" / "CLONE WINS" / "DRAW" / "RESIGNED")
  body: Column
    - Area readout line (suppressed if outcome == resign or areas missing)
    - GoBoard(board: boardAtCurrentPly, lastMove: lastMoveAtCurrentPly, readOnly: true)
    - "Move 23 / 88 (pass)"  ← (pass) only when the current ply is a pass move
    - Slider(min:0, max:totalPlies, value:ply, onChanged: seek)
    - Row(VCR buttons): ⏮ ⏴ ⏯ ⏵ ⏭
    - Speed chip (top-right of slider row): "1×" / "2×" / "4×"
```

The play loop uses `Timer.periodic`; tempos: 1× = 600ms/move, 2× = 300ms, 4× = 150ms. Hitting the end while playing pauses (does not loop) — looping is novelty that grates fast.

### `GoBoard` `readOnly` flag

The board widget today accepts taps and forwards them to the notifier. Add one new optional flag:

```dart
const GoBoard({
  super.key,
  required this.board,
  required this.lastMove,
  this.readOnly = false,
});
```

When `readOnly == true`, the `GestureDetector` is omitted (or its `onTapDown` returns immediately). No other change. Live play stays untouched.

### Pass-move handling

`movePlayed == passMove` indicates a pass ply. The board at ply `k` after a pass is identical to the board at ply `k - 1`. The slider still advances through pass plies — the user sees the move counter tick from "Move 86 / 88" to "Move 87 / 88 (pass)" with no visible board change. Two consecutive passes at the end (the standard Go terminator) render naturally: "Move 87 (pass)" then "Move 88 (pass)" then game over.

For the last-move ring on a pass ply: don't draw one. (There's nowhere to put it.) Logic: `if (lastMove != null && !isPass(lastMove)) drawRing(lastMove)`.

### Strip becomes a tap target

The existing `AreaHistoryStrip` widget itself does *not* change. The wrapping happens on the start screen:

```dart
GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: () => Navigator.pushNamed(context, '/history'),
  child: AreaHistoryStrip(games: notifier.recentGames),
)
```

`HitTestBehavior.opaque` so the entire painted region (including the transparent row gaps) is tappable, even when the strip has few rows.

### Routes

Two named routes in `main.dart`:

```dart
'/history': (ctx) => const HistoryScreen(),
'/replay':  (ctx) => ReplayScreen(game: ModalRoute.of(ctx)!.settings.arguments as RecentGame),
```

`/history` reads `notifier.recentGames` directly — no arguments needed. `/replay` receives the tapped `RecentGame`; the screen kicks off `loadGameForReplay(gameId)` in `initState` and shows a small spinner while frames load (a 100-ply game is ~17KB of board blobs — typically loads in tens of ms but the spinner avoids a jarring blank frame).

### Risks & decision points

1. **Sharing the painter between strip and list row.** Lifting `AreaHistoryPainter` out of the strip file is a 10-line move with no behaviour change, but it does mean the painter is now a public-ish API for two callers. Acceptable — the alternative (duplicate two near-identical painters) violates the prime directive harder.
2. **`RecentGame` typedef growth.** Three new fields make the strip's per-row data slightly heavier (≈40 bytes/row × 100 rows = 4KB). Trivial. The widget code is unchanged; the typedef change is the only diff at the strip side.
3. **Replay controller vs vanilla `setState`.** A `ChangeNotifier` is mild overkill for one screen, but it makes the play-loop testable in isolation (no widget tree needed) and matches the rest of the app's state convention. Cost: one tiny file.
4. **Inversion happens at replay-load time, once.** Alternative: invert per-frame on demand. Rejected — repeated work, no memory benefit at this scale. The inverted frames are at most 100 × 169 bytes = 17 KB.
5. **Replay of in-progress games.** Excluded by `loadRecentGames` (it filters `WHERE outcome IS NOT NULL`). The Resume button on the home screen remains the path for the ongoing game.
6. **No animation on stone placement during replay.** Considered a 150ms fade-in matching live placement; rejected for v1 — replay reads as "scrubbing through history," not "watching the game live." Add later if it feels too snappy on device.
7. **Speed semantics.** `1× / 2× / 4×` cycles via a single chip rather than three radio buttons; one tap to change, fits the bottom-bar real estate, no popup needed. The chip lives in a separate row from the VCR buttons so the VCR buttons each do exactly one thing.
8. **Slider granularity at long games.** A 200-ply game on a phone gives ~3 plies per logical pixel of slider width — fine for coarse seeking; the step buttons handle precise navigation. Acceptable.
9. **What if `frames.length != game.total_moves`?** Defensive: we trust the `game_states` rows (source of truth). `total_moves` is the displayed total; mismatches would indicate DB corruption and we'd want to surface them, not paper over them. v1 assumes consistency.
10. **Out of scope explicitly:** historical narration text (not stored; regenerating against today's DB gives "what the clone would say now" which is misleading), coordinate labels ("K10"), capture animations, sharing/export, multi-game compare. Each is a clear separate change if/when wanted.
