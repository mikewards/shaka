import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/unit_converter.dart';
import '../../data/models/spot_models.dart';
import '../../data/services/unit_preference_service.dart';
import 'chart_common.dart';

/// Intraday swell curve for a single spot-local day, styled to match the tide
/// chart. When [isToday] is true (and "now" falls within the day) a live "Now"
/// marker is drawn; other days render as a pure forecast curve.
class SwellChartCard extends StatefulWidget {
  final List<SwellHourlyPoint> points;
  final bool isToday;

  const SwellChartCard({
    super.key,
    required this.points,
    this.isToday = true,
  });

  @override
  State<SwellChartCard> createState() => _SwellChartCardState();
}

class _SwellChartCardState extends State<SwellChartCard> {
  final _units = UnitPreferenceService();
  static const _cardColor = AppColors.darkSurface;
  static const _borderColor = AppColors.darkBorder;
  static const _swellColor = AppColors.chartSwell;
  static const _nowColor = AppColors.chartNowLine;
  static const _dimText = AppColors.darkTextMuted;
  static const _lightText = AppColors.darkTextSecondary;

  bool get _hasData => widget.points.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _units,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            color: _cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _borderColor),
          ),
          child: Column(
            children: [
              _buildHeader(),
              if (_hasData) _buildExpandedContent(),
            ],
          ),
        );
      },
    );
  }

  /// The point representing "now" (interpolated) for today, else the day's peak.
  SwellHourlyPoint? get _highlightPoint {
    if (widget.points.isEmpty) return null;
    if (widget.isToday) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now >= widget.points.first.epochMs &&
          now <= widget.points.last.epochMs) {
        // Nearest sample to now is good enough for the header label.
        return widget.points.reduce((a, b) =>
            (a.epochMs - now).abs() <= (b.epochMs - now).abs() ? a : b);
      }
    }
    return widget.points
        .reduce((a, b) => a.effectiveHeightFt >= b.effectiveHeightFt ? a : b);
  }

  Widget _buildHeader() {
    final hp = _highlightPoint;
    final headerText = hp == null
        ? ''
        : () {
            final h = UnitConverter.formatChartWaveHeight(
                UnitConverter.feetToMeters(hp.effectiveHeightFt), _units.system);
            final dir = ChartDirection.cardinal(hp.directionDeg);
            final prefix = widget.isToday ? '' : 'Peak ';
            return '$prefix$h @ ${hp.periodSec.round()}s $dir';
          }();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          if (!_hasData) ...[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _swellColor.withOpacity(0.5),
              ),
            ),
            const SizedBox(width: 6),
            Text('Loading...', style: TextStyle(color: _dimText, fontSize: 13)),
          ] else ...[
            Expanded(
              child: Text(
                headerText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _showSwellInfo(context);
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Data sources',
                    style:
                        TextStyle(color: AppColors.darkTextHint, fontSize: 11)),
                SizedBox(width: 4),
                Icon(Icons.info_outline, size: 12, color: AppColors.darkTextHint),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SizedBox(
            height: 160,
            child: CustomPaint(
              size: const Size(double.infinity, 160),
              painter: _SwellCurvePainter(
                points: widget.points,
                unitSystem: _units.system,
                swellColor: _swellColor,
                nowColor: _nowColor,
                dimText: _dimText,
                showNow: widget.isToday,
              ),
            ),
          ),
        ),
        _buildFooter(),
      ],
    );
  }

  Widget _buildFooter() {
    final points = widget.points;
    final peak =
        points.reduce((a, b) => a.effectiveHeightFt >= b.effectiveHeightFt ? a : b);
    final low =
        points.reduce((a, b) => a.effectiveHeightFt <= b.effectiveHeightFt ? a : b);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Row(
        children: [
          _footerChip('Peak', _formatTime(peak.time),
              _height(peak.effectiveHeightFt), _swellColor),
          const SizedBox(width: 8),
          _footerChip('Min', _formatTime(low.time),
              _height(low.effectiveHeightFt), _lightText),
        ],
      ),
    );
  }

  String _height(double ft) => UnitConverter.formatChartWaveHeight(
      UnitConverter.feetToMeters(ft), _units.system);

  Widget _footerChip(String label, String time, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(time, style: TextStyle(color: _lightText, fontSize: 12)),
            const SizedBox(width: 6),
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  void _showSwellInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Swell',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close,
                        color: AppColors.darkTextMuted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'How swell predictions are generated:',
                style: TextStyle(color: AppColors.darkTextMuted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ChartInfoCard.build(
                'Wave Height',
                'Open-Meteo Marine (MFWAM / GWAM)',
                'Hourly',
                'Significant wave height from a global wave model, refreshed daily for the next 7 days. Heights are exposure-corrected for this spot when shoreline data is available.',
              ),
              ChartInfoCard.build(
                'Period & Direction',
                'Open-Meteo Marine',
                'Hourly',
                'Dominant swell period (seconds between waves) and the direction the swell is coming from. Longer periods carry more energy.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwellCurvePainter extends CustomPainter {
  final List<SwellHourlyPoint> points;
  final UnitSystem unitSystem;
  final Color swellColor;
  final Color nowColor;
  final Color dimText;
  final bool showNow;

  _SwellCurvePainter({
    required this.points,
    required this.unitSystem,
    required this.swellColor,
    required this.nowColor,
    required this.dimText,
    required this.showNow,
  });

  double _yValue(double ft) =>
      unitSystem == UnitSystem.metric ? UnitConverter.feetToMeters(ft) : ft;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    const topPad = 20.0;
    const bottomPad = 20.0;
    const leftPad = 30.0;
    const rightPad = 4.0;
    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;

    final firstMs = points.first.epochMs.toDouble();
    final lastMs = points.last.epochMs.toDouble();
    final spanMs = lastMs - firstMs;
    if (spanMs <= 0) return;

    final values = points.map((p) => _yValue(p.effectiveHeightFt)).toList();
    var minH = values.reduce(min);
    var maxH = values.reduce(max);
    // Swell often sits near a small range; pad and anchor near zero for context.
    minH = min(minH, 0) ;
    maxH = maxH + (maxH - minH) * 0.12 + 0.1;
    final rangeH = maxH - minH;
    if (rangeH <= 0) return;

    double xOf(double ms) => leftPad + (ms - firstMs) / spanMs * chartW;
    double yOf(double v) => topPad + (1 - (v - minH) / rangeH) * chartH;

    // Y grid + labels
    final double rawStep = rangeH / 4;
    final double tickStep = rawStep <= 0.5
        ? 0.5
        : rawStep <= 1.0
            ? 1.0
            : rawStep <= 2.0
                ? 2.0
                : rawStep <= 5.0
                    ? 5.0
                    : 10.0;
    final double firstTick = (minH / tickStep).ceil() * tickStep;
    final gridPaint = Paint()..color = dimText.withOpacity(0.12);
    for (double v = firstTick; v <= maxH; v += tickStep) {
      final y = yOf(v);
      canvas.drawLine(
          Offset(leftPad, y), Offset(size.width - rightPad, y), gridPaint);
      final label = v == v.roundToDouble()
          ? '${v.toInt()}'
          : v.toStringAsFixed(1);
      final tp = TextPainter(
        text: TextSpan(
            text: label, style: TextStyle(color: dimText, fontSize: 9)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 4, y - tp.height / 2));
    }

    // Catmull-Rom spline
    final n = points.length;
    final px = List<double>.generate(n, (i) => xOf(points[i].epochMs.toDouble()));
    final py = List<double>.generate(n, (i) => yOf(values[i]));

    final curvePath = Path()..moveTo(px[0], py[0]);
    final fillPath = Path()
      ..moveTo(px[0], size.height - bottomPad)
      ..lineTo(px[0], py[0]);

    for (int i = 0; i < n - 1; i++) {
      final i0 = i > 0 ? i - 1 : 0;
      final i3 = i + 2 < n ? i + 2 : n - 1;
      final cp1x = px[i] + (px[i + 1] - px[i0]) / 6;
      final cp1y = py[i] + (py[i + 1] - py[i0]) / 6;
      final cp2x = px[i + 1] - (px[i3] - px[i]) / 6;
      final cp2y = py[i + 1] - (py[i3] - py[i]) / 6;
      curvePath.cubicTo(cp1x, cp1y, cp2x, cp2y, px[i + 1], py[i + 1]);
      fillPath.cubicTo(cp1x, cp1y, cp2x, cp2y, px[i + 1], py[i + 1]);
    }

    fillPath.lineTo(px[n - 1], size.height - bottomPad);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [swellColor.withOpacity(0.25), swellColor.withOpacity(0.02)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    canvas.drawPath(
      curvePath,
      Paint()
        ..color = swellColor
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Time axis labels (every 3 hours), device-local like the tide chart.
    for (int h = 0; h <= 24; h += 3) {
      final ms = points.first.epochMs + h * 3600000;
      if (ms > points.last.epochMs) break;
      final x = xOf(ms.toDouble());
      final targetHour = DateTime.fromMillisecondsSinceEpoch(ms).hour;
      final label = targetHour == 0
          ? '12A'
          : targetHour == 12
              ? '12P'
              : targetHour > 12
                  ? '${targetHour - 12}P'
                  : '${targetHour}A';
      canvas.drawLine(
        Offset(x, size.height - bottomPad),
        Offset(x, size.height - bottomPad + 4),
        Paint()..color = dimText.withOpacity(0.3),
      );
      final tp = TextPainter(
        text: TextSpan(
            text: label, style: TextStyle(color: dimText, fontSize: 9)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, size.height - bottomPad + 5));
    }

    // Now marker (auto-gated: only when now falls inside this day's range).
    if (showNow) {
      final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
      if (nowMs >= firstMs && nowMs <= lastMs) {
        final nx = xOf(nowMs);
        final dashPaint = Paint()
          ..color = nowColor.withOpacity(0.6)
          ..strokeWidth = 1.0;
        for (double dy = topPad; dy < size.height - bottomPad; dy += 6) {
          canvas.drawLine(Offset(nx, dy),
              Offset(nx, min(dy + 3, size.height - bottomPad)), dashPaint);
        }

        double? nowV;
        for (int i = 1; i < n; i++) {
          if (points[i].epochMs.toDouble() >= nowMs) {
            final t = (nowMs - points[i - 1].epochMs) /
                (points[i].epochMs - points[i - 1].epochMs);
            nowV = values[i - 1] + t * (values[i] - values[i - 1]);
            break;
          }
        }
        if (nowV != null) {
          final ny = yOf(nowV);
          canvas.drawCircle(Offset(nx, ny), 5, Paint()..color = nowColor);
          canvas.drawCircle(
              Offset(nx, ny),
              5,
              Paint()
                ..color = AppColors.darkSurface
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5);
        }

        final tp = TextPainter(
          text: TextSpan(
              text: 'Now',
              style: TextStyle(
                  color: nowColor, fontSize: 9, fontWeight: FontWeight.w600)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(nx - tp.width / 2, topPad - tp.height - 2));
      }
    }
  }

  @override
  bool shouldRepaint(_SwellCurvePainter old) =>
      old.points != points ||
      old.unitSystem != unitSystem ||
      old.showNow != showNow;
}
