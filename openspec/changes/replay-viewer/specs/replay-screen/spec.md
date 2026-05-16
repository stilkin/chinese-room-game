## ADDED Requirements

### Requirement: Replay screen shows a completed game's board at any ply

The Replay screen SHALL display a read-only Go board widget that renders the state of a completed game at the currently-selected ply. The screen SHALL present, alongside the board:

- A header verdict matching the game's outcome — `YOU WIN`, `CLONE WINS`, `DRAW`, or `GAME OVER` (the last is the fallback for any unrecognised outcome value).
- An area readout line (`AREA · YOU X · CLONE Y`) when both areas are persisted, suppressed otherwise.
- A move-counter line of the form `Move N / Total`, with `(pass)` appended when the current ply is a pass move.
- A horizontal ply slider whose range is `[0, totalPlies]`, where ply `0` is the empty pre-game board and ply `k` is the board state after the k-th move.
- A row of VCR-style controls: jump-to-start, step-back, play/pause, step-forward, jump-to-end.
- A speed-control chip cycling through `1×`, `2×`, and `4×`.

The Replay screen SHALL open with the slider at the final ply and playback paused.

#### Scenario: Opens at final ply paused
- **WHEN** the player taps a completed game in the History screen
- **THEN** the Replay screen SHALL open
- **AND** the slider SHALL be positioned at `totalPlies`
- **AND** the play/pause button SHALL show the play icon (i.e. playback is paused)
- **AND** the board SHALL render the final-position state of the game

#### Scenario: Scrubbing the slider updates the board
- **WHEN** the player drags the slider to ply `k` (where `0 ≤ k ≤ totalPlies`)
- **THEN** the board SHALL render the position after the k-th move
- **AND** for `k == 0` the board SHALL render empty
- **AND** the move-counter SHALL update to `Move k / totalPlies`

#### Scenario: VCR jump-to-start
- **WHEN** the player taps the jump-to-start (`⏮`) button
- **THEN** the slider SHALL move to ply `0`
- **AND** playback SHALL pause if it was playing

#### Scenario: VCR jump-to-end
- **WHEN** the player taps the jump-to-end (`⏭`) button
- **THEN** the slider SHALL move to ply `totalPlies`
- **AND** playback SHALL pause if it was playing

#### Scenario: VCR step buttons
- **WHEN** the player taps step-forward (`⏵`) and the current ply is less than `totalPlies`
- **THEN** the slider SHALL advance by exactly one ply
- **WHEN** the player taps step-back (`⏴`) and the current ply is greater than `0`
- **THEN** the slider SHALL retreat by exactly one ply

#### Scenario: Play / pause toggle
- **WHEN** the player taps the play button while paused
- **THEN** playback SHALL begin
- **AND** the slider SHALL advance one ply per tick at the current speed factor
- **WHEN** the player taps the pause button while playing
- **THEN** playback SHALL halt at the current ply

#### Scenario: Playback stops at the end
- **WHEN** playback is active and the slider reaches `totalPlies`
- **THEN** playback SHALL pause automatically
- **AND** the play/pause button SHALL revert to the play icon

#### Scenario: Speed cycling
- **WHEN** the player taps the speed chip
- **THEN** the speed factor SHALL cycle `1× → 2× → 4× → 1×`
- **AND** the displayed chip label SHALL update accordingly
- **AND** if playback is active, the tick interval SHALL update to the new speed factor without interrupting playback

### Requirement: Board renders from the player's perspective regardless of outcome

For a game where the clone won (`outcome == -1`), the per-ply boards stored in `game_states` are sign-flipped (winner-POV convention). The Replay screen SHALL reverse this flip for display so that, at every ply, the player's stones render in the ivory colour and the clone's stones render in the near-black colour — matching live play.

#### Scenario: Bot-won game displays player as ivory
- **WHEN** the player opens a replay for a game with `outcome == -1`
- **THEN** at every ply, every player stone (the moves made by the player) SHALL render in ivory
- **AND** at every ply, every clone stone SHALL render in near-black

#### Scenario: Player-won and drawn games render directly
- **WHEN** the player opens a replay for a game with `outcome == 1` or `outcome == 0`
- **THEN** the loaded board blobs SHALL be rendered directly without inversion

### Requirement: Replay board is read-only

The Go board widget on the Replay screen SHALL ignore tap input. The board SHALL render exactly as the live-play board but without accepting moves.

#### Scenario: Tap on board does nothing
- **WHEN** the player taps any intersection on the replay board
- **THEN** no move SHALL be recorded
- **AND** the displayed ply SHALL NOT change

### Requirement: Pass plies annotated, no ring drawn

When the current ply's `movePlayed` value is the `passMove` sentinel, the move-counter SHALL display "(pass)" appended to the move number, and the last-move highlight ring SHALL NOT be drawn on the board.

#### Scenario: Pass ply annotation
- **WHEN** the current ply's stored `movePlayed` equals `passMove`
- **THEN** the move-counter line SHALL read `Move N / Total (pass)`
- **AND** no last-move ring SHALL be rendered

#### Scenario: Non-pass ply
- **WHEN** the current ply's `movePlayed` is a regular intersection index
- **THEN** the last-move ring SHALL be drawn at that intersection
- **AND** no "(pass)" annotation SHALL appear
