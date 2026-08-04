import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaka/presentation/widgets/ocean_probe_chip.dart';

/// A text is truncated when its render box is narrower than the painted
/// intrinsic width of its content (maxLines: 1 + ellipsis shrink-to-fit).
bool _isTruncated(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
  final painter = TextPainter(
    text: TextSpan(text: text, style: paragraph.text.style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  // Sub-pixel tolerance.
  return paragraph.size.width < painter.width - 0.5;
}

/// The embedded-card header at a typical phone width: icon + title + chip +
/// direction arrow, inside the card's 14px horizontal padding.
Widget _cardHeaderHost({required Widget chip, double width = 390}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const Icon(Icons.public, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Ocean Forecast',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                chip,
                Container(width: 22, height: 22, margin: const EdgeInsets.only(left: 6)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  const value = '7.5 kts W';
  const attribution = 'ECMWF \u00b7 2 PM PDT';

  group('OceanProbeChip — no truncation for typical content', () {
    testWidgets('card style inside the header row at phone width',
        (tester) async {
      await tester.pumpWidget(_cardHeaderHost(
        chip: const OceanProbeChip(
          value: value,
          attribution: attribution,
          accent: Colors.cyan,
          maxWidth: 190,
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(_isTruncated(tester, value), isFalse,
          reason: 'value line must render in full');
      expect(_isTruncated(tester, attribution), isFalse,
          reason: 'attribution line must render in full');
    });

    testWidgets('card style survives a narrow 320px device', (tester) async {
      await tester.pumpWidget(_cardHeaderHost(
        chip: const OceanProbeChip(
          value: value,
          attribution: attribution,
          accent: Colors.cyan,
          maxWidth: 190,
        ),
        width: 320,
      ));
      expect(tester.takeException(), isNull);
      expect(_isTruncated(tester, value), isFalse);
      expect(_isTruncated(tester, attribution), isFalse);
    });

    testWidgets('metric value with long cardinal fits', (tester) async {
      const metricValue = '14 km/h WNW';
      await tester.pumpWidget(_cardHeaderHost(
        chip: const OceanProbeChip(
          value: metricValue,
          attribution: attribution,
          accent: Colors.cyan,
          maxWidth: 190,
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(_isTruncated(tester, metricValue), isFalse);
    });

    testWidgets('full-screen map style centers untruncated', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: OceanProbeChip(
              value: value,
              attribution: attribution,
              accent: Colors.cyan,
              onMap: true,
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(_isTruncated(tester, value), isFalse);
      expect(_isTruncated(tester, attribution), isFalse);
    });
  });

  group('regression — the old Spacer + Flexible layout squeezed the chip', () {
    testWidgets('Spacer and Flexible split slack 50/50 and truncate',
        (tester) async {
      // Documents the bug the header fix removed: with a Spacer competing at
      // equal flex, the chip only gets half the row's free space.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: Row(
                children: [
                  const Icon(Icons.public, size: 18),
                  const SizedBox(width: 8),
                  const Text('Ocean Forecast',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Flexible(
                    child: OceanProbeChip(
                      value: value,
                      attribution: attribution,
                      accent: Colors.cyan,
                      maxWidth: 190,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(_isTruncated(tester, value) || _isTruncated(tester, attribution),
          isTrue,
          reason: 'old layout reproduces the reported ellipsis');
    });
  });
}
