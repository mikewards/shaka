# Synthetic Monitor

Production monitoring for the Shaka backend. Full design + rationale:
[`docs/synthetic-monitor-design.md`](../docs/synthetic-monitor-design.md).

## Pieces

| File | Purpose |
|---|---|
| `probe.py` | The monitor. Tier-1 user journeys (can page) + Tier-2 drift (warn-only), state-transition alerting via the pinned `monitor-status` GitHub issue, Sentry Cron check-in every run. |
| `journeys.json` | The endpoint/shape contract, shared by production runs and the CI contract job. **The one place to update when a user journey changes.** |
| `fixtures/seed.sql` | Seeds one reference spot so the CI contract test asserts against populated responses (empty-DB assertions are vacuous). |

Backend counterpart: `shaka-api/.../monitoring/MonitoringConfig.kt` (single
source of truth for job cadences + thresholds) and `GET /v1/health/summary`
(the backend's machine-readable self-assessment, which the probe relays).

## Alerting policy (why you don't get hourly emails)

- One **workflow-failure email** when a *new* critical incident starts (after
  2 consecutive failing runs; DB-down pages immediately).
- Ongoing incidents are **body-edits** of the status issue (no notifications);
  deliberate re-escalation comments at **72h** and **7d**.
- Recovery closes the loop with one comment after **3 consecutive green runs**.
- Tier-2 warnings only ever touch the issue body (after 3 consecutive runs).
- 403/429/timeouts from bot-hostile upstreams against GitHub's Azure runners
  are recorded as `vantage-blocked (suppressed)` and never count as failures.

## Dead-man's switch

`SENTRY_CRON_CHECKIN_URL` (repo secret) is pinged at the end of **every** run,
pass or fail. The Sentry Cron monitor (`shaka-synthetic-probe`, ~1h interval,
90min grace) emails when a check-in is missed — covering "the probe itself
stopped running" (GitHub disables cron workflows after 60 days of repo
inactivity, broken workflow file, Actions outage). Prove it quarterly by
skipping one run and confirming the email arrives.

## Feature flags (until the backend health refactor is deployed)

| Env var | Enables | Requires deployed |
|---|---|---|
| `PROBE_ENABLE_T8` | T8/W1: `/health/summary` self-assessment relay | `/health/summary` endpoint |
| `PROBE_ENABLE_T4_ANCHOR` | T4 recency anchor (`generatedAt` < 30h) | `generatedAt` on `SpotHourlyResponse` |

Set both to `true` in the workflow env after the next backend deploy.

## Running locally

```bash
# Against production, read-only, no GitHub writes:
python3 monitoring/probe.py --dry-run

# Full CI contract mode (what .github/workflows/ci.yml runs):
docker compose up -d db
psql postgresql://shaka:shaka@localhost:5432/shaka -f monitoring/fixtures/seed.sql
(cd shaka-api && DATABASE_URL=postgresql://shaka:shaka@localhost:5432/shaka \
    DISABLE_SCHEDULED_JOBS=true ./gradlew run &)
# wait for http://localhost:8080/v1/health, then:
python3 monitoring/probe.py --local --base-url http://localhost:8080/v1

# Test the paging path end-to-end (creates a synthetic incident + recovery):
gh workflow run synthetic-monitor.yml -f force_notify=true
```
