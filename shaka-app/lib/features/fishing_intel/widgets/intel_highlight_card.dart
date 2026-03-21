import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/fishing_intel_models.dart';
import '../../../core/theme/app_colors.dart';

class IntelHighlightCard extends StatelessWidget {
  final IntelHighlight highlight;
  
  const IntelHighlightCard({required this.highlight, super.key});
  
  static const _cardColor = AppColors.darkSurface;
  static const _borderColor = AppColors.darkBorder;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text('🐟 ', style: TextStyle(fontSize: 16)),
                    Text(
                      highlight.speciesDisplay.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${highlight.distanceMi.toStringAsFixed(1)}mi away',
                  style: TextStyle(
                    color: AppColors.darkTextMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          
          // Count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              highlight.countDisplay,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
          ),
          
          // Excerpt
          if (highlight.excerpt.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black26,
                border: Border(
                  top: BorderSide(color: _borderColor),
                  bottom: BorderSide(color: _borderColor),
                ),
              ),
              child: Text(
                '"${highlight.excerpt}"',
                style: TextStyle(
                  color: AppColors.darkTextMuted,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          
          // Footer
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.location_on, size: 14, color: AppColors.darkTextMuted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${highlight.boatName ?? ""}${highlight.boatName != null ? " @ " : ""}${highlight.landingName}',
                        style: TextStyle(color: AppColors.darkTextMuted, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 14, color: AppColors.darkTextHint),
                        const SizedBox(width: 4),
                        Text(
                          _formatTime(highlight.publishedAt),
                          style: TextStyle(color: AppColors.darkTextMuted, fontSize: 11),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () => _openSource(highlight.sourceUrl),
                      child: Row(
                        children: [
                          Text(
                            highlight.sourceName,
                            style: const TextStyle(
                              color: AppColors.info,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(Icons.open_in_new, size: 12, color: AppColors.info),
                        ],
                      ),
                    ),
                  ],
                ),
                if (highlight.corroboratedBy.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.check_circle, size: 12, color: AppColors.success),
                      const SizedBox(width: 4),
                      Text(
                        'Also on: ${highlight.corroboratedBy.join(", ")}',
                        style: TextStyle(color: AppColors.darkTextMuted, fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  String _formatTime(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final diff = now.difference(date);
      
      if (diff.inMinutes < 60) {
        return '${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        return '${diff.inHours}h ago';
      } else {
        return '${diff.inDays}d ago';
      }
    } catch (e) {
      return '';
    }
  }
  
  void _openSource(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
