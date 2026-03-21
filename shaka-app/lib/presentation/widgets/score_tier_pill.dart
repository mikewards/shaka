import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// A pill-shaped "battery" indicator showing the score tier (1–5).
///
/// 5 segments, filled based on the tier. The filled segments use the tier
/// color; empty segments are dark/muted.
///
/// [vertical] = true renders bottom-to-top (rotated 90° CCW from horizontal).
class ScoreTierPill extends StatelessWidget {
  final int score;
  final double width;
  final double height;
  final bool vertical;

  const ScoreTierPill({
    super.key,
    required this.score,
    this.width = 60,
    this.height = 14,
    this.vertical = false,
  });

  @override
  Widget build(BuildContext context) {
    final tier = AppColors.getScoreTier(score);
    final color = AppColors.getScoreColor(score);
    const totalSegments = 5;
    const gap = 2.0;

    if (vertical) {
      // Bottom-to-top: tier 1 fills bottom segment, tier 5 fills all
      return SizedBox(
        width: width,
        height: height,
        child: Column(
          children: List.generate(totalSegments, (i) {
            // i=0 is top (segment 5), i=4 is bottom (segment 1)
            final segmentTier = totalSegments - i; // 5, 4, 3, 2, 1
            final isFilled = segmentTier <= tier;
            final isFirst = i == 0; // top
            final isLast = i == totalSegments - 1; // bottom
            return Expanded(
              child: Container(
                margin: EdgeInsets.only(bottom: isLast ? 0 : gap),
                decoration: BoxDecoration(
                  color: isFilled ? color : Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.vertical(
                    top: isFirst ? const Radius.circular(4) : Radius.zero,
                    bottom: isLast ? const Radius.circular(4) : Radius.zero,
                  ),
                ),
              ),
            );
          }),
        ),
      );
    }

    // Horizontal: left-to-right
    return SizedBox(
      width: width,
      height: height,
      child: Row(
        children: List.generate(totalSegments, (i) {
          final isFilled = i < tier;
          final isFirst = i == 0;
          final isLast = i == totalSegments - 1;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: isLast ? 0 : gap),
              decoration: BoxDecoration(
                color: isFilled ? color : Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.horizontal(
                  left: isFirst ? const Radius.circular(4) : Radius.zero,
                  right: isLast ? const Radius.circular(4) : Radius.zero,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
