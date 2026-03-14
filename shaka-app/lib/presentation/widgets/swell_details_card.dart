import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/models/spot_models.dart';

class _ParsedSwell {
  final double heightFt;
  final int periodSec;
  final String cardinal;
  final double degrees;

  const _ParsedSwell({
    required this.heightFt,
    required this.periodSec,
    required this.cardinal,
    required this.degrees,
  });
}

const _cardinalToDegrees = <String, double>{
  'N': 0, 'NNE': 22.5, 'NE': 45, 'ENE': 67.5,
  'E': 90, 'ESE': 112.5, 'SE': 135, 'SSE': 157.5,
  'S': 180, 'SSW': 202.5, 'SW': 225, 'WSW': 247.5,
  'W': 270, 'WNW': 292.5, 'NW': 315, 'NNW': 337.5,
};

final _swellRegex = RegExp(r'([\d.]+)ft\s*@\s*(\d+)s\s+(\w+)');

_ParsedSwell? _parseSwell(String s) {
  final m = _swellRegex.firstMatch(s);
  if (m == null) return null;
  final cardinal = m.group(3)!;
  final deg = _cardinalToDegrees[cardinal];
  if (deg == null) return null;
  return _ParsedSwell(
    heightFt: double.tryParse(m.group(1)!) ?? 0,
    periodSec: int.tryParse(m.group(2)!) ?? 0,
    cardinal: cardinal,
    degrees: deg,
  );
}

/// Expandable card for detailed swell & exposure data with compass visualization.
///
/// COLLAPSED: Shows the swell-at-spot value (e.g., "3.2ft @ 14s SW").
/// EXPANDED: Swell rows with directional badges, then a compass rose showing
/// all swell vectors and the spot's exposure arc.
class SwellDetailsCard extends StatefulWidget {
  final SpotConditions conditions;

  const SwellDetailsCard({super.key, required this.conditions});

  @override
  State<SwellDetailsCard> createState() => _SwellDetailsCardState();
}

class _SwellDetailsCardState extends State<SwellDetailsCard> {
  bool _expanded = false;

  static const _cardColor = Color(0xFF1A1A1A);
  static const _borderColor = Color(0xFF2A2A2A);
  static const _primaryColor = Color(0xFF2DD4BF);
  static const _secondaryColor = Color(0xFF60A5FA);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          _buildHeader(),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: _buildExpandedContent(),
            crossFadeState:
                _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final swellValue =
        widget.conditions.swellCorrected ?? widget.conditions.swell;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _expanded = !_expanded);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                swellValue,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: _expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 250),
              child: const Icon(
                Icons.keyboard_arrow_down,
                size: 20,
                color: Colors.white38,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedContent() {
    final c = widget.conditions;

    // (label, value, parsedSwell, badgeColor)
    final items = <(String, String, _ParsedSwell?, Color?)>[];

    if (c.swellCorrected != null) {
      items.add(('Swell (at spot)', c.swellCorrected!, _parseSwell(c.swellCorrected!), _primaryColor));
      if (c.swellCorrected != c.swell) {
        items.add(('Swell (open ocean)', c.swell, _parseSwell(c.swell), _primaryColor));
      }
    } else {
      items.add(('Swell', c.swell, _parseSwell(c.swell), _primaryColor));
    }

    if (c.secondarySwell != null) {
      if (c.secondarySwellCorrected != null) {
        items.add(('2nd Swell (at spot)', c.secondarySwellCorrected!, _parseSwell(c.secondarySwellCorrected!), _secondaryColor));
        if (c.secondarySwellCorrected != c.secondarySwell) {
          items.add(('2nd Swell (open ocean)', c.secondarySwell!, _parseSwell(c.secondarySwell!), _secondaryColor));
        }
      } else {
        items.add(('2nd Swell', c.secondarySwell!, _parseSwell(c.secondarySwell!), _secondaryColor));
      }
    }

    if (c.exposureBearing != null) {
      items.add((
        'Exposure',
        'Faces ${_bearingToCardinal(c.exposureBearing!)} (${c.exposureWidth ?? 0}°)',
        null,
        null,
      ));
    }

    // Deduplicate by direction for the compass (first per-direction wins = corrected)
    final compassSwells = <(_ParsedSwell, Color)>[];
    for (final item in items) {
      if (item.$3 != null && item.$4 != null) {
        final alreadyAdded = compassSwells.any((s) => s.$1.degrees == item.$3!.degrees);
        if (!alreadyAdded) {
          compassSwells.add((item.$3!, item.$4!));
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 1, color: Colors.white10),
          for (int i = 0; i < items.length; i++)
            _buildRow(
              items[i].$1,
              items[i].$2,
              parsedSwell: items[i].$3,
              swellColor: items[i].$4,
              isLast: i == items.length - 1,
            ),
          if (compassSwells.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: Colors.white10),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 1.0,
              child: CustomPaint(
                painter: _SwellCompassPainter(
                  swells: compassSwells,
                  exposureBearing: c.exposureBearing?.toDouble(),
                  exposureWidth: c.exposureWidth?.toDouble(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(
    String label,
    String value, {
    _ParsedSwell? parsedSwell,
    Color? swellColor,
    bool isLast = false,
  }) {
    return Container(
      padding: EdgeInsets.only(top: 10, bottom: isLast ? 4 : 10),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          if (parsedSwell != null && swellColor != null) ...[
            _SwellDirectionBadge(
              degrees: parsedSwell.degrees,
              color: swellColor,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  static String _bearingToCardinal(int degrees) {
    const dirs = [
      'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
    ];
    return dirs[((degrees % 360) / 22.5).round() % 16];
  }
}

/// Small circular badge with a rotated arrow showing swell source direction.
class _SwellDirectionBadge extends StatelessWidget {
  final double degrees;
  final Color color;

  const _SwellDirectionBadge({required this.degrees, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Transform.rotate(
        angle: (degrees + 180) * pi / 180,
        child: Icon(Icons.navigation, size: 13, color: color),
      ),
    );
  }
}

/// Compass rose showing swell arrows and exposure arc via CustomPainter.
/// Only repaints when swell data or exposure changes.
class _SwellCompassPainter extends CustomPainter {
  final List<(_ParsedSwell, Color)> swells;
  final double? exposureBearing;
  final double? exposureWidth;

  _SwellCompassPainter({
    required this.swells,
    this.exposureBearing,
    this.exposureWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 16;

    // Exposure behind everything so it never clips arrows
    if (exposureBearing != null && exposureWidth != null && exposureWidth! > 0) {
      _drawExposureArc(canvas, center, radius);
    }

    _drawReferenceRings(canvas, center, radius);
    _drawCardinalLabels(canvas, center, radius);
    _drawSwellArrows(canvas, center, radius);
  }

  void _drawReferenceRings(Canvas canvas, Offset center, double radius) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, radius * i / 3, paint);
    }
  }

  void _drawCardinalLabels(Canvas canvas, Offset center, double radius) {
    const labels = ['N', 'E', 'S', 'W'];
    const bearings = [0.0, 90.0, 180.0, 270.0];

    for (int i = 0; i < labels.length; i++) {
      final b = bearings[i] * pi / 180;
      final offset = Offset(
        center.dx + (radius + 10) * sin(b),
        center.dy - (radius + 10) * cos(b),
      );

      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(canvas, Offset(offset.dx - tp.width / 2, offset.dy - tp.height / 2));
    }
  }

  void _drawExposureArc(Canvas canvas, Offset center, double radius) {
    final bearing = exposureBearing!;
    final width = exposureWidth!;

    // Convert compass bearing to Canvas arc angles (0 = east, clockwise)
    final startAngle = (bearing - width / 2 - 90) * pi / 180;
    final sweepAngle = width * pi / 180;

    final fillPaint = Paint()
      ..color = const Color(0xFFD4A037).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final sectorPath = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
      )
      ..close();

    canvas.drawPath(sectorPath, fillPaint);

    final outlinePaint = Paint()
      ..color = const Color(0xFFD4A037).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      outlinePaint,
    );
  }

  void _drawSwellArrows(Canvas canvas, Offset center, double radius) {
    if (swells.isEmpty) return;

    final maxHeight = swells.map((s) => s.$1.heightFt).reduce(max);
    if (maxHeight <= 0) return;

    // Primary first (background), secondary on top so it's always visible
    for (int idx = 0; idx < swells.length; idx++) {
      final (swell, color) = swells[idx];
      final isPrimary = idx == 0;
      final b = swell.degrees * pi / 180;

      final scaleFactor = isPrimary ? 1.0 : 0.65;
      final normalizedLen = (swell.heightFt / maxHeight).clamp(0.4, 1.0);
      final arrowLen = radius * 0.75 * normalizedLen * scaleFactor;
      final baseWidth = isPrimary ? 26.0 : 17.0;
      final notchDepth = isPrimary ? 10.0 : 6.0;

      final startPt = Offset(
        center.dx + radius * 0.93 * sin(b),
        center.dy - radius * 0.93 * cos(b),
      );
      final endPt = Offset(
        center.dx + (radius * 0.93 - arrowLen) * sin(b),
        center.dy - (radius * 0.93 - arrowLen) * cos(b),
      );

      final arrowAngle = atan2(endPt.dy - startPt.dy, endPt.dx - startPt.dx);
      final perpAngle = arrowAngle + pi / 2;

      // Navigation-style kite: pointed tip → wide base with V-notch
      final arrowPath = Path()
        ..moveTo(endPt.dx, endPt.dy)
        ..lineTo(
          startPt.dx + baseWidth / 2 * cos(perpAngle),
          startPt.dy + baseWidth / 2 * sin(perpAngle),
        )
        ..lineTo(
          startPt.dx + notchDepth * cos(arrowAngle),
          startPt.dy + notchDepth * sin(arrowAngle),
        )
        ..lineTo(
          startPt.dx - baseWidth / 2 * cos(perpAngle),
          startPt.dy - baseWidth / 2 * sin(perpAngle),
        )
        ..close();

      canvas.drawPath(arrowPath, Paint()..color = color.withValues(alpha: 0.85));
    }

    // Labels in second pass, always on top of all arrow shapes
    for (int idx = 0; idx < swells.length; idx++) {
      final (swell, color) = swells[idx];
      final isPrimary = idx == 0;
      final b = swell.degrees * pi / 180;

      final scaleFactor = isPrimary ? 1.0 : 0.65;
      final normalizedLen = (swell.heightFt / maxHeight).clamp(0.4, 1.0);
      final arrowLen = radius * 0.75 * normalizedLen * scaleFactor;

      final startPt = Offset(
        center.dx + radius * 0.93 * sin(b),
        center.dy - radius * 0.93 * cos(b),
      );
      final endPt = Offset(
        center.dx + (radius * 0.93 - arrowLen) * sin(b),
        center.dy - (radius * 0.93 - arrowLen) * cos(b),
      );

      final ht = swell.heightFt;
      final htStr = ht == ht.roundToDouble()
          ? '${ht.round()}ft'
          : '${ht.toStringAsFixed(1)}ft';
      final label = '$htStr ${swell.periodSec}s';

      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.95),
            fontSize: isPrimary ? 12 : 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Place label at ~30% from base (widest part of the kite)
      final labelCenter = Offset(
        startPt.dx + (endPt.dx - startPt.dx) * 0.3,
        startPt.dy + (endPt.dy - startPt.dy) * 0.3,
      );

      final arrowAngle = atan2(endPt.dy - startPt.dy, endPt.dx - startPt.dx);

      // Rotate text to align with arrow, keeping it readable (never upside-down)
      var textAngle = arrowAngle;
      if (textAngle > pi / 2) textAngle -= pi;
      if (textAngle < -pi / 2) textAngle += pi;

      canvas.save();
      canvas.translate(labelCenter.dx, labelCenter.dy);
      canvas.rotate(textAngle);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SwellCompassPainter oldDelegate) {
    return swells.length != oldDelegate.swells.length ||
        exposureBearing != oldDelegate.exposureBearing ||
        exposureWidth != oldDelegate.exposureWidth;
  }
}
