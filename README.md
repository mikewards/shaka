Shaka
=====

**Should you dive today?** Shaka answers that question for 789 curated spearfishing spots by fusing real-time satellite and ocean data — NASA imagery, NOAA tides and sea-surface temperature, Copernicus visibility and currents — into a single 0–100 dive score, alongside live fishing intelligence scraped from West Coast dock reports and summarized with AI.

Why it exists: spearfishers check five different sites (swell, tides, visibility, wind, fish counts) before every dive and still guess. Shaka collapses that into one screen.

Highlights:

- **Six-factor scoring engine** — visibility, weather, swell, fish activity, accessibility, safety — with per-day forecast confidence decay
- **Satellite data pipelines** from NASA GIBS (chlorophyll, true color), NOAA ERDDAP (SST), Copernicus Marine (visibility, currents, waves), Open-Meteo (weather/swell) — cached, rate-limited, watchdog-supervised
- **Live fishing intel** scraped every 2 hours across 11 regions (WA to Baja), deduplicated, species-normalized, with AI-generated regional insights
- **Graceful degradation everywhere** — any upstream source can die without taking down a feature
- Flutter app (iOS + Android) backed by Kotlin/Ktor + PostgreSQL/PostGIS on Railway, with Sentry, structured log shipping, and job heartbeats

Download
--------

iOS and Android binaries are built via `flutter build`. See deployment section.

Building
--------

### Prerequisites

- Flutter 3.0+ (`flutter doctor` to verify)
- JDK 17+ for the Kotlin backend
- Docker (optional, for local database)
- Xcode 15+ for iOS builds
- Android SDK for Android builds

### API Server

```bash
cd shaka-api
./gradlew run
```

Server starts at `http://localhost:8080`. Requires PostgreSQL with PostGIS extension.

Environment variables (see `EnvValidation.kt` for the full audited list):
```
DATABASE_URL=postgresql://localhost:5432/shaka
COPERNICUS_CLIENT_ID=...            # optional - CDSE OAuth (realtime clarity)
COPERNICUS_CLIENT_SECRET=...        # optional
COPERNICUSMARINE_SERVICE_USERNAME=... # optional - weather tile pipeline
COPERNICUSMARINE_SERVICE_PASSWORD=...
TIDE_SOURCE=fes2022                 # noaa | fes2022
TIDE_SERVICE_URL=http://...:8000    # required when TIDE_SOURCE=fes2022
FISHING_INTEL_AI_ENABLED=true       # optional - AI region insights (Groq)
FISHING_INTEL_AI_API_KEY=...
SENTRY_DSN=...                      # optional - error tracking
BETTERSTACK_SOURCE_URL=...          # optional - log shipping
BETTERSTACK_SOURCE_TOKEN=...
HEARTBEAT_URLS=job=url,...          # optional - job heartbeat pings
```

### Mobile App

```bash
cd shaka-app
flutter pub get
flutter run
```

For release builds:

```bash
# iOS
flutter build ios --release
flutter install -d iPhone

# Android  
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

IMPORTANT: Never use `flutter run` for physical iOS devices. It causes launch hangs. Always use `flutter build` followed by `flutter install`.

### Docker

```bash
docker-compose up
```

Starts PostgreSQL and the API server.

Architecture
------------

```
shaka/
├── shaka-api/                 Kotlin/Ktor backend
│   └── src/main/kotlin/com/shaka/
│       ├── Application.kt     Entry point, routing setup
│       ├── api/routes/        HTTP endpoint handlers
│       ├── data/
│       │   ├── client/        External API clients
│       │   │   ├── OpenMeteoClient      Weather, swell forecasts
│       │   │   ├── NOAAClient           Tide predictions, SST
│       │   │   ├── NOAATidesClient      CO-OPS tide data
│       │   │   ├── CopernicusClient     Ocean conditions (SST, ZSD)
│       │   │   ├── GIBSClient           NASA satellite imagery URLs
│       │   │   └── RateLimiters         Per-source rate limiting
│       │   ├── cache/
│       │   │   ├── SpotDataCache        Pre-fetched spot conditions
│       │   │   └── OceanDataCache       TTL-based fallback cache
│       │   └── db/
│       │       ├── SpotRepository       Spot CRUD operations
│       │       ├── UserSpotRepository   User-saved locations
│       │       └── SpotTables           Exposed table definitions
│       ├── fishing_intel/     SoCal fishing reports scraping
│       │   ├── api/           REST endpoints for intel data
│       │   ├── db/            Database tables and operations
│       │   ├── jobs/          Scheduled scraping jobs
│       │   ├── models/        Data classes and enums
│       │   ├── parsing/       Fish count and date parsers
│       │   └── processing/    Normalization, deduplication
│       ├── model/             Domain models
│       ├── scoring/           
│       │   └── ShakaScorer    Score calculation algorithm
│       └── service/
│           ├── SpotService        Spot search, details retrieval
│           ├── ForecastService    7-day forecast generation
│           ├── DataPrefetchJobs   Background cache refresh
│           └── HealthService      External dependency monitoring
│
├── shaka-app/                 Flutter mobile client
│   └── lib/
│       ├── main.dart          App entry, router configuration
│       ├── core/
│       │   └── theme/         AppColors, AppTheme definitions
│       ├── data/
│       │   ├── api/
│       │   │   ├── shaka_api_client.dart    Backend REST client
│       │   │   └── gibs_service.dart        NASA GIBS tile URLs
│       │   ├── models/
│       │   │   ├── spot_models.dart         API response models
│       │   │   ├── gibs_layer.dart          Satellite layer config
│       │   │   └── map_background.dart      Map style definitions
│       │   └── services/
│       │       ├── device_id_service.dart   Anonymous user ID
│       │       └── map_background_service.dart  Map style persistence
│       ├── features/
│       │   └── fishing_intel/ Fishing reports UI
│       │       ├── models/    Dart data models
│       │       ├── services/  API client
│       │       └── widgets/   Highlight, species, bait cards
│       └── presentation/
│           ├── bloc/              Search state management
│           ├── screens/
│           │   ├── explore/       Map + spot carousel
│           │   ├── charts/
│           │   │   ├── charts_hub_screen.dart      Chart type selection
│           │   │   ├── gibs_imagery_screen.dart    NASA satellite viewer
│           │   │   └── ocean_forecast_screen.dart   Ocean forecast viewer
│           │   ├── spot_detail/   Individual spot view + Fishing tab
│           │   └── profile/       Settings, saved spots
│           ├── shell/             Bottom navigation
│           └── widgets/           Reusable components
│
└── db/
    └── init.sql               Database schema with PostGIS
```

API
---

### Search Spots

```
GET /v1/spots/search?lat=21.3&lon=-157.8&date=2026-02-01&radius=50
```

Returns spots within radius (km) of coordinates, scored for the given date.

### Name Search

```
GET /v1/spots/search/name?q=hanauma&limit=10
```

Type-ahead search by spot name.

### Spot Details

```
GET /v1/spots/{id}?date=2026-02-01
```

Full spot data including conditions, forecast, and score breakdown.

### User Spots

Requires `X-Device-ID` header for anonymous user identification.

```
POST /v1/user-spots
Content-Type: application/json
X-Device-ID: abc123

{"name": "My Spot", "latitude": 21.3, "longitude": -157.8}
```

```
GET /v1/user-spots
X-Device-ID: abc123
```

```
GET /v1/user-spots/{id}?date=2026-02-01
X-Device-ID: abc123
```

```
DELETE /v1/user-spots/{id}
X-Device-ID: abc123
```

### Fishing Intel

Real-time dock totals scraped from sportfishingreport.com across 11 West Coast regions (WA to Baja).

```
GET /v1/regions/{regionId}/intel?since=72h&tzOffset=-8
```

Returns species trends, recent catches, and AI-generated global insights. Region IDs: `san_diego`, `orange`, `la`, `ventura`, `central_coast`, `bay_area`, `norcal`, `north_coast`, `or_coast`, `wa_coast`, `baja`.

```
GET /v1/spots/{spotId}/intel?since=72h
```

Returns fishing highlights, species summary, and bait status for spots near the location.

```
GET /v1/admin/fishing-intel/health
```

Scraper status and source statistics.

```
POST /v1/admin/fishing-intel/scrape
```

Manually trigger the scraper (bypasses deploy guard).

### Health Check

```
GET /v1/health/detailed
```

Returns status of all external services (OpenMeteo, NOAA, Copernicus, GIBS).

Data Sources
------------

| Data Type | Provider | Update Frequency |
|-----------|----------|------------------|
| Weather | Open-Meteo | Hourly |
| Tides | NOAA CO-OPS | Real-time |
| SST | NOAA GeoPolar Blended (coastwatch.noaa.gov ERDDAP) | Daily |
| Chlorophyll-a | NASA GIBS PACE/VIIRS | Daily |
| True Color | NASA GIBS MODIS/VIIRS | Daily |
| SST, Visibility | Copernicus Marine | Daily |
| Currents, Waves | Copernicus Marine | 6 hours |
| Fishing Intel | SportFishingReport.com | Every 2 hours |

### Fishing Intel Sources

| Source | Type | Coverage |
|--------|------|----------|
| SportFishingReport.com | Dock totals | WA Coast to Baja (11 regions) |

Pre-fetch System
----------------

The backend restores the previous cache from PostgreSQL on startup, then
maintains freshness via in-process scheduled jobs (all wrapped with a
per-iteration watchdog so a hung dependency cannot kill a loop):

| Data | Refresh Interval |
|------|------------------|
| Tides | Hourly (derived from materialized charts; FES service only for missing spots) |
| Tide charts | Every 6 hours + 10-min catch-up |
| Weather/Swell | Every 3 hours |
| SST/Visibility | Every 6 hours |
| Solunar/Buoys | 12h / hourly |
| MPA boundaries | Weekly |
| Fishing Intel | Every 2 hours |

There is no blocking warmup; until jobs converge, missing data is reported
as "Unavailable" rather than substituted with defaults.

Scoring Algorithm
-----------------

The Shaka Score (0-100) is computed from six weighted factors:

| Factor | Weight | Data Source |
|--------|--------|-------------|
| Visibility | 25% | Copernicus ZSD |
| Weather | 20% | Open-Meteo |
| Swell | 20% | Open-Meteo Marine |
| Fish Activity | 15% | Seasonal + chlorophyll |
| Accessibility | 10% | Spot database |
| Safety | 10% | Currents, conditions |

Forecast confidence decays 10% per day from current date.

App Features
------------

### Explore

Interactive map with spot markers. Markers display Shaka Score and respond to tap. Bottom carousel shows spot cards with current conditions. Map style defaults to satellite imagery.

### Spot Detail

Four-tab interface for comprehensive spot information:

- **Overview** - Current conditions, Shaka Score breakdown, 7-day forecast
- **Details** - Depth, access type, target species, hazards
- **Tides** - NOAA tide predictions with chart visualization
- **Fishing** - Live fishing intel from SoCal report sources

### Fishing Intel Tab

Real-time fishing intelligence for SoCal spots:

- **Highlights** - Recent catches with species, counts, boat/landing info
- **Species Summary** - Top species caught in the area
- **Bait Status** - Live bait availability at nearby landings

Data is scraped every 2 hours from dock totals and landing reports.

### NASA GIBS Satellite Imagery

MapLibre-based viewer for NASA Global Imagery Browse Services tiles:

- Chlorophyll-a from PACE OCI, VIIRS NOAA-20/21, Sentinel-3A/3B
- Sea Surface Temperature from MUR SST
- True Color composites from MODIS/VIIRS

Supports multi-layer stacking, opacity control, and date selection back to 2012.

### User Spots

Pin mode allows saving custom locations with crosshair targeting. Coordinates update in real-time during pan. Saved spots appear in Profile and can be viewed in the Saved Spots sheet on map screens.

Map Backgrounds
---------------

Three map styles available across all map screens:

| Style | Base | Overlays |
|-------|------|----------|
| Default | Carto Voyager | None |
| Satellite | Carto Voyager | ArcGIS World Imagery |
| Nautical | Carto Light | ArcGIS Ocean, OpenSeaMap |

Default is Satellite. Selection persists via SharedPreferences.

Graceful Degradation
--------------------

The app continues functioning when external services fail:

| Service Down | Behavior |
|--------------|----------|
| NASA GIBS | Affected layers hidden from picker |
| Copernicus | Option hidden from Charts hub |
| OpenMeteo | Weather shows "unavailable" |
| NOAA | Falls back to regional SST |
| Fishing Intel | Tab shows "no data available" |
| Backend | Error message, cached data used |

All external clients have 10-second timeouts. The app queries `/v1/health/detailed` on startup to determine feature availability.

Deployment
----------

**Full checklist (for API + app on phone):**

1. **Backend (Railway)** – Push to `main`; Railway auto-deploys. Wait for deploy to finish in Railway dashboard.  
   Schema changes (e.g. `thread_url`, `thread_zone`) and geo backfill run automatically on API startup; no manual migration.
2. **BD data (required after schema/ingest changes)** – Existing BD rows were ingested without `thread_url`/`speciesCaught`. Ingest only inserts (skips duplicates), so to get one card per thread and “actually caught” species you must clear and re-ingest:  
   `cd tools/bd-scraper && .venv/bin/python scraper.py --clear-bd-first`  
   (Without `--clear-bd-first`, re-run only adds new posts; existing 25 will be skipped.)
3. **iPhone app** – Build and install so the device gets the latest UI:  
   `cd shaka-app && flutter build ios --release && flutter install -d iPhone`  
   Then force-quit the app on the phone and reopen.

Until both (1) and (3) are done, the phone can show old UI and the API can return old response shapes.

### Backend

Railway auto-deploys from main branch. Configuration via `railway.toml`.

Required environment variables on Railway:
- `DATABASE_URL` - PostgreSQL connection string (auto-provisioned)

### iOS

```bash
cd shaka-app
flutter clean
flutter pub get
flutter build ios --release
flutter install -d iPhone
```

Requires valid signing certificate in Xcode. Trust developer in Settings > General > VPN & Device Management if installation fails.

### Android

```bash
cd shaka-app
flutter clean
flutter pub get
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

USB debugging must be enabled on device.

Database Schema
---------------

Core tables:
- `spots` - 789 curated dive locations with coordinates and metadata
- `spot_cache` - Pre-fetched conditions cache with TTL tracking
- `user_spots` - User-created custom locations

Fishing intel tables:
- `fishing_intel_sources` - Scraping source configuration
- `fishing_intel_reports` - Deduplicated fishing reports
- `fishing_intel_claims` - Individual catch/targeting claims
- `fishing_intel_landings` - SoCal landing definitions
- `fishing_intel_report_geos` - PostGIS spatial indexing

Known Issues
------------

1. `flutter run` on physical iOS devices causes launch hangs. Always use `flutter build` + `flutter install`.

2. MapLibre `MaplibreMap` and `MaplibreMapController` are deprecated. Use `MapLibreMap` and `MapLibreMapController` (capital L) in new code.

3. `Color.withOpacity()` is deprecated in newer Flutter versions. Migrate to `Color.withValues()` as warnings indicate.

Recent Changes
--------------

### v0.5.0 - SoCal Fishing Intel

- Real-time fishing report scraping from 6 sources
- New "Fishing" tab in spot detail with highlights, species, bait status
- Automatic scraping every 2 hours with rate limiting
- Deduplication via SHA-256 fingerprinting
- PostGIS-based proximity queries for nearby reports
- Species normalization and count parsing

### v0.4.0 - UI Polish and Layout Improvements

- Buttons moved above opacity/legend row on GIBS and Ocean maps
- Horizontal button layout: left-aligned (Layers, Map Style) and right-aligned (Pin, Saved Spots)
- Default map style changed to Satellite
- Pin mode coordinates update in real-time during pan
- Pin mode actions (Cancel/Mark Spot) moved inside bottom container
- Badge overflow fixed on Saved Spots button
- Opacity slider and legend consolidated to single row (50/50 split)
- Green success snackbar removed from save spot flow
- Datepicker Cancel/OK buttons brightened
- Explore map style button left-aligned

### v0.3.0 - Data Pre-fetch System

- Instant spot loading from pre-fetched cache
- Background data refresh with staggered intervals
- Data freshness indicators in UI
- Unified map backgrounds across all views
- Fixed map tap detection accuracy

### v0.2.0 - Charts Overhaul

- NASA GIBS integration with multi-layer support
- Copernicus WebView with snapshot save/share
- Unified date picker across chart views
- Dynamic legends extracted from data sources

License
-------

```
Copyright 2026 Ward

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
