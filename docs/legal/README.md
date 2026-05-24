# Shaka legal documents

Canonical (source-of-truth) legal and privacy materials for the Shaka app. The public
versions are served as HTML from the API (see hosting below); these markdown files are
what they are generated from. Keep them in sync.

## Contents
- [privacy-policy.md](privacy-policy.md) — public Privacy Policy.
- [terms-of-service.md](terms-of-service.md) — public Terms of Service.
- [app-store-privacy.md](app-store-privacy.md) — exact App Store Connect "App Privacy"
  answers (must match the Privacy Policy).
- [data-practices.md](data-practices.md) — internal inventory of real data practices
  and open questions for Mike. Not published.

## Hosting (public URLs)
Served by the Railway API as static HTML (see `shaka-api/src/main/resources/legal/` and
`LegalRoutes.kt`):
- Privacy Policy: `https://shaka-production.up.railway.app/legal/privacy`
- Terms of Service: `https://shaka-production.up.railway.app/legal/terms`
- Index: `https://shaka-production.up.railway.app/legal`

Enter the Privacy Policy URL in App Store Connect.

## Versioning
- The in-app clickwrap and the server acceptance record are tied to a single version
  string in `shaka-app/lib/core/legal/legal_content.dart`.
- When the Terms or Privacy Policy change materially: update the markdown here, the
  hosted HTML, the effective date, and bump the version constant so users are
  re-prompted to accept.

## Before submission — required TODOs
- Replace every `PLACEHOLDER_SUPPORT_EMAIL` with a real, monitored support address.
- Resolve the open questions in [data-practices.md](data-practices.md)
  (Railway access logs; Sentry `sendDefaultPii`).

## Attorney review (recommended, non-blocking)
A short attorney review (~$350–750) of the Terms and Privacy Policy is recommended
before launch — particularly the limitation-of-liability cap, the assumption-of-risk
language, and whether to add an arbitration / class-action-waiver clause (currently
omitted, flagged in the Terms). This is a recommendation, not a launch blocker.
