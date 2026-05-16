# Pi-Ying — Play Against Yourself

## Project Vision

A mobile game platform where players play classic board games against an AI "clone" that learns exclusively from their own past games. The clone starts bad and improves as the player accumulates game data. The clone's decision-making is fully transparent — it narrates why it chose each move.

Optionally, players can sync their game logs to an online server where their clone competes against other players' clones in an automated league with leaderboards and replays.

The shipping game is **Go on 13×13**, with a roadmap toward Othello, Chess, and full-size 19×19 Go. Connect Four was the MVP target and lives on as engine regression coverage; it is no longer surfaced in the mobile app.

---

## Core Concept: The Clone Engine

The clone AI does not use neural networks, minimax, or any traditional game AI. Instead, it uses **case-based reasoning** over the player's own game history:

1. **Log every game state.** Each move in every game is recorded as a tuple: `(canonical_board_state, move_played, game_id, final_outcome, moves_to_end)`. Outcome and moves_to_end are backfilled when the game ends.

2. **On the clone's turn**, search the log for states most similar to the current board.

3. **Weight candidates** by outcome (wins > draws > losses) and move efficiency (winning in fewer moves is better).

4. **Play the best-weighted move** from the most similar historical state.

5. **Narrate the decision** to the player: "Playing a move I saw in game #5", "I've seen this before and it didn't end well — trying something different", "I don't know what to do, playing star-point."

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
| Go (shipping)| 13×13      | -1, 0, +1                              |
| Go (future)  | 19×19      | -1, 0, +1                              |
| Othello      | 8×8        | -1, 0, +1                              |
| Connect Four | 7×6        | -1, 0, +1                              |
| Chess        | 8×8        | ±1 to ±20 (weighted by piece value)     |

Go uses a special **pass move** sentinel alongside intersection indices; two consecutive passes terminate the game and trigger Chinese-style area scoring.

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

Board states are treated as tiny grayscale images. Each piece's value is **diffused** — spread across the board according to the game's movement rules — and the resulting influence map is quantized to one signed byte per cell (Int8). Matching is L1 distance over those quantized images, with a per-game candidate prefilter (e.g. ply window for Connect Four, total-material window for Go) to trim the search space before distance compute.

A separate exact-hash layer was considered (Zobrist) and rejected: at our scale, single-pass L1 over Int8 vectors is microseconds and the prefilter already does the broad cut. Two representations per row was more storage and code for no measurable benefit.

### Diffused Similarity

Before computing similarity, board states are **diffused** — each piece's value is spread across the board according to the game's movement rules. The diffusion kernel **is the game definition**.

#### Diffusion Kernels Per Game

- **Go:** Spatial diffusion in all eight directions, attenuating with distance, blocked by opponent stones. Approximates influence/territory — the same concept a human reads off the board when judging "whose area is this?"
- **Connect Four:** Each piece radiates along the four winning directions (horizontal, vertical, two diagonals) for ~3 squares. This captures connection potential.
- **Chess:** Each piece radiates along its legal move paths (rook along rank/file, bishop along diagonals, knight to L-shaped squares, etc.). Stopped by obstacles (other pieces) on the first diffusion step. Subsequent steps are less strict about obstruction since multiple pieces will have moved.
- **Othello:** Diffusion along eight directions, stopped at own pieces or empty squares (flanking lines).

#### Diffusion Depth

2-3 steps is recommended. The diffusion map doesn't need to predict the endgame — it needs to cluster structurally similar positions together. The outcome weighting handles the rest.

#### Result

The diffused board is a kind of **influence map**. Two boards with similar strategic character produce similar influence maps even if exact piece positions differ slightly. We quantize each cell's float influence to a signed Int8 and match by L1 distance over those byte vectors.

### Symmetry Canonicalization

The storage convention is **per-game winner-POV** at write time:

- **Color symmetry:** A bot-won game is replaced row-by-row at backfill time by `invertState(...)` so the winner's pieces are `+1` everywhere. Player-won games and draws stay as-is. The DB invariant after backfill is "winner is `+1`."
- **Left/right symmetry:** Handled at **read time**, not write time. The brain runs four queries — `current`, `flipPerspective(current)`, and a left/right mirror of each — and combines the results. Write-time mirror normalization was tried and removed (subtle bugs, no measurable benefit over query-time mirror).

### Search Strategy

At every move decision, the brain:

1. Runs **four queries** (perspective × mirror) against the stored rows. Per-game `CandidateFilter` trims candidates by, e.g., ply window for Connect Four or total-material window for Go, widening adaptively if too few survive.
2. Ranks survivors by L1 distance over the quantized diffused images; caps at top-K per query (K=20). Candidates beyond a per-game L1 ceiling are dropped.
3. Outcome filter: keeps `outcome=+1` rows from the perspective-flipped queries (own past wins) and `outcome=-1` rows from the unflipped queries (own past losses); discards cross-side rows.
4. Accumulates `weight × candidate.diffusedImage` (mirrored if from a mirror query) into a single signed heatmap, with `weight = 1/(1 + movesToEnd) × 1/(1 + l1Distance)`. Weights are always positive — the candidate image's natural sign carries the win/loss lesson.
5. Scores each legal move via the per-game `MoveScorer`; picks the highest. If the chosen move's heatmap score is `≤ 0`, falls back to the configured personality strategy.

### Performance

All custom Dart, no external libraries needed. Comparison cost per pair:

| Game         | Values per board | 15,000 states brute-force |
|--------------|------------------|---------------------------|
| Connect Four | 42               | ~1.5ms                    |
| Othello      | 64               | ~2-3ms                    |
| Chess        | 64               | ~3-5ms                    |
| Go (13×13)   | 169              | ~80-120ms                 |
| Go (19×19)   | 361              | ~200-300ms                |

These are acceptable for all games at our scale. The per-game candidate filter typically reduces the search space by 90%+. A short "thinking" pause for the clone is part of the UX anyway (the mobile app inserts a 250ms minimum to keep moves visible).

---

## Handling Edge Cases

### Cold Start (No Data)

The player picks a **fallback personality** for their clone via a 5-step slider, ordered left-to-right by observed strength in head-to-head self-play (round-robin gate, 50 games per direction, seed 42).

**For Go (`GoRules`)** — the active set, shipping:

- **Wanderer** (`random`) — localised random: empty cells within Manhattan-2 of any stone, picked uniformly. Falls through to Star-point on an empty board.
- **Star-point** (`goStarPoints`) — static per-cell weights (3 at hoshi/tengen, 2 on the 3rd/4th lines, 1 on the 1st line + centre cross, 0 elsewhere). Picks max with random tie-break. **Default for new installs** — its textbook opening communicates "this is Go" from move 1 and ~30% win-rate against the field gives an encouraging first impression.
- **Contact** (`goContact`) — scores each legal placement by its count of orthogonally-adjacent enemy stones; same Star-point tie-break.
- **Diamond** (`goDiamond`) — scores by `(diagonal-friendly count) − (orthogonal-friendly count)`, actively penalising dumpling shapes and rewarding kosumi / ponnuki extensions. Same tie-break.
- **Greedy** (`goGreedyArea`) — for each candidate placement near existing stones, applies the move and picks the differential `(own_area − opponent_area)` maximiser. Falls through to Star-point if no candidates.

**For Connect Four (`ConnectFourRules`)** — retained for engine regression:

- **Chaotic** (`random`), **Builder** (`ownPileAdjacent`), **Stacker** (`pileFocus`, default), **Connector** (`greedyConnect`), **Sentinel** (`greedyConnectDefense`). `middleFocus` and `edgeFocus` survive in the engine for benchmarking but are never surfaced.

The fallback fires when the clone has no relevant data, when retrieval returns nothing past the L1 ceiling, or when the all-losing guard rejects the chosen move. As game data accumulates, the fallback fires less and less. Legacy persisted values (`goHugger`, `pileFocus` in Go mode, etc.) coerce to the current default at read time.

### Only Losing Data Available

Three strategies, composable:

1. **Inversion (primary):** Flip the board and use the opponent's winning moves from games the player lost. "Playing a move that was used against you in game #12." This is handled automatically by the canonicalization — every game generates data for both sides.

2. **Anti-imitation:** If all similar states led to losses, find the legal move that is *least represented* in the losing data. Explore what hasn't been tried. "Everything I've tried here went badly — trying something new."

3. **Conservative fallback:** When confidence is low (poor match quality or negative expected outcome), blend in the configured personality (Star-point by default). Fades out naturally as data grows.

---

## Clone Narration

The clone always displays a one-liner explaining its reasoning. This is essential to the experience. Examples:

- "Playing a move from game #5 (won in 3 moves)"
- "I've seen this 4 times before — going with what worked best"
- "Playing a move that beat you in game #12"
- "I've never seen anything like this — going with star-point"
- "Everything I know about this position is bad — trying something different"

---

## Tech Stack

### Language: Dart (everywhere)

One language across the entire stack. The game engine is written once as a shared Dart package and imported by all targets.

### Mobile App: Flutter

- **Rendering:** CustomPainter for game boards (GPU-accelerated via Impeller). Scales from Connect Four (42 cells) to 13×13 Go (169 intersections) and beyond without changing rendering strategy.
- **Animations:** Flutter's built-in animation framework (Tween, AnimatedBuilder) for stone placement, captures, last-move ring, etc.
- **Local storage:** `sqflite` (SQLite) for the game state log. Schema currently at v6 (adds `player_area` / `clone_area` columns for per-game Chinese-area scoring).
- **State management:** Plain `ChangeNotifier` (Riverpod considered, deferred — current scale doesn't warrant it).
- **Typography:** Google Fonts' **Klee One** (CJK-capable, hand-brushed sumi feel) — renders Latin and `皮影` in a single typeface.
- **Palette:** Moonlit-goban — warm dark wood `boardPanel`, ivory grid `lineColor`, ivory player stones, near-black clone stones, cinnabar `cinnabar` accent (last-move ring).
- **Targets:** Android shipping; iOS from the same codebase whenever needed.

### Online Frontend: Flutter Web *(phase 3, not yet started)*

- Compiles to static HTML/JS/CSS via `flutter build web`.
- Deployable on any web server (Nginx, Apache, static hosting).
- Features: leaderboards, clone-vs-clone replays, account management.

### Online Backend: Dart (Dart Frog or Relic) *(phase 3, not yet started)*

- Compiled to a native binary via `dart compile exe` — no runtime dependencies.
- REST API for game log sync, clone-vs-clone match execution, leaderboard serving.
- Database: PostgreSQL.
- Hosting: Hetzner VPS (EU data centers, low cost).

### Shared Game Engine Package

A pure Dart library containing:

- Board representation and rules per game (`ConnectFourRules`, `GoRules`).
- Perspective and mirror transforms (`flipPerspective`, `mirrorBoard`, `invertState`).
- Diffusion kernel per game type, with quantization to Int8.
- L1 similarity matching with adaptive-widening per-game `CandidateFilter`.
- Heatmap-based `MoveSelectionStrategy` and per-game `MoveScorer`.
- `CloneBrain` orchestrating four-query retrieval + heatmap + all-losing fallback.
- Game-aware fallback personality strategies (cold-start "personalities").
- Clone narration text generation.

This package has no Flutter dependency — it's pure Dart, testable with `dart test`.

---

## Project Structure

```
chinese-room-game/                  # (Pi-Ying)
├── packages/
│   └── game_engine/                # Shared pure Dart package
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
│       │   │       ├── connect_four.dart   # Engine regression only (no UI)
│       │   │       └── go.dart             # Rules, diffusion, filter, scorer, area-score
│       │   └── game_engine.dart            # Public API barrel file
│       ├── bin/
│       │   └── go_personality_round_robin.dart   # Personality strength gate
│       ├── test/
│       └── pubspec.yaml
│
├── apps/
│   └── mobile/                     # Flutter mobile app (Android shipping)
│       ├── lib/src/
│       │   ├── screens/                    # start, game, post_game, settings
│       │   ├── widgets/                    # go_board, area_history_strip, ...
│       │   ├── state/game_notifier.dart    # ChangeNotifier game loop
│       │   ├── db/database_service.dart    # sqflite, schema v6
│       │   ├── theme.dart                  # Klee One + moonlit-goban palette
│       │   └── main.dart                   # wires GoRules(size: 13)
│       └── pubspec.yaml                    # depends on game_engine
│
│   # apps/web/ and server/ are phase 3 — directories not yet created.
│
├── openspec/                       # Spec-driven workflow
│   ├── config.yaml
│   ├── specs/                      # Canonical specs (15 capabilities)
│   └── changes/                    # Active proposals + archive/
│
├── docs/PROJECT.md                 # This file
├── CLAUDE.md                       # Agent instructions
└── pubspec.yaml                    # Workspace root (Dart pub workspaces)
```

---

## Data Model

### GameState (stored per move)

```dart
class GameState {
  final Board board;                // 2D Int8 array, winner-POV after backfill
  final Int8List diffusedImage;     // Quantized diffused influence map (one byte per cell)
  final int movePlayed;             // Row-major intersection index (Go), column (CF), or passMove sentinel
  final int ply;                    // Move number within the game
  final String gameId;
  final int totalMaterial;          // Used by per-game CandidateFilter
  final int materialBalance;
  // Backfilled on game end:
  final int? outcome;               // +1 = mover-of-this-row won, -1 = lost, 0 = draw
  final int? movesToEnd;            // Plies remaining from this row to game end
}
```

### Game (per completed game, schema v6)

```dart
class Game {
  final String gameId;
  final String gameType;            // "go", "connect_four"
  final int? outcome;               // +1 = player won, 0 = draw, -1 = player lost; null while in progress
  final int totalMoves;
  final DateTime startedAt;
  final String fallbackStrategy;    // What personality was active for this game
  final int? playerArea;            // Go: Chinese-style area for the player at game end (null on resign / pre-v6)
  final int? cloneArea;             // Go: Chinese-style area for the clone at game end
}
```

### CloneConfig

```dart
// Persisted as key/value rows in the clone_config table.
// User-facing values are game-aware. For Go (active): random (Wanderer),
// goStarPoints (default), goContact, goDiamond, goGreedyArea.
// For Connect Four (engine regression): random, pileFocus (default),
// ownPileAdjacent, greedyConnect, greedyConnectDefense.
// Legacy strings (e.g. goHugger, pileFocus persisted while in Go mode,
// middleFocus, edgeFocus) coerce silently to the current game's default
// at load time.
enum FallbackStrategy {
  random,
  // Connect Four
  middleFocus,
  pileFocus,
  ownPileAdjacent,
  greedyConnect,
  greedyConnectDefense,
  // Go
  goStarPoints,
  goDiamond,
  goContact,
  goGreedyArea,
}
```

---

## Build Order

### Phase 1: Core Engine + Mobile Game (MVP) — **shipped**

1. **Shared game engine package** — Connect Four rules, board representation, perspective/mirror transforms, diffusion kernel + quantized Int8 image matching, four-query retrieval, heatmap-based move selection.
2. **Flutter mobile app** — Play Connect Four against the clone. SQLite storage. Clone narration. Fallback personality slider.
3. **Validate the core loop** — Loop felt fun enough to keep going. ✅

### Phase 2: Diffusion + Polish + Go cutover — **shipped**

4. **Diffusion kernels and per-game L1 matching** — done; benchmark-validated against the bit-hash baseline before merging.
5. **Inversion** — done; bot-won games are written back as winner-POV at backfill (`invertState`).
6. **Go engine** — rules, capture, simple-ko, two-pass termination, Chinese-style area scoring (was originally a phase 4 item, pulled forward).
7. **CF → Go mobile cutover** — Flutter app now ships Go on 13×13 as the only user-facing game; CF stays in the engine for regression.
8. **Pi-Ying rebrand** — Klee One typography, moonlit-goban palette, `皮影` lore on start + settings screens. Schema v5 (rebrand wipe).
9. **Go fallback personalities + Diamond/Wanderer rework** — five personalities exposed via the slider, ordered by round-robin strength: Wanderer → Star-point (default) → Contact → Diamond → Greedy.
10. **Area-score history** — schema v6 adds per-game `player_area` / `clone_area`; new `AreaHistoryStrip` on the home screen paints one proportion bar per completed game (cap 100). Post-game screen now shows the area readout.
11. **Game history browser + replay viewer** — home-screen strip is now tappable, opening a History list of completed games; tapping a row opens a scrubbable Replay screen with VCR controls and `½× / 1× / 2× / 3× / 4×` speed selection. Reuses the existing per-ply board blobs — no schema bump, no engine changes.

### Phase 3: Online — *not started*

12. **Dart backend** — REST API for game log sync, accounts.
13. **Clone-vs-clone matchmaking** — background job that pits synced clones against each other.
14. **Web frontend** — Flutter Web for leaderboards, replays, account management.
15. **Deploy** — static web files + Dart backend binary on Hetzner VPS.

### Phase 4: More Games

16. **Othello** — new rules module + diffusion kernel. Everything else reused.
17. **Chess** — new rules module + movement-based diffusion kernel + piece value mapping.
18. **Go 19×19 scale-up** — same rules module, performance validation on the larger board.

---

## Design Principles

- **One language everywhere.** Dart for client, server, and shared logic. No cross-language drift.
- **The diffusion kernel is the game definition.** Adding a new game means implementing a rules module and a diffusion function. The clone engine, storage, similarity search, narration, and UI are all reused.
- **Transparency over magic.** The clone always explains itself. The player should never wonder "why did it do that?"
- **Validate fun before building infrastructure.** The online features are phase 3. If the offline single-player loop isn't compelling, no amount of server architecture saves it.
- **Simple before clever.** Start with brute-force similarity. Add HNSW or vector databases only when profiling proves it's needed (likely never for single-player).
- **Spec-driven, not waterfall.** OpenSpec changes capture proposal / design / specs / tasks; archive on ship. Any artifact can be updated at any time as understanding evolves.
