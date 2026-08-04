import 'package:flutter/material.dart';

/// Probe value chip for the ocean forecast maps: the sampled value
/// ("7.5 kts W") plus, on the wind layer, a one-line attribution
/// ("ECMWF · 2 PM PDT").
///
/// The chip sizes to its intrinsic content — both lines are short by
/// construction — so hosts must give it loose constraints and let OTHER
/// elements (the section title) yield. Never wrap it in a Flexible that
/// competes with a Spacer: with equal flex the chip is capped at half the
/// row's slack and ellipsizes into uselessness. [maxWidth] is a last-resort
/// bound for pathological content only.
class OceanProbeChip extends StatelessWidget {
  final String value;
  final String? attribution;

  /// Layer accent color (border/tint, and text in card style).
  final Color accent;

  /// True for the full-screen map overlay (dark pill, white text);
  /// false for the embedded card header (accent-tinted, accent text).
  final bool onMap;

  final double maxWidth;

  const OceanProbeChip({
    super.key,
    required this.value,
    this.attribution,
    required this.accent,
    this.onMap = false,
    this.maxWidth = 220,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: onMap
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 7)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: onMap ? Colors.black.withOpacity(0.7) : accent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(onMap ? 20 : 12),
        border: Border.all(color: accent.withOpacity(onMap ? 0.5 : 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            onMap ? CrossAxisAlignment.center : CrossAxisAlignment.end,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: onMap ? Colors.white : accent,
              fontSize: onMap ? 15 : 13,
              fontWeight: onMap ? FontWeight.w600 : FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          if (attribution != null)
            Text(
              attribution!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: onMap
                    ? Colors.white.withOpacity(0.65)
                    : accent.withOpacity(0.75),
                fontSize: onMap ? 10.5 : 10,
                fontWeight: onMap ? FontWeight.w500 : FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
        ],
      ),
    );
  }
}
