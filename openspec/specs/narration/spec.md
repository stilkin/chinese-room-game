## Purpose
Defines the clone's verbal explanation of its decisions.

## Requirements

### Requirement: Narration from decision context
The system SHALL generate a one-line narration string for each clone move based on the decision context: how the move was found, from which game, and with what outcome.

#### Scenario: Fuzzy match narration
- **WHEN** the clone plays a move from a diffusion-based fuzzy match
- **THEN** the narration SHALL indicate the match was approximate and reference the source game

#### Scenario: Multiple candidates narration
- **WHEN** the clone aggregates multiple candidates suggesting the same move
- **THEN** the narration SHALL indicate how many times the position was seen (e.g. "I've seen this 4 times before — going with what worked best")

#### Scenario: Fallback narration
- **WHEN** the clone uses a fallback strategy (no relevant data)
- **THEN** the narration SHALL state the fallback (e.g. "I've never seen anything like this — going with middle focus")

#### Scenario: All-losing data narration
- **WHEN** all candidate states led to losses and the clone tries a different move
- **THEN** the narration SHALL indicate the negative data (e.g. "Everything I know about this position is bad — trying something different")

### Requirement: Narration is a plain string
The system SHALL return narration as a plain `String` — no rich text, no formatting. The UI layer is responsible for presentation.

#### Scenario: Narration return type
- **WHEN** the clone brain produces a decision
- **THEN** a non-empty `String` narration SHALL be included in the result
