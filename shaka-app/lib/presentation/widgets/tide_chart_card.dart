import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/unit_converter.dart';
import '../../data/models/spot_models.dart';
import '../../data/services/unit_preference_service.dart';

class TideChartCard extends StatefulWidget {
  final TideChartData? tide;

  const TideChartCard({super.key, this.tide});

  @override
  State<TideChartCard> createState() => _TideChartCardState();
}

class _TideChartCardState extends State<TideChartCard> {
  final _units = UnitPreferenceService();
  static const _cardColor = AppColors.darkSurface;
  static const _borderColor = AppColors.darkBorder;
  static const _tideColor = AppColors.chartTide;
  static const _highColor = AppColors.chartTideHigh;
  static const _lowColor = AppColors.chartTideLow;
  static const _nowColor = AppColors.chartNowLine;
  static const _dimText = AppColors.darkTextMuted;
  static const _lightText = AppColors.darkTextSecondary;

  bool get _hasData =>
      widget.tide != null && widget.tide!.points.isNotEmpty;

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

  Widget _buildHeader() {
    final tide = widget.tide;
    final stageText = tide?.currentStage ?? '';
    final heightText = tide?.currentHeightFt != null
        ? UnitConverter.formatTideHeight(tide!.currentHeightFt, _units.system)
        : '';
    final stageIcon = stageText == 'rising'
        ? Icons.trending_up
        : stageText == 'falling'
            ? Icons.trending_down
            : Icons.remove;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(Icons.waves, size: 18, color: _tideColor),
          const SizedBox(width: 8),
          Text(
            'TIDES',
            style: TextStyle(
              color: _lightText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (!_hasData) ...[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _tideColor.withOpacity(0.5),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Loading...',
              style: TextStyle(color: _dimText, fontSize: 13),
            ),
          ] else if (heightText.isNotEmpty) ...[
            Icon(stageIcon, size: 16, color: _tideColor),
            const SizedBox(width: 4),
            Text(
              '$heightText ${_capitalize(stageText)}',
              style: TextStyle(
                color: _tideColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _showTideInfo(context);
              },
              child: const Icon(Icons.info_outline, size: 14, color: AppColors.darkTextHint),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExpandedContent() {
    final tide = widget.tide!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SizedBox(
            height: 160,
            child: CustomPaint(
              size: const Size(double.infinity, 160),
              painter: _TideCurvePainter(
                points: tide.points,
                extremes: tide.extremes,
                unitSystem: _units.system,
                tideColor: _tideColor,
                highColor: _highColor,
                lowColor: _lowColor,
                nowColor: _nowColor,
                dimText: _dimText,
              ),
            ),
          ),
        ),
        _buildFooter(tide),
      ],
    );
  }

  Widget _buildFooter(TideChartData tide) {
    final allHighs = tide.highs;
    final allLows = tide.lows;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Column(
        children: [
          if (allHighs.isNotEmpty)
            Row(
              children: [
                for (int i = 0; i < allHighs.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  _footerChip('High', _formatTime(allHighs[i].time),
                      UnitConverter.formatTideHeight(allHighs[i].heightFt, _units.system), _highColor),
                ],
              ],
            ),
          if (allHighs.isNotEmpty && allLows.isNotEmpty)
            const SizedBox(height: 8),
          if (allLows.isNotEmpty)
            Row(
              children: [
                for (int i = 0; i < allLows.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  _footerChip('Low', _formatTime(allLows[i].time),
                      UnitConverter.formatTideHeight(allLows[i].heightFt, _units.system), _lowColor),
                ],
              ],
            ),
          const SizedBox(height: 8),
          Text(
            tide.provider == 'fes2022'
                ? 'FES2022 Global Tide Model · ${tide.datum}'
                : '${tide.stationName} · ${UnitConverter.formatDistance(tide.stationDistanceMi, _units.system)} · ${tide.datum}',
            style: TextStyle(color: _dimText, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _footerChip(String label, String time, String height, Color color) {
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
            Text(time,
                style: TextStyle(color: _lightText, fontSize: 12)),
            const SizedBox(width: 6),
            Text(height,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? '' : '${s[0].toUpperCase()}${s.substring(1)}';

  static String _formatTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  void _showTideInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.65,
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
                    child: Text(
                      'Tides',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppColors.darkTextMuted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'How tide predictions are generated:',
                style: TextStyle(color: AppColors.darkTextMuted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              _buildInfoCard(
                'Tide Height',
                'FES2022 Global Tide Model',
                'Predicted',
                'Water level from 34 astronomical harmonic constituents on a global finite-element mesh. Accurate to ~2 cm in open ocean.',
              ),
              _buildInfoCard(
                'Rising / Falling',
                'Interpolated from tide curve',
                'Real-time',
                'Current stage derived from the predicted curve. Rising tide often brings bait and fish closer to shore.',
              ),
              _buildInfoCard(
                'High & Low Points',
                'FES2022 extremes',
                'Daily',
                'Today\'s predicted peaks and troughs with exact times. Tide changes drive current, which moves bait and triggers feeding.',
              ),
              _buildInfoCard(
                'Datum',
                'Station-dependent',
                'Reference level',
                'Heights shown relative to MLLW (Mean Lower Low Water) or MSL (Mean Sea Level). The "zero" baseline for all tide readings.',
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: AppColors.darkTextHint),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Predictions are astronomical only \u2014 storm surge, barometric pressure, and wind effects are not included.',
                        style: TextStyle(color: AppColors.darkTextMuted, fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildInfoCard(String label, String source, String frequency, String description) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  frequency,
                  style: const TextStyle(
                    color: AppColors.darkTextMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            source,
            style: TextStyle(
              color: AppColors.success,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(
              color: AppColors.darkTextSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _TideCurvePainter extends CustomPainter {
  final List<TidePoint> points;
  final List<TideExtreme> extremes;
  final UnitSystem unitSystem;
  final Color tideColor;
  final Color highColor;
  final Color lowColor;
  final Color nowColor;
  final Color dimText;

  _TideCurvePainter({
    required this.points,
    required this.extremes,
    required this.unitSystem,
    required this.tideColor,
    required this.highColor,
    required this.lowColor,
    required this.nowColor,
    required this.dimText,
  });

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

    final heights = points.map((p) => p.heightFt).toList();
    final minH = heights.reduce(min) - 0.3;
    final maxH = heights.reduce(max) + 0.3;
    final rangeH = maxH - minH;
    if (rangeH <= 0) return;

    double xOf(double ms) => leftPad + (ms - firstMs) / spanMs * chartW;
    double yOf(double h) => topPad + (1 - (h - minH) / rangeH) * chartH;

    // Y-axis: pick a tick interval that gives 3–6 ticks across the range
    final double rawStep = rangeH / 5;
    final double tickStep = rawStep <= 0.5 ? 0.5
        : rawStep <= 1.0 ? 1.0
        : rawStep <= 2.0 ? 2.0
        : 5.0;
    final double firstTick = (minH / tickStep).ceil() * tickStep;
    final gridPaint = Paint()..color = dimText.withOpacity(0.12);
    for (double h = firstTick; h <= maxH; h += tickStep) {
      final y = yOf(h);
      canvas.drawLine(Offset(leftPad, y), Offset(size.width - rightPad, y), gridPaint);
      final displayH = UnitConverter.convertTideValue(h, unitSystem);
      final label = displayH == displayH.roundToDouble()
          ? '${displayH.toInt()}'
          : displayH.toStringAsFixed(1);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: dimText, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 4, y - tp.height / 2));
    }

    // Pre-compute screen coordinates for Catmull-Rom spline
    final n = points.length;
    final px = List<double>.generate(n, (i) => xOf(points[i].epochMs.toDouble()));
    final py = List<double>.generate(n, (i) => yOf(points[i].heightFt));

    // Catmull-Rom cubic spline: build curve path and fill path in one pass.
    // For segment i→i+1, control points use neighbors i-1 and i+2 (clamped).
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
        colors: [tideColor.withOpacity(0.25), tideColor.withOpacity(0.02)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    canvas.drawPath(
      curvePath,
      Paint()
        ..color = tideColor
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Time axis labels (every 3 hours, DST-safe)
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

      // Tick
      canvas.drawLine(
        Offset(x, size.height - bottomPad),
        Offset(x, size.height - bottomPad + 4),
        Paint()..color = dimText.withOpacity(0.3),
      );

      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: dimText, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, size.height - bottomPad + 5));
    }

    // High/low markers
    for (final ext in extremes) {
      if (ext.epochMs < points.first.epochMs || ext.epochMs > points.last.epochMs) {
        continue;
      }
      final x = xOf(ext.epochMs.toDouble());
      final y = yOf(ext.heightFt);
      final isHigh = ext.type == 'H';
      final color = isHigh ? highColor : lowColor;

      canvas.drawCircle(Offset(x, y), 4, Paint()..color = color);
      canvas.drawCircle(
          Offset(x, y),
          4,
          Paint()
            ..color = AppColors.darkSurface
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);

      final label = UnitConverter.formatTideHeightCompact(ext.heightFt, unitSystem);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelY = isHigh ? y - tp.height - 4 : y + 6;
      tp.paint(canvas, Offset(x - tp.width / 2, labelY));
    }

    // Now marker
    final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    if (nowMs >= firstMs && nowMs <= lastMs) {
      final nx = xOf(nowMs);

      // Dashed vertical line
      final dashPaint = Paint()
        ..color = nowColor.withOpacity(0.6)
        ..strokeWidth = 1.0;
      for (double dy = topPad; dy < size.height - bottomPad; dy += 6) {
        canvas.drawLine(
          Offset(nx, dy),
          Offset(nx, min(dy + 3, size.height - bottomPad)),
          dashPaint,
        );
      }

      // Interpolate current height for the dot
      double? nowH;
      for (int i = 1; i < points.length; i++) {
        if (points[i].epochMs.toDouble() >= nowMs) {
          final p0 = points[i - 1];
          final p1 = points[i];
          final t = (nowMs - p0.epochMs) / (p1.epochMs - p0.epochMs);
          nowH = p0.heightFt + t * (p1.heightFt - p0.heightFt);
          break;
        }
      }
      if (nowH != null) {
        final ny = yOf(nowH);
        canvas.drawCircle(
          Offset(nx, ny),
          5,
          Paint()..color = nowColor,
        );
        canvas.drawCircle(
          Offset(nx, ny),
          5,
          Paint()
            ..color = AppColors.darkSurface
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }

      // "Now" label
      final tp = TextPainter(
        text: TextSpan(
          text: 'Now',
          style: TextStyle(
              color: nowColor, fontSize: 9, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(nx - tp.width / 2, topPad - tp.height - 2));
    }
  }

  @override
  bool shouldRepaint(covariant _TideCurvePainter old) =>
      points != old.points || extremes != old.extremes || unitSystem != old.unitSystem;
}
