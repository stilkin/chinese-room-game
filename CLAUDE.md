# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Pi-Ying is a mobile game where players play classic board games against an AI "clone" that learns exclusively from their own past games using case-based reasoning over game history (no neural networks or minimax). The first game is Connect Four. The clone narrates every decision it makes.

The full design spec lives in `docs/PROJECT.md`.

## Tech Stack

- **Language:** Dart everywhere (client, server, shared logic)
- **Mobile:** Flutter (CustomPainter for boards, sqflite for local storage, Riverpod or ChangeNotifier for state)
- **Web frontend:** Flutter Web (phase 2)
- **Backend:** Dart Frog or Relic compiled to native binary, PostgreSQL (phase 3)

## Build & Development Commands

This is a Dart pub workspace. The shared game engine is a pure Dart package; apps depend on it via path.

```bash
# Game engine (packages/game_engine/)
dart test                          # Run all tests
dart test test/some_test.dart      # Run a single test
dart analyze                       # Static analysis

# Mobile app (apps/mobile/)
flutter run                        # Run on connected device/emulator
flutter test                       # Run widget/unit tests
flutter build apk                  # Android release build
flutter build ios                  # iOS release build

# Web (apps/web/)
flutter build web                  # Compile to static HTML/JS/CSS

# Server (server/)
dart compile exe lib/main.dart     # Compile backend to native binary
dart run                           # Run in development
```

## Architecture

### Monorepo layout (Dart pub workspaces)

- `packages/game_engine/` — Pure Dart library, no Flutter dependency. Contains all game logic: board representation, rules, perspective/mirror transforms, diffusion kernels, similarity search, move selection, and clone narration.
- `apps/mobile/` — Flutter app. Depends on game_engine.
- `apps/web/` — Flutter Web frontend (phase 2). Depends on game_engine.
- `server/` — Dart backend (phase 3). Depends on game_engine.

### Core engine design

**Board representation:** 2D array of signed bytes (`Int8`). Values are -1/0/+1 for most games; chess uses piece-value weights (pawn=1, knight/bishop=3, rook=5, queen=9, king=20). Negative = opponent.

**Clone decision pipeline:**
1. Run four queries against stored rows: perspective × mirror (`flipPerspective(current)` and unchanged, each also mirrored). The per-game `CandidateFilter` (e.g. `±2 ply window` for Connect Four) trims the candidate pool, widening adaptively.
2. Rank survivors by L1 distance over the quantized Int8 diffused image; cap at top-K per query (K=20).
3. Outcome filter: keep `outcome=+1` rows from the perspective-flipped queries (own past wins), `outcome=-1` rows from the unflipped queries (own past losses); discard cross-side rows; drop candidates beyond the per-game L1 ceiling.
4. Accumulate `weight × candidate.diffusedImage` (mirrored if from a mirror query) into a single signed heatmap, where `weight = 1/(1+movesToEnd) × 1/(1+l1Distance)`. Weights are always positive; the candidate image's natural sign carries the win/loss lesson.
5. Score each legal move via the per-game `MoveScorer`; pick the highest. If the chosen move's score is `≤ 0`, fall back to the personality strategy (the all-losing guard).
6. Generate narration text reporting candidate game count.

**Diffusion kernels** are the game-specific core — each game defines how piece influence spreads across the board (along winning directions for Connect Four, along legal move paths for chess, spatial for Go). 2-3 diffusion steps. The diffused board is an influence map; we quantize it to Int8 (one signed byte per cell) before storage and L1 matching.

**Storage convention** is per-game winner-POV (write-time):
- Player-won games: rows stored as-is.
- Bot-won games: every row replaced by `invertState(...)` — board sign-flipped, diffused image recomputed on the flipped board.
- Draws: rows stored as-is.
- No write-time mirror normalization — left/right symmetry is handled at read time via the mirror queries above.

**Cold start:** Player picks a fallback personality via a 5-step slider. Positions: Chaotic (random), Builder (`ownPileAdjacent`), **Stacker (`pileFocus`) — default**, Connector (`greedyConnect`), Sentinel (`greedyConnectDefense`). The fallback fires when the clone has no relevant data, when retrieval returns nothing past the L1 ceiling, or when the all-losing guard trips. `middleFocus` survives in the engine for benchmark use only — never surfaced via UI.

### Data flow

Each move is stored as `(board_blob, diffused_image, move_played, ply, side, game_id, total_material, material_balance, outcome, moves_to_end)`. `outcome` and `moves_to_end` are null while a game is in progress and backfilled across every row of the game when it ends. SQLite schema is at v3.

## OpenSpec Workflow

This project uses [OpenSpec](https://github.com/Fission-AI/OpenSpec) for spec-driven development. Configuration lives in `openspec/config.yaml`.

**Commands:**
- `/opsx:propose <idea>` — Create a change proposal (generates proposal.md, specs/, design.md, tasks.md)
- `/opsx:apply` — Implement the tasks from a proposal
- `/opsx:archive` — Archive completed work
- `/opsx:verify` — Verify implementation against spec
- `/opsx:continue` — Resume work on an existing proposal

**Artifact structure:** Each change lives in `openspec/changes/<feature-name>/` containing:
- `proposal.md` — Rationale and scope
- `specs/` — Requirements and scenarios
- `design.md` — Technical approach
- `tasks.md` — Implementation checklist

Completed work is archived to `openspec/changes/archive/<date>-<feature-name>/`.

**Philosophy:** Fluid, not rigid — any artifact can be updated at any time. Iterate, don't waterfall.

## Build Phases

The project follows a strict phase order — validate fun before building infrastructure:
1. Game engine + mobile app (Connect Four MVP)
2. Diffusion kernels + inversion + UX polish
3. Online backend, clone-vs-clone league, web frontend
4. Additional games (Othello, Chess, Go)

Adding a new game = new rules module + new diffusion kernel. Everything else (clone brain, storage, similarity, narration, UI) is reused.

## Design Principles

- **Keep it simple, clean, and maintainable.** This is the prime directive. Resist complexity at every level.
- **Validate fun before building infrastructure.** The offline single-player loop must be compelling before investing in server architecture.
- **Transparency over magic.** The clone always explains itself.
- **One language everywhere.** Dart for client, server, and shared logic.
