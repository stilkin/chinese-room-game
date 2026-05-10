## MODIFIED Requirements

### Requirement: Schema v5 rebrand wipe
The mobile persistence layer SHALL be at schema version `5`. The column shapes (board BLOB, diffused_image BLOB, move INTEGER, ply INTEGER, side INTEGER, game_id INTEGER, total_material INTEGER, material_balance INTEGER, outcome INTEGER, moves_to_end INTEGER) SHALL remain identical to v4 — only the migration is new.

`onUpgrade` from `oldVersion < 5` SHALL drop and recreate `game_states` and `games`, clearing all stored game data. `clone_config` SHALL be preserved across the migration so the user's fallback personality choice survives the upgrade. The wipe exists because the rebrand frames Pi-Ying as a new product identity; carrying forward Connect-Four-era and pre-rebrand debug data would muddy the story without offering meaningful learning value.

#### Scenario: Fresh install opens at v5
- **WHEN** the app installs on a device with no prior database
- **THEN** the database SHALL initialise at `_kSchemaVersion = 5` with empty `game_states` and `games` tables

#### Scenario: Upgrade from v4 wipes game data, preserves settings
- **WHEN** the app upgrades from a v4 database
- **THEN** `game_states` SHALL be empty AND `games` SHALL be empty after migration
- **AND** the user's fallback personality choice in `clone_config` SHALL be preserved

#### Scenario: Cumulative upgrade from v3 also wipes
- **WHEN** the app upgrades directly from a v3 database (skipping v4)
- **THEN** the same wipe SHALL occur (the `oldVersion < 5` branch covers all earlier versions)
