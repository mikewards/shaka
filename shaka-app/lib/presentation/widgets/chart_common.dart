import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Shared helpers for the intraday/forecast charts (swell, wind, tide).
class ChartDirection {
  ChartDirection._();

  static const _dirs = [
    'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
    'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
  ];

  /// 16-point compass label for a "coming from" bearing in degrees.
  static String cardinal(int degrees) {
    final idx = (((degrees % 360) + 360) % 360 / 22.5).round() % 16;
    return _dirs[idx];
  }
}

/// A small arrow pointing in the direction the swell/wind is heading
/// (180 deg from the "coming from" bearing), matching the data-source flyouts.
class ChartDirectionArrow extends StatelessWidget {
  final int fromDegrees;
  final Color color;
  final double size;

  const ChartDirectionArrow({
    super.key,
    required this.fromDegrees,
    required this.color,
    this.size = 12,
  });

  @override
  Widget build(BuildContext context) {
    // Arrow icon points up by default; rotate so it flows downstream.
    final radians = (fromDegrees + 180) * 3.1415926535 / 180.0;
    return Transform.rotate(
      angle: radians,
      child: Icon(Icons.navigation, size: size, color: color),
    );
  }
}

/// Builds a data-source info card identical in style to the tide chart's
/// flyout, so swell/wind explanations look consistent.
class ChartInfoCard {
  ChartInfoCard._();

  static Widget build(
      String label, String source, String frequency, String description) {
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
            style: const TextStyle(
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
