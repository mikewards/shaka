import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/models/spot_models.dart';

class TideChartCard extends StatefulWidget {
  final TideChartData? tide;

  const TideChartCard({super.key, this.tide});

  @override
  State<TideChartCard> createState() => _TideChartCardState();
}

class _TideChartCardState extends State<TideChartCard> {
  bool _expanded = false;

  static const _cardColor = Color(0xFF1A1A1A);
  static const _borderColor = Color(0xFF2A2A2A);
  static const _tideColor = Color(0xFF38BDF8);
  static const _highColor = Color(0xFF2DD4BF);
  static const _lowColor = Color(0xFF60A5FA);
  static const _nowColor = Color(0xFFFBBF24);
  static const _dimText = Color(0xFF888888);
  static const _lightText = Color(0xFFE5E5E5);

  bool get _hasData =>
      widget.tide != null && widget.tide!.points.isNotEmpty;

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
            secondChild: _hasData ? _buildExpandedContent() : const SizedBox.shrink(),
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
    final tide = widget.tide;
    final stageText = tide?.currentStage ?? '';
    final heightText = tide?.currentHeightFt != null
        ? '${tide!.currentHeightFt!.toStringAsFixed(1)} ft'
        : '';
    final stageIcon = stageText == 'rising'
        ? Icons.trending_up
        : stageText == 'falling'
            ? Icons.trending_down
            : Icons.remove;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _hasData
          ? () {
              HapticFeedback.lightImpact();
              setState(() => _expanded = !_expanded);
            }
          : null,
      child: Padding(
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
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 250),
                child: Icon(
                  Icons.keyboard_arrow_down,
                  size: 20,
                  color: Colors.white38,
                ),
              ),
            ],
          ],
        ),
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
                      '${allHighs[i].heightFt.toStringAsFixed(1)} ft', _highColor),
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
                      '${allLows[i].heightFt.toStringAsFixed(1)} ft', _lowColor),
                ],
              ],
            ),
          const SizedBox(height: 8),
          Text(
            tide.provider == 'fes2022'
                ? 'FES2022 Global Tide Model · ${tide.datum}'
                : '${tide.stationName} · ${tide.stationDistanceMi.toStringAsFixed(1)} mi · ${tide.datum}',
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
}

class _TideCurvePainter extends CustomPainter {
  final List<TidePoint> points;
  final List<TideExtreme> extremes;
  final Color tideColor;
  final Color highColor;
  final Color lowColor;
  final Color nowColor;
  final Color dimText;

  _TideCurvePainter({
    required this.points,
    required this.extremes,
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
    const leftPad = 4.0;
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

    // Gradient fill
    final fillPath = Path();
    fillPath.moveTo(xOf(points.first.epochMs.toDouble()), size.height - bottomPad);
    for (final p in points) {
      fillPath.lineTo(xOf(p.epochMs.toDouble()), yOf(p.heightFt));
    }
    fillPath.lineTo(xOf(points.last.epochMs.toDouble()), size.height - bottomPad);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [tideColor.withOpacity(0.25), tideColor.withOpacity(0.02)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Curve
    final curvePath = Path();
    curvePath.moveTo(xOf(points.first.epochMs.toDouble()), yOf(points.first.heightFt));
    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final px = xOf(prev.epochMs.toDouble());
      final cx = xOf(curr.epochMs.toDouble());
      final midX = (px + cx) / 2;
      curvePath.cubicTo(
        midX, yOf(prev.heightFt),
        midX, yOf(curr.heightFt),
        cx, yOf(curr.heightFt),
      );
    }

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
            ..color = const Color(0xFF1A1A1A)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);

      final label = '${ext.heightFt.toStringAsFixed(1)}ft';
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
            ..color = const Color(0xFF1A1A1A)
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
      points != old.points || extremes != old.extremes;
}
