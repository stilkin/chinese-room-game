## Context

The game engine package (proposed separately) provides the clone brain, rules, and narration as a pure Dart library. This mobile app is the first playable surface — a Flutter app that wraps the engine with a UI, persistence, and game flow. It targets Android and iOS.

The app must feel simple and responsive. The clone's narration is the emotional hook — it must be prominent, not buried.

## Goals / Non-Goals

**Goals:**
- Playable Connect Four against the clone with full narration
- Persistent game state across app restarts via SQLite
- Minimal screen count: start, game, post-game, settings
- Clean separation between engine logic and app/UI concerns

**Non-Goals:**
- Animations, transitions, or visual polish (Phase 2)
- Game history browser or replay viewer (later proposal)
- Online sync, accounts, or multiplayer (Phase 3)
- Supporting games other than Connect Four (Phase 4)
- Custom theming or branding

## Decisions

### ChangeNotifier for state management

A single `GameNotifier` (extends `ChangeNotifier`) owns the game state: current board, whose turn it is, game outcome, narration text. Screens listen via `ListenableBuilder`. No external state management package.

*Alternative: Riverpod.* Rejected — adds a dependency and learning curve for a 4-screen app with one piece of shared state. ChangeNotifier is built into Flutter and sufficient here.

### Single GameNotifier, not per-screen notifiers

One notifier manages the full game lifecycle (new game → turns → outcome → backfill). Screens are views into that state, not independent state owners. This keeps the turn logic in one place and avoids synchronization bugs.

*Alternative: separate notifiers per screen.* Rejected — the game state flows across screens (start → game → post-game), so splitting it creates handoff complexity for no benefit.

### CustomPainter for the board

The Connect Four board is rendered with a single `CustomPainter` — draw the grid, draw the pieces. Tap detection maps touch coordinates to column index. No widget-per-cell approach.

*Alternative: GridView with widget cells.* Rejected — CustomPainter is simpler for a static grid with circles, avoids widget tree overhead, and generalizes better to other game boards (Chess, Go) in the future.

### SQLite schema mirrors GameState

One `game_states` table with columns matching the engine's `GameState` fields: `id`, `game_id`, `ply`, `board` (blob), `zobrist_hash`, `diffused_hash` (blob), `move_played`, `side`, `outcome`, `moves_to_end`. One `games` table for game-level metadata. A `clone_config` table for the fallback personality setting.

Board is stored as a raw byte blob (Int8List serialization). Hashes as integers or blobs. This is a direct mapping — no ORM, no abstraction layer.

*Alternative: JSON encoding for boards.* Rejected — wastes space and parse time for structured numeric data that maps directly to bytes.

### Load all states into memory on startup

On app launch, read all `game_states` rows into the engine's in-memory `GameLog`. New states are written to SQLite as they're created (dual-write). This keeps the engine's search path simple — pure in-memory operations.

Memory estimate for Connect Four: ~7 KB per game, ~7 MB at 1,000 games. Well within mobile limits.

*Alternative: query SQLite per clone turn.* Rejected for MVP — adds complexity without need at Connect Four scale. The pre-filter's `(total_material, material_balance)` columns are indexed for future SQL-side filtering if needed for larger games.

### Navigator with named routes

Four routes: `/` (start), `/game` (game screen), `/post-game` (post-game screen), `/settings` (settings). Simple push/pop navigation. No deep linking needed.

*Alternative: go_router.* Rejected — overkill for 4 static routes with no URL parameters or deep linking requirements.

## Risks / Trade-offs

**[Clone turn blocks the UI thread]** → The clone brain's search is fast for Connect Four (<5ms), so running it synchronously on the main isolate is fine. If it ever becomes slow (larger games), move to `Isolate.run()`. Not worth the complexity now.

**[Startup load time with large databases]** → At 1,000 games (~40K rows), SQLite read + deserialization takes <1 second. Show a splash/loading indicator if needed. Not a real concern for MVP usage levels.

**[Delete all game logs is irreversible]** → Show a confirmation dialog. No backup/export mechanism for MVP — add that if users request it.

**[No offline-first concerns]** → The app is entirely local. No sync conflicts, no network dependency. This simplifies everything.
