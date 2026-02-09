import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../screens/explore/explore_screen.dart';

/// Main shell with bottom navigation for the app.
/// Contains tabs for Home, Explore, Charts, and Profile.
class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({
    super.key,
    required this.navigationShell,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ExploreScreen.pinModeActive,
      builder: (context, isPinMode, _) {
    return Scaffold(
      body: navigationShell,
      // Hide bottom nav during Explore pin mode (map goes full-screen)
      bottomNavigationBar: isPinMode ? null : Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D0D),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.explore_outlined,
                activeIcon: Icons.explore,
                label: 'Explore',
                isSelected: navigationShell.currentIndex == 0,
                onTap: () => _onTap(context, 0),
              ),
              _NavItem(
                icon: Icons.phishing,
                activeIcon: Icons.phishing,
                label: 'Reports',
                isSelected: navigationShell.currentIndex == 1,
                onTap: () => _onTap(context, 1),
              ),
              _NavItem(
                icon: Icons.layers_outlined,
                activeIcon: Icons.layers,
                label: 'Charts',
                isSelected: navigationShell.currentIndex == 2,
                onTap: () => _onTap(context, 2),
              ),
              _NavItem(
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: 'Profile',
                isSelected: navigationShell.currentIndex == 3,
                onTap: () => _onTap(context, 3),
              ),
            ],
          ),
        ),
        ),
      ),
    );
      },
    );
  }

  void _onTap(BuildContext context, int index) {
    HapticFeedback.lightImpact();
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected 
        ? AppColors.info
        : Colors.white54;
    
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: isSelected 
              ? AppColors.info.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: color,
              size: 22,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
