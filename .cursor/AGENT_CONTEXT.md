# Shaka - Agent Context

Paste this into a new agent when starting work on this project.

---

## Overview

Shaka is a spearfishing spot finder app - a Flutter mobile app + Kotlin backend that ranks dive spots by weather, ocean conditions, and fish patterns.

**GitHub:** https://github.com/wardmic4/shaka

**Stack:**
- Backend: Kotlin/Ktor (`shaka-api/`)
- Mobile: Flutter/Dart (`shaka-app/`)
- Database: PostgreSQL + PostGIS (not yet connected)

**Git:** All commits must show as **wardmic4** on GitHub. This repo has `user.name=wardmic4` and `user.email=zmikewardz@gmail.com` set locally; do not use "cursoragent" or any other author when making commits.

## Directory Structure

```
shaka-api/
  src/main/kotlin/com/shaka/
    api/routes/       SpotRoutes.kt
    data/client/      SpotDatabase.kt, OpenMeteoClient.kt, CopernicusClient.kt, CommunityClient.kt
    service/          SpotService.kt, ForecastService.kt
    scoring/          ShakaScorer.kt
    model/            Models.kt
  src/main/resources/ application.conf, logback.xml

shaka-app/
  lib/
    core/theme/       app_colors.dart, app_theme.dart
    data/
      api/            shaka_api_client.dart
      models/         spot_models.dart
      repositories/   spot_repository.dart
    presentation/
      bloc/           search_bloc.dart
      screens/        home/, results/, spot_detail/
      widgets/        Various UI components

db/                   init.sql (PostGIS schema)
docker-compose.yml    Local dev (PostGIS + Redis)
```

## Current State (60-70% complete)

### Working
- API routes and scoring engine
- 500+ spots in-memory database
- Flutter app with full UI flow (home, results, detail screens)
- Weather integration via Open-Meteo
- BLoC state management
- Map view with markers (flutter_map)

### Incomplete
- Spot database: 500 spots (target: 10,000+)
- PostgreSQL/PostGIS not connected (in-memory only)
- Community data (Reddit, forums) stubbed out
- Forecast in detail view returns empty
- GitHub Actions CI blocked by token scope

## API Endpoints

```
GET  /v1/health                           Health check
GET  /v1/spots/search?lat=&lon=&date=&radius=   Search spots
GET  /v1/spots/{id}?date=                 Get spot details
GET  /v1/forecast/{spotId}?days=          Multi-day forecast
GET  /v1/reports/{region}                 Community reports
```

## Scoring Algorithm (`ShakaScorer.kt`)

Shaka Score (0-100) weighted average:
- Visibility: 25% - Water clarity from satellite/historical
- Weather: 20% - Wind, rain, cloud cover
- Swell: 20% - Wave height and period
- Fish Activity: 15% - Migration patterns, moon phase, sightings
- Accessibility: 10% - Shore vs boat, parking, permits
- Safety: 10% - Currents, hazards, shark risk

Confidence decay with forecast distance:
- Same day: 95%
- 3 days: 85%
- 7 days: 70%
- 14 days: 50%
- 30 days: 30%

## TODOs in Code

**File:** `shaka-api/src/main/kotlin/com/shaka/service/SpotService.kt`

```kotlin
Line 41:  recentSightings = 3 // TODO: Get from community data
Line 124: forecast = emptyList() // TODO: Generate multi-day forecast
Line 138: communityReports = emptyList() // TODO: Fetch from Reddit/forums
Line 163: // TODO: Implement seasonal fish patterns
```

**File:** `shaka-api/src/main/kotlin/com/shaka/data/client/CommunityClient.kt`
- Reddit API integration works
- Forum/blog scraping returns placeholder data

**File:** `shaka-api/src/main/kotlin/com/shaka/data/client/CopernicusClient.kt`
- Falls back to regional estimates (needs credentials)

## Phase 1: Fix GitHub Token and CI

Token needs `workflow` scope to push `.github/workflows/build.yml`.

1. Go to https://github.com/settings/tokens
2. Edit token, add `workflow` scope
3. Push: `git add .github && git commit -m "Add CI workflow" && git push`

## Phase 2: Expand Spot Database (500 -> 10,000+)

**File:** `shaka-api/src/main/kotlin/com/shaka/data/client/SpotDatabase.kt`

**Priority Regions:**
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

**Approach:**
- Scrape/aggregate from spearfishing forums, dive site databases
- Cross-reference with marine charts
- Validate coordinates and access info

## Phase 3: Connect PostgreSQL + PostGIS

**Files:**
- `db/init.sql` - Schema ready with spatial queries
- `docker-compose.yml` - PostGIS container ready
- `shaka-api/build.gradle.kts` - Dependencies added (PostgreSQL, Exposed ORM)

**Tasks:**
1. Create `DatabaseFactory.kt` for connection management
2. Create `SpotRepository.kt` using Exposed ORM
3. Migrate spots from `SpotDatabase.kt` to SQL
4. Use `ST_DWithin` for geo queries (function already in init.sql)

**Local dev:**
```bash
docker-compose up -d
cd shaka-api && ./gradlew run
```

## Phase 4: Complete TODO Items

- Wire up `ForecastService` to return actual multi-day forecasts in `SpotService.getSpotDetail()`
- Wire up `CommunityClient` to populate `communityReports` in `SpotService`
- Implement fish migration patterns by region/month

## Phase 5: Deploy

1. Add Dockerfile to `shaka-api/`
2. Deploy API to Railway
3. Deploy PostgreSQL to Railway
4. Build Flutter app for TestFlight/Play Store

## Data Sources

- **Open-Meteo:** Weather and marine forecasts
- **Copernicus Marine:** Satellite ocean data (chlorophyll, turbidity)
- **NOAA:** Tides and currents (mentioned in README, not implemented)
- **Community:** Reddit API works, forum scraping placeholder

## Flutter App Architecture

- **State:** BLoC pattern (`SearchBloc`)
- **Navigation:** GoRouter
- **HTTP:** Dio client
- **Maps:** flutter_map with OpenStreetMap tiles
- **Models:** JSON serialization with `json_annotation`

**Screens:**
- `HomeScreen` - Location picker, date picker, search button
- `ResultsScreen` - List view + map view with spot cards
- `SpotDetailScreen` - Full spot info, conditions, forecast, gear, risks

## Deploy to Phone (iOS / Android)

**When the user says "deploy to our phone", "deploy to iPhone", "deploy to Android", or "deploy so we can test" — follow the full guide:**

**→ [docs/MOBILE_DEPLOYMENT.md](../docs/MOBILE_DEPLOYMENT.md)**

That doc includes:
- Pre-deployment verification (e.g. `main.dart` must not use `async`/`await` before `runApp()`)
- Step-by-step iOS: `flutter clean` → `flutter build ios --release` → `flutter install -d iPhone` (never `flutter run` on physical iPhone)
- Step-by-step Android: `flutter build apk --release` → `adb install -r ...` or `flutter install -d <device-id>`
- Quick reference one-liners and post-deploy verification
- What NOT to do (no `flutter run` on iOS device, no `async` on `main()`, etc.)

**iOS-specific rules** (launch hangs, dark launch screen): see `.cursor/rules/ios-deployment.mdc`.

## Commit Strategy

Commit and push to GitHub after every substantive change.
