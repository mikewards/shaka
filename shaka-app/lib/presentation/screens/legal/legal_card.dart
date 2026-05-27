import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';

/// Shared styling for the legal/disclaimer screens so they match Shaka's
/// dark design system (mirrors the `_ProfileRow` card + section-label
/// patterns used in profile_screen.dart) instead of looking like a generic
/// Material dialog.

/// Uppercase section label (12px, w600, letterSpacing 1.2, muted).
Widget legalSectionLabel(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: AppColors.darkTextMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );

/// Rounded dark surface card with a 1px border, matching `_ProfileRow`.
class LegalCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const LegalCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: child,
    );
  }
}

/// Tappable row with a rounded icon tile, title/subtitle, and chevron —
/// the same visual language as the profile settings rows.
class LegalLinkRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const LegalLinkRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.iconColor = AppColors.info,
    this.subtitle = '',
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: LegalCard(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.darkTextMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.open_in_new,
                color: AppColors.darkTextHint, size: 18),
          ],
        ),
      ),
    );
  }
}
