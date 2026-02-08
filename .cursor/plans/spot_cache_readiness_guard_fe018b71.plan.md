---
name: Spot Cache Readiness Guard
overview: Expose `mpaChecked` boolean in the API response. On the spot detail screen, if MPA hasn't been checked yet, show a loading state on the Regulations card and re-fetch in the background until data arrives -- same pattern as the map bubble scores.
todos:
  - id: backend-model
    content: "Add `mpaChecked: Boolean` to `RegulationInfo` in Models.kt"
    status: pending
  - id: backend-wire
    content: Set `mpaChecked` from SpotDataCache mpa CachedValue presence when building spot detail responses
    status: pending
  - id: frontend-model
    content: Add `mpaChecked` to Dart `RegulationInfo` model in spot_models.dart
    status: pending
  - id: frontend-ui
    content: Show loading state in `_buildRegulationsInfo` when mpa is null and mpaChecked is false
    status: pending
  - id: frontend-poll
    content: Re-fetch spot detail in background until mpaChecked is true, then update UI in place
    status: pending
isProject: false
---

# MPA Loading Guard

## Problem

When `mpa_fetched_at` is NULL in the cache (prefetch hasn't run yet), the frontend receives `mpaStatus: null` and displays a green "No MPA restrictions nearby" -- identical to when MPA was genuinely checked and nothing was found.

## Pattern to Follow

The map bubble already solves this exact problem for shaka scores:

1. `_loadSavedSpots()` returns spot with `shakaScore: null` -- bubble renders grey
2. `_fetchMissingScores()` fires immediately, calling `getUserSpotDetail()` in the background
3. ~12 seconds later, data arrives, `setState` fires, score pops into the bubble in place

The MPA section in the spot detail screen should do the same thing: show a loading state, re-fetch in the background, update in place when `mpa_fetched_at` becomes non-null.

## Backend

### 1. Add `mpaChecked` to `RegulationInfo`

**File:** `shaka-api/src/main/kotlin/com/shaka/model/Models.kt`

```kotlin
val mpaChecked: Boolean = false  // true when mpa_fetched_at is NOT NULL in cache
```

### 2. Set `mpaChecked` when building spot detail

**File:** `shaka-api/src/main/kotlin/com/shaka/service/SpotService.kt`

Wherever `RegulationInfo` is constructed:

```kotlin
mpaChecked = SpotDataCache.get(cacheId)?.mpa != null
```

True when the `CachedValue` wrapper exists (MPA fetch was attempted), regardless of whether the inner value is null (no MPA found) or populated (MPA found).

## Frontend

### 3. Add `mpaChecked` to Dart model

**File:** `shaka-app/lib/data/models/spot_models.dart`

Add to `RegulationInfo`:

```dart
final bool mpaChecked;
```

Parse: `mpaChecked: json['mpaChecked'] as bool? ?? false`

### 4. Show loading state when MPA not yet checked

**File:** `shaka-app/lib/presentation/screens/spot_detail/spot_detail_screen.dart` (line ~722)

Change the `mpa == null` branch in `_buildRegulationsInfo`:

```dart
if (mpa == null && !regulations.mpaChecked) {
  // MPA check hasn't run yet -- show loading
  statusColor = Colors.grey;
  statusText = 'Checking MPA restrictions...';
  statusIcon = null; // CircularProgressIndicator instead
} else if (mpa == null || mpa.spearfishingStatus == 0) {
  // Checked, no restrictions (safe)
  statusColor = AppColors.success;
  statusText = 'No MPA restrictions nearby';
  statusIcon = Icons.check_circle;
}
```

### 5. Re-fetch in background until MPA data arrives

**File:** `shaka-app/lib/presentation/screens/spot_detail/spot_detail_screen.dart`

Same pattern as `_fetchMissingScores()` on the GIBS map. After the spot detail loads, if `mpaChecked` is false, start a background re-fetch loop:

```dart
// After spot detail loads successfully:
if (spotDetail.regulations?.mpaChecked == false) {
  _pollForMPA();
}

Future<void> _pollForMPA() async {
  while (mounted) {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    try {
      final detail = await _apiClient.getUserSpotDetail(
        spotId: widget.spotId, date: _date,
      );
      if (detail.spot.regulations?.mpaChecked == true) {
        if (mounted) {
          setState(() => _userSpotDetail = detail.spot);
        }
        return; // done, stop polling
      }
    } catch (_) {}
  }
}
```

Polls every 3 seconds. The moment `mpaChecked` comes back true, updates the UI in place and stops. The MPA card transitions from spinner to the real status without the user doing anything.

## Files to Modify

- `shaka-api/src/main/kotlin/com/shaka/model/Models.kt` -- add `mpaChecked` to `RegulationInfo`
- `shaka-api/src/main/kotlin/com/shaka/service/SpotService.kt` -- set `mpaChecked` when building response
- `shaka-app/lib/data/models/spot_models.dart` -- add `mpaChecked` to Dart model
- `shaka-app/lib/presentation/screens/spot_detail/spot_detail_screen.dart` -- loading state + background re-fetch
