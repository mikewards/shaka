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

// ── Satellite tile helpers ──────────────────────────────────────────────────

const _tileZoom = 14;
const _tileSize = 256.0;
const _arcgisBase =
    'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile';

int _lonToTileX(double lon, int z) =>
    ((lon + 180) / 360 * (1 << z)).floor();

int _latToTileY(double lat, int z) =>
    ((1 - log(tan(lat * pi / 180) + 1 / cos(lat * pi / 180)) / pi) / 2 *
            (1 << z))
        .floor();

double _lonToPixelX(double lon, int z) =>
    (lon + 180) / 360 * (1 << z) * 256;

double _latToPixelY(double lat, int z) =>
    (1 - log(tan(lat * pi / 180) + 1 / cos(lat * pi / 180)) / pi) / 2 *
    (1 << z) *
    256;

/// Returns 4 ArcGIS tile URLs forming a 2x2 grid centered on the spot.
List<String> _satelliteTileUrls(double lat, double lon) {
  const z = _tileZoom;
  final tx = _lonToTileX(lon, z);
  final ty = _latToTileY(lat, z);
  final localX = _lonToPixelX(lon, z) - tx * 256;
  final localY = _latToPixelY(lat, z) - ty * 256;

  // Pick the 2x2 quadrant that keeps the spot near the center
  final startTx = localX >= 128 ? tx : tx - 1;
  final startTy = localY >= 128 ? ty : ty - 1;

  return [
    '$_arcgisBase/$z/$startTy/$startTx',
    '$_arcgisBase/$z/$startTy/${startTx + 1}',
    '$_arcgisBase/$z/${startTy + 1}/$startTx',
    '$_arcgisBase/$z/${startTy + 1}/${startTx + 1}',
  ];
}

/// Pixel offset to translate the 2x2 grid so the spot is view-centered.
Offset _satelliteTileOffset(double lat, double lon, double viewWidth, double viewHeight) {
  const z = _tileZoom;
  final tx = _lonToTileX(lon, z);
  final ty = _latToTileY(lat, z);
  final localX = _lonToPixelX(lon, z) - tx * 256;
  final localY = _latToPixelY(lat, z) - ty * 256;

  final startTx = localX >= 128 ? tx : tx - 1;
  final startTy = localY >= 128 ? ty : ty - 1;

  final spotInGridX = _lonToPixelX(lon, z) - startTx * 256;
  final spotInGridY = _latToPixelY(lat, z) - startTy * 256;

  return Offset(viewWidth / 2 - spotInGridX, viewHeight / 2 - spotInGridY);
}

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
  final Coordinates? coordinates;

  const SwellDetailsCard({
    super.key,
    required this.conditions,
    this.coordinates,
  });

  /// Pre-warm satellite tiles into Flutter's image cache (fire-and-forget).
  static void precacheTiles(BuildContext context, double lat, double lon) {
    for (final url in _satelliteTileUrls(lat, lon)) {
      precacheImage(NetworkImage(url), context);
    }
  }

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

    // Deduplicate by (direction, swell category) so corrected/uncorrected
    // collapse but primary + secondary always both appear on the compass.
    final compassSwells = <(_ParsedSwell, Color)>[];
    for (final item in items) {
      if (item.$3 != null && item.$4 != null) {
        final alreadyAdded = compassSwells.any(
          (s) => s.$1.degrees == item.$3!.degrees && s.$2 == item.$4!,
        );
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewWidth = constraints.maxWidth;
                  final viewHeight = constraints.maxHeight;
                  final coords = widget.coordinates;
                  final tileUrls = coords != null
                      ? _satelliteTileUrls(coords.lat, coords.lon)
                      : null;
                  final tileOffset = coords != null
                      ? _satelliteTileOffset(coords.lat, coords.lon, viewWidth, viewHeight)
                      : null;

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: viewWidth,
                      height: viewHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Satellite imagery tiles
                          if (tileUrls != null && tileOffset != null)
                            for (int i = 0; i < 4; i++)
                              Positioned(
                                left: tileOffset.dx + (i % 2) * _tileSize,
                                top: tileOffset.dy + (i ~/ 2) * _tileSize,
                                child: Image.network(
                                  tileUrls[i],
                                  width: _tileSize,
                                  height: _tileSize,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      SizedBox(width: _tileSize, height: _tileSize),
                                ),
                              ),
                          // Compass rose
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _SwellCompassPainter(
                                swells: compassSwells,
                                exposureBearing: c.exposureBearing?.toDouble(),
                                exposureWidth: c.exposureWidth?.toDouble(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
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
/// All structural lines use the crosshair pattern: white border + black center.
class _SwellCompassPainter extends CustomPainter {
  final List<(_ParsedSwell, Color)> swells;
  final double? exposureBearing;
  final double? exposureWidth;

  _SwellCompassPainter({
    required this.swells,
    this.exposureBearing,
    this.exposureWidth,
  });

  static const _shadowStyle = [
    Shadow(color: Color(0xFF000000), blurRadius: 4),
    Shadow(color: Color(0xCC000000), blurRadius: 8),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 24;

    if (exposureBearing != null && exposureWidth != null && exposureWidth! > 0) {
      _drawExposureArc(canvas, center, radius);
    }

    _drawReferenceRings(canvas, center, radius);
    _drawCenterCrosshair(canvas, center);
    _drawCardinalLabels(canvas, center, radius);
    _drawSwellArrows(canvas, center, radius);
  }

  /// White border + black center — same pattern as the crosshair.
  void _drawReferenceRings(Canvas canvas, Offset center, double radius) {
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final centerPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (int i = 1; i <= 3; i++) {
      final r = radius * i / 3;
      canvas.drawCircle(center, r, borderPaint);
      canvas.drawCircle(center, r, centerPaint);
    }
  }

  void _drawCenterCrosshair(Canvas canvas, Offset center) {
    const gap = 8.0;
    const lineLen = 18.0;

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final centerPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    for (final paint in [borderPaint, centerPaint]) {
      canvas.drawLine(Offset(center.dx, center.dy - gap),
          Offset(center.dx, center.dy - gap - lineLen), paint);
      canvas.drawLine(Offset(center.dx, center.dy + gap),
          Offset(center.dx, center.dy + gap + lineLen), paint);
      canvas.drawLine(Offset(center.dx - gap, center.dy),
          Offset(center.dx - gap - lineLen, center.dy), paint);
      canvas.drawLine(Offset(center.dx + gap, center.dy),
          Offset(center.dx + gap + lineLen, center.dy), paint);
    }

    canvas.drawCircle(center, 3, Paint()..color = Colors.red);
  }

  void _drawCardinalLabels(Canvas canvas, Offset center, double radius) {
    const labels = ['N', 'E', 'S', 'W'];
    const bearings = [0.0, 90.0, 180.0, 270.0];

    for (int i = 0; i < labels.length; i++) {
      final b = bearings[i] * pi / 180;
      final offset = Offset(
        center.dx + (radius + 14) * sin(b),
        center.dy - (radius + 14) * cos(b),
      );

      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            shadows: _shadowStyle,
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

    final rect = Rect.fromCircle(center: center, radius: radius);

    // White border + black center pattern (matching crosshair/rings)
    canvas.drawArc(rect, startAngle, sweepAngle, false, Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5);

    canvas.drawArc(rect, startAngle, sweepAngle, false, Paint()
      ..color = const Color(0xFFD4A037).withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
  }

  void _drawSwellArrows(Canvas canvas, Offset center, double radius) {
    if (swells.isEmpty) return;

    final maxHeight = swells.map((s) => s.$1.heightFt).reduce(max);
    if (maxHeight <= 0) return;

    final primaryNorm = (swells[0].$1.heightFt / maxHeight).clamp(0.6, 1.0);
    final primaryTipR = radius * 0.93 - radius * 0.85 * primaryNorm;

    for (int idx = 0; idx < swells.length; idx++) {
      final (swell, color) = swells[idx];
      final isPrimary = idx == 0;
      final b = swell.degrees * pi / 180;

      final barWidth = isPrimary ? 26.0 : 16.0;
      final halfW = barWidth / 2;

      final normalizedLen = (swell.heightFt / maxHeight).clamp(0.6, 1.0);
      final arrowLen = radius * 0.85 * normalizedLen * (isPrimary ? 1.0 : 0.85);
      final outerR = isPrimary ? radius * 0.93 : primaryTipR + arrowLen;

      final startPt = Offset(
        center.dx + outerR * sin(b),
        center.dy - outerR * cos(b),
      );
      final endPt = Offset(
        center.dx + (outerR - arrowLen) * sin(b),
        center.dy - (outerR - arrowLen) * cos(b),
      );

      final arrowAngle = atan2(endPt.dy - startPt.dy, endPt.dx - startPt.dx);
      final perpAngle = arrowAngle + pi / 2;

      final baseR = Offset(
        startPt.dx + halfW * cos(perpAngle),
        startPt.dy + halfW * sin(perpAngle),
      );
      final baseL = Offset(
        startPt.dx - halfW * cos(perpAngle),
        startPt.dy - halfW * sin(perpAngle),
      );

      final ctrl1R = Offset(
        endPt.dx + (startPt.dx - endPt.dx) * 0.25 + halfW * 0.8 * cos(perpAngle),
        endPt.dy + (startPt.dy - endPt.dy) * 0.25 + halfW * 0.8 * sin(perpAngle),
      );
      final ctrl2R = Offset(
        endPt.dx + (startPt.dx - endPt.dx) * 0.50 + halfW * cos(perpAngle),
        endPt.dy + (startPt.dy - endPt.dy) * 0.50 + halfW * sin(perpAngle),
      );
      final ctrl2L = Offset(
        endPt.dx + (startPt.dx - endPt.dx) * 0.50 - halfW * cos(perpAngle),
        endPt.dy + (startPt.dy - endPt.dy) * 0.50 - halfW * sin(perpAngle),
      );
      final ctrl1L = Offset(
        endPt.dx + (startPt.dx - endPt.dx) * 0.25 - halfW * 0.8 * cos(perpAngle),
        endPt.dy + (startPt.dy - endPt.dy) * 0.25 - halfW * 0.8 * sin(perpAngle),
      );

      // C1-continuous base cap: control points along the backward tangent
      // so the curve is smooth where sides meet the rounded cap.
      final capDepth = halfW * 0.55;
      final backDx = -cos(arrowAngle);
      final backDy = -sin(arrowAngle);
      final baseCapCtrlR = Offset(
        baseR.dx + capDepth * backDx,
        baseR.dy + capDepth * backDy,
      );
      final baseCapCtrlL = Offset(
        baseL.dx + capDepth * backDx,
        baseL.dy + capDepth * backDy,
      );

      final arrowPath = Path()
        ..moveTo(endPt.dx, endPt.dy)
        ..cubicTo(ctrl1R.dx, ctrl1R.dy, ctrl2R.dx, ctrl2R.dy,
            baseR.dx, baseR.dy)
        ..cubicTo(baseCapCtrlR.dx, baseCapCtrlR.dy,
            baseCapCtrlL.dx, baseCapCtrlL.dy, baseL.dx, baseL.dy)
        ..cubicTo(ctrl2L.dx, ctrl2L.dy, ctrl1L.dx, ctrl1L.dy,
            endPt.dx, endPt.dy);

      canvas.drawPath(arrowPath, Paint()
        ..color = Colors.white.withValues(alpha: isPrimary ? 0.5 : 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isPrimary ? 3.0 : 2.5
        ..strokeJoin = StrokeJoin.round);

      canvas.drawPath(arrowPath, Paint()..color = color.withValues(alpha: 0.9));
    }

    // Labels in second pass, always on top of all arrow shapes
    for (int idx = 0; idx < swells.length; idx++) {
      final (swell, _) = swells[idx];
      final isPrimary = idx == 0;
      final b = swell.degrees * pi / 180;

      final normalizedLen = (swell.heightFt / maxHeight).clamp(0.6, 1.0);
      final arrowLen = radius * 0.85 * normalizedLen * (isPrimary ? 1.0 : 0.85);
      final outerR = isPrimary ? radius * 0.93 : primaryTipR + arrowLen;

      final startPt = Offset(
        center.dx + outerR * sin(b),
        center.dy - outerR * cos(b),
      );
      final endPt = Offset(
        center.dx + (outerR - arrowLen) * sin(b),
        center.dy - (outerR - arrowLen) * cos(b),
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
            color: Colors.white,
            fontSize: isPrimary ? 13.0 : 10.0,
            fontWeight: FontWeight.w500,
            shadows: _shadowStyle,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelT = isPrimary ? 0.25 : 0.25;
      final labelCenter = Offset(
        startPt.dx + (endPt.dx - startPt.dx) * labelT,
        startPt.dy + (endPt.dy - startPt.dy) * labelT,
      );

      final arrowAngle = atan2(endPt.dy - startPt.dy, endPt.dx - startPt.dx);

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
