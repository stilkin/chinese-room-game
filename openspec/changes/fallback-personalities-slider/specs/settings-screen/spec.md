## MODIFIED Requirements

### Requirement: Fallback personality picker

The settings screen SHALL allow the player to select a fallback personality for the clone via a discrete 5-step slider. The slider positions, in order from `0` (least complex) to `4` (most complex), correspond to the personalities below; only these five SHALL be selectable via the UI:

| Position | Strategy                | Name      | Blurb                              |
|----------|-------------------------|-----------|------------------------------------|
| 0        | `random`                | Chaotic   | plays anywhere. no plan.           |
| 1        | `pileFocus`             | Stacker   | stacks the tallest pile.           |
| 2        | `ownPileAdjacent`       | Builder   | builds next to its own pieces.     |
| 3        | `greedyConnect`         | Connector | plays for longer chains.           |
| 4        | `greedyConnectDefense`  | Sentinel  | plays for chains. blocks losses.   |

The selection SHALL persist across app restarts. The default for fresh installs SHALL be position 2 (Builder).

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
- **THEN** the slider SHALL be at position 2 (Builder) and no save SHALL have occurred yet

#### Scenario: Legacy persisted value remapped on read
- **WHEN** the persisted fallback value is `edgeFocus` or `middleFocus` (no longer user-selectable)
- **THEN** the settings screen SHALL display the slider at position 2 (Builder) without overwriting storage; the value SHALL be normalised to `ownPileAdjacent` the next time the player makes any selection

#### Scenario: Personality affects clone fallback only
- **WHEN** the clone has relevant past-game data
- **THEN** the chosen personality SHALL NOT influence the move (it only fires when the clone falls back)
