## MODIFIED Requirements

### Requirement: Schema v5 rebrand wipe step
This requirement defines the **v4 → v5 migration step** only; it does not assert the final schema version (later migrations such as v5 → v6 remain valid and are described by their own change specs). The column shapes (board BLOB, diffused_image BLOB, move INTEGER, ply INTEGER, side INTEGER, game_id INTEGER, total_material INTEGER, material_balance INTEGER, outcome INTEGER, moves_to_end INTEGER) SHALL remain identical to v4 — only the migration is new.

`onUpgrade` for databases with `oldVersion < 5` SHALL drop and recreate `game_states` and `games`, clearing all stored game data. `clone_config` SHALL be preserved across the migration so the user's fallback personality choice survives the upgrade. The wipe exists because the rebrand frames Pi-Ying as a new product identity; carrying forward Connect-Four-era and pre-rebrand debug data would muddy the story without offering meaningful learning value.

#### Scenario: Upgrade from v4 wipes game data, preserves settings
- **WHEN** the app upgrades from a v4 database
- **THEN** `game_states` SHALL be empty AND `games` SHALL be empty after the v5 step
- **AND** the user's fallback personality choice in `clone_config` SHALL be preserved

#### Scenario: Cumulative upgrade from v3 also wipes
- **WHEN** the app upgrades directly from a v3 database (skipping v4)
- **THEN** the same wipe SHALL occur (the `oldVersion < 5` branch covers all earlier versions)
