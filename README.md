Shaka
=====

Spearfishing conditions app. Aggregates real-time ocean data from NASA, NOAA, and Copernicus satellites to score dive locations. Multi-platform Flutter client backed by a Kotlin API server.

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

Server starts at `http://localhost:8080`. Requires PostgreSQL.

Environment variables:
```
DATABASE_URL=postgresql://localhost:5432/shaka
COPERNICUS_USER=your_username      # optional
COPERNICUS_PASSWORD=your_password  # optional
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
│       │   │   └── CircuitBreaker       Failure isolation
│       │   ├── cache/
│       │   │   ├── SpotDataCache        Pre-fetched spot conditions
│       │   │   └── OceanDataCache       TTL-based fallback cache
│       │   └── db/
│       │       ├── SpotRepository       Spot CRUD operations
│       │       ├── UserSpotRepository   User-saved locations
│       │       └── SpotTables           Exposed table definitions
│       ├── model/             Domain models
│       ├── scoring/           
│       │   └── ShakaScorer    Score calculation algorithm
│       └── service/
│           ├── SpotService        Spot search, details retrieval
│           ├── ForecastService    7-day forecast generation
│           ├── DataPrefetchJobs   Background cache refresh
│           └── HealthService      External dependency monitoring
│
└── shaka-app/                 Flutter mobile client
    └── lib/
        ├── main.dart          App entry, router configuration
        ├── core/
        │   └── theme/         AppColors, AppTheme definitions
        ├── data/
        │   ├── api/
        │   │   ├── shaka_api_client.dart    Backend REST client
        │   │   └── gibs_service.dart        NASA GIBS tile URLs
        │   ├── models/
        │   │   ├── spot_models.dart         API response models
        │   │   ├── gibs_layer.dart          Satellite layer config
        │   │   └── map_background.dart      Map style definitions
        │   └── services/
        │       ├── device_id_service.dart   Anonymous user ID
        │       └── map_background_service.dart  Map style persistence
        └── presentation/
            ├── bloc/              Search state management
            ├── screens/
            │   ├── explore/       Map + spot carousel
            │   ├── charts/
            │   │   ├── charts_hub_screen.dart      Chart type selection
            │   │   ├── gibs_imagery_screen.dart    NASA satellite viewer
            │   │   └── ocean_charts_webview.dart   Copernicus viewer
            │   ├── spot_detail/   Individual spot view
            │   └── profile/       Settings, saved spots
            ├── shell/             Bottom navigation
            └── widgets/           Reusable components
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
| SST (High-Res) | NASA GIBS MUR/GHRSST | Daily |
| Chlorophyll-a | NASA GIBS PACE/VIIRS | Daily |
| True Color | NASA GIBS MODIS/VIIRS | Daily |
| SST, Visibility | Copernicus Marine | Daily |
| Currents, Waves | Copernicus Marine | 6 hours |

Pre-fetch System
----------------

The backend pre-fetches conditions for all 631 spots on startup and maintains freshness via scheduled jobs:

| Data | Refresh Interval |
|------|------------------|
| Tides | Hourly |
| Weather/Swell | Every 3 hours |
| SST/Visibility | Every 6 hours |

Initial cache warmup takes approximately 45 seconds. During warmup, requests fall through to live API calls.

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

### NASA GIBS Satellite Imagery

MapLibre-based viewer for NASA Global Imagery Browse Services tiles:

- Chlorophyll-a from PACE OCI, VIIRS NOAA-20/21, Sentinel-3A/3B
- Sea Surface Temperature from MUR SST
- True Color composites from MODIS/VIIRS

Supports multi-layer stacking, opacity control, and date selection back to 2012.

### Copernicus Ocean Conditions

WebView wrapper for Copernicus Marine viewer. Displays animated currents, SST, waves, wind, and chlorophyll. Supports snapshot saving for offline reference.

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
| Backend | Error message, cached data used |

All external clients have 10-second timeouts. The app queries `/v1/health/detailed` on startup to determine feature availability.

Deployment
----------

### Backend

Railway auto-deploys from main branch. Configuration via `railway.toml`.

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

Known Issues
------------

1. `flutter run` on physical iOS devices causes launch hangs. Always use `flutter build` + `flutter install`.

2. MapLibre `MaplibreMap` and `MaplibreMapController` are deprecated. Use `MapLibreMap` and `MapLibreMapController` (capital L) in new code.

3. `Color.withOpacity()` is deprecated in newer Flutter versions. Migrate to `Color.withValues()` as warnings indicate.

Recent Changes
--------------

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

Contributing
------------

See [CONTRIBUTING.md](CONTRIBUTING.md).

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
