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

There are two workflows. **Option A is the default** — use it any time you need to test changes on the iPhone.

### Option A: Deploy with logging (DEFAULT — use this for testing changes)

This is a **single command** that replaces the entire old `flutter clean && flutter pub get && flutter build ios --release && flutter install -d iPhone` chain. It builds your code, installs it to the iPhone, launches the app, and streams all log output to the terminal:

```bash
cd shaka-app && flutter run --profile -d iPhone
```

That's it. No `flutter clean`, no `flutter pub get`, no `flutter build`, no `flutter install` as separate steps. `flutter run --profile` does all of it.

**Expect the Xcode build to take 30-90 seconds.** It is not instant. The terminal will show `Running Xcode build...` while it compiles. Wait for it. After the build completes, the app launches on the iPhone automatically and logs start streaming.

Profile mode uses AOT compilation (not JIT), so it runs at near-release speed on the device.

All `print()` and `debugPrint()` output from **any screen** in the app appears in the terminal prefixed with `flutter:`.

To stop: press `q` in the terminal, or Ctrl+C.

**Important — Local Network permission:** On first run, iOS will show a Local Network permission dialog on the iPhone. **The user must accept it.** If they decline, the Dart VM service connection breaks and you get zero logs. If previously declined: Settings -> Privacy & Security -> Local Network -> find the app -> toggle on.

### Option B: Deploy without logging (final release verification only)

Only use this when you need a production release build and do NOT need any log output:

```bash
cd shaka-app && flutter clean && flutter pub get && flutter build ios --release && flutter install -d iPhone
```

Then launch manually by tapping the app icon on the iPhone. There is no way to see logs from a release build.

### WebView JS Debugging via Safari Web Inspector

All WKWebView instances in the app have `isInspectable = true` set, which allows Safari Web Inspector to connect for full JS console, DOM, and network debugging.

Setup (one-time):
1. **iPhone**: Settings -> Safari -> Advanced -> Web Inspector ON
2. **iPhone**: Settings -> Privacy & Security -> Developer Mode ON
3. Connect iPhone via USB cable

To inspect:
1. Open Safari on Mac
2. Safari menu -> Settings -> Advanced -> check "Show features for web developers"
3. Develop menu -> select your iPhone -> select the WebView page
4. Full JS console (`console.log` output), DOM inspector, and network tab are available

This works in both profile and release builds.

### iOS Troubleshooting

- **Build feels stuck:** `flutter run --profile` takes 30-90 seconds for the Xcode build. Look for `Running Xcode build...` in the output. Wait for it.
- **Build fails:** Check Xcode signing certificates.
- **Install fails:** Trust the developer on the iPhone: Settings -> General -> VPN & Device Management.
- **App hangs on startup:** Verify `main.dart` pattern (see Pre-Deployment Verification above).
- **No log output from `flutter run --profile`:** The user must accept the iOS Local Network permission dialog on the iPhone. If already dismissed, enable it in Settings -> Privacy & Security -> Local Network.
- **`flutter run` crashes with `mprotect failed: 13`:** You're running in debug mode. Always use `--profile` or `--release` on iOS 26+ physical devices. Debug mode uses JIT compilation which iOS 26 blocks.

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

Open the app on the Android device. It should launch within 2-3 seconds.

---

## Post-Deployment Verification

After deploying, verify the app works:

1. **App launches** — Map visible within ~5 seconds.
2. **Charts** — Tap Charts tab, open Satellite Imagery; map with satellite tiles should load.
3. **Pin mode (if implemented):** Tap "+" -> crosshairs appear, GPS updates as you pan -> "Mark Spot" to save.
4. **Profile** — Saved spots appear; tap one -> spot detail loads.

---

## Quick Reference Commands

```bash
# iOS — deploy with logging (DEFAULT for testing)
cd shaka-app && flutter run --profile -d iPhone

# iOS — release build (no logging, final verification only)
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

- **NEVER** use `flutter run` without `--profile` or `--release` on iOS 26+ physical devices. Debug mode uses JIT compilation which iOS 26 blocks via `mprotect`.
- **NEVER** use `flutter build + flutter install` and then expect `flutter logs` to work. `flutter logs` requires the Dart VM connection that only `flutter run` establishes. It will always be empty.
- **NEVER** add `async` to the `main()` function in `main.dart`.
- **NEVER** put `await` before `runApp()`.
- **NEVER** assume simulator success means the physical device will work — always test on a real device for deploy verification.
