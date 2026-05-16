## ADDED Requirements

### Requirement: History screen lists completed games

The History screen SHALL display all completed games (up to the same 100-game cap used by the home-screen strip) as a vertical scrollable list, ordered most-recent-first. Each list row SHALL show: the game's start date and time, an outcome chip (`WIN` / `LOSS` / `DRAW` / `—`), the total move count, the per-game area split (e.g. "84 : 76", or "—" when area data is unavailable), and a thin proportion bar reusing the same painter as the home-screen strip. Resigned losses are not distinguished from natural losses at the chip level — the persistence layer carries no `end_reason` signal in v1, so the implicit "did not reach a territory verdict" cue is the muted-grey DNF bar (rendered whenever the area columns are null).

#### Scenario: List populates from completed games
- **WHEN** the History screen is opened with N completed games in the database (`outcome IS NOT NULL`)
- **THEN** the screen SHALL render exactly N rows
- **AND** the topmost row SHALL correspond to the most-recently-completed game

#### Scenario: Row content for a player win
- **WHEN** the row's game has `outcome == 1`, `playerArea == 84`, `cloneArea == 76`, `totalMoves == 87`
- **THEN** the row SHALL show the outcome chip `WIN`, the move count `87 moves`, the area split `84 : 76`, and a proportion bar leaning ivory

#### Scenario: Row content for a resigned / legacy game
- **WHEN** the row's game has `playerArea == null` or `cloneArea == null`
- **THEN** the area-split string SHALL be `—`
- **AND** the proportion bar SHALL render as a solid muted-grey DNF row
- **AND** the outcome chip SHALL still be `WIN` / `LOSS` / `DRAW` based solely on `outcome` (resignation is not surfaced separately in v1)

#### Scenario: Empty state on a fresh install
- **WHEN** the History screen is opened with zero completed games
- **THEN** the screen SHALL display a centred muted message "No completed games yet."
- **AND** no list rows SHALL be rendered

### Requirement: Tapping a row opens the replay

Each list row SHALL be a tap target. Tapping a row SHALL navigate to the Replay screen for that game, passing the row's full game-summary record (including `gameId`) as route arguments.

#### Scenario: Tap navigates to replay
- **WHEN** the player taps a list row
- **THEN** the app SHALL navigate to the `/replay` route
- **AND** the route arguments SHALL include the row's `gameId`

#### Scenario: Back navigation returns to history
- **WHEN** the player is on the Replay screen and taps the back arrow
- **THEN** the app SHALL return to the History screen
- **AND** the scroll position of the History list SHALL be preserved
