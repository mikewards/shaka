# Shaka — Data Practices Inventory (internal)

Internal, non-public reference. This is the factual basis for the Privacy Policy,
Terms of Service, and the App Store Connect "App Privacy" answers. Everything here
was verified against the codebase. Keep this in sync whenever data handling changes.

Owner: Mike Ward (individual, not a company)
Governing law: California, USA
Effective date of current legal docs: 2026-06-16
Public support contact: **PLACEHOLDER_SUPPORT_EMAIL** (TODO: Mike must set a real,
monitored address before App Store submission — Apple requires a working contact.)

---

## 1. Identifiers

- **Anonymous device ID.** A random UUID v4 generated on first launch by
  `shaka-app/lib/data/services/device_id_service.dart`, stored in
  `flutter_secure_storage` (iOS Keychain / Android EncryptedSharedPreferences).
  - It is **not** a hardware identifier (no IMEI/serial/IDFA/IDFV).
  - It identifies an **install**, not a person. On iOS the Keychain value can
    survive app reinstall; on Android it is cleared on uninstall.
  - Sent to the backend only as the `X-Device-ID` HTTP header on:
    - `/v1/user-spots*` (saved spots), and
    - `/v1/legal/acceptances` (the legal acceptance record — see section 6).
  - No account, email, phone, name, or password is collected anywhere.

## 2. Location

- **No GPS and no OS location permission.** `geolocator` / `permission_handler`
  were declared in `pubspec.yaml` but unused; there are no `NSLocation*` keys in
  `ios/Runner/Info.plist` and no location permissions in the Android manifest.
  (Unused packages are being removed; see the cleanup commits.)
- "Location" that exists is user-supplied coordinates, not device positioning:
  - **Map Home** — a center point the user picks; stored locally in secure storage
    (`map_home_lat`, `map_home_lon`). Not transmitted.
  - **Saved spots** — lat/lon the user pins and names; **sent to the server** and
    stored in Postgres `user_spots`, keyed to the anonymous device ID.
  - **Map-area search/forecast** — the coordinates of the area the user is viewing
    are sent to the API to fetch conditions. Not stored as a user record.

## 3. User content

- **Saved spot names + coordinates** are stored on Shaka's servers (Railway-hosted
  Postgres), keyed to the anonymous device ID, max 100 per device. Users can list
  and delete their own spots.

## 4. Diagnostics

- **Sentry** crash/error reporting.
  - App side: `shaka-app/lib/main.dart`, enabled when built with
    `--dart-define=SENTRY_DSN=...` (the deploy runbook ships a DSN, so treat as ON
    in production). `tracesSampleRate = 0`.
  - Server side: `shaka-api/.../Application.kt`, ERROR level, `tracesSampleRate = 0`.
  - Sentry may attach diagnostic context (e.g. stack traces). See uncertainty (c).
- **BetterStack** receives operational **job-run metrics only** (job name, counts,
  success rate, top error strings) — no end-user content.

## 5. Third parties

- **Receive user-derived data:**
  - Railway (hosting + Postgres) — stores device IDs, saved spots, acceptance records.
  - Sentry — crash/error diagnostics (when enabled).
  - `is-on-water.balbona.me` — receives a spot's lat/lon when a spot is saved
    (land/water validation).
- **Upstream sources we fetch FROM (no user identity sent; they receive coordinates
  only, not tied to a person):** NOAA, NASA GIBS, Copernicus / CMEMS, Open-Meteo,
  ProtectedSeas, Global Fishing Watch, SportFishingReport.
- **AI (Groq / OpenAI):** receives scraped **public forum text** and aggregated
  region summaries to generate fishing intel. **No Shaka user data is sent.**
- **Map tiles / WebView CDNs** (Carto, Esri/ArcGIS, NASA GIBS, EOX, GEBCO,
  OpenSeaMap, Stadia, the Shaka Cloudflare weather worker): receive tile/asset
  requests, which include the device's IP at the network layer.

## 6. Legal acceptance record (server-side)

- On first launch the app requires acceptance of the Terms and Privacy Policy
  (clickwrap). The acceptance is recorded server-side in Postgres table
  `legal_acceptances`:
  `device_id`, `legal_version`, `document`, `accepted_at`, `app_version`, `platform`.
- **No IP address or user-agent is captured** at acceptance (minimal posture; see
  the decision note below). A local mirror in `shared_preferences` is kept only to
  drive the gate quickly and offline; the server row is the authoritative record.
- Purpose: prove assent to the Terms (record-keeping / legal compliance). This adds
  a purpose to the already-disclosed Device ID identifier; it does **not** add any
  OS permission.

## 7. Not collected / not done

- No analytics or product telemetry (no Firebase/GA/Mixpanel/Amplitude/Segment).
- No advertising, no ad SDKs, no ATT prompt, no cross-app/site tracking.
- No sale or sharing of personal information.
- Not directed to children; no knowing collection from children under 13.
- Server application code does not log client IPs or user-agents (but see (b)).

---

## Uncertainties / TODOs for Mike (resolve before submission)

- **(a) Support email.** Replace every `PLACEHOLDER_SUPPORT_EMAIL` with a real,
  monitored address.
- **(b) Railway access logs.** The hosting/proxy layer may log standard access
  metadata (IP, path, status). Confirm and disclose as hosting-provider logging.
- **(c) Sentry `sendDefaultPii`.** Sentry can attach the client IP by default.
  Confirm the project setting so the policy statement ("we don't intentionally
  collect your IP") stays accurate; disable if not needed.
- **(d) Device ID persistence.** Disclosed as "the anonymous ID may persist across
  reinstall on iOS." Confirm acceptable.
- **(e) Acceptance-record IP (decided: NO).** We store device_id + version +
  timestamp + app version + platform only. Reversible — capturing IP would add
  weak corroborating evidence at the cost of a broader privacy disclosure.

## Attorney review

A short attorney review (~$350–750) of the Terms and Privacy Policy is recommended
before launch — especially the liability cap, assumption-of-risk language, and any
arbitration/class-action-waiver clause. This is a recommendation, not a blocker.
