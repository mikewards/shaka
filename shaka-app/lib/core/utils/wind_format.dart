import 'dart:math';
import 'package:flutter/material.dart';
import '../../data/services/unit_preference_service.dart';

/// Single source of truth for wind presentation.
///
/// Every wind surface in the app (conditions card, swell details compass,
/// wind chart, ocean forecast probes, explore cards) must format wind through
/// this module so a given reading renders identically everywhere:
/// - ONE cardinal table (16-point, 22.5° sectors, round-to-nearest),
/// - ONE rounding rule (round(), matching the server's preformatted strings),
/// - ONE set of unit conversions,
/// - ONE arrow widget ([WindArrow]) with an explicit downwind flag.
class WindFormat {
  WindFormat._();

  /// 16-point compass rose, index 0 = N, step 22.5°.
  static const List<String> cardinals = [
    'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
    'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
  ];

  static const Map<String, double> _cardinalDegrees = {
    'N': 0, 'NNE': 22.5, 'NE': 45, 'ENE': 67.5,
    'E': 90, 'ESE': 112.5, 'SE': 135, 'SSE': 157.5,
    'S': 180, 'SSW': 202.5, 'SW': 225, 'WSW': 247.5,
    'W': 270, 'WNW': 292.5, 'NW': 315, 'NNW': 337.5,
  };

  // --- Conversions (exact factors, one definition) ---

  static const double _ktsToKmh = 1.852; // knot is exactly 1.852 km/h
  static const double _msToKts = 1.94384;

  static double knotsToKmh(double kts) => kts * _ktsToKmh;
  static double kmhToKnots(double kmh) => kmh / _ktsToKmh;
  static double msToKnots(double ms) => ms * _msToKts;
  static double msToKmh(double ms) => ms * 3.6;

  // --- Direction ---

  /// 16-point compass label for a meteorological FROM bearing in degrees.
  /// Accepts any real number (normalizes into [0, 360)).
  static String cardinal(num degreesFrom) {
    final norm = ((degreesFrom % 360) + 360) % 360;
    return cardinals[(norm / 22.5).round() % 16];
  }

  /// Center bearing of a 16-point cardinal label, or null if not a cardinal.
  /// Only for legacy string payloads — prefer numeric `windDirectionDeg`.
  static double? cardinalToDegrees(String cardinal) =>
      _cardinalDegrees[cardinal.trim().toUpperCase()];

  // --- Speed formatting: the ONE rounding rule (round-half-up via round()) ---

  /// "12 kts" / "22 km/h". Converts first, then rounds, so metric and
  /// imperial views always describe the same underlying value.
  static String speedLabel(double? speedKts, UnitSystem system) {
    if (speedKts == null) return 'N/A';
    if (system == UnitSystem.metric) {
      return '${knotsToKmh(speedKts).round()} km/h';
    }
    return '${speedKts.round()} kts';
  }

  /// "12 kts NW" — speed plus optional FROM cardinal.
  static String label(double? speedKts, String? cardinal, UnitSystem system) {
    if (speedKts == null) return 'N/A';
    final speed = speedLabel(speedKts, system);
    return cardinal != null ? '$speed $cardinal' : speed;
  }

  // --- Ocean-map wind (ECMWF 0.25° raster) attribution ---

  /// Source label for the weather-CDN wind layer. Matches Phase 3 kind honesty:
  /// the map is a coarse offshore model, not the spot's nearshore forecast.
  static const String mapWindSource = 'ECMWF offshore model';

  /// Subtle caption shown on wind-layer map surfaces so sheltered/lee spots
  /// (e.g. Casino Point) aren't read as a contradiction of the spot forecast.
  static const String mapWindHint =
      'Offshore model (25 km) — sheltered spots may differ from the spot forecast';

  /// Spot-local wall clock for map/probe labels, e.g. "2:00 PM PDT".
  /// When [utcOffsetMinutes] is null, falls back to device-local with no zone.
  static String spotLocalClock(
    DateTime utc, {
    int? utcOffsetMinutes,
    String? timezoneAbbr,
  }) {
    final dt = utcOffsetMinutes != null
        ? utc.toUtc().add(Duration(minutes: utcOffsetMinutes))
        : utc.toLocal();
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    final abbr =
        utcOffsetMinutes != null && timezoneAbbr != null ? ' $timezoneAbbr' : '';
    return '$hour12:$minute $ampm$abbr';
  }

  /// Kind + valid-time attribution for a map wind probe, e.g.
  /// "ECMWF offshore model · valid 2:00 PM PDT". Pair with the speed/cardinal
  /// line (Phase 3 two-line style) or join with " · " for a single chip line.
  static String mapWindAttribution({
    DateTime? validAtUtc,
    int? utcOffsetMinutes,
    String? timezoneAbbr,
  }) {
    if (validAtUtc == null) return mapWindSource;
    final clock = spotLocalClock(
      validAtUtc,
      utcOffsetMinutes: utcOffsetMinutes,
      timezoneAbbr: timezoneAbbr,
    );
    return '$mapWindSource \u00b7 valid $clock';
  }

  /// Full single-line probe label:
  /// "11.4 kts W · ECMWF offshore model · valid 2:00 PM PDT".
  static String mapProbeWindLabel({
    required String speedAndCardinal,
    DateTime? validAtUtc,
    int? utcOffsetMinutes,
    String? timezoneAbbr,
  }) {
    return '$speedAndCardinal \u00b7 ${mapWindAttribution(
      validAtUtc: validAtUtc,
      utcOffsetMinutes: utcOffsetMinutes,
      timezoneAbbr: timezoneAbbr,
    )}';
  }
}

/// The single wind/flow direction arrow.
///
/// [fromDegrees] is the meteorological FROM bearing (0 = wind from the north).
/// With [pointsDownwind] true — the default and the convention used by Windy,
/// Windguru and Surfline — the arrow flies WITH the wind (a north wind renders
/// an arrow pointing down/south). Pass false only for bearings that are
/// already flow/TO directions (e.g. ocean currents), where the arrow should
/// point AT the given bearing.
class WindArrow extends StatelessWidget {
  final num fromDegrees;
  final bool pointsDownwind;
  final Color color;
  final double size;
  final IconData icon;

  const WindArrow({
    super.key,
    required this.fromDegrees,
    this.pointsDownwind = true,
    required this.color,
    this.size = 12,
    this.icon = Icons.navigation,
  });

  @override
  Widget build(BuildContext context) {
    // Icons.navigation points up (north) at 0 rotation.
    final bearing = pointsDownwind ? fromDegrees + 180 : fromDegrees;
    return Transform.rotate(
      angle: bearing * pi / 180.0,
      child: Icon(icon, size: size, color: color),
    );
  }
}
