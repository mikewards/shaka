import 'package:flutter/material.dart';

/// Profile and settings screen.
/// Currently a placeholder - will include saved spots management,
/// preferences, and account settings in the future.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        title: const Text(
          'Profile',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Saved Spots Section
          _buildSectionHeader('Saved Spots'),
          const SizedBox(height: 12),
          _buildSettingsCard([
            _SettingsTile(
              icon: Icons.bookmark_outline,
              title: 'Manage Saved Spots',
              subtitle: 'Reorder and remove favorites',
              onTap: () {
                // TODO: Navigate to saved spots management
              },
            ),
          ]),
          
          const SizedBox(height: 24),
          
          // Preferences Section
          _buildSectionHeader('Preferences'),
          const SizedBox(height: 12),
          _buildSettingsCard([
            _SettingsTile(
              icon: Icons.straighten,
              title: 'Units',
              subtitle: 'Metric / Imperial',
              trailing: const Text(
                'Imperial',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
              onTap: () {
                // TODO: Toggle units
              },
            ),
            const Divider(color: Colors.white12, height: 1),
            _SettingsTile(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              subtitle: 'Alerts for saved spots',
              trailing: Switch(
                value: false,
                onChanged: (value) {
                  // TODO: Toggle notifications
                },
                activeColor: const Color(0xFF5B9BD5),
              ),
              onTap: null,
            ),
          ]),
          
          const SizedBox(height: 24),
          
          // About Section
          _buildSectionHeader('About'),
          const SizedBox(height: 12),
          _buildSettingsCard([
            _SettingsTile(
              icon: Icons.info_outline,
              title: 'About Shaka',
              subtitle: 'Version 1.0.0',
              onTap: () {
                // TODO: Show about dialog
              },
            ),
            const Divider(color: Colors.white12, height: 1),
            _SettingsTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy Policy',
              onTap: () {
                // TODO: Open privacy policy
              },
            ),
            const Divider(color: Colors.white12, height: 1),
            _SettingsTile(
              icon: Icons.description_outlined,
              title: 'Terms of Service',
              onTap: () {
                // TODO: Open terms
              },
            ),
          ]),
          
          const SizedBox(height: 32),
          
          // App branding
          Center(
            child: Column(
              children: [
                Text(
                  'SHAKA',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Find your dive',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.2),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 100), // Bottom padding for nav bar
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        color: Colors.white.withOpacity(0.5),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: children,
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 22),
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
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              const Icon(
                Icons.chevron_right,
                color: Colors.white38,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
