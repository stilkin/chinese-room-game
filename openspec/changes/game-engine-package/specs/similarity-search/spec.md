## ADDED Requirements

### Requirement: Two-scalar pre-filter
The system SHALL pre-filter candidate states using two values computed from the board: `total_material` (sum of absolute piece values) and `material_balance` (sum of signed piece values). Only states within the current filter window on both axes SHALL be considered.

#### Scenario: Filter excludes distant game phases
- **WHEN** the current board has total_material=10 and the filter window is ±2
- **THEN** stored states with total_material < 8 or > 12 SHALL be excluded

#### Scenario: Filter on both axes
- **WHEN** the current board has total_material=10 and material_balance=0
- **THEN** only states within ±window on BOTH total_material AND material_balance SHALL pass

### Requirement: Adaptive widening
The system SHALL start with a filter window of ±2 on each axis. If fewer than 5 candidates pass, the window SHALL double iteratively until at least 5 candidates are found or the entire database has been searched.

#### Scenario: Enough candidates at initial window
- **WHEN** 8 stored states fall within ±2 on both axes
- **THEN** the system SHALL use those 8 candidates without widening

#### Scenario: Widening on insufficient candidates
- **WHEN** only 2 stored states fall within ±2
- **THEN** the system SHALL widen to ±4 and re-filter

#### Scenario: Full database fallback
- **WHEN** widening still yields fewer than 5 candidates after reaching the maximum possible window
- **THEN** the system SHALL search the entire database

### Requirement: Exact match via Zobrist takes priority
The system SHALL check for Zobrist hash exact matches before performing diffusion-based similarity search. Exact matches SHALL be ranked above all fuzzy matches.

#### Scenario: Exact match found
- **WHEN** the current board's Zobrist hash matches a stored state
- **THEN** that state SHALL appear first in the candidate list regardless of diffusion similarity

### Requirement: Fuzzy ranking by Hamming distance
For non-exact-match candidates, the system SHALL rank them by Hamming distance between their diffused bit hash and the current board's diffused bit hash. Lower distance means higher similarity.

#### Scenario: Closer hash ranked higher
- **WHEN** candidate A has Hamming distance 3 and candidate B has Hamming distance 7
- **THEN** candidate A SHALL be ranked above candidate B
