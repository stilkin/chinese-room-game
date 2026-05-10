## MODIFIED Requirements

### Requirement: Fallback personality picker

The settings screen SHALL allow the player to select a fallback personality for the clone via a discrete 5-step slider. For Go mode, the slider positions, in order from `0` (simplest, weakest) to `4` (most complex, strongest), correspond to the personalities below; only these five SHALL be selectable via the UI:

| Position | Strategy        | Name       | Blurb                                  |
|----------|-----------------|------------|----------------------------------------|
| 0        | `random`        | Chaotic    | plays anywhere legal.                  |
| 1        | `goStarPoints`  | Star-point | favours classic opening points.        |
| 2        | `goHugger`      | Hugger     | extends its own shapes.                |
| 3        | `goContact`     | Contact    | plays right at your stones.            |
| 4        | `goGreedyArea`  | Greedy     | tries to maximise its territory.       |

The slider's positions are ordered by behavioural strength as observed in head-to-head self-play, so "further right" reads as both "more complex" and "stronger." If the round-robin gate observes a different ordering, slider positions SHALL be swapped to match. The selection SHALL persist across app restarts. The default for fresh installs SHALL be position 2 (Hugger).

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

#### Scenario: Default for fresh installs (Go mode)
- **WHEN** the player opens the settings screen for the first time on a fresh install in Go mode
- **THEN** the slider SHALL be at position 2 (Hugger) and no save SHALL have occurred yet

#### Scenario: Legacy or unknown persisted value remapped on read
- **WHEN** the persisted fallback value is not in the Go user-facing slider list (e.g. `pileFocus`, `ownPileAdjacent`, `greedyConnect`, `greedyConnectDefense`, `middleFocus`, `edgeFocus`, or any unrecognised string)
- **THEN** `loadFallback` SHALL return `goHugger` and the settings screen SHALL display the slider at position 2 (Hugger)

#### Scenario: Personality affects clone fallback only
- **WHEN** the clone has relevant past-game data
- **THEN** the chosen personality SHALL NOT influence the move (it only fires when the clone falls back)
