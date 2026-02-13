import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// A horizontal pill-shaped "battery" indicator showing the score tier (1–5).
///
/// 5 segments, filled left-to-right based on the tier. The filled segments
/// use the tier color; empty segments are dark/muted.
///
/// Used alongside the numeric score in carousel cards and spot detail headers
/// to give an instant visual read on quality.
class ScoreTierPill extends StatelessWidget {
  final int score;
  final double width;
  final double height;

  const ScoreTierPill({
    super.key,
    required this.score,
    this.width = 60,
    this.height = 14,
  });

  @override
  Widget build(BuildContext context) {
    final tier = AppColors.getScoreTier(score);
    final color = AppColors.getScoreColor(score);
    const totalSegments = 5;
    const gap = 2.0;

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
                color: isFilled ? color : Colors.white.withOpacity(0.08),
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
