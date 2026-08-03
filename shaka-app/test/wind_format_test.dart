import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaka/core/utils/wind_format.dart';
import 'package:shaka/data/services/unit_preference_service.dart';

/// Golden-value tests for the shared WindFormat module (Phase 4 of the wind
/// audit). These pin the ONE cardinal table, the ONE rounding rule and the
/// arrow convention so a refactor can't silently reintroduce the divergent
/// helpers this module replaced.
void main() {
  group('cardinal table', () {
    test('sector centers', () {
      expect(WindFormat.cardinal(0), 'N');
      expect(WindFormat.cardinal(22.5), 'NNE');
      expect(WindFormat.cardinal(45), 'NE');
      expect(WindFormat.cardinal(90), 'E');
      expect(WindFormat.cardinal(135), 'SE');
      expect(WindFormat.cardinal(180), 'S');
      expect(WindFormat.cardinal(225), 'SW');
      expect(WindFormat.cardinal(270), 'W');
      expect(WindFormat.cardinal(315), 'NW');
      expect(WindFormat.cardinal(337.5), 'NNW');
    });

    test('sector boundaries round to nearest', () {
      expect(WindFormat.cardinal(11.24), 'N');
      expect(WindFormat.cardinal(11.25), 'NNE');
      expect(WindFormat.cardinal(348.74), 'NNW');
      expect(WindFormat.cardinal(348.75), 'N');
    });

    test('normalizes out-of-range bearings', () {
      expect(WindFormat.cardinal(360), 'N');
      expect(WindFormat.cardinal(365), 'N');
      expect(WindFormat.cardinal(-10), 'N');
      expect(WindFormat.cardinal(-90), 'W');
      expect(WindFormat.cardinal(720 + 90), 'E');
    });

    test('cardinalToDegrees round-trips every label', () {
      for (final label in WindFormat.cardinals) {
        final deg = WindFormat.cardinalToDegrees(label);
        expect(deg, isNotNull);
        expect(WindFormat.cardinal(deg!), label,
            reason: '$label -> $deg -> ${WindFormat.cardinal(deg)}');
      }
      expect(WindFormat.cardinalToDegrees('nw'), 315); // case-insensitive
      expect(WindFormat.cardinalToDegrees('bogus'), isNull);
    });
  });

  group('conversions', () {
    test('exact factors', () {
      expect(WindFormat.knotsToKmh(10), closeTo(18.52, 1e-9));
      expect(WindFormat.kmhToKnots(1.852), closeTo(1.0, 1e-9));
      expect(WindFormat.msToKnots(1), closeTo(1.94384, 1e-9));
      expect(WindFormat.msToKmh(10), closeTo(36.0, 1e-9));
    });

    test('round-trip stability', () {
      expect(WindFormat.kmhToKnots(WindFormat.knotsToKmh(7.3)),
          closeTo(7.3, 1e-9));
    });
  });

  group('speed labels — the ONE rounding rule (half away from zero)', () {
    test('imperial', () {
      expect(WindFormat.speedLabel(5.7, UnitSystem.imperial), '6 kts');
      expect(WindFormat.speedLabel(6.4, UnitSystem.imperial), '6 kts');
      expect(WindFormat.speedLabel(6.5, UnitSystem.imperial), '7 kts');
      expect(WindFormat.speedLabel(0.4, UnitSystem.imperial), '0 kts');
    });

    test('metric converts THEN rounds', () {
      // 10 kts = 18.52 km/h -> 19, not round(10)*1.852 = 18.52 -> 19. Same
      // here, but 8.9 kts = 16.48 km/h -> 16, while round-first would give
      // 9 * 1.852 = 16.67 -> 17.
      expect(WindFormat.speedLabel(10, UnitSystem.metric), '19 km/h');
      expect(WindFormat.speedLabel(8.9, UnitSystem.metric), '16 km/h');
    });

    test('null is N/A, never a fabricated zero', () {
      expect(WindFormat.speedLabel(null, UnitSystem.imperial), 'N/A');
      expect(WindFormat.label(null, 'W', UnitSystem.imperial), 'N/A');
    });

    test('label appends FROM cardinal', () {
      expect(WindFormat.label(6.7, 'W', UnitSystem.imperial), '7 kts W');
      expect(WindFormat.label(6.7, null, UnitSystem.imperial), '7 kts');
    });
  });

  group('map wind attribution (ECMWF offshore)', () {
    test('spotLocalClock uses offset + zone abbr', () {
      final utc = DateTime.utc(2026, 8, 3, 21); // 2:00 PM PDT
      expect(
        WindFormat.spotLocalClock(utc,
            utcOffsetMinutes: -420, timezoneAbbr: 'PDT'),
        '2:00 PM PDT',
      );
    });

    test('spotLocalClock falls back to device-local without zone', () {
      final utc = DateTime.utc(2026, 8, 3, 21);
      final label = WindFormat.spotLocalClock(utc);
      // Device zone varies; just assert shape "H:MM AM/PM" with no trailing abbr.
      expect(label, matches(RegExp(r'^\d{1,2}:\d{2} (AM|PM)$')));
    });

    test('mapWindAttribution and mapProbeWindLabel', () {
      final utc = DateTime.utc(2026, 8, 3, 21);
      expect(
        WindFormat.mapWindAttribution(
          validAtUtc: utc,
          utcOffsetMinutes: -420,
          timezoneAbbr: 'PDT',
        ),
        'ECMWF offshore model · valid 2:00 PM PDT',
      );
      expect(
        WindFormat.mapProbeWindLabel(
          speedAndCardinal: '11.4 kts W',
          validAtUtc: utc,
          utcOffsetMinutes: -420,
          timezoneAbbr: 'PDT',
        ),
        '11.4 kts W · ECMWF offshore model · valid 2:00 PM PDT',
      );
      expect(WindFormat.mapWindAttribution(), 'ECMWF offshore model');
    });
  });

  group('WindArrow rotation', () {
    Future<double> pumpAndReadAngle(WidgetTester tester, WindArrow arrow) async {
      await tester.pumpWidget(
          MaterialApp(home: Center(child: arrow)));
      final transform = tester.widget<Transform>(find.byType(Transform));
      // Transform.rotate builds a rotationZ matrix; recover the angle.
      final m = transform.transform;
      return atan2(m.entry(1, 0), m.entry(0, 0));
    }

    testWidgets('north wind points downwind (south) by default',
        (tester) async {
      final angle = await pumpAndReadAngle(
          tester, const WindArrow(fromDegrees: 0, color: Colors.white));
      // 180° in radians, normalized by atan2 to ±pi.
      expect(angle.abs(), closeTo(pi, 1e-6));
    });

    testWidgets('west wind (270°) flies east', (tester) async {
      final angle = await pumpAndReadAngle(
          tester, const WindArrow(fromDegrees: 270, color: Colors.white));
      // 270 + 180 = 450 -> 90°.
      expect(angle, closeTo(pi / 2, 1e-6));
    });

    testWidgets('pointsDownwind=false points AT the bearing (flow/TO data)',
        (tester) async {
      final angle = await pumpAndReadAngle(
        tester,
        const WindArrow(
            fromDegrees: 90, pointsDownwind: false, color: Colors.white),
      );
      expect(angle, closeTo(pi / 2, 1e-6));
    });
  });
}
