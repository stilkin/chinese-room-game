# Pi-Ying rebrand — moonlit goban aesthetic + 皮影 lore

## Why

The app's identity is at a hinge point: Connect Four was retired, Go shipped, and the visual language hasn't caught up. The current dark-VHS retro palette (PressStart2P + VT323, neon yellow/red/blue) was a deliberate stylistic choice when the game was abstract and Connect-Four-flavoured — but for a Go app it's culturally adjacent at best, and it actively obscures the rich metaphor already baked into the project name.

"Pi-Ying" is **皮影** (pí yǐng) — Chinese shadow-puppet theatre, where a puppeteer manipulates flat figures behind a backlit screen. The product is exactly that: the player casts a shadow of themselves into the engine, and the clone performs that shadow back at them. Kept hidden in the current build, this is just an opaque project codename. Surfaced and supported by the visuals, it's the strongest possible framing for "play yourself".

This change rebrands the app to lean into both the 皮影 metaphor and Go's actual visual culture (warm wood, ink-thin lines, ivory + slate stones, sparing red accent). Pi-Ying stays as the name; what changes is everything around it.

## What Changes

- **Palette: moonlit goban.** Dark warm bg (aged-wood-at-night), aged amber wood for the board panel, soft cream for grid lines and body text, deep cinnabar red as the single accent (last-move ring, win callout, destructive UI). Drops neon yellow/red/blue.
- **Typography.** Drops PressStart2P (8-bit retro) and VT323 (terminal serif). Single Google-Fonts family throughout — **Klee One** (a contemporary Japanese-influenced typeface with both Latin and CJK glyphs, handwritten warmth without being ornamental). Two weights: 400 body, 600 titles.
- **In-app lore surface.** The start screen's subtitle now carries the 皮影 reference rather than hiding it: `"皮影 — shadow play of go"` (or comparable). A short line on the settings screen explains the metaphor for users curious enough to look. Single-stop information, not bombastic.
- **Board widget colours.** `GoBoard` switches to the new wood/cream palette; the cinnabar last-move ring is the single brand-coloured element on the board.
- **Data wipe.** Schema bumped v4 → v5; `onUpgrade` clears `game_states` and `games`. `clone_config` (fallback choice) preserved. The current pre-rebrand Connect-Four-and-debug data isn't worth carrying forward, and a clean slate matches the "this is a new product" narrative.
- **Description & metadata.** `pubspec.yaml` description updated; mentions Go and the 皮影 metaphor.

## Impact

- **Heavy churn in `apps/mobile/lib/src/theme.dart`** — palette, font family, text theme, button themes, dialog theme all rewrite.
- **`apps/mobile/lib/src/widgets/go_board.dart`** — colour constants swap.
- **`apps/mobile/lib/src/screens/start_screen.dart`** — subtitle copy.
- **`apps/mobile/lib/src/screens/settings_screen.dart`** — adds a small "About" / lore block.
- **`apps/mobile/lib/src/db/database_service.dart`** — schema v5, onUpgrade.
- **`apps/mobile/pubspec.yaml`** — description, `google_fonts` dependency, font asset declarations dropped.
- **Tests** — schema-version constants and the round-trip helper boards stay 13×13; existing tests should mostly continue to pass.
- **No engine changes.**

## Out of scope (this change)

- **Launcher icon redesign.** Generating a custom PNG icon (a stone with the 影 character, sumi-ink style) needs image tooling we don't have on hand. The existing icon stays for this rebrand; icon redesign is a follow-up once we have a designed asset.
- **Audio / sound design.** Tier 2 audio (stone-on-wood click, capture chime) is a separate effort; the new visual direction was a prerequisite so the audio matches the visual register.
- **Animations / transitions.** Could add ink-wash transitions, stone-place fade-ins, etc. Out of scope; the v1 of the rebrand is colour + type + copy only.
