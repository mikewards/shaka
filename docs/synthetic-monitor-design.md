# Synthetic Monitor v2 — Design

**Status:** Proposed **v2** (revised after two adversarial reviews: codebase verification + process critique; design only, nothing implemented yet)
**Date:** July 2026
**Replaces:** `scripts/synthetic_probe.py` + `.github/workflows/synthetic-probe.yml` (the "Synthetic Probe" workflow)

## Background: why the old probe failed

The Synthetic Probe (added May 23, 2026, commit `e9d6343`) ran `scripts/synthetic_probe.py` every 30 minutes from GitHub Actions and turned red on *any* of 12 checks failing. As of early July 2026 it had failed **every one of the 208 retained runs** (back to Jun 11), emailing on each, for three reasons:

1. **Tide "staleness" false positive.** `/health/freshness` in `SpotRoutes.kt` hardcodes a 180-minute tide threshold, but the Jun 21–22 refactor (`f55365f`, `b8919d8`, `78604f9`) moved tide to a **precomputed full-year series** with a monthly horizon top-up. Tide cache timestamps are now ~10 days old *by design*; nobody updated the threshold.
2. **`hourly_swell_wind` BREACH.** `MonitoringService` marks any job below 99% success as BREACH. The job runs at ~95% (41/825 spots failing their Open-Meteo fetch), and because it runs daily, a single sub-99% run stays red for 24 hours.
3. **NOAA CoastWatch ERDDAP 403s.** The probe hit `coastwatch.noaa.gov` directly from GitHub's Azure runners, which NOAA appears to block/rate-limit. The backend (on Railway) has fallbacks and was unaffected — the check measured the wrong vantage point.

Root failure mode: **the probe duplicated business assumptions (thresholds, data-refresh models, upstream URLs) that the backend rewrote out from under it, and nothing forced the two to move together.** This design fixes that structurally, not just the individual checks.

## Current backend facts this design is grounded in

- **Job scheduling** lives in `shaka-api/src/main/kotlin/com/shaka/Application.kt` via `scheduleJob(name, initialDelayMs, intervalMs, maxRunMs, runImmediately)`. `maxRunMs` is a watchdog (default `intervalMs × 4`); **jobs report to `MonitoringService` only after they complete**, so a legal `lastRun` age can far exceed the interval:

  | Job (scheduled name) | Interval | Max run (watchdog) | Reports to MonitoringService as |
  |---|---|---|---|
  | `hourly_swell_wind_prefetch` | 24 h | 24 h | `hourly_swell_wind` |
  | `hourly_snapshot_tick` | 1 h | 5 min | (not reported — in-memory derive) |
  | `satellite_prefetch` | 6 h | 24 h | `satellite_prefetch` |
  | `user_spots_prefetch` | 3 h | 24 h | `user_spots_prefetch` |
  | `solunar_vessel_prefetch` | 12 h | 48 h (default) | `fishing_intel_prefetch` |
  | `buoy_readings` | 1 h | 4 h (default) | `buoy_readings` |
  | `tide_horizon_topup` | 30 d | 100 min | `tide_horizon_topup` |
  | `mpa_prefetch` | 7 d | 24 h | `mpa_prefetch` |
  | `tide_chart_cleanup` | 24 h | 96 h (default) | (not reported) |
  | `hourly_series_cleanup` | 24 h | 96 h (default) | (not reported) |
  | `weather_tile_pipeline` | 6 h | 24 h (default) | `weather_tile_pipeline` |
  | `fishing_intel_scrape` | 2 h | 8 h (default) | `fishing_intel_scrape` |

  Note the **scheduled-name vs reporting-name mismatches** (`hourly_swell_wind_prefetch` → `hourly_swell_wind`, `solunar_vessel_prefetch` → `fishing_intel_prefetch`) — an easy drift trap. Additional names report only from on-demand/admin paths, not the scheduler: `tide_chart_materialize`, `tide_chart_catchup`, `tide_year_backfill`, `tide_remaining_backfill`.
- **Refresh jobs are staleness-gated.** `satellite_prefetch` only refetches spots whose data is ≥ `SATELLITE_STALE_HOURS=12` old; `solunar_vessel_prefetch` gates on `VESSEL_STALE_HOURS=24` / `SOLUNAR_STALE_HOURS=12`; `mpa_prefetch` on `MPA_STALE_HOURS=168`. `prefetchHourlySwellWind` is ungated (fetches every spot each run). Consequence: **legitimate data age = eligibility gate + wait for next run + run duration** — e.g. vessel data lawfully reaches ~36 h+, far above any "cadence + margin" threshold.
- **Three divergent threshold sources already exist** and must be collapsed into one:
  - `DataPrefetchJobs.kt` companion object: `TIDE_STALE_HOURS=2`, `WEATHER_STALE_HOURS=4`, `SATELLITE_STALE_HOURS=12`, `MPA_STALE_HOURS=168`, `VESSEL_STALE_HOURS=24`, `SOLUNAR_STALE_HOURS=12`, plus tide horizon tuning (`HORIZON_TARGET_DAYS=365`, `HORIZON_REFRESH_DAYS=45`).
  - `SpotRoutes.kt` `/health/freshness` `staleThresholds` map (minutes): tide=180, swell/wind=480, sst/visibility/chlorophyll/gibs_satellite=1500, mpa=64800, vessel/solunar=1800.
  - The old probe's implicit expectations.
- **`/health/freshness` evaluates the *median* age per data type**, not the max. Medians pass with little headroom under the gated-refresh model, and a single failed job run can push the median across a tight threshold and back (flapping). Thresholds must be sized against the *lawful maximum* age, and freshness is a warn-tier signal, not a paging signal.
- **Tide `fetchedAt` in `spot_cache` can be months old by design** (full-year precompute) — it must never be used for tide freshness; only `spot_tide_series.generatedThrough` (horizon) is meaningful.
- **`/health/jobs`** is backed by `MonitoringService.latestRuns`, an in-memory `ConcurrentHashMap` — wiped on every deploy; jobs that haven't run since deploy are silently absent; BREACH = latest-run success rate < 0.99 (single global `THRESHOLD`).
- **`/health/detailed`** (`HealthService.kt`) already checks Open-Meteo, GIBS, NOAA, Copernicus **from Railway's vantage point** with a 5-minute cache. The probe should read this instead of hitting those upstreams itself.
- **Existing alerting plumbing (verified):** **Sentry is the one live alerting system** — backend SDK (`io.sentry:sentry` 8.16.0 + `sentry-logback`, initialized in `Application.kt` from `SENTRY_DSN`; `MonitoringService` sends job-breach events) and Flutter (`sentry_flutter`). **Better Stack is a log sink only**: `BETTERSTACK_SOURCE_URL`/`_TOKEN` exist as repo secrets and optional backend env vars, and `MonitoringService`/the surfline-benchmark workflow POST job-run log lines to it — no Better Stack uptime/heartbeat monitor has ever been configured. The old probe's `PROBE_HEARTBEAT_URL` was **dead code**: the secret was never created (`gh secret list` confirms), so it pinged nothing even on success — the "missed heartbeat = probe dead" channel described in its own comments never existed. The dead-man's switch therefore targets **Sentry Crons** (no new system) and must be proven before cutover (step 0).
- **Tide horizon bookkeeping:** `spot_tide_series` rows (`SpotDataCache.TideSeriesRow`) carry `generatedFrom` / `generatedThrough` / `generatedAt` / `status` per spot — remaining horizon is computable server-side.
- **Groq LLM integration** (`fishing_intel/ai/FishingIntelAiService.kt`): calls `api.groq.com` chat completions (`llama-3.3-70b-versatile`; OpenAI `gpt-4o-mini` fallback), gated by `FISHING_INTEL_AI_ENABLED` + `FISHING_INTEL_AI_API_KEY`. Two live uses: thread TL;DR/species analysis on the **`POST /v1/intel/ingest` HTTP path** (fed by the local BD Outdoors scraper — *not* the `fishing_intel_scrape` job; `analyzePost`/`shouldAnalyze` are dead code), and `generateRegionInsights` (the Reports screen's "West Coast Overview" card), pre-generated by `FishingIntelPrefetchJob` after every scrape (2 h cadence) into `fishing_intel_region_insights` keyed by local-date slot (`all_regions`, `slotKey`) and served from Postgres via `/regions/{id}/intel` → `keyInsights`. Failures are **silent**: 25 s timeout, `catch → null`, warn log only, nothing reported to `MonitoringService`; the app hides the card when `keyInsights` is empty. Calls cost money per token, so the monitor must never trigger LLM calls — it checks the cached artifact instead.
- **Fabricated-conditions fingerprint is dead.** The old probe checked wind ≠ `5.39957` kts (Open-Meteo's former hardcoded 10 km/h fallback). That fallback was removed from `OpenMeteoClient.kt` (returns `null` now; `ShakaScorer` treats null as neutral — "Jun 2026 lesson" comments throughout). The fingerprint can no longer be produced by current code and is dropped from the checks.
- **Real app user journeys** (`shaka-app/lib/data/api/shaka_api_client.dart`, base URL `https://shaka-production.up.railway.app/v1`): `/spots/search`, `/spots/{id}?date=`, `/spots/{id}/hourly`, `/spots/{id}/wind/live`, `/spots/{id}/tide?days=7`, `/spots/batch`, `/spots/all`, `/spots/search/name`, `/regions`, `/forecast/{id}`, `/reports/{region}`, user-spots CRUD with `X-Device-ID` header, `/health/detailed`; region/spot fishing intel via `/regions/{id}/intel` and `/spots/{id}/intel` (note: `hotSpecies`/`coldSpecies` are `@Deprecated` in `FishingIntelResponses.kt` — `speciesWithTrends` is current); GIBS tiles fetched **directly from the device** (`gibs_service.dart`). `SpotHourlyResponse` (`Models.kt`) currently has **no `generatedAt`** — it must be added for the probe's recency anchor.

---

## (a) Architecture: a two-layer monitor

**Principle: the backend self-assesses using thresholds it owns; the probe verifies real user journeys end-to-end and relays the backend's self-assessment. The probe contains no business-logic thresholds — with two deliberate exceptions (the probe-owned recency anchors, §Tier 1), which exist precisely so the backend cannot self-ratify its own breakage.**

### Layer 1 — self-describing backend (Kotlin, `shaka-api`)

#### 1. `MonitoringConfig` — single source of truth for thresholds

New file: `shaka-api/src/main/kotlin/com/shaka/monitoring/MonitoringConfig.kt`.

Contains, per **job**: name, expected interval, watchdog, eligibility gate, per-job breach thresholds; per **data type**: freshness rule *derived* from the owning job's spec.

```kotlin
object MonitoringConfig {
    data class JobSpec(
        val name: String,              // MonitoringService reporting name (NOT the scheduled name)
        val intervalMs: Long,          // drives scheduleJob AND missed-run detection
        val maxRunMs: Long,            // watchdog; also feeds missed-run + freshness math
        val staleGateHours: Long = 0,  // eligibility gate: data younger than this is skipped
        val degradedBelow: Double,     // success rate -> "degraded"
        val criticalBelow: Double,     // success rate -> "critical"
    )

    val jobs = listOf(
        JobSpec("hourly_swell_wind",      86_400_000,  86_400_000, 0,   degradedBelow = 0.99, criticalBelow = 0.50),
        JobSpec("satellite_prefetch",     21_600_000,  86_400_000, 12,  degradedBelow = 0.95, criticalBelow = 0.50),
        JobSpec("user_spots_prefetch",    10_800_000,  86_400_000, 4,   degradedBelow = 0.95, criticalBelow = 0.50),
        JobSpec("fishing_intel_prefetch", 43_200_000, 172_800_000, 12,  degradedBelow = 0.90, criticalBelow = 0.30),
        JobSpec("buoy_readings",           3_600_000,  14_400_000, 0,   degradedBelow = 0.90, criticalBelow = 0.30),
        JobSpec("tide_horizon_topup",  2_592_000_000,   6_000_000, 0,   degradedBelow = 0.95, criticalBelow = 0.50),
        JobSpec("mpa_prefetch",          604_800_000,  86_400_000, 168, degradedBelow = 0.90, criticalBelow = 0.30),
        JobSpec("weather_tile_pipeline",  21_600_000,  86_400_000, 0,   degradedBelow = 1.00, criticalBelow = 0.99),
        JobSpec("fishing_intel_scrape",    7_200_000,  28_800_000, 0,   degradedBelow = 0.80, criticalBelow = 0.30),
    )

    // Registry boundary (documented allowlist for the registry unit test, §c):
    //  - Scheduled but intentionally unmonitored (no reportRun): hourly_snapshot_tick,
    //    tide_chart_cleanup, hourly_series_cleanup.
    //  - Report to MonitoringService but only from on-demand/admin paths, not the
    //    scheduler: tide_chart_materialize, tide_chart_catchup, tide_year_backfill,
    //    tide_remaining_backfill.
    val registryExempt = setOf(
        "hourly_snapshot_tick", "tide_chart_cleanup", "hourly_series_cleanup",
        "tide_chart_materialize", "tide_chart_catchup", "tide_year_backfill",
        "tide_remaining_backfill",
    )

    // Freshness threshold = lawful maximum age, NOT cadence + margin:
    //   staleGate + interval (wait for next eligible run) + maxRun (report only
    //   on completion) + 1h margin. Deliberately conservative: freshness is a
    //   warn-tier signal; the tight user-facing bound is the probe's recency
    //   anchors (Tier 1). Evaluated against /health/freshness MEDIAN age, so a
    //   lawful-max threshold keeps headroom and avoids single-bad-run flapping.
    fun freshnessThresholdHours(type: String): Long = ...

    // Tide is NOT age-based (spot_cache tide fetchedAt is months old by design).
    // Horizon semantics from spot_tide_series.generatedThrough:
    const val TIDE_HORIZON_DEGRADED_DAYS = 30   // median remaining horizon
    const val TIDE_HORIZON_CRITICAL_DAYS = 7
    const val TIDE_COVERAGE_MIN = 0.95          // fraction of spots with a series

    // AI region insights (Groq): generation is attempted after every
    // fishing_intel_scrape (2h). Degraded when today's local-date slot in
    // fishing_intel_region_insights is still empty after this many hours
    // into the day (>= 4 failed generation attempts). Never critical —
    // the app hides the card gracefully.
    const val AI_INSIGHTS_SLOT_GRACE_HOURS = 8

    // Missed-run detection (accounts for report-on-completion):
    //   degraded when lastRunAge > intervalMs + maxRunMs + 1h
    //   critical when lastRunAge > 2 * (intervalMs + maxRunMs)
    // Deploy grace: suppress "missed" until initialDelayMs + intervalMs + maxRunMs
    // after process start.
}
```

Concrete freshness values this yields (`gate + interval + maxRun + 1 h`, replacing the `SpotRoutes.kt` hardcoded map):

| Type | Owning job | Gate + interval + maxRun | Stale threshold (median age) |
|---|---|---|---|
| swell / wind | `hourly_swell_wind_prefetch` | 0 + 24 h + 24 h | 49 h (was 8 h) |
| sst / visibility / chlorophyll / gibs_satellite | `satellite_prefetch` | 12 h + 6 h + 24 h | 43 h (was 25 h) |
| vessel | `solunar_vessel_prefetch` | 24 h + 12 h + 48 h | 85 h (was 30 h — 25 h would false-positive at the lawful ~36 h+) |
| solunar | `solunar_vessel_prefetch` | 12 h + 12 h + 48 h | 73 h (was 30 h) |
| mpa | `mpa_prefetch` | 168 h + 168 h + 24 h | 361 h ≈ 15 d (was 45 d) |
| tide | `tide_horizon_topup` | — | **horizon-based, never age-based** (see above) |

These are deliberately loose: they can only fire when something is truly wrong, which is what a warn-tier signal is for. The *user-facing* bound on data recency is enforced by the probe's Tier-1 anchors, which do not depend on this config.

`Application.kt`'s `scheduleJob` calls take their `intervalMs`/`maxRunMs` **from** `MonitoringConfig.jobs` (mapped through the scheduled-name → reporting-name table), so config and reality cannot diverge.

#### 2. Fix `/health/jobs` (in `SpotRoutes.kt` + `MonitoringService.kt`)

- Add `expectedIntervalMs`, `maxRunMs`, and `lastRunAgeMs` per job so a **silently-dead job** is detectable (currently a job that never ran since deploy is just absent from the response).
- Persist latest runs to a small Postgres table (`job_runs_latest`: job_name PK, finished_at, total, succeeded, failed, duration_ms) so a redeploy doesn't blank the endpoint. In-memory map stays as a read-through cache.
- Replace the single global 0.99 BREACH threshold with per-job `degradedBelow`/`criticalBelow` from `MonitoringConfig`. `hourly_swell_wind` at 95% becomes `degraded` (visible, non-paging); `critical` is reserved for success < 50% or a missed run.
- Missed-run detection uses `interval + maxRun + margin` (NOT `2× interval` — `satellite_prefetch` has a 6 h interval but may lawfully report only after a 24 h run, so its lastRun age can legally reach ~30 h). Deploy grace = `initialDelay + interval + maxRun` after process start.

#### 3. New `/health/summary` endpoint

One endpoint aggregating everything into a machine-readable self-assessment (use a `@Serializable data class`, never `Map<String, Any>` — see `.cursor/rules/serialization.mdc`):

```json
{
  "severity": "ok | degraded | critical",
  "checkedAt": "2026-07-02T18:00:00Z",
  "causes": [
    {
      "check": "job:hourly_swell_wind",
      "severity": "degraded",
      "observed": "successRate=0.9503 (784/825)",
      "threshold": "degradedBelow=0.99"
    },
    {
      "check": "tide_horizon",
      "severity": "ok",
      "observed": "medianRemainingDays=312, coverage=0.957",
      "threshold": "degraded<30d, critical<7d, coverage>=0.95"
    }
  ]
}
```

Inputs: DB ping, freshness (via `MonitoringConfig`), job statuses + missed-run detection, tide horizon (computed from `spot_tide_series.generatedThrough`), AI region insights (`check: "ai_region_insights"` — `degraded` when `fishing_intel_region_insights` has no non-empty row for `("all_regions", today's slotKey)` and local time is past `AI_INSIGHTS_SLOT_GRACE_HOURS`; catches expired Groq keys, model deprecation, or a disabled flag **without spending tokens**; "no reports scraped in the past week" counts as ok, not degraded), and the existing `/health/detailed` upstream statuses (mapped to at most `degraded` — upstream problems the backend already degrades around are never `critical` here). The severity aggregation logic is a pure function → unit-tested in `shaka-api/src/test/`.

**Local/CI mode:** a `DISABLE_SCHEDULED_JOBS=true` env var (used by the CI contract job, §c) skips all `scheduleJob` registrations; when set, `/health/summary` reports job/freshness causes as `ok (schedulers disabled)` so T8 is assertable in CI without `weather_tile_pipeline` (30 s initial delay, script at `/app/scripts/weather_pipeline.py` that doesn't exist locally) or missed-run detection poisoning the severity.

### Layer 2 — the probe (Python, GitHub Actions)

Location: `monitoring/probe.py` (new directory; delete `scripts/synthetic_probe.py`). Runs from `.github/workflows/synthetic-probe.yml` on `cron: '*/30 * * * *'` (GitHub throttles this to roughly hourly in practice — acceptable) plus `workflow_dispatch`.

Why keep GitHub Actions: free, zero infra, already wired; hosted uptime monitors cannot do multi-step journey assertions; the Sentry Cron check-in (below) covers "the probe itself stopped running". The one caveat — Azure-runner IPs being blocked by upstreams — is addressed by *not probing upstreams from the runner* (Tier 2 reads the backend's `/health/detailed` instead) and by **vantage-blocked suppression** on the few remaining outside-in checks.

#### Tier 1 — user-impacting, can page

Only checks that mirror what `shaka_api_client.dart` actually does. All against `https://shaka-production.up.railway.app/v1`, latency budget 10 s each:

| # | Check | Assertions |
|---|---|---|
| T1 | API up | `GET /health` → 200, `db == "ok"` |
| T2 | Spot detail | `GET /spots/cali-la-jolla-cove?date={today}` → 200, has `conditions`, latency < 10 s. (The old `5.39957` fabricated-wind fingerprint is dropped — the fallback that produced it was removed from `OpenMeteoClient`; current failure mode is honest nulls, covered by the recency anchor below.) |
| T3 | Search | `GET /spots/search?lat=33.5&lon=-117.8&date={today}&radius=50` → 200, `spots` non-empty |
| T4 | Hourly series | `GET /spots/cali-la-jolla-cove/hourly` → 200, contains **today and tomorrow** (spot-local dates) with ≥ 20 hourly points each, **and `generatedAt` < 30 h old** — see "recency anchors" below |
| T5 | Tide range | `GET /spots/cali-la-jolla-cove/tide?days=7` → 200, 7 day-curves present (doubles as the tide anchor: serving 7 days requires ≥ 7 days of remaining horizon, independent of backend thresholds) |
| T6 | User spots | `GET /user-spots` with `X-Device-ID: synthetic-probe` → 200 |
| T7 | Region intel | `GET /regions/san_diego/intel?since=72h&tzOffset=-8` → 200, **key-presence only**: `speciesWithTrends` key exists (`hotSpecies` is deprecated). Deliberately NOT non-empty — a sportfishingreport scrape outage must not page. Data quality demoted to Tier 2 (W7) |
| T8 | Backend self-assessment | `GET /health/summary` → 200 and `severity != "critical"` |

**Probe-owned recency anchors (backend-distrusting, by design).** Backend-owned thresholds have a self-ratification hole: a PR that wrongly changes a job interval auto-loosens the derived freshness threshold, and `/health/summary` stays green. Two anchors close it:

- **T4's `generatedAt < 30 h`**: requires adding `generatedAt` (the hourly series' `fetchedAt`, already tracked in `SpotDataCache.HourlySeries`) to `SpotHourlyResponse` in `Models.kt`. The 30 h constant lives **in the probe**, is *not* read from `MonitoringConfig`, and is derived from physics/UX, not job cadence: a swell/wind forecast regenerated daily that is > 30 h old is materially wrong for users regardless of what any config says.
- **T5's 7 day-curves**: an implicit horizon floor no backend threshold change can relax.

If a legitimate architecture change ever breaks an anchor (e.g. hourly fetch moves to a 3-day cadence), the probe *should* go red — that is the forcing function to consciously revisit the anchor, which is the point.

#### Tier 2 — drift, warn-only (never fails the workflow)

| # | Check | Source |
|---|---|---|
| W1 | Backend `severity == "degraded"` with its `causes` | `/health/summary` (relays freshness softness, job breaches, tide-horizon warnings, AI-insights staleness — thresholds all backend-owned) |
| W2 | Upstream reachability (Open-Meteo, NOAA/ERDDAP, Copernicus, GIBS) | **read from `/health/detailed`** — Railway's vantage point, not Azure's |
| W3 | GIBS tile fetch from the runner | direct: the app hits GIBS from devices, so an outside-in fetch is meaningful (`OCI_PACE_Chlorophyll_a` tile for `today-2d`). Vantage-blocked suppression applies (below): 403/429 → suppressed; 404 → real drift (layer deprecated) |
| W4 | Copernicus WMTS layer rotation | direct GetCapabilities content check for `cmems_obs-oc_glo_bgc-transp_nrt_l3-multi-4km_P1D_202311`. Content asserted **only on HTTP 200**; 403/429/timeout → vantage-blocked. *Deferrable (see minimal subset)* |
| W5 | sportfishingreport.com HTML structure | direct: `Dock Totals` count ≥ 5, `/landings/` links present. Same vantage-blocked rule. *Deferrable — scrape failures already surface via the `fishing_intel_scrape` job status in W1* |
| W6 | Tide microservice | `GET https://lavish-radiance-production.up.railway.app/health`. `status == "ok"` expected; a 200 with `status == "loading"` (single warm instance cold-starting) is a warn-tier observation, never incident material |
| W7 | Intel data quality (incl. AI insights) | reuse T7's `/regions/san_diego/intel` response: `speciesWithTrends` non-empty and `keyInsights` non-empty. Zero extra requests and **never triggers an LLM call** (insights are read from Postgres). Backed by the backend-owned `ai_region_insights` cause in `/health/summary` (W1); this outside-in assertion additionally catches serving-path regressions |

**Vantage-blocked suppression (W3–W5):** a 403/429 or connect timeout from an Azure runner against a bot-hostile upstream is recorded in the status issue as `vantage-blocked (suppressed)` — a distinct state that never counts toward warning streaks. Only content-level failures on successful responses (and 404s where the resource is claimed to exist) count as drift. Rationale: a dashboard that is yellow from day one re-trains the ignore reflex that killed the old probe; the ERDDAP 403 saga must not be reproduced one tier down.

#### Grace policy

Lives in a small config block at the top of `monitoring/probe.py` (probe-mechanics plus the two anchors — nothing else):

- Tier 1 pages after **2 consecutive** failing runs (~1 h at effective cadence), **except** connection-refused / `db: unreachable`, which pages on the first run.
- Recovery requires **3 consecutive** green runs (hysteresis symmetric with onset — flapping must not cycle onset/recovery notifications).
- Tier 2 surfaces in the status issue after **3 consecutive** failing runs; never affects exit code.
- Latency budget 10 s; per-check retry once (5 s backoff) within a run to absorb blips.

---

## (b) Alerting: state transitions, not run conclusions

The old probe emailed hourly because GitHub notifies on every failed run and the probe's exit code *was* the alert. Decouple them:

1. **Pinned "Production monitor status" GitHub issue**, managed by the probe (workflow permission `issues: write`, calls via `gh` CLI). The issue body is the dashboard: current Tier-1/Tier-2 state, first-seen timestamps, consecutive-failure counters, vantage-suppressed observations, last-checked time. Labels encode state (`monitor:ok` / `monitor:warning` / `monitor:critical`) **for state storage only — GitHub does not send notifications on relabel**, so labels are never relied on to alert anyone. The probe finds the issue by the `monitor-status` label, creates it if missing.
2. **Previous state is read from that issue** (labels + a machine-readable HTML comment block in the body) at the start of each run. No artifacts/cache plumbing; survives runner ephemerality; human-visible.
3. **Exit-code policy = notification policy:**
   - New critical incident (after onset grace): update issue, **exit 1** → exactly one failure email + one red run marking incident start.
   - Ongoing critical: **body-edit** the issue (duration, latest evidence), **exit 0**. Never comment for routine updates — **issue comments email all participants and would recreate hourly spam**.
   - Bounded re-escalation: post a comment (deliberately emailing) at **72 h** and again at **7 d** of continuous critical ("still down, day 3"), so a long incident can't fall silent after its single onset email.
   - Recovery (after 3 consecutive green runs): comment "recovered after Xh Ym" and close the incident section — the close/comment notification is the deliberate recovery email. Relabel `monitor:ok`.
   - Warnings only: body-edit, **exit 0**.
4. **Human-interference rules (state machine must survive people):** if the status issue is missing, closed, or its state block is unparsable → state = `unknown`: recreate/repair the issue, **never page from `unknown`** — normal onset grace must re-accumulate first. If multiple open `monitor-status` issues exist → use the newest, close the rest.
5. **Dead-man's switch — Sentry Cron check-in (no new system):** every alert above originates *from* the probe, so none of them can fire when the probe itself is dead — and the probe can die silently: GitHub **auto-disables scheduled workflows after 60 days without repo activity** (a real risk if development pauses), the workflow file can be broken/renamed, `pip`/runner setup can start failing, or Actions can be disabled repo-wide. Cover this with **Sentry Cron Monitoring**, since Sentry is already the live alerting channel (backend SDK + job-breach events): the probe sends a check-in at the end of **every completed run, pass or fail** — a single HTTP GET to `https://sentry.io/api/0/organizations/{org}/monitors/shaka-synthetic-probe/checkins/latest/` -style ping URL (`SENTRY_CRON_CHECKIN_URL` secret; no SDK needed), with the monitor's schedule declared as interval ≈ 1 h, grace ≈ 90 min (probe cron is `*/30` but GitHub throttles to ~hourly). Sentry alerts on a **missed check-in** via a normal Sentry alert rule routed to email. Caveats: check-ins draw from the Sentry plan's cron-monitor quota (free tier includes one active monitor — exactly what's needed), and the alert rule must be explicitly created and pointed at the owner's email. Pass/fail status in the check-in is a bonus (`?status=error` on red runs) but the paging semantics stay with the GitHub issue — Sentry's job here is only "the probe stopped running". Rejected alternatives: a Better Stack heartbeat monitor (would be a **new** system — Better Stack today is only an optional log sink, and the old probe's `PROBE_HEARTBEAT_URL` secret never existed); a second watchdog GitHub workflow (same failure domain — whatever disables one scheduled workflow disables both); backend-side "no probe traffic recently" detection (the backend has no email path of its own, and a backend outage would mask a probe outage). Must be **proven before cutover** (implementation step 0) and re-proven periodically (below).
6. **Alert-path self-test:** `workflow_dispatch` input `force_notify: boolean` exercises the full paging path (fake critical → issue update → exit 1 → recovery). Run it **quarterly** (calendar reminder or a scheduled reminder issue) so the channel doesn't decay untested; the missed-check-in proof from step 0 is repeated at the same cadence by skipping one check-in (e.g. temporarily disabling the workflow for one cycle).

Result: an incident produces one email at onset, bounded reminders at 72 h / 7 d, and one at recovery — instead of 300+ over two weeks.

---

## (c) Sync-with-code strategy

Evaluated against the actual failure mode (the Jun 21–22 tide/hourly-weather refactor silently invalidated probe assumptions):

1. **Backend-owned thresholds (adopt — highest value).** All thresholds live in `MonitoringConfig.kt`, co-located with the `scheduleJob` calls that read their intervals from it. The person changing a job cadence is staring at the dependent threshold in the same diff. The probe reads `severity`, never thresholds — with the two probe-owned anchors (§a) as the deliberate, documented exception that prevents the backend from self-ratifying a bad change.

2. **Registry unit test (adopt — converts the convention into a check).** A `shaka-api` unit test asserts that **every job name passed to `scheduleJob` and every name reported to `MonitoringService.reportRun`/`captureItemFailure` has a `JobSpec` in `MonitoringConfig` or is in the documented `registryExempt` allowlist** (scheduled-but-unmonitored: `hourly_snapshot_tick`, cleanups; on-demand/admin reporters: `tide_chart_materialize`, `tide_chart_catchup`, `tide_year_backfill`, `tide_remaining_backfill`). The scheduled-name → reporting-name mismatches (`solunar_vessel_prefetch` → `fishing_intel_prefetch`) are exactly the trap this catches: add a job or rename a reporting name without touching the registry and the build fails. Implementation: the scheduled-name mapping lives beside `jobs` in `MonitoringConfig`, and `scheduleJob`/`reportRun` route through it (or the test scans call sites).

3. **CI contract test (adopt — the enforcement teeth, made non-vacuous).** New `probe-contract` job in `.github/workflows/ci.yml`:
   - **Path-filter it** to `shaka-api/**` and `monitoring/**` (note: `ci.yml`'s `pull_request:` trigger currently has **no** `paths` filter — the new job must add its own filter, e.g. via a `paths-filter` step or job-level conditions, so app-only PRs don't boot the API).
   - Start Postgres from the repo's `docker-compose.yml`; boot the API with **`DISABLE_SCHEDULED_JOBS=true`** — mandatory, for two verified reasons: `hourly_swell_wind_prefetch` (`initialDelay` 120 s, `runImmediately`) would start fetching 789 spots from Open-Meteo *out of CI* if the API lives past 2 minutes, and `weather_tile_pipeline` (30 s delay, script path `/app/scripts/weather_pipeline.py` that doesn't exist locally) would report a failed run and poison `/health/summary` severity, breaking the T8 assertion.
   - **Load a minimal seed fixture first** (`monitoring/fixtures/seed.sql`: one spot — `cali-la-jolla-cove` — with a `spot_cache` conditions row, a 2-day hourly swell/wind series, a `spot_tide_series` row + 7 days of tide curves, and one `fishing_intel_region_insights` row). Without it the test is **vacuous**: against an empty DB the tide/hourly/region-intel endpoints return 404 and search returns `[]`, so no shape assertion ever executes and the job degenerates to "routes are registered" — it would **not** have caught the June tide refactor. With the fixture, every Tier-1 journey exercises a populated response.
   - Run `python3 monitoring/probe.py --local --base-url http://localhost:8080/v1 --skip-external` — asserts every Tier-1 endpoint responds with the shapes in `monitoring/journeys.json` **against seeded data**, and `/health/summary` parses with job causes reading `ok (schedulers disabled)`. Production-only data-quality assertions (recency anchors, non-empty search beyond the seeded spot) are relaxed in local mode; shape, existence, and seeded-journey correctness are enforced.
   - Effect: a refactor like `f55365f` (drop tide jobs) or `06fad1d` (new hourly endpoint) that breaks a probe assumption fails **the PR**, not production monitoring two weeks later.
   - Shared expectations live in one file, `monitoring/journeys.json` (endpoint, params, required response fields per journey), consumed by the probe in both CI and production modes — one place to update when a journey changes.

4. **Cursor rule (adopt — catches semantic changes CI can't).** New `.cursor/rules/monitoring.mdc` with globs on `shaka-api/src/main/kotlin/com/shaka/Application.kt`, `service/DataPrefetchJobs.kt`, `monitoring/**.kt`, `api/routes/SpotRoutes.kt`, and `monitoring/**`. Content: *"If you add/remove/rename a scheduled job, change a job cadence, change how a data type is refreshed (e.g. age-based → horizon-based), or change a health endpoint's shape: update `MonitoringConfig.kt`, `monitoring/journeys.json`, and `monitoring/probe.py` in the same change, and say so in the commit message. If a change legitimately violates a probe recency anchor, update the anchor consciously in the same PR."* The registry unit test (#2) mechanically enforces the job-name clause; the rule covers what tests can't (threshold semantics, anchor intent). This repo already encodes hard-won lessons as rules (`serialization.mdc` exists because of three production crashes); with a single committer working heavily via agents, an agent-facing rule outperforms review-process gates.

5. **CODEOWNERS (skip).** Single-committer repo; pure ceremony here.

6. **Self-describing health endpoints (adopt — part of #1).** `/health/summary` *is* this mechanism: the backend exposes its own expectations and assessment; the probe verifies the self-assessment plus true end-to-end journeys plus the two anchors it deliberately refuses to take the backend's word on.

**Recommended combination: 1 + 2 + 3 + 4.** #2/#3 are the mechanical guarantees; #1 minimizes what can ever drift; #4 catches intent-level changes.

---

## (d) Implementation order

Each step independently shippable:

0. **Prove the dead-man's switch.** Create the Sentry Cron monitor (`shaka-synthetic-probe`, interval ~1 h, grace ~90 min) in the existing Sentry org, add an alert rule for missed check-ins routed to the owner's email, store the check-in URL as the `SENTRY_CRON_CHECKIN_URL` repo secret, send a few check-ins manually (`curl`), then **deliberately miss one and confirm the alert email actually arrives**. The old probe's `PROBE_HEARTBEAT_URL` was dead code — the secret never existed, so the "probe stopped running" channel has literally never worked; nothing else in this design is trustworthy until this is proven. Repeat quarterly alongside the `force_notify` self-test.
1. **Fix the real `hourly_swell_wind` issue** — 41/825 spots fail their Open-Meteo fetch every run; check Sentry (fingerprint `job_breach:hourly_swell_wind`) or `railway logs` for the dominant error class, then fix or exclude those spots. **Moved from last to first: the monitor must be born green.** If it launches showing `degraded`, "degraded is normal" gets normalized in week one and the ignore reflex that killed v1 is re-trained immediately.
2. **`shaka-api`: `MonitoringConfig` + health refactor** (everything else reads from it)
   - New `monitoring/MonitoringConfig.kt` (job registry incl. `mpa_prefetch`, `maxRunMs`, `staleGateHours`, `registryExempt` allowlist; lawful-max freshness derivation; tide-horizon thresholds; AI-insights slot check; corrected missed-run policy).
   - `Application.kt`: `scheduleJob` intervals/watchdogs driven by the registry; `DISABLE_SCHEDULED_JOBS` env flag.
   - `SpotRoutes.kt`: `/health/freshness` reads `MonitoringConfig` (fixes the tide false positive); `/health/jobs` gains `expectedIntervalMs`/`maxRunMs`/`lastRunAgeMs`/deploy grace; add `/health/summary` (incl. `ai_region_insights` and schedulers-disabled behavior).
   - `Models.kt` + `SpotService.getSpotHourly`: expose `generatedAt` on `SpotHourlyResponse` (from `HourlySeries.fetchedAt`) for the probe anchor.
   - `MonitoringService.kt`: persist latest runs to Postgres (`job_runs_latest`); per-job thresholds.
   - Unit tests: severity aggregation + the **registry test** (every scheduled/reported job name ∈ registry ∪ allowlist).
3. **`monitoring/journeys.json` + `monitoring/fixtures/seed.sql`** — endpoint/shape contract for the Tier-1 journeys and the seed data that makes CI assertions non-vacuous.
4. **`monitoring/probe.py`** (+ `monitoring/README.md`; delete `scripts/synthetic_probe.py`) — tiers, recency anchors, grace/hysteresis counters, vantage-blocked suppression, status-issue state machine (incl. `unknown` state and duplicate-issue handling), `--local --skip-external` mode, Sentry Cron check-in on every run.
5. **`.github/workflows/synthetic-probe.yml`** — point at the new probe; add `permissions: issues: write`, a `concurrency` group, the `force_notify` dispatch input, and the `SENTRY_CRON_CHECKIN_URL` secret in the probe step's env (replacing the never-configured `PROBE_HEARTBEAT_URL`).
6. **`.github/workflows/ci.yml`** — add the `probe-contract` job (path-filtered; docker-compose Postgres → seed fixture → boot API with `DISABLE_SCHEDULED_JOBS=true` → probe in local mode).
7. **`.cursor/rules/monitoring.mdc`** — the sync convention (incl. the anchor-update clause).

Dependency note: Tier-1 check T8 and the T4 `generatedAt` anchor require step 2 deployed; ship the probe with both behind flags until the backend is live in production.

### Minimal subset (solo-maintainer scope)

If implementing incrementally, the load-bearing core is: **step 0 (Sentry Cron missed-check-in proof), step 1 (born green), `MonitoringConfig` + `/health/summary`, probe checks T1–T5 + T8, the state-transition status issue with hysteresis/body-edit/re-escalation rules, and the check-in on every run.** Deferrable without losing the design's value: W4/W5 (bot-hostile outside-in drift checks), the AI-insights checks (`ai_region_insights` + W7), T6/T7, and the quarterly self-test automation (do it manually from a calendar reminder).
