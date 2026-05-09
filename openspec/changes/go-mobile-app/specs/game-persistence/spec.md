## MODIFIED Requirements

### Requirement: Schema v4 stores Go-shaped data
The mobile persistence layer SHALL be at schema version `4`. The column shapes (board BLOB, diffused_image BLOB, move INTEGER, ply INTEGER, side INTEGER, game_id INTEGER, total_material INTEGER, material_balance INTEGER, outcome INTEGER, moves_to_end INTEGER) SHALL remain identical to v3 — only the BLOB sizes differ as a function of the active game's board dimensions.

`onUpgrade` from v3 to v4 SHALL drop and recreate `game_states` and `games`, because Connect-Four-shaped (7×6) blobs are byte-incompatible with Go-shaped (13×13) blobs. Settings (fallback choice and similar) live in a separate table and SHALL be preserved.

#### Scenario: Fresh install opens at v4
- **WHEN** the app installs on a device with no prior database
- **THEN** the database SHALL initialise at `_kSchemaVersion = 4` with empty `game_states` and `games` tables

#### Scenario: Upgrade from v3 wipes game data, preserves settings
- **WHEN** the app upgrades from a v3 database
- **THEN** `game_states` SHALL be empty AND `games` SHALL be empty after migration
- **AND** the user's fallback personality choice (if any) SHALL be preserved

#### Scenario: Go state round-trips
- **WHEN** a Go `GameState` is written and re-read
- **THEN** `board`, `diffusedImage`, `movePlayed`, `ply`, `gameId`, `totalMaterial`, `materialBalance`, `outcome`, and `movesToEnd` SHALL match the original byte-for-byte
