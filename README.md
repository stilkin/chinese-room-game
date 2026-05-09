# Pi-Ying

A mobile game where you play classic board games against an AI "clone" that learns exclusively from your own past games. The clone starts bad and improves as you play more. It narrates every decision it makes, reflecting your own patterns back at you.

The first game is **Connect Four**.

## How It Works

The clone uses **case-based reasoning** over your game history — no neural networks, no minimax. Every move you and the clone make is recorded along with a perceptual fingerprint of the board (a quantized diffused-influence image — one signed byte per cell). When it's the clone's turn, it doesn't simulate or look ahead; it asks "have I been somewhere like this before?" and acts on what it finds.

A few specifics:

- **Per-game winner-POV storage.** Every game in the database is stored as if the winner was the side with the +1 pieces — player wins go in as-is, bot wins are flipped at game end. This keeps a single invariant ("winner is +1") across the whole DB and makes the data forward-compatible with averaging diffused images of winning trajectories.
- **Four-query search at decision time.** The bot queries the database four times — perspective × mirror — to exploit both the winner-POV convention and the board's left/right symmetry. From the perspective-flipped queries we keep `outcome=+1` rows (own past wins); from the unflipped queries we keep `outcome=-1` rows (own past losses).
- **L1-distance heatmap accumulation.** Each retrieved candidate contributes `weight × candidate.diffusedImage` (mirrored if it came from a mirror query) to a single signed heatmap, with `weight = 1/(1 + movesToEnd) × 1/(1 + l1Distance)` — closer matches matter more, faster wins matter more. Sign isn't a multiplier on the weight: the candidate image's *natural sign* carries the win/loss lesson (winner pieces are positive territory, loser pieces are negative). The legal move with the highest heatmap score wins; if every legal move scores ≤ 0, the bot falls back to a personality strategy.
- **Resume.** Every move is persisted. Close the app mid-game, kill it, come back tomorrow — the start screen surfaces a Resume button and replays your moves to bring the game back exactly as you left it.
- **Transparent narration.** The clone tells you why it made each move, drawing on the candidates it found.

## Project Structure

- `packages/game_engine/` — Pure Dart library: rules, clone brain, perceptual matching, narration. No Flutter dependency.
- `apps/mobile/` — Flutter mobile app (Android & iOS). Uses sqflite for local persistence.
- `docs/PROJECT.md` — Design spec and long-term direction.
- `openspec/` — Spec-driven development artifacts (active changes + archive of shipped ones).

## Build & Run

This is a Dart pub workspace.

```bash
# Game engine
cd packages/game_engine
dart test
dart analyze

# Mobile app
cd apps/mobile
flutter run                  # on a connected device or emulator
flutter test
flutter build apk            # Android release
flutter build ios            # iOS release
```

A `scripts/pre-commit` hook formats and analyzes both packages — install it via `git config core.hooksPath scripts/`.

## Status

Connect Four MVP is playable on Android. The clone learns from completed games and uses the matching system above to pick its moves. Next up is more games (Othello, Chess, Go) — each one is a new rules module + a new diffusion kernel; the brain, storage, similarity, narration, and UI are reused.

## License

[PolyForm Noncommercial License 1.0.0](LICENSE) — free for personal use, research, education, and other noncommercial purposes. Commercial use requires a separate license.
