# Pi-Ying — Play Against Yourself

## Project Vision

A mobile game platform where players play classic board games against an AI "clone" that learns exclusively from their own past games. The clone starts bad and improves as the player accumulates game data. The clone's decision-making is fully transparent — it narrates why it chose each move.

Optionally, players can sync their game logs to an online server where their clone competes against other players' clones in an automated league with leaderboards and replays.

The first game is **Connect Four**, with a roadmap toward Othello, Chess, and Go.

---

## Core Concept: The Clone Engine

The clone AI does not use neural networks, minimax, or any traditional game AI. Instead, it uses **case-based reasoning** over the player's own game history:

1. **Log every game state.** Each move in every game is recorded as a tuple: `(canonical_board_state, move_played, game_id, final_outcome, moves_to_end)`. Outcome and moves_to_end are backfilled when the game ends.

2. **On the clone's turn**, search the log for states most similar to the current board.

3. **Weight candidates** by outcome (wins > draws > losses) and move efficiency (winning in fewer moves is better).

4. **Play the best-weighted move** from the most similar historical state.

5. **Narrate the decision** to the player: "Playing a move I saw in game #5", "I've seen this before and it didn't end well — trying something different", "I don't know what to do, playing randomly."

### Key Properties

- The clone can only be as good as the player's own games.
- It improves naturally as the player plays more.
- It develops a "personality" that mirrors the player's style.
- The narration creates an engaging feedback loop — players see their own patterns reflected back.

---

## Board Representation

All games use a **2D array of signed bytes** (`Int8`). This covers:

| Game         | Board Size | Values Needed                          |
|--------------|------------|----------------------------------------|
| Connect Four | 7×6        | -1, 0, +1                              |
| Othello      | 8×8        | -1, 0, +1                              |
| Go           | 19×19      | -1, 0, +1                              |
| Chess        | 8×8        | ±1 to ±20 (weighted by piece value)     |

For chess, piece values are mapped to pixel intensities to make similarity search more strategically meaningful:

| Piece  | Value |
|--------|-------|
| Pawn   | 1     |
| Knight | 3     |
| Bishop | 3     |
| Rook   | 5     |
| Queen  | 9     |
| King   | 20    |

Negative values represent the opponent's pieces. The high king value ensures king-position differences dominate the similarity metric, reflecting strategic importance.

---

## Similarity Search: Board States as Images

Board states are treated as tiny grayscale images. Each piece's value is **diffused** — spread across the board according to the game's movement rules — and the resulting influence map is quantized to one signed byte per cell (Int8). Matching is L1 distance over those quantized images, with a per-game candidate prefilter (e.g. ply window for Connect Four) to trim the search space before distance compute.

A separate exact-hash layer was considered (Zobrist) and rejected: at our scale, single-pass L1 over Int8 vectors is microseconds and the prefilter already does the broad cut. Two representations per row was more storage and code for no measurable benefit.

### Diffused Similarity

Before computing similarity, board states are **diffused** — each piece's value is spread across the board according to the game's movement rules. The diffusion kernel **is the game definition**.

#### Diffusion Kernels Per Game

- **Connect Four:** Each piece radiates along the four winning directions (horizontal, vertical, two diagonals) for ~3 squares. This captures connection potential.
- **Go:** Spatial diffusion in all directions, attenuating with distance, blocked by opponent stones. Approximates influence/territory.
- **Chess:** Each piece radiates along its legal move paths (rook along rank/file, bishop along diagonals, knight to L-shaped squares, etc.). Stopped by obstacles (other pieces) on the first diffusion step. Subsequent steps are less strict about obstruction since multiple pieces will have moved.
- **Othello:** Diffusion along eight directions, stopped at own pieces or empty squares (flanking lines).

#### Diffusion Depth

2-3 steps is recommended. The diffusion map doesn't need to predict checkmate — it needs to cluster structurally similar positions together. The outcome weighting handles the rest.

#### Result

The diffused board is a kind of **influence map**. Two boards with similar strategic character produce similar influence maps even if exact piece positions differ slightly. We quantize each cell's float influence to a signed Int8 and match by L1 distance over those byte vectors.

### Symmetry Canonicalization

The storage convention is **per-game winner-POV** at write time:

- **Color symmetry:** A bot-won game is replaced row-by-row at backfill time by `invertState(...)` so the winner's pieces are `+1` everywhere. Player-won games and draws stay as-is. The DB invariant after backfill is "winner is `+1`."
- **Left/right symmetry:** Handled at **read time**, not write time. The brain runs four queries — `current`, `flipPerspective(current)`, and a left/right mirror of each — and combines the results. Write-time mirror normalization was tried and removed (subtle bugs, no measurable benefit over query-time mirror).

### Search Strategy

At every move decision, the brain:

1. Runs **four queries** (perspective × mirror) against the stored rows. Per-game `CandidateFilter` trims candidates by, e.g., ply window for Connect Four, widening adaptively if too few survive.
2. Ranks survivors by L1 distance over the quantized diffused images; caps at top-K per query (K=20). Candidates beyond a per-game L1 ceiling are dropped.
3. Outcome filter: keeps `outcome=+1` rows from the perspective-flipped queries (own past wins) and `outcome=-1` rows from the unflipped queries (own past losses); discards cross-side rows.
4. Accumulates `weight × candidate.diffusedImage` (mirrored if from a mirror query) into a single signed heatmap, with `weight = 1/(1 + movesToEnd) × 1/(1 + l1Distance)`. Weights are always positive — the candidate image's natural sign carries the win/loss lesson.
5. Scores each legal move via the per-game `MoveScorer`; picks the highest. If the chosen move's heatmap score is `≤ 0`, falls back to the configured personality strategy.

### Performance

All custom Dart, no external libraries needed. Comparison cost per pair:

| Game         | Values per board | 15,000 states brute-force |
|--------------|-----------------|---------------------------|
| Connect Four | 42              | ~1.5ms                    |
| Chess        | 64              | ~3-5ms                    |
| Go (19×19)   | 361             | ~200-300ms                |

These are acceptable for all games. The ply-count filter typically reduces the search space by 90%+. A "thinking" spinner for the clone is part of the UX anyway.

---

## Handling Edge Cases

### Cold Start (No Data)

The player picks a **fallback personality** for their clone via a 5-step slider. For Connect Four, ordered by observed strength in head-to-head play:

- **Chaotic** (`random`) — uniform random legal column.
- **Builder** (`ownPileAdjacent`) — drops next to the tallest stack of own pieces.
- **Stacker** (`pileFocus`) — plays the column with the highest pile of pieces, any colour. **Default for new installs.**
- **Connector** (`greedyConnect`) — extends own longest chain (length-4 wins fall out for free).
- **Sentinel** (`greedyConnectDefense`) — Connector plus a one-step defensive block on opponent length-4 threats.

`middleFocus` (closest-to-centre) survives in the engine for benchmark use only — never surfaced via UI. `edgeFocus` was removed entirely as a known weak strategy with no narrative purpose.

The fallback fires when the clone has no relevant data, when retrieval returns nothing past the L1 ceiling, or when the all-losing guard rejects the chosen move. As game data accumulates, the fallback fires less and less.

### Only Losing Data Available

Three strategies, composable:

1. **Inversion (primary):** Flip the board and use the opponent's winning moves from games the player lost. "Playing a move that was used against you in game #12." This is handled automatically by the canonicalization — every game generates data for both sides.

2. **Anti-imitation:** If all similar states led to losses, find the legal move that is *least represented* in the losing data. Explore what hasn't been tried. "Everything I've tried here went badly — trying something new."

3. **Conservative fallback:** When confidence is low (poor match quality or negative expected outcome), blend in a simple heuristic (maximize material, center control, etc.). Fades out naturally as data grows.

---

## Clone Narration

The clone always displays a one-liner explaining its reasoning. This is essential to the experience. Examples:

- "Playing a move from game #5 (won in 3 moves)"
- "I've seen this 4 times before — going with what worked best"
- "Playing a move that beat you in game #12"
- "I've never seen anything like this — going with stacker"
- "Everything I know about this position is bad — trying something different"

---

## Tech Stack

### Language: Dart (everywhere)

One language across the entire stack. The game engine is written once as a shared Dart package and imported by all targets.

### Mobile App: Flutter

- **Rendering:** CustomPainter for game boards (GPU-accelerated via Impeller). Scales from Connect Four (42 cells) to Go (361 intersections) without changing rendering strategy.
- **Animations:** Flutter's built-in animation framework (Reanimated, Tween, AnimatedBuilder) for piece drops, captures, etc.
- **Local storage:** `sqflite` (SQLite) for the game state log.
- **State management:** Riverpod or ChangeNotifier (keep it simple).
- **Targets:** Android and iOS from a single codebase.

### Online Frontend: Flutter Web

- Compiles to static HTML/JS/CSS via `flutter build web`.
- Deployable on any web server (Nginx, Apache, static hosting).
- Features: leaderboards, clone-vs-clone replays, account management.

### Online Backend: Dart (Dart Frog or Relic)

- Compiled to a native binary via `dart compile exe` — no runtime dependencies.
- REST API for game log sync, clone-vs-clone match execution, leaderboard serving.
- Database: PostgreSQL.
- Hosting: Hetzner VPS (EU data centers, low cost).

### Shared Game Engine Package

A pure Dart library containing:

- Board representation and rules per game.
- Perspective and mirror transforms (`flipPerspective`, `mirrorBoard`, `invertState`).
- Diffusion kernel per game type, with quantization to Int8.
- L1 similarity matching with adaptive-widening per-game `CandidateFilter`.
- Heatmap-based `MoveSelectionStrategy` and per-game `MoveScorer`.
- `CloneBrain` orchestrating four-query retrieval + heatmap + all-losing fallback.
- Fallback personality strategies (cold-start "personalities").
- Clone narration text generation.

This package has no Flutter dependency — it's pure Dart, testable with `dart test`.

---

## Project Structure

```
clone_wars/
├── packages/
│   └── game_engine/            # Shared pure Dart package
│       ├── lib/
│       │   ├── src/
│       │   │   ├── board.dart              # Board representation (2D Int8 array)
│       │   │   ├── canonicalize.dart       # flipPerspective, mirrorBoard, invertState
│       │   │   ├── diffusion.dart          # DiffusionKernel + quantizeInfluenceMap
│       │   │   ├── similarity.dart         # L1 distance + searchSimilar + CandidateFilter
│       │   │   ├── game_state.dart         # GameState + GameLog
│       │   │   ├── game_rules.dart         # GameRules abstract base
│       │   │   ├── move_selection.dart     # InfluenceOverlayStrategy + MoveScorer
│       │   │   ├── clone_brain.dart        # Four-query brain + fallback personalities
│       │   │   ├── narration.dart          # Clone narration text
│       │   │   └── games/
│       │   │       └── connect_four.dart   # Rules, diffusion kernel, filter, scorer
│       │   │       # othello / chess / go land here when phase 4 starts
│       │   └── game_engine.dart            # Public API barrel file
│       ├── test/
│       └── pubspec.yaml
│
├── apps/
│   ├── mobile/                  # Flutter mobile app
│   │   ├── lib/
│   │   │   ├── screens/
│   │   │   ├── widgets/
│   │   │   ├── services/
│   │   │   │   ├── game_log_service.dart   # SQLite read/write
│   │   │   │   └── sync_service.dart       # API sync (phase 2)
│   │   │   └── main.dart
│   │   └── pubspec.yaml                    # depends on game_engine
│   │
│   └── web/                     # Flutter web frontend (phase 2)
│       ├── lib/
│       └── pubspec.yaml                    # depends on game_engine
│
├── server/                      # Dart backend (phase 2)
│   ├── lib/
│   │   ├── routes/
│   │   ├── services/
│   │   │   ├── matchmaking.dart            # Clone-vs-clone execution
│   │   │   └── leaderboard.dart
│   │   └── main.dart
│   └── pubspec.yaml                        # depends on game_engine
│
└── pubspec.yaml                 # Workspace root (Dart pub workspaces)
```

---

## Data Model

### GameState (stored per move)

```dart
class GameState {
  final Board board;                // 2D Int8 array, winner-POV after backfill
  final Int8List diffusedImage;     // Quantized diffused influence map (one byte per cell)
  final int movePlayed;             // Column (Connect Four) or square index
  final int ply;                    // Move number within the game
  final String gameId;
  final int totalMaterial;          // Used by per-game CandidateFilter
  final int materialBalance;
  // Backfilled on game end:
  final int? outcome;               // +1 = mover-of-this-row won, -1 = lost, 0 = draw
  final int? movesToEnd;            // Plies remaining from this row to game end
}
```

### Game (per completed game)

```dart
class Game {
  final int id;
  final String gameType;            // "connect_four", "chess", etc.
  final int outcome;                // 1 = player won, 0 = draw, -1 = player lost
  final int totalMoves;
  final DateTime playedAt;
  final String fallbackStrategy;    // What personality was active
}
```

### CloneConfig

```dart
// Persisted as a single key/value row in the clone_config table.
// Slider-selectable values: "random", "ownPileAdjacent", "pileFocus" (default),
// "greedyConnect", "greedyConnectDefense". "middleFocus" survives in the
// engine for benchmark use only and is silently coerced to "pileFocus" if
// found in storage. Legacy "edgeFocus" is also coerced to "pileFocus".
enum FallbackStrategy {
  random,
  middleFocus,
  pileFocus,
  ownPileAdjacent,
  greedyConnect,
  greedyConnectDefense,
}
```

---

## Build Order

### Phase 1: Core Engine + Mobile Game (MVP) — **shipped**

1. **Shared game engine package** — Connect Four rules, board representation, perspective/mirror transforms, diffusion kernel + quantized Int8 image matching, four-query retrieval, heatmap-based move selection.
2. **Flutter mobile app** — Play Connect Four against the clone. SQLite storage (schema v3). Clone narration. Fallback personality slider.
3. **Validate the core loop** — Is it fun? Does the clone feel like it's learning? Is the narration engaging?

### Phase 2: Diffusion + Polish — **mostly shipped**

4. **Diffusion kernels and per-game L1 matching** — done; benchmark validated against the bit-hash baseline before merging.
5. **Inversion** — done; bot-won games are written back as winner-POV at backfill (`invertState`).
6. **Polish UX** — animations and core polish are in. A game history browser / replay viewer is still on the table.

### Phase 3: Online

7. **Dart backend** — API for game log sync, user accounts.
8. **Clone-vs-clone matchmaking** — Background job that pits synced clones against each other.
9. **Web frontend** — Leaderboards, replays, account management.
10. **Deploy** — Static web files + Dart backend binary on Hetzner VPS.

### Phase 4: More Games

11. **Othello** — New rules module + diffusion kernel. Everything else reused.
12. **Chess** — New rules module + movement-based diffusion kernel + piece value mapping.
13. **Go** — New rules module + spatial diffusion kernel. Performance validation at 19×19.

---

## Design Principles

- **One language everywhere.** Dart for client, server, and shared logic. No cross-language drift.
- **The diffusion kernel is the game definition.** Adding a new game means implementing a rules module and a diffusion function. The clone engine, storage, similarity search, narration, and UI are all reused.
- **Transparency over magic.** The clone always explains itself. The player should never wonder "why did it do that?"
- **Validate fun before building infrastructure.** The online features are phase 3. If the offline single-player loop isn't compelling, no amount of server architecture saves it.
- **Simple before clever.** Start with brute-force similarity. Add HNSW or vector databases only when profiling proves it's needed (likely never for single-player).
