## Why

The four fallback personalities — Random, Middle Focus, Edge Focus, Pile Focus — exist to give the clone *something* to do when it has no relevant data, but they're an uncurated grab-bag rather than a deliberate strength ladder:

- **Edge Focus** is genuinely bad at Connect Four (corners are weak); it has no narrative purpose beyond being a punching bag.
- **Middle Focus** and **Pile Focus** are largely shadow-equivalent in opening play — both default to the centre column with the recent tie-break tweak — so they don't give the player a meaningful choice.
- **None of them feel like personalities.** They feel like tuning knobs.

The fallback only fires when the clone has no relevant data, which is mostly the player's first ~10 games. That's the moment when the player is forming a first impression of "who am I playing against," and a flat list of four near-equivalent radio buttons doesn't sell the clone-personality framing the rest of the app leans into.

This change replaces the four-radio picker with a five-step **complexity slider** of *named* personalities, ordered from chaotic to tactical, with a clear default that gives the player a recognisable-but-beatable opponent out of the box. The clone gets recognisable character early; the player gets a knob they can dial up or down depending on how much fight they want from the cold-start brain.

## What Changes

- **Remove** `FallbackStrategy.edgeFocus` from the engine enum (no UX value, no benchmark value).
- **Keep** `FallbackStrategy.middleFocus` in the engine for self-play benchmark use, but **hide** it from the user-facing slider.
- **Rename** the user-facing label of `FallbackStrategy.pileFocus` to **"Stacker"** (engine name unchanged, to minimise churn).
- **Add** three new engine fallback strategies:
  - `ownPileAdjacent` — labelled **"Builder"**: drops next to the tallest own-colour stack. Tie-break by closeness to centre. Empty board → centre column.
  - `greedyConnect` — labelled **"Connector"**: one-ply lookahead. For each legal column, simulate dropping own piece, compute longest run of own colour through the resulting cell. Pick the column that maximises that run. Tie-break by closeness to centre.
  - `greedyConnectDefense` — labelled **"Sentinel"**: if the opponent has a move that wins on their next turn, play that column to block; otherwise play `greedyConnect`. (Block only winning moves, not threats — keeps the bot firmly out of minimax territory.)
- **Replace** the radio-button settings UI with a **discrete 5-step slider** showing one personality name at a time:
  1. Chaotic (random)
  2. Builder (ownPileAdjacent)
  3. **Stacker** (existing pileFocus) ← default
  4. Connector (greedyConnect)
  5. Sentinel (greedyConnectDefense)
- **Migrate** persisted config: any stored value not in the user-facing set (including legacy `edgeFocus` and `middleFocus`) is silently mapped to `pileFocus` (Stacker) on read.
- **Validate ordering via benchmark** before ship: round-robin among the four offence-bearing personalities. Original expectation was Connector > Builder > Stacker > Chaotic; the head-to-head gate showed Stacker beating Builder, so the slider order between positions 2 and 3 was swapped to match observed strength. Final ordering: Chaotic < Builder < Stacker < Connector ≲ Sentinel.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `clone-brain`: the **Cold-start fallback personalities** requirement is rewritten. Edge focus is removed. Three new personalities are added. The middle-focus personality survives as a benchmark-only construct, no longer surfaced via configuration.
- `settings-screen`: the **Fallback personality picker** requirement is rewritten. Radio-button list becomes a 5-step slider with named labels and a one-line description per step. The default changes from "Random" to "Stacker."

## Impact

- `packages/game_engine/lib/src/clone_brain.dart` — `FallbackStrategy` enum churns: `edgeFocus` removed, three new values added. `_fallbackMove` switch grows three new cases and loses one.
- `packages/game_engine/lib/src/games/connect_four.dart` *(possibly)* — the Builder/Connector/Sentinel helpers may live here if they want game-specific knowledge of gravity. *Decision*: Connect Four-only logic stays in `clone_brain.dart` for now, since the enum is already CF-shaped (column moves) and a clean abstraction can come when Game #2 forces it. Aligns with prime directive (KISS, no premature abstraction).
- `packages/game_engine/test/clone_brain_test.dart` — new unit tests for Builder/Connector/Sentinel.
- `packages/game_engine/bin/self_play_benchmark.dart` — accepts the new coach names as CLI tokens (`builder`, `connector`, `sentinel`); drop `edge` token.
- `apps/mobile/lib/src/screens/settings_screen.dart` — radio list → slider widget. New labels and per-step description text.
- `apps/mobile/lib/src/db/database_service.dart` — `loadFallback` translates any non-user-facing stored value (including legacy `edgeFocus` and benchmark-only `middleFocus`) to `pileFocus` at read time.
- `apps/mobile/lib/src/state/game_notifier.dart` — default fallback in cold-start path: `pileFocus` (was `random`).
- `apps/mobile/test/database_service_test.dart` — round-trip test additions for the three new values; legacy-mapping test for `edgeFocus`/`middleFocus` → `pileFocus`.
- `apps/mobile/test/game_notifier_test.dart` — minor: default-fallback assertion changes if it asserts on the literal value.
- **Storage**: no schema change. `clone_config` value column already stores arbitrary text.
- **Migration**: non-destructive. Existing user choice is honoured if it's still valid; legacy/hidden values silently become Stacker.
- **Behavioural**: cold-start games feel more deliberate. Strongest fallback (Sentinel) is recognisably stronger than weakest (Chaotic) but still beatable by an attentive player and clearly *not* minimax — the clone's gimmick stays intact.
