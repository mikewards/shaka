# Shaka — App Store Connect "App Privacy" answers

These are the exact answers to enter under App Store Connect →
[App] → App Privacy. They match `privacy-policy.md` and the verified
practices in `data-practices.md`. Re-confirm before each submission if data
handling changes.

Privacy Policy URL to enter: `https://shaka-production.up.railway.app/legal/privacy`

---

## Tracking
- **Do you or your third-party partners use data for tracking?** **No.**
- No App Tracking Transparency prompt, no advertising SDKs, no cross-app/cross-site
  tracking. **No tracking domains** to declare.

## Data types collected

For each type below, "Linked to you" means linked to the anonymous device identifier
(Shaka has no accounts and collects no name/email). None is used for Tracking.

### 1. Identifiers — Device ID
- **Collected:** Yes
- **Linked to identity:** Yes
- **Used for tracking:** No
- **Purposes:** App Functionality (associate saved spots with your install) and
  legal/record-keeping (record your acceptance of the Terms).

### 2. Location — Precise Location
- **Collected:** Yes
- **Linked to identity:** Yes
- **Used for tracking:** No
- **Purpose:** App Functionality.
- **Note:** Shaka does not use device GPS or request location permission. This covers
  the precise coordinates the user chooses (saved spots sent to the server, and the
  map area used to fetch conditions). Declared as Precise Location to be accurate and
  conservative.

### 3. User Content — Other User Content
- **Collected:** Yes
- **Linked to identity:** Yes
- **Used for tracking:** No
- **Purpose:** App Functionality.
- **Note:** Names the user gives to saved spots.

### 4. Diagnostics — Crash Data
- **Collected:** Yes (via Sentry, when enabled in the build)
- **Linked to identity:** No
- **Used for tracking:** No
- **Purpose:** App Functionality (diagnose crashes/errors).

### 5. Diagnostics — Performance Data
- **Collected:** Yes (Sentry; performance tracing is disabled, so minimal — declare
  conservatively)
- **Linked to identity:** No
- **Used for tracking:** No
- **Purpose:** App Functionality.

## Data types NOT collected
Contact Info (name, email, phone, address), Health & Fitness, Financial Info, Contacts,
Browsing History, Search History (recent searches are stored only on the device),
Purchases, Sensitive Info, Audio/Photos/Video, and Other Data are **not** collected.

---

## Cross-checks
- "No tracking / no ads / no sale" claims in the Privacy Policy are reflected here
  (Tracking = No).
- Device ID purpose "legal record-keeping" matches the `legal_acceptances` server
  record described in the Privacy Policy and `data-practices.md`.
- No IP address is captured for the acceptance record, so no IP/coarse-location data
  type is declared on that basis. (If Mike later decides to capture IP at acceptance,
  add an Identifiers/Diagnostics IP entry here and in the Privacy Policy.)
