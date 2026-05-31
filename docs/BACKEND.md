# Pi-Ying Backend Design

> **Status:** design-only. Phase 3 has not started. This document captures the agreed shape so that, when implementation begins, individual OpenSpec changes (one per feature) can reference a single source of truth instead of rediscovering decisions.
>
> See [PROJECT.md](PROJECT.md) for the project as a whole. Ops-level install state for the host (`crg-oci-mini-3`) lives in the operator's memory system, not in the repo.

---

## Purpose

The backend exists so a player's clone, trained locally on their own games, can compete against other players' clones in an automated, asynchronous league. It is **not** a multiplayer server. There are no real-time matches between humans, no chat, no accounts.

Three product surfaces:

1. **Mobile app → backend:** the player publishes a snapshot of their clone (the "bot"). Snapshots are immutable.
2. **Backend internals:** a continuous worker pairs published bots, runs matches using the same Dart engine the mobile app uses, updates ratings.
3. **Web frontend → backend (read-only):** leaderboards, individual bot profiles, replays. No login required to browse.

---

## Hosting & Stack

| Layer       | Choice                                                                 |
|-------------|------------------------------------------------------------------------|
| Host        | Oracle Cloud Always Free (`crg-oci-mini-3`, x86_64, ~954 MiB RAM)      |
| Edge        | Caddy v2 — TLS, reverse-proxy, static file serving                     |
| Runtime     | Dart, `dart compile exe` → single native binary, no SDK on the server  |
| Framework   | Dart Frog or Relic (decide at first PR)                                |
| Database    | SQLite, replicated off-box with Litestream                             |
| Backup      | Litestream → OCI Object Storage Always Free (or bg-production disk — TBD) |

Schema is kept portable so a later swap to PostgreSQL stays open if scale demands it. **Don't use SQLite-isms** (`INSERT OR REPLACE`, etc.); thin data-access layer keeps statements uniform.

### Routing on `piying.pocito.fyi`

| Path     | Handler                                  | Purpose                                                         |
|----------|------------------------------------------|-----------------------------------------------------------------|
| `/`      | `file_server /var/www/piying`            | Marketing / explainer landing page for the game                 |
| `/play`  | `file_server` + SPA fallback             | Flutter Web client (built with `--base-href=/play/`)             |
| `/api/*` | `reverse_proxy 127.0.0.1:8080`           | Dart binary                                                     |

Caddy handler order: specific (`/api/*`, `/play/*`) before the root file_server. The Dart binary binds loopback only; Caddy is the only public surface.

---

## Identity Model

There are no users server-side. Only **bots**. A device can spawn many bots over time. Each bot is independent, immutable in its knowledge, and competes eternally.

This dissolves several problems we'd otherwise face: no accounts, no email, no passwords, no GDPR exit interviews; the multi-device case (player gets a new phone) becomes "publish a new bot from the new device — the old phone's bot keeps playing."

### Bot row

| Field               | Type        | Notes                                                            |
|---------------------|-------------|------------------------------------------------------------------|
| `id`                | uuid        | server-assigned                                                  |
| `device_id_hash`    | opaque      | **strictly server-side**, never in any public JSON               |
| `display_name`      | string      | user-chosen                                                      |
| `discriminator`     | 4 digits    | derived from `hash(device_id)`; same device+name → same #1234   |
| `game_type`         | string      | one game per bot: `go-13`, `othello`, `chess`, eventually `go-19` |
| `engine_data`       | blob        | full game log + per-ply raw board states; **immutable**          |
| `kernel_version`    | int         | which diffusion kernel the bot's index was computed against      |
| `game_count`        | int         | from `engine_data` — how many games the corpus represents        |
| `game_id_set`       | hash        | for reset detection (see below)                                  |
| `game_state_hash`   | hash        | for upload dedup                                                 |
| `created_at`        | ts          |                                                                  |
| `last_synced_at`    | ts          |                                                                  |
| `last_match_at`     | ts          |                                                                  |
| `rating`            | float       | Glicko-2                                                         |
| `rating_deviation`  | float       | Glicko-2 RD                                                      |
| `rating_volatility` | float       | Glicko-2 σ                                                       |
| `state`             | enum        | `active` / `settled` / `archived`                                |

**Display-name uniqueness is Discord-style:** `name#discriminator` must be unique, but the same `display_name` may repeat across devices. A device that picks a name another device has used gets a different discriminator (because their device_id hashes differ), so collisions are silent.

### Lifecycle

| State    | Initiates matches?            | Paired as opponent? | ELO updates? |
|----------|-------------------------------|---------------------|--------------|
| Active   | Yes (high pairing priority)   | Yes                 | Yes          |
| Settled  | Yes (low priority)            | Yes                 | Yes          |
| Archived | No                            | Yes                 | Yes          |

Transitions:

- **New publish → Active.** Min-game gate is a publish-time check (see Anti-spam); failing bots are never created server-side.
- **Active → Settled** when `RD ≤ ~150` AND `≥ 5 matches played` (Glicko-2 has converged).
- **Settled/Active → Archived** when the owning device publishes a newer bot AND the device's active-bot cap (5) is exceeded → oldest active bot is auto-archived (FIFO, age-based).
- **No transitions back from Archived.** Immutable knowledge means an archived bot cannot legitimately "improve."

**The load-bearing rule:** ratings evolve in *all* states, including Archived. Knowledge (`engine_data`) is frozen; the league's measurement of that knowledge is not. This kills the obvious abuse vector — "ride a hot streak then archive to lock in inflated rating" — because Glicko-2 regresses the inflated rating toward true level as the archived bot continues to be paired as an opponent. The "frozen in amber" identity is the *game history*, not the leaderboard number.

### Reset detection

When a publish arrives from a device that already has bots:

- Compare new bot's `game_id` set against the union of prior bots' `game_id` sets.
- `new ⊋ prior` → true superset (legitimate continuation); the new bot supersedes the previous active set.
- Otherwise → **divergent** (history reset, deleted games, etc.); published as a fresh active bot. Prior bots are not affected.

This handles "I wiped my local history" gracefully without privileging or punishing it.

---

## Auth

Anonymous device-token bearer auth. No passwords, no email, no recovery.

1. First sync from a device: server generates a 256-bit random token, stores `argon2id(token)` keyed by `device_id_hash`, returns the plaintext token to the client once.
2. Client persists the token in the platform secure keystore (iOS Keychain, Android Keystore).
3. All subsequent requests carry `Authorization: Bearer <token>`.
4. All bots from the same device share one token — the device owns its bot family.
5. **No rotation, no expiry for v1.** Add only if abuse appears.

**Trade-off:** keystore loss = bot family lost. v1 accepts this. A recovery-phrase UX is a deferred feature.

---

## Sync Protocol

The mobile app uploads a bot snapshot when the player taps **Publish** (manual; no auto-sync — see Publish UX below).

### Wire format

- JSON body, HTTP-compressed (`Content-Encoding: zstd` preferred, `gzip` fallback for older clients).
- Schema mirrors the local SQLite tables — same column shape, no parallel format to maintain.
- **Derived columns are not transmitted.** Diffused-image Int8 blobs, total_material, material_balance — all recomputable server-side from `(board, kernel_version)`. This is both bandwidth (3–5× saving) and a kernel-version-consistency guarantee.

### What's actually sent

Per game: `(game_id, started_at, ended_at, outcome, moves_to_end, player_area, clone_area)`
Per ply within a game: `(ply, side, board_bytes_base64, move_played)`

Plus a `device_token` in the header and a `display_name` in the body.

### Server side

1. Verify token (Argon2id match on `device_id_hash`).
2. Check rate limits (per device, per IP).
3. Check `game_state_hash` for dedup — if it matches an existing bot from this device, **silent replace**.
4. Run reset detection.
5. Compute diffused images from raw boards using the current kernel.
6. Insert one bot row + N game rows + M state rows in a single transaction.
7. Return `201 Created` with the new bot's `id` and current state.

Estimated wire size: 1000-game bot ≈ 5–20 MB raw → ~1–3 MB after zstd. Acceptable.

### Publish UX

- **Manual button**, not auto-sync. Lives in the post-game screen and Settings.
- Disabled when the min-game gate isn't met; surface progress (e.g. "Publish unlocks in 3 more games").
- **First Publish tap is the online consent.** Modal explaining what gets uploaded (anonymous bot data + game log; no PII), Confirm both consents and publishes. No separate Settings toggle. GDPR-defensible because no PII is collected; the dialog is the audit trail.

---

## Rating System

**Glicko-2**, not vanilla ELO. Reasons:

- RD (rating deviation) models pairing urgency directly — high RD = uncertain rating = high priority. Maps onto our "active vs settled" lifecycle naturally.
- RD grows with idleness → archived bots' ratings naturally re-prioritise themselves when stale.
- Volatility captures erratic performance; for immutable bots should converge low (a useful sanity check on the rating system itself).
- Lichess-proven; well-documented; one-page math.
- Implementation: ~150 LoC of pure Dart, zero dependencies.

| Parameter            | Initial value |
|----------------------|---------------|
| Rating               | 1500          |
| RD                   | 350           |
| Volatility           | 0.06          |
| System constant `τ`  | 0.5           |
| Rating period        | 1 day         |

Provisional ratings (Lichess-style "?" suffix) are derived from `RD > threshold`; no separate state needed.

---

## Match Scheduling

A continuous worker thread inside the Dart binary picks the highest-priority bot from a Glicko-2-driven queue, pairs it with a similar-RD opponent (±200 rating), runs the match using the same Dart engine the mobile app uses, updates ratings, repeats.

Throttle target: keep CPU under ~30% so HTTP request latency stays bounded. Configurable via env var.

**Server runs the same engine** — no second implementation, no drift between mobile and league play. This is a load-bearing benefit of pure-Dart-everywhere.

### Pairing strategy by pool size

| Pool size  | Strategy                                                                  |
|------------|---------------------------------------------------------------------------|
| ≤50 bots   | Effectively round-robin (everyone high-priority until they've played all) |
| 50–500     | Glicko-2 priority queue, ±200-rating opponent selection                   |
| 500+       | ELO-bucketed pools, weekly promotion/demotion windows                     |

### Compute envelope

Go-13 inference: ~1 ms per ply via case-based lookup. A typical match: ~200 plies = ~200 ms. On 1 OCPU at 30% throttle, that's roughly 5000 matches/day before saturation. Plenty for the foreseeable bot population.

### On-demand top-up

When a player opens the leaderboard and their newest bot has fewer than N matches, kick a small synchronous burst of pairings for that bot. Keeps leaderboard feel responsive at low pool sizes.

---

## Replay & Match Storage

Store **moves only**. Everything else (per-ply board state, captures, area at each ply, etc.) is derivable by replaying the move sequence through the engine. Server-side recompute is trivial (~10 ms for 200 moves) and avoids drift on engine updates.

### Schema

```
matches(
  id,            -- uuid
  white_bot,     -- fk → bots.id
  black_bot,     -- fk → bots.id
  game_type,
  outcome,       -- +1 white, -1 black, 0 draw
  white_area,    -- denormalised final score
  black_area,    -- denormalised final score
  played_at,
  rating_change_white,
  rating_change_black,
  engine_version
)
replays(
  match_id,      -- pk, fk → matches.id
  move_blob      -- compressed JSON int list
)
```

The split lets leaderboard queries hit `matches` without dragging blob storage along.

### Wire format

JSON: `{ "moves": [12, 34, ...], "outcome": 1, ... }`. zstd at the HTTP layer.

- Moves are **ints**, not coordinates. Coord rendering (e.g. "D4") happens client-side via the `rules.moveDescription` helper (deferred work from the `go-mobile-app` change finally has a real consumer). Optional `?format=coord` query param on the replay endpoint for server-side rendering when curl-debugging.
- Sizing: ~200 plies → 1–2 KB raw → ~500 B zstd. 10,000 matches ≈ 5 MB on disk. Trivial.

### Standards-format export

**Deferred but architecturally noted.** Each rules module gets an optional per-game serialiser slot: SGF for Go, PGN for Chess, etc. Useful for ecosystem interop (KaTrain, Sabaki, OGS, Lichess analysis). Not v1 work.

### Visibility

**All replays publicly browsable.** Public surface: `display_name#discriminator`, rating, game-type, replay (move list), outcome, area scores, `played_at`.

**Never public:** `device_id_hash`, device tokens, bot↔device grouping. A device's bot family stays anonymous unless the owner reveals it.

---

## Leaderboards

**Per-game-type, global.** One leaderboard per game type (`go-13`, `othello`, `chess`, eventually `go-19`). Each bot is bound to one game type at publish time; no cross-game-type ranking (avoids the rating-normalisation rabbit hole).

A device's bots may span multiple game types; a future "device summary" view aggregates across leaderboards.

---

## Anti-spam & Caps

| Knob                                  | Default               | Rationale                                                                                    |
|---------------------------------------|-----------------------|----------------------------------------------------------------------------------------------|
| Min games to publish                  | 10 per game-type      | Publish-time gate; bots failing this are never created                                       |
| Rate limit, bot creation per device   | 1 per 5 minutes       | Engagement-friendly; abuse is bounded by min-game gate + dedup + storage cap                  |
| Rate limit, bot creation per IP       | 10 per hour           | Catches device-id rotation abuse                                                              |
| `game_state_hash` dedup               | Silent replace        | Identical resubmits don't create new bots                                                    |
| Active bots per device                | 5                     | Oldest auto-archived FIFO when exceeded                                                       |
| All-time bots per device              | 50                    | Hard cap; overflow refused                                                                    |
| Max upload payload                    | 50 MB                 | ~5000 games of history                                                                       |
| Display-name moderation               | Static blocklist + report button | Multi-language blocklist at submit; manual moderation queue for reports                |

Quality-aware gates (`median game length > 30s`, `% resigned < 50%`, etc.) are not v1 — add only if abuse outpaces the structural limits above.

---

## Diffusion-Kernel Evolution

When the diffusion kernel for a game changes, the server **recomputes every existing bot's diffused-image index** using the new kernel. Single code path, no historical-kernel maintenance burden.

Honest trade-off: archived bots' move choices may shift slightly after a kernel revision (case-based similarity depends on the kernel). The "frozen knowledge" promise applies to the **game log**, not to the derived diffused-image index. Surface this in the UI when it happens — e.g. an "engine v1.2 retuned" indicator on bot profiles.

`kernel_version` on the bot row tracks the latest version the index was computed against. Kernel revisions are deliberate, batched, downtime-tolerant; ship them with a "what changed" note for users.

---

## API Surface

All paths are under `/api`. JSON in / JSON out. Errors are HTTP status + a small JSON `{ "error": "...", "code": "..." }` body.

### Auth

| Method | Path                | Body / params                                | Returns                                                            |
|--------|---------------------|----------------------------------------------|--------------------------------------------------------------------|
| POST   | `/api/devices`      | `{ "device_id": "<opaque>" }`                | `{ "token": "<256-bit hex>" }` — once; client persists it          |

`device_id` is generated client-side (random UUID, persisted in secure storage). The server only ever sees its hash. Token rotation is not supported.

### Bots

| Method | Path                                | Body / params                                                                   | Returns                                |
|--------|-------------------------------------|---------------------------------------------------------------------------------|----------------------------------------|
| POST   | `/api/bots`                         | `{ display_name, game_type, engine_data: { games: [...], states: [...] } }`     | Bot row (public fields only)           |
| GET    | `/api/bots/:id`                     |                                                                                 | Bot row (public fields only)           |
| GET    | `/api/bots/:id/matches?limit=&before=` |                                                                              | Page of match summaries                |

`POST /api/bots` requires the device token. The other two are public.

### Leaderboards

| Method | Path                                       | Returns                                                                |
|--------|--------------------------------------------|------------------------------------------------------------------------|
| GET    | `/api/leaderboards/:game_type?limit=&offset=` | Paged bot rows ordered by rating desc                              |

### Matches & replays

| Method | Path                                       | Returns                                                                |
|--------|--------------------------------------------|------------------------------------------------------------------------|
| GET    | `/api/matches/:id`                         | Match metadata (no replay blob)                                        |
| GET    | `/api/matches/:id/replay?format=int\|coord` | Replay move list                                                       |

### Reports & moderation

| Method | Path                                | Body                                            | Returns        |
|--------|-------------------------------------|-------------------------------------------------|----------------|
| POST   | `/api/reports`                      | `{ target_bot_id, reason }`                     | `202 Accepted` |

Admin moderation endpoints (review queue, name override, bot suspension) live under `/api/admin/*` behind a separate admin token — out of scope for v1.

### Health & metrics

| Method | Path           | Purpose                                                            |
|--------|----------------|--------------------------------------------------------------------|
| GET    | `/api/health`  | Liveness probe; returns `200 OK`                                   |
| GET    | `/api/metrics` | Process metrics for in-process scraping (no Prometheus dep for v1) |

---

## Logging & Observability

- **Structured JSON to stderr** → systemd-journald. Same pattern as Caddy.
- Levels TRACE/DEBUG/INFO/WARN/ERROR. Env var `PI_YING_LOG_LEVEL`, default INFO in prod, DEBUG in dev.
- Per-request fields: `method`, `path`, `status`, `latency_ms`, `bot_id?`, `device_id_hash?`, `ua`.
- In-process counters/gauges exposed at `/api/metrics`: match queue depth, matches/hour, ELO drift histogram, p50/p95/p99 latency per endpoint.
- v1 dashboard is `journalctl -u pi-ying -f`. Loki + Grafana is a later decision **and not on the 954 MiB box** — when added, it goes on a separate target.

---

## Storage Envelope

Each bot needs the player's full game log to make moves. A 1000-game player ≈ 5–20 MB of `engine_data`.

OCI Object Storage Always Free is 20 GB → roughly 1000–4000 bots before scale-out is needed. Mitigations if it becomes real:

- Cap `engine_data` size per bot (e.g. last 500 games).
- Pay for additional storage.
- Move blobs out of SQLite into Object Storage with row-level references.

None of these are needed for v1.

---

## Still Open

Minor / v1.1+ tuning, none of which block design or initial implementation:

- Per-bot match-cadence cap (e.g. max N matches per bot per day) for compute fairness.
- Match-worker throttle target as env var; per-bot rest periods after N matches.
- Display-name moderation cadence and abuse-response policy beyond "manual queue."
- Manual archive / restore by owner device (UX feature).
- ELO decay over multi-year timescales — bounded by "ratings always evolve" but worth revisiting at scale.
- Device recovery phrase for keystore loss.

---

## When Implementation Starts

Build with **one OpenSpec change per shippable feature**, not one big "backend" change. Suggested sequence:

1. `backend-bootstrap` — Dart Frog/Relic skeleton, systemd unit, Caddy reverse-proxy wiring, `/api/health`.
2. `backend-auth` — `POST /api/devices`, token storage, middleware.
3. `backend-publish` — `POST /api/bots`, schema, dedup, reset detection, kernel-version recompute pipeline.
4. `backend-leaderboard` — `GET /api/leaderboards/:game_type` + read-side `GET /api/bots/:id`.
5. `backend-league-worker` — Glicko-2, continuous pairing thread, `matches` + `replays` schema, rating periods.
6. `backend-replays` — `GET /api/matches/:id` + replay endpoint.
7. `backend-reports` — `POST /api/reports`, blocklist, moderation queue.
8. `web-frontend-skeleton` — Flutter Web client at `/play`, leaderboard view first.

Each change references this document for shared context.
