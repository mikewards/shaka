import 'package:flutter/animation.dart';

/// Animation constants for Quiet Luxury design system.
/// 
/// Principle: Smooth and slow, never jarring.
/// Animations should feel meditative, not snappy.
class AppAnimations {
  AppAnimations._();

  // State transitions (color, size changes)
  static const Duration stateTransition = Duration(milliseconds: 450);
  
  // Micro-interactions (pill selection, toggles)
  static const Duration microInteraction = Duration(milliseconds: 180);
  
  // Ambient breathing animation (hero elements)
  static const Duration breathing = Duration(milliseconds: 2500);
  
  // Page transitions
  static const Duration pageTransition = Duration(milliseconds: 350);
  
  // Fade in/out
  static const Duration fade = Duration(milliseconds: 300);
  
  // Default curve - smooth sine wave
  static const Curve defaultCurve = Curves.easeInOutSine;
  
  // Subtle curve for breathing
  static const Curve breathingCurve = Curves.easeInOutSine;
  
  // Entry curve
  static const Curve entryCurve = Curves.easeOutCubic;
  
  // Exit curve
  static const Curve exitCurve = Curves.easeInCubic;
  
  // Breathing animation scale range (2-3%)
  static const double breathingMinScale = 1.0;
  static const double breathingMaxScale = 1.025;
}
