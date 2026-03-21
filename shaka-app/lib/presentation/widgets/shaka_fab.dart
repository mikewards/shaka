import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';

/// Standardized floating action button.
/// Size: 44x44 (Apple HIG minimum touch target)
class ShakaFab extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? iconColor;
  final String? tooltip;

  const ShakaFab({
    super.key,
    required this.icon,
    this.onTap,
    this.backgroundColor,
    this.iconColor,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: onTap != null ? () {
        HapticFeedback.lightImpact();
        onTap!();
      } : null,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: backgroundColor ?? AppColors.darkSurface.withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Icon(
          icon,
          color: iconColor ?? AppColors.darkTextSecondary,
          size: 22,
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
