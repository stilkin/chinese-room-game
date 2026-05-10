## 1. Dependencies & assets

- [x] 1.1 Add `google_fonts` to `apps/mobile/pubspec.yaml` dependencies.
- [x] 1.2 Drop the PressStart2P and VT323 font declarations from pubspec's `flutter > fonts` section. Leave the TTF files in `assets/fonts/` for now (no need to delete; they just don't get bundled).
- [x] 1.3 Update pubspec `description`: replace the Connect-Four-era line with "Pi-Ying — 皮影 — Go against a learning clone."
- [x] 1.4 `flutter pub get`.

## 2. Theme rewrite

- [x] 2.1 In `apps/mobile/lib/src/theme.dart`, replace the colour constants with the moonlit-goban palette (see design.md table). Keep the existing names where they make sense (`bg`, `surface`, `surfaceLow`, `outline`, `onSurface`, `onSurfaceMuted`); add `boardPanel`, `lineColor`, `cinnabar`. Drop `red`/`yellow`/`blue` — and their `amber`/`cyan` aliases.
- [x] 2.2 Replace `_headlineFamily = 'PressStart2P'` and `_bodyFamily = 'VT323'` with `google_fonts`-driven `TextStyle` factories. Use `GoogleFonts.kleeOne(weight: FontWeight.w600, ...)` for headlines and `GoogleFonts.kleeOne(weight: FontWeight.w400, ...)` for body.
- [x] 2.3 Rewrite the `textTheme` block with the new sizes (table in design.md).
- [x] 2.4 Rewrite button themes (`filledButtonTheme`, `outlinedButtonTheme`, `textButtonTheme`) to use the new palette. Filled buttons are cinnabar bg + onSurface text (used sparingly); outlined buttons are onSurface text + onSurface 1px outline; text buttons are onSurface.
- [x] 2.5 Update `appBarTheme`: bg = `bg`, foreground/title = `onSurface`.
- [x] 2.6 Update `dialogTheme`: bg = `surface`, border = `outline` (1px). Drop the 2px yellow border.
- [x] 2.7 Update `snackBarTheme` accordingly.
- [x] 2.8 Search the codebase for direct references to `PiYingTheme.red` / `.yellow` / `.blue` / `.amber` / `.cyan` and replace with the new tokens (`onSurface`, `cinnabar`, `lineColor`, etc., as appropriate).

## 3. Board widget colours

- [x] 3.1 In `apps/mobile/lib/src/widgets/go_board.dart`: swap `_kBoardBackground`, `_kLineColor`, `_kCloneStone` outline values to the new palette.
- [x] 3.2 Last-move ring: `PiYingTheme.blue` → `PiYingTheme.cinnabar`.
- [x] 3.3 Verify star-point dot colour reads on the new wood tone (it'll be `lineColor`, same as grid lines).

## 4. In-app lore

- [x] 4.1 In `apps/mobile/lib/src/screens/start_screen.dart`, replace the subtitle. Two lines: `皮影` rendered large (display style), and `shadow play of go` rendered smaller below. The `PI-YING` headline above stays.
- [x] 4.2 In `apps/mobile/lib/src/screens/settings_screen.dart`, add a small "About" block above the personality picker:
    ```
    Pi-Ying — 皮影 (pí yǐng), Chinese shadow theatre,
    where a puppeteer animates flat figures behind a
    backlit screen. Your clone is your shadow,
    learning your moves and playing them back at you.
    ```
    Use `bodySmall` style, muted color.

## 5. Schema migration (v4 → v5)

- [x] 5.1 In `apps/mobile/lib/src/db/database_service.dart`, bump `_kSchemaVersion` to `5`.
- [x] 5.2 Extend `onUpgrade` with `if (oldVersion < 5)` branch — drop `game_states`, drop `games`, recreate empty. Reuse the v3→v4 pattern.
- [x] 5.3 `clone_config` untouched (settings preserved).
- [x] 5.4 Note in the comment block that v4→v5 is a rebrand wipe, not a schema-shape change.

## 6. Tests

- [x] 6.1 Update `database_service_test.dart` if it references the schema version constant directly. Existing tests using inMemoryDatabasePath always run `onCreate` (no upgrade triggered), so most should continue to pass.
- [x] 6.2 No new tests required for the visual rebrand itself (no behaviour change). The data-wipe path is a thin replay of v3→v4 and would only need a dedicated test if we'd built that earlier.

## 7. Verification

- [x] 7.1 `flutter analyze` clean.
- [x] 7.2 `flutter test` clean (36 mobile tests + any new ones).
- [x] 7.3 `flutter build apk --debug` succeeds.
- [ ] 7.4 Install and smoke on device:
  - Start screen renders new palette + Klee One typography.
  - `皮影` and Latin co-render in the same font on screen.
  - Game board: warm dark wood, cream lines, ivory + slate stones still readable.
  - Cinnabar last-move ring pops appropriately (not too aggressive).
  - Settings: about block reads cleanly; personality label uses new typography.
  - Old data wiped (gamesPlayed = 0 on first run after upgrade).

## 8. Out of scope (track as follow-ups)

- [ ] 8.1 Launcher icon redesign — needs an external PNG asset (stone-with-影 sumi-ink). Defer until source asset exists.
- [ ] 8.2 Audio / sound design (Tier 2). Defer; should match the new visual register.
- [ ] 8.3 Animations / transitions (ink-wash fade-ins, etc.). Defer.
