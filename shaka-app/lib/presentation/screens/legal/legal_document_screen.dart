import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/legal/legal_content.dart';
import 'legal_card.dart';

/// Lightweight in-app wrapper for a hosted legal document. Shows the plain
/// summary and opens the full, canonical page (served by the API) in the
/// browser. Used for both the Privacy Policy and the Terms of Service.
class LegalDocumentScreen extends StatelessWidget {
  final String title;
  final String url;

  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.url,
  });

  Future<void> _open(BuildContext context) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open $url'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
        elevation: 0,
        title: Text(
          title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          legalSectionLabel('About Shaka'),
          LegalCard(
            child: Text(
              LegalContent.summary,
              style: const TextStyle(
                color: AppColors.darkTextSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 24),
          legalSectionLabel('Full document'),
          LegalLinkRow(
            icon: title.toLowerCase().contains('privacy')
                ? Icons.privacy_tip_outlined
                : Icons.description_outlined,
            iconColor: AppColors.info,
            title: 'Open $title',
            subtitle: 'Opens the latest version in your browser',
            onTap: () => _open(context),
          ),
        ],
      ),
    );
  }
}
