# Pi-Ying

A mobile game where you play classic board games against an AI "clone" that learns exclusively from your own past games. The clone starts bad and improves as you play more. It narrates every decision it makes, reflecting your own patterns back at you.

The first game is **Connect Four**.

## How It Works

The clone uses **case-based reasoning** over your game history — no neural networks, no minimax. Each move you play is recorded. On the clone's turn, it searches for similar board positions in your history, weights them by outcome, and picks the best move. It always tells you why.

## Project Structure

- `packages/game_engine/` — Pure Dart library: rules, clone brain, similarity search, narration
- `apps/mobile/` — Flutter mobile app (Android & iOS)
- `docs/` — Design spec (`PROJECT.md`)
- `openspec/` — Spec-driven development artifacts

## Status

Early development — building the game engine and Connect Four MVP.
