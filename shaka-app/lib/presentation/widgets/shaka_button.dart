import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/animations.dart';

/// Primary button with Quiet Luxury styling.
/// 
/// Hero buttons should use [isHero: true] for:
/// - No ripple effect (relies on state change)
/// - Breathing animation wrapper should be added externally
/// - Haptic feedback on press
class ShakaButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isExpanded;
  final bool isLoading;
  final bool isHero;

  const ShakaButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isExpanded = false,
    this.isLoading = false,
    this.isHero = false,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: onPressed == null ? AppColors.border : AppColors.oceanBlue,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: isLoading ? null : _handleTap,
        borderRadius: BorderRadius.circular(12),
        // No splash for hero buttons - quiet luxury
        splashColor: isHero ? Colors.transparent : null,
        highlightColor: isHero ? Colors.transparent : null,
        child: AnimatedContainer(
          duration: AppAnimations.stateTransition,
          curve: AppAnimations.defaultCurve,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
          ),
          child: isLoading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.textOnDark,
                    ),
                  ),
                )
              : Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                    color: onPressed == null 
                        ? AppColors.textMuted 
                        : AppColors.textOnDark,
                  ),
                ),
        ),
      ),
    );

    if (isExpanded) {
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: button,
      );
    }

    return button;
  }

  void _handleTap() {
    // Haptic feedback for significant actions
    HapticFeedback.lightImpact();
    onPressed?.call();
  }
}

/// Breathing animation wrapper for hero buttons.
/// Creates subtle 2-3% scale animation that feels alive but meditative.
class BreathingWidget extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const BreathingWidget({
    super.key,
    required this.child,
    this.enabled = true,
  });

  @override
  State<BreathingWidget> createState() => _BreathingWidgetState();
}

class _BreathingWidgetState extends State<BreathingWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppAnimations.breathing,
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: AppAnimations.breathingMinScale,
      end: AppAnimations.breathingMaxScale,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: AppAnimations.breathingCurve,
    ));

    if (widget.enabled) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(BreathingWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.enabled && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
