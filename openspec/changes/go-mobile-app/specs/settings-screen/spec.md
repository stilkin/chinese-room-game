## MODIFIED Requirements

### Requirement: Fallback personality picker
The settings screen SHALL provide a slider for selecting the clone's fallback personality. For the Go-mobile-app launch, the slider SHALL contain a single position: `Chaotic` (random legal move). Future ladder entries are tracked by a separate change.

#### Scenario: Slider has a single entry
- **WHEN** the settings screen renders
- **THEN** the personality slider SHALL display exactly one position labelled `Chaotic` with a blurb describing random play

#### Scenario: Persistence preserves the choice
- **WHEN** the user opens settings, leaves the slider on `Chaotic`, and reopens settings later
- **THEN** the slider SHALL still be on `Chaotic`

#### Scenario: Legacy persisted values coerce to Chaotic
- **WHEN** persistence holds a value that is not in the current user-facing set (e.g. `pileFocus`, `ownPileAdjacent`, `greedyConnect`, `greedyConnectDefense`, or any unrecognised string)
- **THEN** loading the fallback SHALL return `random` (Chaotic) without prompting the user
