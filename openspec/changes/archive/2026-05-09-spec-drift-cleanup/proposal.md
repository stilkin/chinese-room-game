# Spec drift cleanup

## Why

After archiving `image-similarity-foundation` and `fallback-personalities-slider`, three canonical-spec leftovers describe the pre-shipped pipeline:

1. `diffusion-engine/spec.md` — has a "Influence map converts to bit hash" requirement with Hamming-distance scenarios. The kernel actually outputs a quantized `Int8List` image now.
2. `move-selection/spec.md` — "Connect Four uses vote-by-move" scenario references a strategy that no longer exists; "Cold-start fallback personalities (carried forward)" duplicates and contradicts the authoritative list in `clone-brain/spec.md` (still mentions `edge-focus`).
3. `clone-brain/spec.md` — "Move selection delegates to game-specific strategy" mentions vote-by-move and overlaps with the new "Decision pipeline" requirement.

These didn't ride along in either prior change because the deltas were scoped narrowly. They're not code-driving — the tests and shipped behaviour are correct — but they're misleading on a fresh read. Clean up before opening the Go proposals.

## What Changes

- `diffusion-engine`: REMOVE `Influence map converts to bit hash`; ADD `Influence map quantizes to Int8 image` reflecting the shipped `quantizeInfluenceMap` behaviour.
- `move-selection`: MODIFY `Move selection strategy is game-specific` to reference `InfluenceOverlayStrategy`; REMOVE `Cold-start fallback personalities (carried forward)` (clone-brain owns this).
- `clone-brain`: REMOVE `Move selection delegates to game-specific strategy` (subsumed by `Decision pipeline`).

No code changes. No mobile changes. No tests. Pure spec hygiene.

## Impact

- Canonical specs match shipped code on first read.
- Future game proposals (Go) start from a clean canonical baseline; no inherited drift.
