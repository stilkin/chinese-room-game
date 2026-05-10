## 1. Engine: Game interface extension

- [x] 1.1 In `packages/game_engine/lib/src/game_rules.dart`, add `bool isTerminal(GameLog log)` and `int finalOutcome(GameLog log)` to the `GameRules` abstract class.
- [x] 1.2 In `packages/game_engine/lib/src/games/connect_four.dart`, implement both: `isTerminal(log) => checkWinner(log.currentBoard) != null`, `finalOutcome(log) => checkWinner(log.currentBoard) ?? 0`.
- [x] 1.3 Update the orchestration call site (`CloneBrain` or wherever `checkWinner` is currently consulted for end-of-game) to use `isTerminal` / `finalOutcome` instead.
- [x] 1.4 Existing engine tests stay green.

## 2. Engine: Go module

- [x] 2.1 New file `packages/game_engine/lib/src/games/go.dart` with `class GoRules implements GameRules`.
- [x] 2.2 Constructor: `GoRules({this.size = 13})`. Expose `int get rows => size`, `int get cols => size`.
- [x] 2.3 Pass sentinel: `int get passMove => size * size`.
- [x] 2.4 `legalMoves(Board)`: every empty intersection where placement is not suicide and not a ko violation, plus `passMove`. Ko is checked against the previous board hash (state passed in via `GameLog` — extend signature if needed).
- [x] 2.5 `applyMove(GameLog log, int move, int side) → GameLog`: place the stone (if not pass), run `_captureAdjacentEnemyGroups`, return the new log with appended state.
- [x] 2.6 `_captureAdjacentEnemyGroups(board, r, c, side)`: flood-fill each opposing neighbour group; remove if zero liberties.
- [x] 2.7 `_isSelfSuicide(board, r, c, side)`: flood-fill the placed stone's own group; suicide if zero liberties.
- [x] 2.8 `_floodGroup(board, r, c) → (cells, liberties)`: shared walker used by both helpers.
- [x] 2.9 `_simpleKoBlocked(boardAfter, boardBefore) → bool`: the placement creates a board byte-equal to the immediately-previous board.
- [x] 2.10 `isTerminal(log)`: true when the last two moves were both `passMove`, OR the board has zero non-pass legal moves remaining.
- [x] 2.11 `finalOutcome(log)`: run area scoring; return `+1` if white wins by stones+territory, `-1` for black, `0` for tie.
- [x] 2.12 `_areaScore(board) → (white, black)`: Chinese-style — own stones plus empties whose flood-fill region touches only one colour.

## 3. Engine: Go diffusion kernel

- [x] 3.1 In `go.dart`, add `class GoDiffusionKernel implements DiffusionKernel`.
- [x] 3.2 `diffuse(Board, {int steps = 2})`: orthogonal-line spread (4-neighbour), attenuating by `0.5` per step. No diagonal influence.
- [x] 3.3 Wire into `GoRules.diffusionKernel`.

## 4. Engine: Go prefilter

- [x] 4.1 In `go.dart`, add `class GoFilter implements CandidateFilter` storing `(queryMoveCount, window)`.
- [x] 4.2 `matches(GameState candidate)`: candidate's move count differs from query's by at most `window`.
- [x] 4.3 `widened()`: returns `GoFilter(queryMoveCount, window * 2)`.
- [x] 4.4 Initial `window = 4`.
- [x] 4.5 Wire `GoRules.prefilter(GameState query) → GoFilter(query.moveCount, 4)`.
- [x] 4.6 Set `GoRules.maxCandidateL1Distance = 120`.

## 5. Engine: Go move scorer

- [x] 5.1 In `go.dart`, add `class GoMoveScorer implements MoveScorer`.
- [x] 5.2 `scoreMove(move, board, heatmap)`: pass returns `0.01`, intersections return `heatmap[move ~/ size][move % size]`.
- [x] 5.3 Wire `GoRules.moveScorer = GoMoveScorer(size)`.
- [x] 5.4 Wire `GoRules.moveSelectionStrategy = InfluenceOverlayStrategy(GoMoveScorer(size))`.

## 6. Engine: tests

- [x] 6.1 New file `packages/game_engine/test/go_test.dart`.
- [x] 6.2 Rules group: legal moves on empty 9×9 (all intersections + pass), suicide rejected, ko rejected (build the classic 4-stone shape), multi-stone capture, snapback (recapture after sacrifice).
- [x] 6.3 Termination group: two consecutive passes terminate, area score on a small synthetic position.
- [x] 6.4 Diffusion group: empty board → zero map; single stone radiates 4-direction lines; opposing colour radiates negative.
- [x] 6.5 Prefilter group: matches within window, rejects outside, `widened()` doubles.
- [x] 6.6 Move scorer group: pass returns `0.01`, intersection returns heatmap value.
- [x] 6.7 `dart format && dart analyze && dart test` clean.

## 7. Engine: smoke benchmark

- [x] 7.1 New file `packages/game_engine/bin/go_smoke_benchmark.dart`.
- [x] 7.2 10 self-play games on 9×9 (cheaper than 13×13 for smoke), seed 42, fresh log.
- [x] 7.3 Print: per-game move count, final outcome, peak retrieval candidate count, any errors.
- [x] 7.4 Pass criterion: all 10 games terminate without crash; final scores look sane (not all 0–0; some games end in win/loss).

## 8. Verification

- [x] 8.1 `dart format` clean.
- [x] 8.2 `dart analyze` clean.
- [x] 8.3 `dart test` — all green (existing CF tests + new Go tests).
- [x] 8.4 `dart run bin/go_smoke_benchmark.dart` — passes the smoke criterion above.
