/// Canonical legal constants for the app: hosted URLs, the current legal
/// version (drives the first-launch acceptance gate and the server record),
/// and the short plain-language copy shown in-app.
///
/// When the Terms or Privacy Policy change materially, bump
/// [currentLegalVersion] so users are re-prompted to accept, and update the
/// hosted pages + docs/legal markdown to match.
class LegalContent {
  LegalContent._();

  /// Date-stamped version of the Terms + Privacy Policy currently in effect.
  /// Must match the effective date in docs/legal and the hosted pages.
  static const String currentLegalVersion = '2026-06-16';

  // Public legal pages, served by the API at the root level (not under /v1).
  static const String _base = 'https://shaka-production.up.railway.app/legal';
  static const String privacyUrl = '$_base/privacy';
  static const String termsUrl = '$_base/terms';
  static const String legalIndexUrl = _base;

  /// One-line positioning used across the disclaimer UI.
  static const String tagline =
      'Shaka is a planning aid, not a safety device.';

  /// The core safety acknowledgement shown on the first-launch clickwrap.
  static const List<String> acknowledgements = [
    'Shaka is an informational planning aid — NOT a dive computer, safety '
        'device, or navigation tool.',
    'Spearfishing and freediving are dangerous. Conditions change fast and can '
        'differ from anything shown in the app.',
    'I am responsible for checking real conditions myself and for my own '
        'safety. When in doubt, I won\'t dive.',
    'I am 18 or older (or the age of majority where I live).',
  ];

  /// Short summary shown above the links on the in-app legal document screen.
  static const String summary =
      'Shaka turns ocean and satellite data into a dive score and fishing '
      'intel. It is a planning aid only — never a substitute for your own '
      'training, judgment, and a check of real conditions. Read the full Terms '
      'and Privacy Policy below.';
}
