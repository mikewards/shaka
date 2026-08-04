import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaka/data/models/spot_models.dart';
import 'package:shaka/presentation/widgets/wind_chart_card.dart';

/// Regression tests for the wind chart footer: zone-suffixed spot-local
/// times ("Peak 6 PM PDT") must fit the footer chips without overflowing
/// the card border at typical (and narrow) device widths.
void main() {
  // A day of hourly points peaking at 18:30 spot-local so footer times get
  // minutes AND a zone suffix ("6:30 PM PDT") — the longest realistic form.
  final dayStartUtc = DateTime.utc(2026, 8, 4, 7); // midnight PDT
  List<WindHourlyPoint> points() => [
        for (int h = 0; h < 24; h++)
          WindHourlyPoint(
            epochMs: dayStartUtc
                .add(Duration(hours: h, minutes: h == 18 ? 30 : 0))
                .millisecondsSinceEpoch,
            speedKts: h == 18 ? 14.2 : 5.0 + (h % 5),
            directionDeg: 200,
            gustKts: h == 18 ? 19.6 : 7.0 + (h % 5),
          ),
      ];

  Future<void> pumpCard(WidgetTester tester, double width) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: WindChartCard(
              points: points(),
              isToday: false,
              utcOffsetMinutes: -420,
              timezoneAbbr: 'PDT',
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('footer chips fit at typical phone width', (tester) async {
    await pumpCard(tester, 390 - 32); // screen minus page padding
    expect(tester.takeException(), isNull,
        reason: 'no RenderFlex overflow with zone-suffixed times');
    expect(find.textContaining('PDT'), findsWidgets);
  });

  // The test Ahem font renders every glyph at the full font size (~2x a real
  // font), so passing here means comfortable headroom on real devices.
  testWidgets('footer chips fit on a narrow 320px device', (tester) async {
    await pumpCard(tester, 320 - 32);
    expect(tester.takeException(), isNull);
  });
}
