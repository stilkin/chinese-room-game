## 1. Engine: Game interface extension

- [ ] 1.1 In `packages/game_engine/lib/src/game_rules.dart`, add `bool isTerminal(GameLog log)` and `int finalOutcome(GameLog log)` to the `GameRules` abstract class.
- [ ] 1.2 In `packages/game_engine/lib/src/games/connect_four.dart`, implement both: `isTerminal(log) => checkWinner(log.currentBoard) != null`, `finalOutcome(log) => checkWinner(log.currentBoard) ?? 0`.
- [ ] 1.3 Update the orchestration call site (`CloneBrain` or wherever `checkWinner` is currently consulted for end-of-game) to use `isTerminal` / `finalOutcome` instead.
- [ ] 1.4 Existing engine tests stay green.

## 2. Engine: Go module

- [ ] 2.1 New file `packages/game_engine/lib/src/games/go.dart` with `class GoRules implements GameRules`.
- [ ] 2.2 Constructor: `GoRules({this.size = 13})`. Expose `int get rows => size`, `int get cols => size`.
- [ ] 2.3 Pass sentinel: `int get passMove => size * size`.
- [ ] 2.4 `legalMoves(Board)`: every empty intersection where placement is not suicide and not a ko violation, plus `passMove`. Ko is checked against the previous board hash (state passed in via `GameLog` — extend signature if needed).
- [ ] 2.5 `applyMove(GameLog log, int move, int side) → GameLog`: place the stone (if not pass), run `_captureAdjacentEnemyGroups`, return the new log with appended state.
- [ ] 2.6 `_captureAdjacentEnemyGroups(board, r, c, side)`: flood-fill each opposing neighbour group; remove if zero liberties.
- [ ] 2.7 `_isSelfSuicide(board, r, c, side)`: flood-fill the placed stone's own group; suicide if zero liberties.
- [ ] 2.8 `_floodGroup(board, r, c) → (cells, liberties)`: shared walker used by both helpers.
- [ ] 2.9 `_simpleKoBlocked(boardAfter, boardBefore) → bool`: the placement creates a board byte-equal to the immediately-previous board.
- [ ] 2.10 `isTerminal(log)`: true when the last two moves were both `passMove`, OR the board has zero non-pass legal moves remaining.
- [ ] 2.11 `finalOutcome(log)`: run area scoring; return `+1` if white wins by stones+territory, `-1` for black, `0` for tie.
- [ ] 2.12 `_areaScore(board) → (white, black)`: Chinese-style — own stones plus empties whose flood-fill region touches only one colour.

## 3. Engine: Go diffusion kernel

- [ ] 3.1 In `go.dart`, add `class GoDiffusionKernel implements DiffusionKernel`.
- [ ] 3.2 `diffuse(Board, {int steps = 2})`: orthogonal-line spread (4-neighbour), attenuating by `0.5` per step. No diagonal influence.
- [ ] 3.3 Wire into `GoRules.diffusionKernel`.

## 4. Engine: Go prefilter

- [ ] 4.1 In `go.dart`, add `class GoFilter implements CandidateFilter` storing `(queryMoveCount, window)`.
- [ ] 4.2 `matches(GameState candidate)`: candidate's move count differs from query's by at most `window`.
- [ ] 4.3 `widened()`: returns `GoFilter(queryMoveCount, window * 2)`.
- [ ] 4.4 Initial `window = 4`.
- [ ] 4.5 Wire `GoRules.prefilter(GameState query) → GoFilter(query.moveCount, 4)`.
- [ ] 4.6 Set `GoRules.maxCandidateL1Distance = 120`.

## 5. Engine: Go move scorer

- [ ] 5.1 In `go.dart`, add `class GoMoveScorer implements MoveScorer`.
- [ ] 5.2 `scoreMove(move, board, heatmap)`: pass returns `0.01`, intersections return `heatmap[move ~/ size][move % size]`.
- [ ] 5.3 Wire `GoRules.moveScorer = GoMoveScorer(size)`.
- [ ] 5.4 Wire `GoRules.moveSelectionStrategy = InfluenceOverlayStrategy(GoMoveScorer(size))`.

## 6. Engine: tests

- [ ] 6.1 New file `packages/game_engine/test/go_test.dart`.
- [ ] 6.2 Rules group: legal moves on empty 9×9 (all intersections + pass), suicide rejected, ko rejected (build the classic 4-stone shape), multi-stone capture, snapback (recapture after sacrifice).
- [ ] 6.3 Termination group: two consecutive passes terminate, area score on a small synthetic position.
- [ ] 6.4 Diffusion group: empty board → zero map; single stone radiates 4-direction lines; opposing colour radiates negative.
- [ ] 6.5 Prefilter group: matches within window, rejects outside, `widened()` doubles.
- [ ] 6.6 Move scorer group: pass returns `0.01`, intersection returns heatmap value.
- [ ] 6.7 `dart format && dart analyze && dart test` clean.

## 7. Engine: smoke benchmark

- [ ] 7.1 New file `packages/game_engine/bin/go_smoke_benchmark.dart`.
- [ ] 7.2 10 self-play games on 9×9 (cheaper than 13×13 for smoke), seed 42, fresh log.
- [ ] 7.3 Print: per-game move count, final outcome, peak retrieval candidate count, any errors.
- [ ] 7.4 Pass criterion: all 10 games terminate without crash; final scores look sane (not all 0–0; some games end in win/loss).

## 8. Verification

- [ ] 8.1 `dart format` clean.
- [ ] 8.2 `dart analyze` clean.
- [ ] 8.3 `dart test` — all green (existing CF tests + new Go tests).
- [ ] 8.4 `dart run bin/go_smoke_benchmark.dart` — passes the smoke criterion above.
