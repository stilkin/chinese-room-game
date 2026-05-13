## MODIFIED Requirements

### Requirement: Fallback personality picker

The settings screen SHALL allow the player to select a fallback personality for the clone via a discrete 5-step slider. For Go mode, the slider positions, in order from `0` (simplest, weakest) to `4` (most complex, strongest), correspond to the personalities below; only these five SHALL be selectable via the UI:

| Position | Strategy        | Name       | Blurb                                  |
|----------|-----------------|------------|----------------------------------------|
| 0        | `random`        | Wanderer   | plays randomly near existing stones.   |
| 1        | `goStarPoints`  | Star-point | favours classic opening points.        |
| 2        | `goContact`     | Contact    | plays right at your stones.            |
| 3        | `goDiamond`     | Diamond    | plays in ponnuki-like diamond shapes.  |
| 4        | `goGreedyArea`  | Greedy     | tries to maximise its territory.       |

The slider's positions are ordered by behavioural strength as observed in head-to-head self-play (round-robin gate, 50 games per direction, seed 42), so "further right" reads as both "more complex" and "stronger." The `random` strategy at position 0 is labelled **Wanderer** in Go mode: a Manhattan-2 prefilter restricts the random pool to cells near existing stones, which produces more-interactive (and slightly stronger) play than pure-random on a 13×13 board. The reworked `goDiamond` at position 3 replaces the prior `goHugger`: it scores by `(diagonal-friendly count) − (orthogonal-friendly count)`, actively penalising dumpling shapes and rewarding kosumi / ponnuki extensions. The selection SHALL persist across app restarts.

The default for fresh installs SHALL be position 1 (Star-point). The default sits at slider-position-1 rather than the slider's middle because Star-point's ~30% win-rate against the field gives an encouraging first impression (the cold-start beginner wins most games), and its textbook-Go opening (hoshi / 3-3 / 4-4) visually communicates "this is Go" from move 1.

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
- **THEN** the slider SHALL be at position 1 (Star-point) and no save SHALL have occurred yet

#### Scenario: Legacy `goHugger` value coerced on read
- **WHEN** the persisted fallback value is the literal string `goHugger` (from before the rename)
- **THEN** `loadFallback` SHALL NOT match any enum value
- **AND** SHALL return `goStarPoints`
- **AND** the settings screen SHALL display the slider at position 1 (Star-point)

#### Scenario: Other legacy or unknown persisted values remapped on read
- **WHEN** the persisted fallback value is not in the Go user-facing slider list (e.g. `pileFocus`, `ownPileAdjacent`, `greedyConnect`, `greedyConnectDefense`, `middleFocus`, `edgeFocus`, or any unrecognised string)
- **THEN** `loadFallback` SHALL return `goStarPoints` and the settings screen SHALL display the slider at position 1 (Star-point)

#### Scenario: Personality affects clone fallback only
- **WHEN** the clone has relevant past-game data
- **THEN** the chosen personality SHALL NOT influence the move (it only fires when the clone falls back)
