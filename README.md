Shaka
=====

Spearfishing spot finder with real-time ocean data. Ranks locations by weather, ocean conditions, and fish patterns. Features professional-grade oceanographic charts.

Download
--------

Coming soon to iOS and Android.

Features
--------

### Spot Finder

Search for spearfishing spots by location and date. Each spot is ranked with a Shaka Score (0-100) based on:

- Water visibility (satellite-measured Secchi depth)
- Sea surface temperature
- Swell height and period
- Wind conditions
- Tide state
- Fish activity patterns
- Accessibility and safety

### Ocean Charts

Full-screen oceanographic visualization with real-time satellite data from Copernicus Marine Service:

- **Sea Surface Temperature (SST)** - Updated every 6 hours
- **Chlorophyll-a** - Indicates water clarity and fish activity
- **Water Visibility** - Secchi disk depth measurements
- **Sea Surface Height** - Identifies currents and upwelling zones
- **Ocean Currents** - Vector visualization of water movement

Features include:
- Multiple base maps (dark, satellite, nautical)
- Layer opacity controls
- 14-day historical data scrubber
- Tap-for-data at any point
- Colormap legends

Data Sources
------------

All condition data comes from real measurements, not estimates:

| Data | Source | Update Frequency |
|------|--------|------------------|
| Weather | Open-Meteo | Hourly |
| SST, Visibility, Chlorophyll | Copernicus Marine (L3 NRT) | Daily |
| Currents, Sea Height | Copernicus Marine | 6 hours |
| Tides | NOAA CO-OPS | Real-time |
| Spot Info | Community database | Ongoing |

API
---

Search for spots:

```
GET /v1/spots/search?lat=21.3&lon=-157.8&date=2026-02-15&radius=50
```

Get spot details:

```
GET /v1/spots/{id}?date=2026-02-15
```

Health check:

```
GET /health/detailed
```

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
├── shaka-api/          Kotlin backend (Ktor)
│   ├── data/
│   │   ├── client/     External API clients
│   │   ├── cache/      In-memory caching
│   │   └── db/         PostgreSQL repositories
│   ├── model/          Domain models
│   ├── scoring/        Shaka Score algorithm
│   └── service/        Business logic
│
└── shaka-app/          Flutter mobile app
    ├── data/
    │   ├── api/        Backend + Copernicus WMTS clients
    │   └── models/     Data models
    └── presentation/
        ├── screens/
        │   ├── home/       Location/date selection
        │   ├── results/    Spot list and map
        │   ├── spot_detail/ Individual spot view
        │   └── charts/     Ocean Charts feature
        └── widgets/        Reusable components
```

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
