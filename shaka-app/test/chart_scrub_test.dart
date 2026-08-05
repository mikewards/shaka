import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaka/core/utils/unit_converter.dart';
import 'package:shaka/core/utils/wind_format.dart';
import 'package:shaka/data/models/spot_models.dart';
import 'package:shaka/data/services/live_wind_service.dart';
import 'package:shaka/data/services/unit_preference_service.dart';
import 'package:shaka/presentation/widgets/chart_scrub.dart';
import 'package:shaka/presentation/widgets/swell_chart_card.dart';
import 'package:shaka/presentation/widgets/tide_chart_card.dart';
import 'package:shaka/presentation/widgets/wind_chart_card.dart';

/// Plain text of the scrubbed kind+time label (rendered as rich text when
/// the reset affordance is appended).
String _scrubLabelText(WidgetTester tester) {
  final t = tester.widget<Text>(find.textContaining('Forecast \u00b7'));
  return t.data ?? t.textSpan!.toPlainText();
}

/// Interactive time-scrubbing on the spot-detail charts: dragging/tapping the
/// chart moves the marker, the header value+time follow the scrubbed instant,
/// and the kind label switches honestly (never "Live" while scrubbed).
void main() {
  const utcOffset = -420; // PDT
  const tz = 'PDT';

  /// x position inside the scrubber that maps to [ms], mirroring the chart
  /// painters' time->x mapping.
  Offset posAt(WidgetTester tester, int firstMs, int lastMs, int ms) {
    final rect = tester.getRect(find.byType(ChartTimeScrubber));
    final chartW =
        rect.width - ChartTimeScrubber.leftPad - ChartTimeScrubber.rightPad;
    final frac = (ms - firstMs) / (lastMs - firstMs);
    return Offset(
        rect.left + ChartTimeScrubber.leftPad + frac * chartW, rect.center.dy);
  }

  String clock(int ms) => WindFormat.compactClock(
        DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
        utcOffsetMinutes: utcOffset,
        timezoneAbbr: tz,
      );

  /// Tap-to-position: the tap-down is delivered to the scrubber after the
  /// tap recognizer's deadline, so pump a little simulated time.
  Future<void> scrubTapAt(WidgetTester tester, Offset at) async {
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Reset via the header label's "× reset" affordance.
  Future<void> tapReset(WidgetTester tester) async {
    await tester.tap(find.textContaining('\u00d7 reset'));
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('ChartScrubMath', () {
    test('lerpAt interpolates linearly between samples and clamps', () {
      final xs = [0, 100, 200];
      final ys = <double?>[10.0, 20.0, 40.0];
      expect(ChartScrubMath.lerpAt(xs, ys, 50), 15.0);
      expect(ChartScrubMath.lerpAt(xs, ys, 150), 30.0);
      expect(ChartScrubMath.lerpAt(xs, ys, -5), 10.0);
      expect(ChartScrubMath.lerpAt(xs, ys, 999), 40.0);
    });

    test('lerpAt falls back to the neighbor across null samples', () {
      expect(ChartScrubMath.lerpAt([0, 100], [null, 20.0], 50), 20.0);
      expect(ChartScrubMath.lerpAt([0, 100], [10.0, null], 50), 10.0);
    });

    test('nearestIndex picks the closest sample', () {
      expect(ChartScrubMath.nearestIndex([0, 100, 200], 140), 1);
      expect(ChartScrubMath.nearestIndex([0, 100, 200], 160), 2);
    });
  });

  group('wind chart scrubbing', () {
    // Flat forecast curve (12 kts E) around a seeded live reading (5 kts SSW)
    // so the two header states are unambiguous.
    const spotId = 'scrub-spot';
    const live = LiveWind(
      windSpeedKts: 5.13,
      windDirectionCardinal: 'SSW',
      windDirectionDeg: 209,
      retrievedAt: 0,
      windKind: 'live',
    );
    late int firstMs;
    late int lastMs;

    List<WindHourlyPoint> points() {
      final start = DateTime.now().subtract(const Duration(hours: 12));
      final pts = [
        for (int h = 0; h <= 24; h++)
          WindHourlyPoint(
            epochMs: start.add(Duration(hours: h)).millisecondsSinceEpoch,
            speedKts: 12.0,
            directionDeg: 90,
          ),
      ];
      firstMs = pts.first.epochMs;
      lastMs = pts.last.epochMs;
      return pts;
    }

    setUp(() => LiveWindService.instance.debugSeed(spotId, live));
    tearDown(() => LiveWindService.instance.debugClear());

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WindChartCard(
              points: points(),
              isToday: true,
              spotId: spotId,
              utcOffsetMinutes: utcOffset,
              timezoneAbbr: tz,
            ),
          ),
        ),
      ));
    }

    testWidgets(
        'drag scrubs to a forecast sample, time follows, label never Live',
        (tester) async {
      await pump(tester);
      // Default: unified live reading.
      expect(find.text('5 kts SSW'), findsOneWidget);
      expect(find.textContaining('Live \u00b7'), findsOneWidget);

      // Scrub to +6h from now (move past touch slop so the horizontal drag
      // recognizer accepts, then settle on the exact target).
      final t1 = DateTime.now()
          .add(const Duration(hours: 6))
          .millisecondsSinceEpoch;
      final p1 = posAt(tester, firstMs, lastMs, t1);
      final gesture = await tester.startGesture(p1 - const Offset(24, 0));
      await gesture.moveTo(p1);
      await tester.pump();

      expect(find.text('12 kts E'), findsOneWidget,
          reason: 'header shows the forecast sample at the scrubbed time');
      expect(find.textContaining('Forecast \u00b7'), findsOneWidget);
      expect(find.textContaining('Live \u00b7'), findsNothing,
          reason: 'scrubbed readout must never claim Live');
      final label1 = _scrubLabelText(tester);
      expect(label1, contains(clock(t1)));

      // Keep dragging: the time readout updates live.
      final t2 = DateTime.now()
          .add(const Duration(hours: 10))
          .millisecondsSinceEpoch;
      await gesture.moveTo(posAt(tester, firstMs, lastMs, t2));
      await tester.pump();
      final label2 = _scrubLabelText(tester);
      expect(label2, isNot(label1));
      expect(label2, contains(clock(t2)),
          reason: 'readout tracks the scrubbed instant');

      // Release: the scrub position (and forecast labeling) persists.
      await gesture.up();
      await tester.pump();
      expect(find.textContaining('Forecast \u00b7'), findsOneWidget);
      expect(find.textContaining('Live \u00b7'), findsNothing);
    });

    testWidgets('tap positions the scrub; reset returns the live reading',
        (tester) async {
      await pump(tester);
      final t = DateTime.now()
          .add(const Duration(hours: 5))
          .millisecondsSinceEpoch;
      await scrubTapAt(tester, posAt(tester, firstMs, lastMs, t));
      expect(find.textContaining('Forecast \u00b7'), findsOneWidget);
      expect(find.text('12 kts E'), findsOneWidget);

      await tapReset(tester);
      expect(find.text('5 kts SSW'), findsOneWidget,
          reason: 'back at now: unified live reading again');
      expect(find.textContaining('Live \u00b7'), findsOneWidget);
    });

    testWidgets('scrubbing back onto now snaps to the live state',
        (tester) async {
      await pump(tester);
      final away = DateTime.now()
          .add(const Duration(hours: 5))
          .millisecondsSinceEpoch;
      final pAway = posAt(tester, firstMs, lastMs, away);
      final gesture = await tester.startGesture(pAway - const Offset(24, 0));
      await gesture.moveTo(pAway);
      await tester.pump();
      expect(find.textContaining('Forecast \u00b7'), findsOneWidget);

      final now = DateTime.now().millisecondsSinceEpoch;
      await gesture.moveTo(posAt(tester, firstMs, lastMs, now));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(find.textContaining('Live \u00b7'), findsOneWidget,
          reason: 'within the snap window the chart returns to now');
      expect(find.text('5 kts SSW'), findsOneWidget);
    });
  });

  group('swell chart scrubbing', () {
    late int firstMs;
    late int lastMs;

    // Height ramps 1.0 -> 13.0 ft across the day so every hour reads
    // differently.
    List<SwellHourlyPoint> points() {
      final start = DateTime.now().subtract(const Duration(hours: 12));
      final pts = [
        for (int h = 0; h <= 24; h++)
          SwellHourlyPoint(
            epochMs: start.add(Duration(hours: h)).millisecondsSinceEpoch,
            heightFt: 1.0 + h * 0.5,
            periodSec: 14,
            directionDeg: 225,
          ),
      ];
      firstMs = pts.first.epochMs;
      lastMs = pts.last.epochMs;
      return pts;
    }

    testWidgets('tap scrubs the header value and time readout',
        (tester) async {
      final pts = points();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SwellChartCard(
              points: pts,
              isToday: true,
              utcOffsetMinutes: utcOffset,
              timezoneAbbr: tz,
            ),
          ),
        ),
      ));
      // Default: nearest-hour sample with its own time readout.
      expect(find.textContaining('Forecast \u00b7 nearest hour'),
          findsOneWidget);

      // Tap exactly on the 18th sample (6h after now).
      final sample = pts[18];
      await scrubTapAt(tester, posAt(tester, firstMs, lastMs, sample.epochMs));

      final expectedHeight = UnitConverter.formatChartWaveHeight(
          UnitConverter.feetToMeters(sample.effectiveHeightFt),
          UnitSystem.imperial);
      expect(find.text('$expectedHeight @ 14s SW'), findsOneWidget,
          reason: 'header shows the sample at the scrubbed time');
      expect(_scrubLabelText(tester),
          startsWith('Forecast \u00b7 ${clock(sample.epochMs)}'));
    });
  });

  group('tide chart scrubbing', () {
    late int firstMs;
    late int lastMs;

    TideChartData tide() {
      final start = DateTime.now().subtract(const Duration(hours: 12));
      final pts = [
        for (int h = 0; h <= 24; h++)
          TidePoint(
            epochMs: start.add(Duration(hours: h)).millisecondsSinceEpoch,
            heightFt: 0.5 + h * 0.25, // steadily rising
          ),
      ];
      firstMs = pts.first.epochMs;
      lastMs = pts.last.epochMs;
      return TideChartData(
        provider: 'test',
        stationId: 's1',
        stationName: 'Test Station',
        stationDistanceMi: 1.0,
        datum: 'MLLW',
        timezoneId: 'America/Los_Angeles',
        points: pts,
        extremes: const [],
        currentHeightFt: 3.5,
        currentStage: 'rising',
        available: true,
        localDate: '2026-08-04',
      );
    }

    testWidgets('scrub shows the predicted height+stage at that time',
        (tester) async {
      final data = tide();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TideChartCard(
              tide: data,
              utcOffsetMinutes: utcOffset,
              timezoneAbbr: tz,
            ),
          ),
        ),
      ));
      // Default: the current reading, labeled as now.
      final nowHeight = UnitConverter.formatTideHeight(
          data.currentHeightFt, UnitSystem.imperial);
      expect(find.text('$nowHeight Rising'), findsOneWidget);
      expect(find.textContaining('Now \u00b7'), findsOneWidget);

      // Tap on the 18th sample (6h ahead).
      final sample = data.points[18];
      await scrubTapAt(tester, posAt(tester, firstMs, lastMs, sample.epochMs));

      final expected = UnitConverter.formatTideHeight(
          sample.heightFt, UnitSystem.imperial);
      expect(find.text('$expected Rising'), findsOneWidget,
          reason: 'interpolated height + slope-derived stage at scrub time');
      expect(find.textContaining('Predicted \u00b7 ${clock(sample.epochMs)}'),
          findsOneWidget);
      expect(find.textContaining('Now \u00b7'), findsNothing,
          reason: 'scrubbed readout must not claim to be now');

      // Reset: back to the current reading.
      await tapReset(tester);
      expect(find.text('$nowHeight Rising'), findsOneWidget);
      expect(find.textContaining('Now \u00b7'), findsOneWidget);
    });
  });
}
