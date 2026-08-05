import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';

/// Shared time-scrubbing behavior for the spot-detail charts (tide, swell,
/// wind) — implemented once, applied by every chart card.
///
/// Wraps a chart's paint area and turns horizontal touch into a scrubbed
/// instant along the displayed day. Contract shared by all charts:
///  - tap or drag positions the scrub line and it stays put on release, so
///    the header readout can be studied;
///  - on today's charts, scrubbing within [snapWindowMs] of "now" snaps back
///    to the default now state (so the line is either meaningfully away from
///    now, or exactly at it); tapping the header's [ChartScrubLabel] also
///    resets;
///  - the parent chart owns the scrubbed value: null means default (now for
///    today, day summary otherwise). LABELING INTEGRITY: while scrubbed the
///    header must present the value as a forecast/predicted sample at that
///    time — never as "Live".
class ChartTimeScrubber extends StatelessWidget {
  /// Horizontal chart-area padding used by every chart painter. The x <->
  /// time mapping here must stay in sync with the painters' `xOf`.
  static const double leftPad = 30.0;
  static const double rightPad = 4.0;

  /// Scrubbing this close to [snapToMs] resets to the default now state.
  static const int snapWindowMs = 8 * 60 * 1000;

  final int firstMs;
  final int lastMs;

  /// Non-null on today's charts: the "now" instant that scrubbing snaps
  /// back to. Null on future days (no now on that chart).
  final int? snapToMs;

  /// Current scrubbed instant (null = default position).
  final int? value;

  final ValueChanged<int?> onChanged;
  final Widget child;

  const ChartTimeScrubber({
    super.key,
    required this.firstMs,
    required this.lastMs,
    this.snapToMs,
    required this.value,
    required this.onChanged,
    required this.child,
  });

  void _scrubTo(double dx, double width) {
    final chartW = width - leftPad - rightPad;
    if (chartW <= 0 || lastMs <= firstMs) return;
    final frac = ((dx - leftPad) / chartW).clamp(0.0, 1.0);
    final ms = (firstMs + frac * (lastMs - firstMs)).round();
    final snap = snapToMs;
    if (snap != null &&
        snap >= firstMs &&
        snap <= lastMs &&
        (ms - snap).abs() <= snapWindowMs) {
      if (value != null) {
        HapticFeedback.selectionClick();
        onChanged(null);
      }
      return;
    }
    if (ms != value) onChanged(ms);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _scrubTo(d.localPosition.dx, constraints.maxWidth),
        onHorizontalDragStart: (d) =>
            _scrubTo(d.localPosition.dx, constraints.maxWidth),
        onHorizontalDragUpdate: (d) =>
            _scrubTo(d.localPosition.dx, constraints.maxWidth),
        child: child,
      ),
    );
  }
}

/// The header's kind+time readout line under a chart headline ("Live · 2:50
/// PM PDT", "Forecast · 5 PM PDT"). While scrubbed it appends a compact
/// reset affordance and tapping the line returns the chart to its default
/// (now) state.
class ChartScrubLabel extends StatelessWidget {
  final String text;
  final bool scrubbed;
  final VoidCallback onReset;

  const ChartScrubLabel({
    super.key,
    required this.text,
    required this.scrubbed,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(color: AppColors.darkTextHint, fontSize: 10);
    if (!scrubbed) return Text(text, style: base);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        HapticFeedback.lightImpact();
        onReset();
      },
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: text, style: base),
          const TextSpan(
            text: '   \u00d7 reset',
            style: TextStyle(
              color: AppColors.darkTextSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ]),
      ),
    );
  }
}

/// Sample-series math for scrubbed readouts. Values interpolate linearly
/// between hourly samples — the same interpolation the charts already use
/// for their "now" dot — while categorical fields (direction) take the
/// nearest sample.
class ChartScrubMath {
  ChartScrubMath._();

  /// Linear interpolation of [values] (parallel to [epochs]) at [ms],
  /// clamped to the series range. Null samples fall back to the neighbor.
  static double? lerpAt(List<int> epochs, List<double?> values, int ms) {
    if (epochs.isEmpty) return null;
    if (ms <= epochs.first) return values.first;
    if (ms >= epochs.last) return values.last;
    for (int i = 1; i < epochs.length; i++) {
      if (epochs[i] >= ms) {
        final a = values[i - 1];
        final b = values[i];
        if (a == null) return b;
        if (b == null) return a;
        final t = (ms - epochs[i - 1]) / (epochs[i] - epochs[i - 1]);
        return a + (b - a) * t;
      }
    }
    return values.last;
  }

  /// Index of the sample nearest to [ms].
  static int nearestIndex(List<int> epochs, int ms) {
    var best = 0;
    for (int i = 1; i < epochs.length; i++) {
      if ((epochs[i] - ms).abs() < (epochs[best] - ms).abs()) best = i;
    }
    return best;
  }
}

/// The scrubbed-time marker, drawn by each chart painter on top of its
/// curve: a SOLID vertical line (visually distinct from the dashed "Now"
/// line) with a dot at the interpolated curve value.
class ChartScrubMarker {
  ChartScrubMarker._();

  static void draw(
    Canvas canvas,
    Size size, {
    required double x,
    double? y,
    required Color color,
    double topPad = 20,
    double bottomPad = 20,
  }) {
    canvas.drawLine(
      Offset(x, topPad),
      Offset(x, size.height - bottomPad),
      Paint()
        ..color = color.withOpacity(0.9)
        ..strokeWidth = 1.5,
    );
    if (y != null) {
      canvas.drawCircle(Offset(x, y), 5.5, Paint()..color = color);
      canvas.drawCircle(
          Offset(x, y),
          5.5,
          Paint()
            ..color = AppColors.darkSurface
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
  }
}
