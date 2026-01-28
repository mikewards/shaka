# Shaka - Agent Context

Paste this into a new agent when starting work on this project:

---

This is the Shaka spearfishing app - a Flutter mobile app + Kotlin backend that ranks dive spots by weather, ocean conditions, and fish patterns.

GitHub: https://github.com/wardmic4/shaka

## Current State (60-70% complete)

Working:
- API routes and scoring engine
- 500+ spots in-memory database
- Flutter app with full UI flow (home, results, detail screens)
- Weather integration via Open-Meteo

Incomplete:
- Spot database has 500 spots (target: 10,000+)
- PostgreSQL/PostGIS not connected (in-memory only)
- Community data (Reddit, forums) stubbed out
- Forecast in detail view returns empty
- GitHub Actions CI blocked by token scope

## Phase 1: Fix GitHub Token and CI

Token needs `workflow` scope to push `.github/workflows/build.yml` (file exists locally, just couldn't push).

1. Go to https://github.com/settings/tokens
2. Edit token, add `workflow` scope
3. Push: `git add .github && git commit -m "Add CI workflow" && git push`

## Phase 2: Expand Spot Database (500 -> 10,000+)

File: `shaka-api/src/main/kotlin/com/shaka/data/client/SpotDatabase.kt`

Priority Regions:
- Hawaii: ~50 now, need 500+
- Caribbean/Bahamas: ~30 now, need 300+
- Mediterranean (Italy, France, Spain, Greece, Croatia): ~20 now, need 500+
- Australia/New Zealand: Missing, need 300+
- French Polynesia/South Pacific: Need 200+
- Indonesia/Philippines: Need 200+
- Mexico (Pacific + Caribbean): Need 200+
- Japan: Need 100+
- South Africa/Mozambique: Need 100+
- Brazil: Need 100+
- US Coasts (Florida, California): Need 500+

Approach: Scrape/aggregate from spearfishing forums and dive site databases, cross-reference with marine charts, validate coordinates.

## Phase 3: Connect PostgreSQL + PostGIS

Files:
- `db/init.sql` - Schema ready with spatial queries
- `docker-compose.yml` - PostGIS container ready
- `shaka-api/build.gradle.kts` - Dependencies added (PostgreSQL, Exposed ORM)

Tasks:
1. Create `DatabaseFactory.kt` for connection management
2. Create `SpotRepository.kt` using Exposed ORM
3. Migrate spots from `SpotDatabase.kt` to SQL
4. Use `ST_DWithin` for geo queries (function already in init.sql)

## Phase 4: Complete TODO Items

File: `shaka-api/src/main/kotlin/com/shaka/service/SpotService.kt`

```
Line 41:  recentSightings = 3 // TODO: Get from community data
Line 124: forecast = emptyList() // TODO: Generate multi-day forecast
Line 138: communityReports = emptyList() // TODO: Fetch from Reddit/forums
Line 163: // TODO: Implement seasonal fish patterns
```

- Wire up `ForecastService` to return actual multi-day forecasts
- Wire up `CommunityClient` to populate reports
- Implement fish migration patterns by region/month

## Phase 5: Deploy

1. Add Dockerfile to `shaka-api/`
2. Deploy API to Railway
3. Deploy PostgreSQL to Railway
4. Build Flutter app for TestFlight/Play Store

## Key Files

- `shaka-api/src/main/kotlin/com/shaka/data/client/SpotDatabase.kt` - spot data (in-memory)
- `shaka-api/src/main/kotlin/com/shaka/service/SpotService.kt` - main service with TODOs
- `shaka-api/src/main/kotlin/com/shaka/scoring/ShakaScorer.kt` - scoring algorithm
- `shaka-api/src/main/kotlin/com/shaka/data/client/CommunityClient.kt` - Reddit/forum scraping (partial)
- `shaka-api/src/main/kotlin/com/shaka/service/ForecastService.kt` - multi-day forecasts
- `docker-compose.yml` - local dev (PostGIS + Redis)
- `db/init.sql` - PostgreSQL schema with spatial queries

## Commit Strategy

Commit and push to GitHub after every substantive change.
