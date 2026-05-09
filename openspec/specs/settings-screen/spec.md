## Purpose
Defines the settings UI (fallback personality, data reset).
## Requirements
### Requirement: Fallback personality picker

The settings screen SHALL allow the player to select a fallback personality for the clone via a discrete 5-step slider. The slider positions, in order from `0` (least complex) to `4` (most complex), correspond to the personalities below; only these five SHALL be selectable via the UI:

| Position | Strategy                | Name      | Blurb                              |
|----------|-------------------------|-----------|------------------------------------|
| 0        | `random`                | Chaotic   | plays anywhere. no plan.           |
| 1        | `ownPileAdjacent`       | Builder   | builds next to its own pieces.     |
| 2        | `pileFocus`             | Stacker   | stacks the tallest pile.           |
| 3        | `greedyConnect`         | Connector | plays for longer chains.           |
| 4        | `greedyConnectDefense`  | Sentinel  | plays for chains. blocks losses.   |

The slider's positions are ordered by behavioural strength as observed in head-to-head self-play, so "further right" reads as both "more complex" and "stronger." The selection SHALL persist across app restarts. The default for fresh installs SHALL be position 2 (Stacker).

#### Scenario: Slider shows current personality name and blurb
- **WHEN** the player opens the settings screen
- **THEN** the screen SHALL display the slider, the name of the currently selected personality (in display font), and a one-line blurb (in body font) describing the strategy

#### Scenario: Drag updates name and blurb live
- **WHEN** the player drags the slider thumb
- **THEN** the displayed name and blurb SHALL update on each step the thumb passes through

#### Scenario: Slider release persists choice
- **WHEN** the player releases the slider on a position different from the previously persisted one
- **THEN** the new personality SHALL be saved to the configuration store
- **AND** subsequent app launches SHALL initialise to the same position

#### Scenario: Default for fresh installs
- **WHEN** the player opens the settings screen for the first time on a fresh install
- **THEN** the slider SHALL be at position 2 (Stacker) and no save SHALL have occurred yet

#### Scenario: Legacy or unknown persisted value remapped on read
- **WHEN** the persisted fallback value is not in the user-facing slider list (e.g. `edgeFocus`, `middleFocus`, or any unrecognised string)
- **THEN** `loadFallback` SHALL return `pileFocus` and the settings screen SHALL display the slider at position 2 (Stacker)

#### Scenario: Personality affects clone fallback only
- **WHEN** the clone has relevant past-game data
- **THEN** the chosen personality SHALL NOT influence the move (it only fires when the clone falls back)

### Requirement: Delete all game logs
The settings screen SHALL have a "Delete All Game Logs" button that erases all stored game states and resets the clone.

#### Scenario: Delete with confirmation
- **WHEN** the player taps "Delete All Game Logs"
- **THEN** a confirmation dialog SHALL appear before deleting

#### Scenario: Confirm delete
- **WHEN** the player confirms the deletion
- **THEN** all game states SHALL be removed from SQLite, the in-memory game log SHALL be cleared, and the games-played count SHALL reset to 0

#### Scenario: Cancel delete
- **WHEN** the player cancels the deletion dialog
- **THEN** no data SHALL be deleted

