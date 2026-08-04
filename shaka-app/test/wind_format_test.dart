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

  group('gust suffix — hidden unless it DISPLAYS above the speed', () {
    test('raw gust above speed but same rounded number is hidden', () {
      // The Avalon Bank case: speed 3.73 -> "4", gust 4.48 -> "4". Printing
      // "4 kts G4" is noise even though raw gust > raw speed.
      expect(WindFormat.gustSuffix(3.73, 4.48, UnitSystem.imperial), '');
    });

    test('shown when the rounded gust exceeds the rounded speed', () {
      expect(WindFormat.gustSuffix(4.4, 6.6, UnitSystem.imperial), ' G7');
      expect(WindFormat.gustSuffix(12.0, 18.2, UnitSystem.imperial), ' G18');
    });

    test('null gust is empty', () {
      expect(WindFormat.gustSuffix(5.0, null, UnitSystem.imperial), '');
    });

    test('metric compares converted display values', () {
      // 10 kts = 18.52 -> 19 km/h; 10.4 kts = 19.26 -> 19 km/h: hidden.
      expect(WindFormat.gustSuffix(10.0, 10.4, UnitSystem.metric), '');
      // 12 kts = 22.2 -> 22 km/h: shown.
      expect(WindFormat.gustSuffix(10.0, 12.0, UnitSystem.metric), ' G22');
    });
  });

  group('map wind attribution (compact, single-line)', () {
    final utc = DateTime.utc(2026, 8, 3, 21); // 2:00 PM PDT

    test('compactClock drops :00 minutes and appends zone', () {
      expect(
        WindFormat.compactClock(utc, utcOffsetMinutes: -420, timezoneAbbr: 'PDT'),
        '2 PM PDT',
      );
      expect(
        WindFormat.compactClock(DateTime.utc(2026, 8, 3, 21, 30),
            utcOffsetMinutes: -420, timezoneAbbr: 'PDT'),
        '2:30 PM PDT',
      );
      expect(
        WindFormat.compactClock(DateTime.utc(2026, 8, 3, 19),
            utcOffsetMinutes: -600, timezoneAbbr: 'HST'),
        '9 AM HST',
      );
      // Midnight and noon render as 12, not 0.
      expect(
        WindFormat.compactClock(DateTime.utc(2026, 8, 3, 7),
            utcOffsetMinutes: -420, timezoneAbbr: 'PDT'),
        '12 AM PDT',
      );
      expect(
        WindFormat.compactClock(DateTime.utc(2026, 8, 3, 19),
            utcOffsetMinutes: -420, timezoneAbbr: 'PDT'),
        '12 PM PDT',
      );
    });

    test('compactClock falls back to device-local without zone label', () {
      final label = WindFormat.compactClock(utc);
      // Device zone varies; assert shape "H[:MM] AM/PM" with no trailing abbr.
      expect(label, matches(RegExp(r'^\d{1,2}(:\d{2})? (AM|PM)$')));
    });

    test('mapWindAttribution is short: "ECMWF · 2 PM PDT"', () {
      expect(
        WindFormat.mapWindAttribution(
          validAtUtc: utc,
          utcOffsetMinutes: -420,
          timezoneAbbr: 'PDT',
        ),
        'ECMWF · 2 PM PDT',
      );
      expect(WindFormat.mapWindAttribution(), 'ECMWF');
    });

    test('hint copy is one short grammatical line', () {
      expect(WindFormat.mapWindHint, 'Offshore model — sheltered spots may differ');
      expect(WindFormat.mapWindHint.contains('\n'), isFalse);
      expect(WindFormat.mapWindHint.length, lessThan(50));
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
