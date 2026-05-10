# Design — Pi-Ying rebrand

## Goal

Replace the dark-VHS retro identity with a moonlit-goban aesthetic that supports both Go's visual culture and the 皮影 (shadow play) metaphor. Pure mobile-app change; engine untouched.

## Palette

A **warm-dark moonlit** variant rather than the conventional bright wood-on-cream goban. Differentiates the app from cookie-cutter Go clients and retains some of the current build's atmospheric warmth.

| Role | Colour | Notes |
|---|---|---|
| `bg` | `#1A1612` | Very dark warm brown — charcoal-aged-wood-at-night. Not pure black. |
| `surface` | `#2A2218` | Slightly lighter; panels, dialogs. |
| `surfaceLow` | `#100C08` | Sunken; under-board, scrim. |
| `boardPanel` | `#4A3520` | Aged kaya wood, dark amber. The board itself reads as warm against the darker bg. |
| `lineColor` | `#D4B886` | Soft cream-amber; reads crisp against the dark wood without being bright. |
| `outline` | `#6A5840` | Muted warm border. |
| `onSurface` | `#EAD8B5` | Warm ivory; primary text. Same tone as the player's stones — visual rhyme. |
| `onSurfaceMuted` | `#9A8B6F` | Faded cream; secondary text. |
| `cinnabar` | `#C13C2B` | Deep red; **only** accent — last-move ring, win callout, destructive actions. Used sparingly. |

The cinnabar is the *single* brand-coloured element. The current build's three primaries (red, yellow, blue) collapse into one. Sumi-ink restraint: the dark/warm/cream/black-ink stones should carry the visual identity; saturated colour earns its place by being rare.

Stones stay ivory + near-black (already shipped); only the *outline* on the dark stone needs slight tweaking against the new dark-wood board (less contrast needed than against the previous near-black surface).

## Typography

**Klee One** (Google Fonts) for everything. Two weights: 400 (body) and 600 (titles).

Reasoning:
- Single family — visual cohesion, no font-pairing landmines.
- Contemporary Japanese-influenced typeface; renders both Latin and CJK glyphs natively (so 皮影 doesn't need a fallback path).
- Handwritten warmth without crossing into "ornamental Japanese" cosplay.
- Cleaner at small sizes than fancier brush serifs (Shippori Mincho, Yuji Boku, etc.).

Loaded via the `google_fonts` package — fonts are fetched on first run and cached. Trades a small first-run latency for not having to bundle font assets in the APK.

The current PressStart2P (~25KB) and VT323 (~50KB) get unbundled. Net APK change: roughly neutral (google_fonts package adds machinery but the font assets themselves move out of the APK). Acceptable.

## Type scale

Mirrors the current scale's logical structure (display/headline/title/body/label) but with new sizes that suit a serif/handwritten face rather than a 6×8 pixel grid:

| Style | Size | Weight | Use |
|---|---|---|---|
| `displayLarge` | 32 | 600 | Marquee titles ("PI-YING" splash) |
| `displayMedium` | 26 | 600 | Personality name on settings |
| `displaySmall` | 20 | 600 | |
| `headlineLarge` | 22 | 600 | Section headings |
| `headlineMedium` | 18 | 600 | |
| `headlineSmall` | 16 | 600 | |
| `titleLarge` | 16 | 600 | AppBar title |
| `titleMedium` | 14 | 600 | Status banner ("YOUR TURN") |
| `titleSmall` | 13 | 600 | Subtle headings |
| `bodyLarge` | 16 | 400 | Primary body |
| `bodyMedium` | 14 | 400 | Default body |
| `bodySmall` | 12 | 400 | Captions, area-score line |
| `labelLarge` | 14 | 600 | Filled-button text |
| `labelMedium` | 12 | 600 | |
| `labelSmall` | 11 | 600 | |

## In-app lore

Two surfaces:

1. **Start screen subtitle.** Current copy is `"go against\nyour learning clone"`. Replace with two lines: the Asian characters `皮影` (large, in the title font) plus `shadow play of go` (smaller, body font). Doesn't break the user's instant comprehension but hands them a hook to investigate.

2. **Settings screen About panel.** A small block above the personality picker:
   > *Pi-Ying* — 皮影 (pí yǐng), Chinese shadow theatre, where a puppeteer animates flat figures behind a backlit screen. Your clone is your shadow, learning your moves and playing them back at you.

   3-4 lines. Quiet. Discoverable for the curious.

## Board widget changes

`GoBoard` painter swaps three constants:

```dart
const _kBoardBackground = PiYingTheme.boardPanel;  // was surface
const _kLineColor = PiYingTheme.lineColor;         // was yellow
const _kPlayerStone = PiYingTheme.onSurface;       // unchanged-ish (ivory)
const _kCloneStone = Color(0xFF0E0E14);            // unchanged
```

Last-move ring: changes from `PiYingTheme.blue` to `PiYingTheme.cinnabar`. Single tonal accent across the whole UI.

Star points: continue to render in `lineColor` (soft cream-amber on dark wood — exactly the goban convention).

## Schema migration

`_kSchemaVersion`: 4 → 5. `onUpgrade` for `oldVersion < 5` drops `game_states`, drops `games`, recreates them empty. `clone_config` untouched (fallback choice preserved). Same pattern as the v3→v4 wipe; rationale is the same — a new identity warrants a fresh slate, and the test user base is minimal.

## Why not also change the launcher icon

Designing a custom 影-on-stone PNG that reads at every Android adaptive-icon size needs image tooling we don't have at hand. Doing it badly is worse than doing it later — the existing icon's continuity through the rebrand is a smaller cost than shipping a half-baked one. Track as a follow-up: source a designed PNG (or use a vector tool to generate one), then swap via `flutter_launcher_icons`.

## Open questions (defer to device test)

1. **Cinnabar saturation on the dark board.** `#C13C2B` may pop too aggressively; adjusting toward a slightly muted variant (`#A33526`) is one knob.
2. **Subtle wood grain on the board?** Even a faint texture overlay on `boardPanel` could nudge the realism. Out of scope unless the flat colour reads too sterile on device.
3. **Klee One CJK glyph rendering.** Need to verify on device that 皮影 renders without falling back to a system font.

## Alternatives considered

- **Cream/parchment light theme.** The canonical goban look. Rejected — moonlit-dark is the user's preference and differentiates from existing Go apps.
- **Shippori Mincho serif throughout.** Considered — more "literary" feel — but its Latin glyphs are designed-around-Japanese-text and read slightly stiff. Klee One's Latin is more natural.
- **Multi-family pairing (Cormorant Garamond title + Inter body).** Considered. Cohesive single-family wins.
- **Wholesale icon redesign in this change.** Out of scope; needs assets we don't yet have.
