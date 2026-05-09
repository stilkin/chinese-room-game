## ADDED Requirements

### Requirement: Influence map quantizes to Int8 image
The system SHALL convert the diffused influence map (a `List<List<double>>`) to a row-major `Int8List` via `quantizeInfluenceMap`: each cell value is rounded and clamped to the signed-byte range `[-128, 127]`. The resulting image is stored alongside each `GameState` as its `diffusedImage` and is the input to L1 distance retrieval.

#### Scenario: Identical boards produce identical images
- **WHEN** two identical boards are diffused and quantized
- **THEN** the resulting `Int8List` images SHALL be byte-for-byte equal

#### Scenario: Similar boards produce small L1 distances
- **WHEN** two boards differ by one piece placement
- **THEN** the L1 distance between their diffused images SHALL be small relative to the total cell count

#### Scenario: Out-of-range values clamp to byte bounds
- **WHEN** an influence map cell holds a value outside `[-128, 127]`
- **THEN** `quantizeInfluenceMap` SHALL clamp it to the bound rather than overflow

## REMOVED Requirements

### Requirement: Influence map converts to bit hash
**Reason**: Replaced by Int8 quantization. Bit-hashing collapsed each cell to a single bit (sign of influence) and matched via Hamming distance. The shipped pipeline preserves cell magnitude as a signed byte and matches via L1 distance, which is more discriminating and supports the heatmap accumulation in `InfluenceOverlayStrategy`.
**Migration**: `influenceMapToBitHash` was deleted; callers use `quantizeInfluenceMap` and L1 distance instead. Stored data uses a `diffused_image BLOB` column at schema v3.
