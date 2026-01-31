Shaka
=====

Spearfishing and diving spot finder with real-time ocean data. Ranks locations by weather, ocean conditions, and fish patterns. Features professional-grade oceanographic charts from NASA and Copernicus satellites.

Download
--------

Coming soon to iOS and Android.

Recent Changes
--------------

### v0.3.0 - Data Pre-fetch System

- **Instant spot loading**: All 631 spots now load instantly from pre-fetched cache
- **Background data refresh**: Staggered prefetch jobs keep data fresh
  - Tides: Hourly refresh
  - Weather/Swell: Every 3 hours
  - Satellite data: Every 6 hours
- **Data freshness indicators**: Shows "Updated X min ago" in spot details
- **Unified map backgrounds**: Satellite, Terrain, Nautical, and Default styles across all map views
- **Improved splash screen**: Properly sized icon for Android 12+ adaptive splash
- **Fixed map tap detection**: Accurate spot selection with devicePixelRatio correction

### v0.2.0 - Charts Overhaul

- **NASA GIBS integration**: Multi-layer satellite imagery with 5 chlorophyll sources
- **Copernicus WebView**: Animated ocean conditions with save/share
- **Unified date picker**: Tap date indicator in top-right to change dates
- **Dynamic legends**: Auto-extracted from data sources with proper units

Features
--------

### Spot Finder

Interactive map for discovering dive spots. Surfline-style interface with map above and horizontal spot carousel below. Each spot is ranked with a Shaka Score (0-100) based on:

- Water visibility (satellite-measured Secchi depth)
- Sea surface temperature
- Swell height and period
- Wind conditions
- Tide state
- Fish activity patterns
- Accessibility and safety

Features include type-ahead search, region browsing, and filter chips (All, Shore, Boat, 80+).

### NASA GIBS Satellite Imagery

High-resolution satellite imagery from NASA's Global Imagery Browse Services (GIBS):

- **Chlorophyll-a** - PACE OCI, VIIRS NOAA-20/21, Sentinel-3A/3B
- **Sea Surface Temperature** - MUR SST (0.01 degree resolution), GHRSST
- **True Color** - Daily composites from MODIS and VIIRS

Features include:
- Multi-layer stacking (combine up to 5 chlorophyll satellites for full coverage)
- Layer presets: Full Coverage, Afternoon Pass, Morning Pass
- Historical data scrubbing back to 2012
- Dynamic legends with units
- Opacity controls per layer
- Multiple map backgrounds (Satellite, Terrain, Nautical, Default)

### Copernicus Ocean Conditions

Animated ocean data visualization from Copernicus Marine Service:

- **Sea Surface Temperature (SST)** - Updated every 6 hours
- **Ocean Currents** - Animated vector visualization
- **Waves** - Height, period, direction
- **Wind** - Speed and direction overlay
- **Chlorophyll-a** - Water clarity indicator

Features include:
- Hourly snapshots for time-series viewing
- Save snapshots to device gallery
- Share snapshots directly
- Layer opacity controls
- Tap date indicator to change dates

Data Sources
------------

All condition data comes from real measurements, not estimates:

| Data | Source | Update Frequency |
|------|--------|------------------|
| Weather | Open-Meteo | Hourly |
| SST (High-Res) | NASA GIBS MUR/GHRSST | Daily |
| Chlorophyll-a | NASA GIBS PACE/VIIRS/MODIS | Daily |
| True Color | NASA GIBS MODIS/VIIRS | Daily |
| SST, Visibility | Copernicus Marine (L3 NRT) | Daily |
| Currents, Waves | Copernicus Marine | 6 hours |
| Tides | NOAA CO-OPS | Real-time |
| Spot Info | Community database | Ongoing |

API
---

Search for spots by location:

```
GET /v1/spots/search?lat=21.3&lon=-157.8&date=2026-02-15&radius=50
```

Search spots by name (type-ahead):

```
GET /v1/spots/search/name?q=hanauma&limit=10
```

Get spot details:

```
GET /v1/spots/{id}?date=2026-02-15
```

Get available regions:

```
GET /v1/regions
```

Health check with external service status:

```
GET /v1/health/detailed
```

Returns status of OpenMeteo, NOAA, Copernicus, and NASA GIBS services. Used by the app to auto-degrade features when services are unavailable.

Building
--------

### API (Kotlin/Ktor)

```bash
cd shaka-api
./gradlew run
```

Runs at `http://localhost:8080`.

Environment variables:
- `DATABASE_URL` - PostgreSQL connection string
- `COPERNICUS_USER` / `COPERNICUS_PASSWORD` - Optional, for bulk data access

### Mobile App (Flutter)

Requires [Flutter](https://flutter.dev/docs/get-started/install) 3.0+.

```bash
cd shaka-app
flutter pub get
flutter run
```

### Docker

```bash
docker-compose up
```

Starts API server and PostgreSQL database.

Architecture
------------

```
shaka/
├── shaka-api/              Kotlin backend (Ktor)
│   ├── data/
│   │   ├── client/         External API clients (OpenMeteo, NOAA, Copernicus, GIBS)
│   │   ├── cache/          
│   │   │   ├── SpotDataCache    Pre-fetched data for all spots (in-memory)
│   │   │   └── OceanDataCache   TTL-based fallback cache
│   │   └── db/             PostgreSQL repositories
│   ├── model/              Domain models
│   ├── scoring/            Shaka Score algorithm
│   └── service/
│       ├── SpotService     Spot search and details (cache-first)
│       ├── ForecastService 7-day forecasts
│       ├── DataPrefetchJobs Background data refresh scheduler
│       └── HealthService   External service health checks
│
└── shaka-app/              Flutter mobile app
    ├── data/
    │   ├── api/            Backend client, GIBS service
    │   ├── models/         Data models (spots, forecasts, layers, map backgrounds)
    │   └── services/       Health monitoring, map background service
    └── presentation/
        ├── screens/
        │   ├── explore/    Map + carousel spot discovery
        │   ├── charts/     Charts hub, GIBS viewer, Copernicus viewer
        │   ├── spot_detail/ Individual spot view with tabs
        │   └── profile/    User settings
        ├── shell/          Bottom navigation shell
        └── widgets/        Reusable components (legends, pickers, cards)
```

App Navigation:
- Explore tab: Interactive map with spot carousel
- Charts tab: Selection between NASA GIBS and Copernicus viewers
- Profile tab: Settings and preferences

Data Pre-fetch System
---------------------

The backend pre-fetches ocean data for all 631 spots on startup and refreshes on a schedule:

| Data Type | Refresh Interval | Source | Cache Duration |
|-----------|-----------------|--------|----------------|
| Tides | Hourly | NOAA CO-OPS | Until next refresh |
| Weather/Swell | Every 3 hours | Open-Meteo | Until next refresh |
| SST/Visibility | Every 6 hours | Copernicus, NOAA ERDDAP | Until next refresh |

On server startup, all data is pre-fetched in parallel (~45 seconds for full cache). Requests during this warmup period fall back to live API calls.

The cache stores dual timestamps:
- `fetchedAt`: When the server retrieved the data
- `dataValidAt`: When the external provider recorded the data

This enables showing "Updated 5 min ago" and "Satellite: Jan 27" in the app.

Graceful Degradation
--------------------

The app is designed to continue working when external services are unavailable:

| Service Down | App Behavior |
|--------------|--------------|
| NASA GIBS | Unavailable layers hidden from picker |
| Copernicus | Option hidden from Charts hub, banner shown |
| OpenMeteo | Weather shows "unavailable" in spot details |
| NOAA | Falls back to regional SST estimates |
| Backend | Clear error messages, cached data when available |

The `/v1/health/detailed` endpoint checks all external services and returns their status. The Flutter app queries this on startup and caches the result for 5 minutes, automatically hiding features that depend on unavailable services.

Backend clients have explicit 10-second timeouts to prevent hangs. The SpotService fetches data in parallel with per-source timeouts (5-8 seconds), falling back to defaults when individual sources fail.

Deployment
----------

**Backend:** Railway (auto-deploys from main branch)

**Mobile:** App Store / Play Store (coming soon)

Scoring Algorithm
-----------------

The Shaka Score combines six factors with weighted importance:

| Factor | Weight | Source |
|--------|--------|--------|
| Visibility | 25% | Copernicus ZSD satellite data |
| Weather | 20% | Open-Meteo (precipitation, clouds) |
| Swell | 20% | Open-Meteo marine API |
| Fish Activity | 15% | Seasonal patterns + chlorophyll |
| Accessibility | 10% | Spot database |
| Safety | 10% | Currents, swell, conditions |

Confidence score decays with forecast distance (100% today, -10% per day).

Contributing
------------

See [CONTRIBUTING.md](CONTRIBUTING.md).

License
-------

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
