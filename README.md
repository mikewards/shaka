Shaka
=====

Spearfishing spot finder. Ranks locations by weather, ocean conditions, and fish patterns.

Download
--------

Coming soon to iOS and Android.

Usage
-----

Search for spots by location and date:

```
GET /v1/spots/search?lat=21.3&lon=-157.8&date=2026-02-15&radius=50
```

Response includes ranked spots with Shaka Score (0-100), conditions breakdown, gear recommendations, and access info.

Building
--------

### API

```
cd shaka-api
./gradlew run
```

Runs at `http://localhost:8080`.

### Mobile

Requires [Flutter](https://flutter.dev/docs/get-started/install).

```
cd shaka-app
flutter pub get
flutter run
```

Architecture
------------

```
shaka/
├── shaka-api/     Kotlin backend (Ktor)
└── shaka-app/     Flutter mobile app
```

**Data sources:** Open-Meteo (weather), Copernicus Marine (satellite), NOAA (tides), community reports.

**Scoring factors:** Visibility (25%), weather (20%), swell (20%), fish activity (15%), accessibility (10%), safety (10%). Confidence decays with forecast distance.

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
