## MODIFIED Requirements

### Requirement: Start screen surfaces the 皮影 metaphor
The start screen SHALL render the brand identity in three layers:

1. The headline `PI-YING` rendered in the title typeface.
2. The Chinese characters `皮影` rendered immediately below in the title typeface (so they read as the same brand mark).
3. A short subtitle in the body typeface: `shadow play of go`.

The Resume / New Game / Settings actions remain unchanged.

#### Scenario: Start screen displays brand mark and subtitle
- **WHEN** the start screen mounts on a fresh launch
- **THEN** the screen SHALL display `PI-YING` and `皮影` as the brand mark
- **AND** the line `shadow play of go` SHALL appear below

#### Scenario: New Game still launches a Go game
- **WHEN** the user taps `New Game`
- **THEN** the app SHALL navigate to the game screen with a fresh 13×13 Go log (rebrand does not change navigation behaviour)
