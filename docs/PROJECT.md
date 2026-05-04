# Clone Wars — Play Against Yourself

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

Board states are treated as tiny grayscale images. Similarity search uses a combination of exact hashing and fuzzy matching via "diffused" board representations.

### Layer 1: Zobrist Hashing (Exact Match)

Precompute a table of random 64-bit integers for each `(piece_type, square)` combination. The hash of a board state is the XOR of all entries for pieces on the board. This gives O(1) exact-match lookup and can be incrementally updated per move.

### Layer 2: Diffused Similarity (Fuzzy Match)

Before computing similarity, board states are **diffused** — each piece's value is spread across the board according to the game's movement rules. The diffusion kernel **is the game definition**.

#### Diffusion Kernels Per Game

- **Connect Four:** Each piece radiates along the four winning directions (horizontal, vertical, two diagonals) for ~3 squares. This captures connection potential.
- **Go:** Spatial diffusion in all directions, attenuating with distance, blocked by opponent stones. Approximates influence/territory.
- **Chess:** Each piece radiates along its legal move paths (rook along rank/file, bishop along diagonals, knight to L-shaped squares, etc.). Stopped by obstacles (other pieces) on the first diffusion step. Subsequent steps are less strict about obstruction since multiple pieces will have moved.
- **Othello:** Diffusion along eight directions, stopped at own pieces or empty squares (flanking lines).

#### Diffusion Depth

2-3 steps is recommended. The diffusion map doesn't need to predict checkmate — it needs to cluster structurally similar positions together. The outcome weighting handles the rest.

#### Result

The diffused board is a kind of **influence map**. Two boards with similar strategic character produce similar influence maps even if exact piece positions differ slightly. This is then used for perceptual-style hashing and Hamming distance comparison.

### Symmetry Canonicalization

Handle symmetry at **write time**, not query time:

- **Left/right mirror:** If the board's left half has a higher hash than the right half, mirror it before storing.
- **Color symmetry:** Always store from the perspective of the side to move.
- **Inversion:** A lost game is stored as a *won* game from the opponent's perspective (board flipped, colors swapped). This doubles useful training data per game.

### Search Strategy

1. Filter by ply count / piece count (narrow to ±2 of current state).
2. Check Zobrist hash for exact matches.
3. Compare diffused hashes via Hamming distance for fuzzy matches.
4. Rank top candidates by outcome weighting.

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

The player selects a **fallback personality** for their clone at creation. For Connect Four:

- **True Random** — uniform random legal move.
- **Middle Focus** — prefer center columns (objectively stronger in Connect Four).
- **Edge Focus** — prefer edge columns (produces unusual games).
- **Pile Focus** — play near where most stones already are (clustering heuristic).

The fallback is framed as the clone's "personality when it doesn't know what to do." As game data accumulates, the fallback fires less and less.

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
- "I've never seen anything like this — going with middle focus"
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
- Canonicalization (symmetry normalization, perspective flipping).
- Zobrist hash computation.
- Diffusion kernel per game type.
- Similarity/distance functions.
- Move weighting and selection logic.
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
│       │   │   ├── canonicalize.dart       # Symmetry normalization
│       │   │   ├── zobrist.dart            # Zobrist hashing
│       │   │   ├── diffusion.dart          # Diffusion kernel interface
│       │   │   ├── similarity.dart         # Distance/comparison functions
│       │   │   ├── clone_brain.dart        # Move selection + weighting
│       │   │   ├── narration.dart          # Clone narration text
│       │   │   └── games/
│       │   │       ├── connect_four.dart   # Rules + diffusion kernel
│       │   │       ├── othello.dart
│       │   │       ├── chess.dart
│       │   │       └── go.dart
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
  final int id;
  final int gameId;
  final int ply;                    // Move number
  final List<List<int>> board;      // Raw 2D board state (canonical)
  final int zobristHash;            // Precomputed Zobrist hash
  final List<int> diffusedHash;     // Precomputed diffused influence map
  final int movePlayed;             // Column (Connect Four) or square index
  final int side;                   // Which side played this move
  // Backfilled on game end:
  final int? outcome;               // 1 = win, 0 = draw, -1 = loss (from side's perspective)
  final int? movesToEnd;            // How many moves until the game ended
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
class CloneConfig {
  final String gameType;
  final String fallbackStrategy;    // "random", "middle", "edge", "pile"
  final double confidenceThreshold; // Below this, use fallback
}
```

---

## Build Order

### Phase 1: Core Engine + Mobile Game (MVP)

1. **Shared game engine package** — Connect Four rules, board representation, canonicalization, Zobrist hashing, basic brute-force similarity (no diffusion yet, just exact match + raw Hamming distance).
2. **Flutter mobile app** — Play Connect Four against the clone. SQLite storage. Clone narration. Fallback personality selector.
3. **Validate the core loop** — Is it fun? Does the clone feel like it's learning? Is the narration engaging?

### Phase 2: Diffusion + Polish

4. **Add diffusion kernels** — Implement the Connect Four diffusion kernel. Precompute diffused hashes at write time. Compare: does diffused similarity find better matches than raw Hamming?
5. **Add inversion** — Use opponent data from losses. Observe effect on clone quality.
6. **Polish UX** — Animations, game history browser, game replay viewer, clone stats ("your clone has played 47 games, win rate 38%").

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
