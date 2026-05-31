import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/legal/legal_content.dart';
import '../../../data/services/legal_acceptance_service.dart';
import 'legal_card.dart';

/// First-launch clickwrap. The user must affirmatively check the box and tap
/// "I Agree" before they can use the app. Acceptance is recorded via
/// [LegalAcceptanceService]; [onAccepted] is invoked to leave the gate.
///
/// Designed as a conspicuous, scrollable clickwrap with explicit
/// "by tapping I Agree you accept" language and tappable links to the full
/// Terms and Privacy Policy.
class DisclaimerAcceptanceScreen extends StatefulWidget {
  final VoidCallback onAccepted;

  const DisclaimerAcceptanceScreen({super.key, required this.onAccepted});

  @override
  State<DisclaimerAcceptanceScreen> createState() =>
      _DisclaimerAcceptanceScreenState();
}

class _DisclaimerAcceptanceScreenState
    extends State<DisclaimerAcceptanceScreen> {
  bool _checked = false;
  bool _submitting = false;

  Future<void> _openUrl(String url) async {
    HapticFeedback.lightImpact();
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open $url'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _accept() async {
    if (!_checked || _submitting) return;
    setState(() => _submitting = true);
    HapticFeedback.lightImpact();
    await LegalAcceptanceService.recordAcceptance();
    if (mounted) widget.onAccepted();
  }

  // No account exists, so declining simply means the app stays gated. We
  // explain that rather than silently doing nothing on the disabled button.
  void _decline() {
    HapticFeedback.lightImpact();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Agreement required',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'You can only use Shaka after accepting the Terms of Service and '
          'Privacy Policy. You can review them above, then check the box and '
          'tap "I Agree" to continue.',
          style: TextStyle(color: AppColors.darkTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK',
                style: TextStyle(color: AppColors.darkAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
                children: [
                  const Text(
                    'Welcome to Shaka',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    LegalContent.tagline,
                    style: const TextStyle(
                      color: AppColors.darkAccent,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  legalSectionLabel('Before you start'),
                  LegalCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0;
                            i < LegalContent.acknowledgements.length;
                            i++) ...[
                          if (i > 0) const SizedBox(height: 14),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2, right: 10),
                                child: Icon(Icons.check_circle_outline,
                                    color: AppColors.darkAccent, size: 18),
                              ),
                              Expanded(
                                child: Text(
                                  LegalContent.acknowledgements[i],
                                  style: const TextStyle(
                                    color: AppColors.darkTextSecondary,
                                    fontSize: 14,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _DocLinkButton(
                          label: 'Terms of Service',
                          onTap: () => _openUrl(LegalContent.termsUrl),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DocLinkButton(
                          label: 'Privacy Policy',
                          onTap: () => _openUrl(LegalContent.privacyUrl),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Acceptance controls (always visible above the fold)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: const BoxDecoration(
                color: AppColors.darkSurface,
                border: Border(
                    top: BorderSide(color: AppColors.darkBorder)),
              ),
              child: Column(
                children: [
                  InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _checked = !_checked);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _checked,
                            activeColor: AppColors.darkAccent,
                            onChanged: (v) {
                              HapticFeedback.selectionClick();
                              setState(() => _checked = v ?? false);
                            },
                          ),
                          const Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text(
                                'I have read and agree to the Terms of Service '
                                'and Privacy Policy, and I understand Shaka is a '
                                'planning aid, not a safety device.',
                                style: TextStyle(
                                  color: AppColors.darkTextSecondary,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _checked && !_submitting ? _accept : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.darkAccent,
                        disabledBackgroundColor: AppColors.darkBorder,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'I Agree',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  TextButton(
                    onPressed: _submitting ? null : _decline,
                    child: const Text(
                      'Decline',
                      style: TextStyle(color: AppColors.darkTextMuted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocLinkButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DocLinkButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.darkBorder),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.darkAccent,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
