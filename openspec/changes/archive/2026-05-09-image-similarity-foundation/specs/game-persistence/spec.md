## MODIFIED Requirements

### Requirement: Board stored as byte blob
The app SHALL store both the canonical board (`board` BLOB) and the quantized diffused image (`diffused_image` BLOB) as raw byte blobs (Int8List) in SQLite, not as JSON or text.

#### Scenario: Board round-trip
- **WHEN** a board is stored and then loaded
- **THEN** the loaded board SHALL be byte-identical to the original

#### Scenario: Diffused image round-trip
- **WHEN** a `diffusedImage` Int8List is stored and then loaded
- **THEN** the loaded image SHALL be byte-identical to the original (length matches `rows × cols`; every cell value preserved within Int8 range)

## ADDED Requirements

### Requirement: Schema v3 stores diffused images, not bit-hashes
The `game_states` table SHALL include a `diffused_image BLOB NOT NULL` column. This replaces the v2 schema's `diffused_hash BLOB NOT NULL` column. Schema bump from v2 to v3 SHALL drop and recreate `game_states` with the new shape, and SHALL clear the `games` table. Existing v1 → v2 migration logic SHALL remain in place for legacy upgrades that may still hit it.

#### Scenario: Fresh install creates v3 schema directly
- **WHEN** a fresh install opens the database
- **THEN** `game_states` SHALL be created with the `diffused_image BLOB NOT NULL` column and no `diffused_hash` column

#### Scenario: Upgrade from v2 wipes game_states
- **WHEN** the database is opened with `oldVersion = 2` and `newVersion = 3`
- **THEN** `game_states` SHALL be dropped and recreated with the v3 shape, and the `games` table SHALL be cleared (`DELETE FROM games`); `clone_config` SHALL NOT be touched

#### Scenario: V3 schema preserves indices
- **WHEN** `game_states` is created at v3
- **THEN** the table SHALL have `idx_game_states_game_id` on `game_id` and `idx_game_states_filter` on `(total_material, material_balance)` for compatibility with future per-game filters
