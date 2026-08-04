import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaka/core/utils/unit_converter.dart';
import 'package:shaka/core/utils/wind_format.dart';
import 'package:shaka/data/models/spot_models.dart';
import 'package:shaka/data/services/unit_preference_service.dart';
import 'package:shaka/presentation/widgets/conditions_card.dart';
import 'package:shaka/presentation/widgets/swell_details_card.dart';

/// Cross-surface consistency test (Phase 4 of the wind audit): ONE fixture
/// reading rendered through every wind surface must produce the same numbers.
/// The audit found six surfaces disagreeing about the same wind (5 vs 6 kts,
/// m/s vs km/h, upwind vs downwind arrows); everything now routes through
/// WindFormat, and this test fails if any surface grows its own math again.
///
/// Fixture: 11.7 kts FROM 315° (NW), kind=hourlyForecast.
void main() {
  const speedKts = 11.7;
  const directionDeg = 315;
  const cardinal = 'NW';

  final conditions = SpotConditions(
    visibility: 'Blue water',
    waterTemp: '24°C',
    swell: '3.2ft @ 14s SW',
    wind: '12 kts NW', // preformatted legacy string (deprecated)
    tideState: 'rising',
    swellHeightFt: 3.2,
    swellPeriodSec: 14,
    swellDirection: 'SW',
    windSpeedKts: speedKts,
    windDirectionCardinal: cardinal,
    windDirectionDeg: directionDeg,
    windKind: 'hourlyForecast',
    windSource: 'open-meteo',
  );

  group('imperial: every surface renders 12 kts NW', () {
    const system = UnitSystem.imperial;

    test('surface 1 — conditions row / spot card formatter', () {
      expect(UnitConverter.formatWind(speedKts, cardinal, system), '12 kts NW');
      expect(UnitConverter.formatWindSpeed(speedKts, system), '12 kts');
    });

    test('surface 2 — wind chart header formatter', () {
      final speed = UnitConverter.formatWindSpeed(speedKts, system);
      final dir = WindFormat.cardinal(directionDeg);
      expect('$speed $dir', '12 kts NW');
    });

    test('surface 3 — ocean map probe cardinal (same table)', () {
      expect(WindFormat.cardinal(directionDeg.toDouble()), cardinal);
    });

    test('surface 4 — WindFormat directly (the source of truth)', () {
      expect(WindFormat.label(speedKts, cardinal, system), '12 kts NW');
    });

    testWidgets('surface 5 — ConditionsCard wind row', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ConditionsCard(conditions: conditions)),
      ));
      expect(find.text('12 kts NW'), findsOneWidget);
    });

    testWidgets('surface 6 — SwellDetailsCard wind row + compass pill',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SwellDetailsCard(conditions: conditions),
          ),
        ),
      ));
      // Row value (inside the expandable details; AnimatedCrossFade builds it
      // either way).
      expect(find.text('12 kts NW'), findsOneWidget);
      // Kind honesty label on the row.
      expect(find.text('Wind (forecast)'), findsOneWidget);
    });
  });

  group('metric: same reading, same km/h everywhere', () {
    const system = UnitSystem.metric;
    // 11.7 kts = 21.6684 km/h -> 22 km/h.

    test('all formatters agree on 22 km/h', () {
      expect(UnitConverter.formatWindSpeed(speedKts, system), '22 km/h');
      expect(WindFormat.speedLabel(speedKts, system), '22 km/h');
      expect(WindFormat.label(speedKts, cardinal, system), '22 km/h NW');
      // Ocean map probe gets the same reading as m/s (21.6684 km/h =
      // 6.019 m/s) and must land on the same 22 km/h.
      const asMs = speedKts * 1.852 / 3.6;
      expect(UnitConverter.formatChartWind(asMs, system), '22 km/h');
    });
  });

  group('live vs snapshot kind', () {
    testWidgets('live reading relabels the SwellDetailsCard row',
        (tester) async {
      const live = LiveWind(
        windSpeedKts: 14.2,
        windDirectionCardinal: 'W',
        windDirectionDeg: 270,
        retrievedAt: 0,
        windKind: 'live',
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SwellDetailsCard(conditions: conditions, liveWind: live),
          ),
        ),
      ));
      expect(find.text('Wind (live)'), findsOneWidget);
      expect(find.text('14 kts W'), findsOneWidget);
    });
  });
}
