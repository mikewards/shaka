# Shaka

Find the best spearfishing spots based on weather, ocean conditions, and fish patterns.

## Features

- Search spots by location and date (up to 30 days forecast)
- Shaka Score - confidence-weighted ranking of dive conditions
- Weather, swell, visibility, and fish activity analysis
- Gear recommendations based on conditions
- Risk assessment - what could go wrong
- Access info - shore dive vs boat, directions, parking

## Architecture

```
shaka/
├── shaka-app/     # Flutter mobile app (iOS + Android)
└── shaka-api/     # Kotlin backend (Ktor)
```

## Data Sources

- Open-Meteo: Weather and marine forecasts
- Copernicus Marine: Satellite ocean data (chlorophyll, turbidity)
- NOAA: Tides and currents
- Community: Reddit, fishing forums, local reports

## Running Locally

### Backend

```bash
cd shaka-api
./gradlew run
```

API runs at http://localhost:8080

### Mobile App

Requires Flutter SDK installed.

```bash
cd shaka-app
flutter pub get
flutter run
```

## API Endpoints

```
GET /v1/spots/search?lat=21.3&lon=-157.8&date=2026-02-15&radius=50
GET /v1/spots/{id}?date=2026-02-15
GET /v1/forecast/{spotId}?days=7
GET /v1/reports/{region}
```

## Scoring Algorithm

The Shaka Score (0-100) is a weighted average of:

- Visibility (25%): Water clarity from satellite and historical data
- Weather (20%): Wind, rain, cloud cover
- Swell (20%): Wave height and period
- Fish Activity (15%): Migration patterns, moon phase, recent sightings
- Accessibility (10%): Shore vs boat, parking, permits
- Safety (10%): Currents, hazards, shark risk

Confidence decreases with forecast distance:
- Same day: 95%
- 3 days: 85%
- 7 days: 70%
- 14 days: 50%
- 30 days: 30%

## Tech Stack

- Mobile: Flutter, Dart, BLoC, flutter_map
- Backend: Kotlin, Ktor, kotlinx.serialization
- APIs: Open-Meteo, Copernicus Marine, NOAA

## License

MIT
