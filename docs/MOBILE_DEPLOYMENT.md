# Mobile Deployment Guide (iOS & Android)

**When the user says "deploy to our phone", "deploy to iPhone", "deploy to Android", or "deploy so we can test" — follow this guide.**

New agents: read this before running any deploy commands. It prevents hangs on physical devices and ensures the correct build/install flow.

---

## Pre-Deployment Verification

Before deploying, verify these things are correct in the codebase.

### 1. Check `main.dart` has the correct pattern

Read the file:

```bash
head -50 shaka-app/lib/main.dart
```

It **must** look like this (NO `async` on `main`, NO `await` before `runApp`):

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(...);  // OK - synchronous
  runApp(const ShakaApp());                   // App starts FIRST
  Future.microtask(() async {
    // Async stuff goes HERE, after runApp
  });
}
```

- If you see `void main() async` or any `await` before `runApp()` — **fix it first** or the iOS app will hang on physical devices.

---

## iOS Deployment (Physical iPhone)

### Step 1: Ensure iPhone is connected

```bash
flutter devices
```

You should see the iPhone in the list.

### Step 2: Clean and build

```bash
cd shaka-app
flutter clean
flutter pub get
flutter build ios --release
```

### Step 3: Install to device

```bash
flutter install -d iPhone
```

**CRITICAL:** Do **not** use `flutter run -d iPhone` — it causes hangs on physical devices.

### Step 4: Launch manually

Open the app on the physical iPhone by tapping the icon. If it hangs on the launch screen for more than 5 seconds, something is wrong.

### iOS Troubleshooting

- **Build fails:** Check Xcode signing certificates.
- **Install fails:** Trust the developer on the iPhone: Settings → General → VPN & Device Management.
- **App hangs:** Verify `main.dart` pattern (see Pre-Deployment Verification above).

---

## Android Deployment (Physical Android)

### Step 1: Ensure Android is connected with USB debugging enabled

```bash
flutter devices
```

You should see the Android device in the list.

### Step 2: Build release APK

```bash
cd shaka-app
flutter clean
flutter pub get
flutter build apk --release
```

### Step 3: Install to device

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Or using Flutter (use the device id from `flutter devices`):

```bash
flutter install -d <device-id>
```

### Step 4: Launch and test

Open the app on the Android device. It should launch within 2–3 seconds.

---

## Post-Deployment Verification

After deploying, verify the app works:

1. **App launches** — Map visible within ~5 seconds.
2. **Charts** — Tap Charts tab, open Satellite Imagery; map with satellite tiles should load.
3. **Pin mode (if implemented):** Tap "+" → crosshairs appear, GPS updates as you pan → "Mark Spot" to save.
4. **Profile** — Saved spots appear; tap one → spot detail loads.

---

## Quick Reference Commands

```bash
# iOS — full rebuild and deploy
cd shaka-app && flutter clean && flutter pub get && flutter build ios --release && flutter install -d iPhone

# Android — full rebuild and deploy
cd shaka-app && flutter clean && flutter pub get && flutter build apk --release && adb install -r build/app/outputs/flutter-apk/app-release.apk

# Check connected devices
flutter devices

# Check for build errors
flutter analyze
```

---

## What NOT To Do

- **NEVER** use `flutter run` for physical iOS devices (use `flutter build ios --release` then `flutter install -d iPhone`).
- **NEVER** add `async` to the `main()` function in `main.dart`.
- **NEVER** put `await` before `runApp()`.
- **NEVER** skip `flutter clean` after code changes when preparing a deploy.
- **NEVER** assume simulator success means the physical device will work — always test on a real device for deploy verification.
