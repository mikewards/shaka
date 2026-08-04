import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/unit_converter.dart';
import '../../core/utils/wind_format.dart';
import '../../data/models/spot_models.dart';
import '../../data/services/unit_preference_service.dart';
import 'chart_common.dart';
import 'live_wind_value.dart';

/// Intraday wind curve for a single spot-local day, styled to match the tide
/// chart: primary wind-speed curve, a lighter gust curve, and the wind
/// direction shown in the header and at the live "Now" marker.
class WindChartCard extends StatefulWidget {
  final List<WindHourlyPoint> points;
  final bool isToday;

  /// When set (and [isToday]), the header's "now" value comes from the same
  /// shared near-real-time reading as the spot cards and conditions row —
  /// ONE agreed current number everywhere. The curve itself stays hourly
  /// forecast; that's its purpose.
  final String? spotId;

  /// Spot's current UTC offset in minutes (from SpotHourlyResponse). When
  /// present the time axis and footer times render in SPOT-local time; when
  /// null they fall back to device-local (legacy behavior).
  final int? utcOffsetMinutes;

  /// Short zone label ("HST", "PDT") shown next to footer times when the
  /// spot's zone is known.
  final String? timezoneAbbr;

  const WindChartCard({
    super.key,
    required this.points,
    this.isToday = true,
    this.spotId,
    this.utcOffsetMinutes,
    this.timezoneAbbr,
  });

  @override
  State<WindChartCard> createState() => _WindChartCardState();
}

class _WindChartCardState extends State<WindChartCard> {
  final _units = UnitPreferenceService();
  static const _cardColor = AppColors.darkSurface;
  static const _borderColor = AppColors.darkBorder;
  static const _windColor = AppColors.chartWind;
  static const _nowColor = AppColors.chartNowLine;
  static const _dimText = AppColors.darkTextMuted;
  static const _lightText = AppColors.darkTextSecondary;

  bool get _hasData => widget.points.isNotEmpty;

  WindHourlyPoint? get _highlightPoint {
    if (widget.points.isEmpty) return null;
    if (widget.isToday) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now >= widget.points.first.epochMs &&
          now <= widget.points.last.epochMs) {
        return widget.points.reduce((a, b) =>
            (a.epochMs - now).abs() <= (b.epochMs - now).abs() ? a : b);
      }
    }
    return widget.points.reduce((a, b) => a.speedKts >= b.speedKts ? a : b);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _units,
      builder: (context, _) {
        if (widget.spotId != null && widget.isToday) {
          return LiveWindValue(
            spotId: widget.spotId!,
            builder: (context, live) => _buildCard(live),
          );
        }
        return _buildCard(null);
      },
    );
  }

  Widget _buildCard(LiveWind? live) {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          _buildHeader(live),
          if (_hasData) _buildExpandedContent(),
        ],
      ),
    );
  }

  Widget _buildHeader(LiveWind? live) {
    final hp = _highlightPoint;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!_hasData) ...[
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _windColor.withOpacity(0.5),
                  ),
                ),
                const SizedBox(width: 6),
                Text('Loading...',
                    style: TextStyle(color: _dimText, fontSize: 13)),
              ] else if (hp != null) ...[
                WindArrow(
                    fromDegrees: live?.windDirectionDeg ?? hp.directionDeg,
                    color: _windColor,
                    size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    live != null ? _liveHeaderText(live) : _headerText(hp),
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
                  _showWindInfo(context);
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Data sources',
                        style: TextStyle(
                            color: AppColors.darkTextHint, fontSize: 11)),
                    SizedBox(width: 4),
                    Icon(Icons.info_outline,
                        size: 12, color: AppColors.darkTextHint),
                  ],
                ),
              ),
            ],
          ),
          // Kind honesty: with a live reading the headline is the shared
          // current value (same number as the cards); otherwise it's a
          // forecast sample and states which hour it represents.
          if (_hasData && hp != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                live != null
                    ? 'Live \u00b7 ${_formatTime(live.retrievedAt)}'
                    : widget.isToday
                        ? 'Forecast \u00b7 nearest hour ${_formatTime(hp.epochMs)}'
                        : 'Forecast \u00b7 peak at ${_formatTime(hp.epochMs)}',
                style: const TextStyle(
                    color: AppColors.darkTextHint, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }

  String _headerText(WindHourlyPoint hp) {
    final speed = UnitConverter.formatWindSpeed(hp.speedKts, _units.system);
    final dir = WindFormat.cardinal(hp.directionDeg);
    // Suffix is empty when the gust wouldn't display above the speed
    // ("4 kts G4" is noise, not information).
    final gust = WindFormat.gustSuffix(hp.speedKts, hp.gustKts, _units.system);
    final prefix = widget.isToday ? '' : 'Peak ';
    return '$prefix$speed$gust $dir';
  }

  /// Headline from the shared near-real-time reading — identical formatting
  /// path as the forecast sample so the number matches the other surfaces.
  String _liveHeaderText(LiveWind live) {
    final speed =
        UnitConverter.formatWindSpeed(live.windSpeedKts, _units.system);
    final gust =
        WindFormat.gustSuffix(live.windSpeedKts, live.gustKts, _units.system);
    final dir = live.windDirectionDeg != null
        ? WindFormat.cardinal(live.windDirectionDeg!)
        : (live.windDirectionCardinal ?? '');
    return '$speed$gust $dir'.trimRight();
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
              painter: _WindCurvePainter(
                points: widget.points,
                unitSystem: _units.system,
                windColor: _windColor,
                nowColor: _nowColor,
                dimText: _dimText,
                showNow: widget.isToday,
                utcOffsetMinutes: widget.utcOffsetMinutes,
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
    final peak = points.reduce((a, b) => a.speedKts >= b.speedKts ? a : b);
    WindHourlyPoint? gustPeak;
    for (final p in points) {
      if (p.gustKts == null) continue;
      if (gustPeak == null || p.gustKts! > gustPeak.gustKts!) gustPeak = p;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Row(
        children: [
          _footerChip(
              'Peak',
              _formatTime(peak.epochMs),
              UnitConverter.formatWindSpeed(peak.speedKts, _units.system),
              _windColor),
          const SizedBox(width: 8),
          if (gustPeak != null)
            _footerChip(
                'Gust',
                _formatTime(gustPeak.epochMs),
                UnitConverter.formatWindSpeed(gustPeak.gustKts!, _units.system),
                _lightText)
          else
            const Expanded(child: SizedBox.shrink()),
        ],
      ),
    );
  }

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
            const SizedBox(width: 6),
            // One flexible text so the chip can never overflow its border:
            // the value leads (kept whole in practice), the muted
            // zone-suffixed time trails and gives way first when space runs
            // out on narrow devices.
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: value,
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                  TextSpan(
                      text: ' \u00b7 $time',
                      style: TextStyle(color: _lightText, fontSize: 12)),
                ]),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Footer time in SPOT-local time (with zone label) when the offset is
  /// known, else device-local. A Hawaii spot browsed from NY must say
  /// "Peak 2 PM HST", not the meaningless device-local hour. Uses the
  /// compact clock (minutes only when nonzero) so the zone suffix fits the
  /// footer chips.
  String _formatTime(int epochMs) {
    return WindFormat.compactClock(
      DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true),
      utcOffsetMinutes: widget.utcOffsetMinutes,
      timezoneAbbr: widget.timezoneAbbr,
    );
  }

  void _showWindInfo(BuildContext context) {
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
                    child: Text('Wind',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon:
                        const Icon(Icons.close, color: AppColors.darkTextMuted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'How wind predictions are generated:',
                style: TextStyle(color: AppColors.darkTextMuted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ChartInfoCard.build(
                'Wind Speed',
                'Open-Meteo (GFS / ICON)',
                'Hourly',
                'Sustained wind speed 10 m above the surface, refreshed daily for the next 7 days. For today, the current reading is updated from near-real-time wind when available.',
              ),
              ChartInfoCard.build(
                'Gusts',
                'Open-Meteo wind gusts',
                'Hourly',
                'Short-lived peak wind speed. Large gust-to-speed gaps signal unstable, choppy conditions.',
              ),
              ChartInfoCard.build(
                'Direction',
                'Open-Meteo wind direction',
                'Hourly',
                'The direction the wind is blowing from. Offshore wind (blowing from land to sea) usually cleans up surf.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WindCurvePainter extends CustomPainter {
  final List<WindHourlyPoint> points;
  final UnitSystem unitSystem;
  final Color windColor;
  final Color nowColor;
  final Color dimText;
  final bool showNow;
  final int? utcOffsetMinutes;

  _WindCurvePainter({
    required this.points,
    required this.unitSystem,
    required this.windColor,
    required this.nowColor,
    required this.dimText,
    required this.showNow,
    this.utcOffsetMinutes,
  });

  /// Hour-of-day for an instant in SPOT-local time when the offset is known,
  /// else device-local (legacy). The series is grouped by spot-local day
  /// server-side, so device-local axis labels were wrong whenever the viewer
  /// wasn't in the spot's timezone.
  int _hourOf(int ms) {
    final offset = utcOffsetMinutes;
    if (offset != null) {
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true)
          .add(Duration(minutes: offset))
          .hour;
    }
    return DateTime.fromMillisecondsSinceEpoch(ms).hour;
  }

  double _yValue(double kts) =>
      unitSystem == UnitSystem.metric ? UnitConverter.knotsToKmh(kts) : kts;

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

    final speed = points.map((p) => _yValue(p.speedKts)).toList();
    final gust = points
        .map((p) => p.gustKts != null ? _yValue(p.gustKts!) : null)
        .toList();
    final hasGust = gust.any((g) => g != null);

    final upper = <double>[
      ...speed,
      ...gust.whereType<double>(),
    ];
    var minH = 0.0; // wind anchors at zero
    var maxH = upper.reduce(max);
    maxH = maxH + maxH * 0.12 + 1;
    final rangeH = maxH - minH;
    if (rangeH <= 0) return;

    double xOf(double ms) => leftPad + (ms - firstMs) / spanMs * chartW;
    double yOf(double v) => topPad + (1 - (v - minH) / rangeH) * chartH;

    // Y grid + labels
    final double rawStep = rangeH / 4;
    final double tickStep = rawStep <= 5
        ? 5
        : rawStep <= 10
            ? 10
            : rawStep <= 20
                ? 20
                : 50;
    final double firstTick = (minH / tickStep).ceil() * tickStep;
    final gridPaint = Paint()..color = dimText.withOpacity(0.12);
    for (double v = firstTick; v <= maxH; v += tickStep) {
      final y = yOf(v);
      canvas.drawLine(
          Offset(leftPad, y), Offset(size.width - rightPad, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(
            text: '${v.toInt()}',
            style: TextStyle(color: dimText, fontSize: 9)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 4, y - tp.height / 2));
    }

    final n = points.length;
    final px =
        List<double>.generate(n, (i) => xOf(points[i].epochMs.toDouble()));

    // Gust curve first (lighter, dashed), so the speed line sits on top.
    if (hasGust) {
      final gy = List<double>.generate(n, (i) => yOf(gust[i] ?? speed[i]));
      final gustPath = _smoothPath(px, gy, n);
      canvas.drawPath(
        _dashPath(gustPath),
        Paint()
          ..color = windColor.withOpacity(0.45)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    // Speed curve + gradient fill
    final py = List<double>.generate(n, (i) => yOf(speed[i]));
    final curvePath = _smoothPath(px, py, n);
    final fillPath = Path.from(curvePath)
      ..lineTo(px[n - 1], size.height - bottomPad)
      ..lineTo(px[0], size.height - bottomPad)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [windColor.withOpacity(0.25), windColor.withOpacity(0.02)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    canvas.drawPath(
      curvePath,
      Paint()
        ..color = windColor
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Time axis labels (every 3 hours), in spot-local time when available.
    for (int h = 0; h <= 24; h += 3) {
      final ms = points.first.epochMs + h * 3600000;
      if (ms > points.last.epochMs) break;
      final x = xOf(ms.toDouble());
      final targetHour = _hourOf(ms);
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

    // Now marker + direction arrow
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

        int seg = 0;
        double? nowV;
        for (int i = 1; i < n; i++) {
          if (points[i].epochMs.toDouble() >= nowMs) {
            seg = i;
            final t = (nowMs - points[i - 1].epochMs) /
                (points[i].epochMs - points[i - 1].epochMs);
            nowV = speed[i - 1] + t * (speed[i] - speed[i - 1]);
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
          _drawWindArrow(canvas, Offset(nx, ny - 14),
              points[seg == 0 ? 0 : seg].directionDeg, nowColor);
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

  Path _smoothPath(List<double> px, List<double> py, int n) {
    final path = Path()..moveTo(px[0], py[0]);
    for (int i = 0; i < n - 1; i++) {
      final i0 = i > 0 ? i - 1 : 0;
      final i3 = i + 2 < n ? i + 2 : n - 1;
      final cp1x = px[i] + (px[i + 1] - px[i0]) / 6;
      final cp1y = py[i] + (py[i + 1] - py[i0]) / 6;
      final cp2x = px[i + 1] - (px[i3] - px[i]) / 6;
      final cp2y = py[i + 1] - (py[i3] - py[i]) / 6;
      path.cubicTo(cp1x, cp1y, cp2x, cp2y, px[i + 1], py[i + 1]);
    }
    return path;
  }

  /// Approximates a dashed stroke by sampling the path into dash segments.
  Path _dashPath(Path source) {
    final dashed = Path();
    for (final metric in source.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final next = min(dist + 5, metric.length);
        dashed.addPath(metric.extractPath(dist, next), Offset.zero);
        dist = next + 4;
      }
    }
    return dashed;
  }

  void _drawWindArrow(Canvas canvas, Offset at, int fromDeg, Color color) {
    // Wind flows toward (fromDeg + 180). 0 deg = up (north).
    final angle = (fromDeg + 180) * pi / 180.0;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle);
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, -5)
      ..lineTo(3, 4)
      ..lineTo(0, 2)
      ..lineTo(-3, 4)
      ..close();
    canvas.drawPath(path, p);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WindCurvePainter old) =>
      old.points != points ||
      old.unitSystem != unitSystem ||
      old.showNow != showNow ||
      old.utcOffsetMinutes != utcOffsetMinutes;
}
