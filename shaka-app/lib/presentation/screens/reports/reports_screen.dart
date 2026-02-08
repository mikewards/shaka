import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/fishing_intel/models/fishing_intel_models.dart';
import '../../../features/fishing_intel/services/fishing_intel_service.dart';

/// Regional fishing reports. Region-ready UI: tabs for SoCal (and future NorCal, etc.).
/// Data is filtered by sources.regional_report in the backend; no spot/geo.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  static const _bgColor = Color(0xFF0D0D0D);
  static const _cardColor = Color(0xFF1A1A1A);
  static const _borderColor = Color(0xFF2A2A2A);

  /// Region tabs: SoCal first; add more (e.g. NorCal) here when backend has them.
  static const _regions = [
    _RegionTab(id: 'socal', label: 'SoCal'),
    // Future: _RegionTab(id: 'norcal', label: 'NorCal'),
  ];

  late TabController _tabController;
  final _service = FishingIntelService();
  final Map<String, FishingIntelResponse?> _intelByRegion = {};
  final Map<String, bool> _loading = {};
  final Map<String, String?> _error = {};
  /// Expanded species key per region: when set, that fish row shows calculation details.
  final Map<String, String?> _expandedSpeciesByRegion = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _regions.length, vsync: this);
    for (final r in _regions) {
      _loadRegion(r.id);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRegion(String regionId) async {
    setState(() {
      _loading[regionId] = true;
      _error[regionId] = null;
    });
    try {
      final tzOffset = DateTime.now().timeZoneOffset.inHours;
      final response = await _service.getRegionIntel(
        regionId,
        tzOffset: tzOffset,
      );
      if (mounted) {
        setState(() {
          _intelByRegion[regionId] = response;
          _loading[regionId] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error[regionId] = e.toString();
          _loading[regionId] = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        title: const Text(
          'Fishing Reports',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: _regions.length > 1
            ? TabBar(
                controller: _tabController,
                indicatorColor: AppColors.info,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                tabs: _regions
                    .map((r) => Tab(text: r.label))
                    .toList(),
              )
            : null,
      ),
      body: _regions.length > 1
          ? TabBarView(
              controller: _tabController,
              children: _regions
                  .map((r) => _buildRegionContent(r.id, r.label))
                  .toList(),
            )
          : _buildRegionContent(_regions.first.id, _regions.first.label),
    );
  }

  Widget _buildRegionContent(String regionId, String regionLabel) {
    if (_loading[regionId] == true) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: AppColors.info),
        ),
      );
    }
    if (_error[regionId] != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Unable to load $regionLabel fishing reports',
            style: TextStyle(color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final intel = _intelByRegion[regionId];
    if (intel == null || !intel.hasData) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.phishing, size: 48, color: Colors.grey[700]),
              const SizedBox(height: 16),
              Text(
                'No recent $regionLabel fishing reports',
                style: TextStyle(color: Colors.grey[500]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Section title: regional report name
        Text(
          '$regionLabel Fishing Report',
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        // Insights (Groq-generated, Hemingway-style)
        if (intel.keyInsights.isNotEmpty) ...[
          _buildInsightsSection(intel.keyInsights),
          const SizedBox(height: 20),
        ],
        // Catch numbers (expandable rows; proportional height)
        if (intel.speciesList.isNotEmpty) ...[
          Text(
            'Catch Numbers | Last 48hr',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ...intel.speciesList.asMap().entries.map((entry) {
            final index = entry.key;
            final s = entry.value;
            return Padding(
              padding: EdgeInsets.only(bottom: index < intel.speciesList.length - 1 ? 6 : 0),
              child: _buildSpeciesRow(s, regionId, intel),
            );
          }),
          const SizedBox(height: 16),
          _buildSourcesAndDetails(intel),
        ],
      ],
    );
  }

  Widget _buildInsightsSection(List<String> keyInsights) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Insights',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ...keyInsights.map(
            (line) {
              // Format "Headline, detail" as "Headline\n        • detail" to avoid wrapping
              final displayText = line.contains(',')
                  ? '${line.substring(0, line.indexOf(',')).trim()}\n        • ${line.substring(line.indexOf(',') + 1).trim()}'
                  : line;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  displayText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.35,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNarrativeCard(NarrativeInsight insight) {
    final displayTldr = insight.tldr.isNotEmpty
        ? insight.tldr
        : '${insight.species} at ${insight.location}';
    final dateLabel = _formatInsightDate(insight.publishedAt);
    final showExcerpt = insight.tldr.isEmpty &&
        insight.excerpt.isNotEmpty &&
        insight.excerpt != displayTldr;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (dateLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                dateLabel,
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
            ),
          Text(
            displayTldr,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 8,
            overflow: TextOverflow.clip,
          ),
          if (showExcerpt) ...[
            const SizedBox(height: 6),
            Text(
              insight.excerpt,
              style: TextStyle(color: Colors.grey[400], fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (insight.threadUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _launchUrl(insight.threadUrl);
              },
              child: Text(
                'View source →',
                style: TextStyle(
                  color: AppColors.info,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatInsightDate(String publishedAt) {
    if (publishedAt.isEmpty) return '';
    try {
      final dt = DateTime.parse(publishedAt);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inDays == 0) return 'Today';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays} days ago';
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return '';
    }
  }

  Widget _buildSpeciesRow(
    TrendingSpecies s,
    String regionId,
    FishingIntelResponse intel,
  ) {
    final isUp = s.isUp;
    final isDown = s.isDown;
    final trendColor = isUp
        ? const Color(0xFF22C55E)
        : isDown
            ? const Color(0xFFEF4444)
            : Colors.white54;
    final isExpanded = _expandedSpeciesByRegion[regionId] == s.species;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() {
              _expandedSpeciesByRegion[regionId] =
                  isExpanded ? null : s.species;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _borderColor),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    s.species,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                // Fixed-width block: caret column (32) then count + chevron so all ^/v align
                SizedBox(
                  width: 100,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 32,
                        child: Center(
                          child: _TrendArrow(
                            isUp: isUp,
                            isDown: isDown,
                            percentChange: s.percentChange,
                            color: trendColor,
                            showPercentInFlyoutOnly: true,
                          ),
                        ),
                      ),
                      Text(
                        '${s.count24h}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: Colors.white38,
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded) ...[
          const SizedBox(height: 6),
          _buildSpeciesFlyout(s),
        ],
      ],
    );
  }

  /// Flyout below selected row: vs 5 day trailing avg and percent only.
  Widget _buildSpeciesFlyout(TrendingSpecies s) {
    final isUp = s.isUp;
    final isDown = s.isDown;
    final trendColor = isUp
        ? const Color(0xFF22C55E)
        : isDown
            ? const Color(0xFFEF4444)
            : Colors.white54;
    String changeText;
    if (s.percentChange > 500) {
      changeText = 'New!';
    } else {
      final sign = s.percentChange > 0 ? '+' : '';
      changeText = '$sign${s.percentChange}%';
    }
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _borderColor),
        ),
        child: Row(
          children: [
            Text(
              'vs 5 day trailing avg',
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              changeText,
              style: TextStyle(
                color: trendColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourcesAndDetails(FishingIntelResponse intel) {
    final sourcesLabel = intel.sourcesUsed.isEmpty
        ? 'Regional reports'
        : intel.sourcesUsed.join(', ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardColor.withOpacity(0.8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sources and details',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${intel.totalReports} reports. Data: last 48hr catch counts vs 5-day trailing average. Sources: $sourcesLabel.',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// Ticker-style trend indicator: ↑ green, ↓ red, − gray. Percent can be shown on row or only in flyout.
class _TrendArrow extends StatelessWidget {
  final bool isUp;
  final bool isDown;
  final int percentChange;
  final Color color;
  /// When true, show only the caret on the row; percent is shown in the flyout.
  final bool showPercentInFlyoutOnly;

  const _TrendArrow({
    required this.isUp,
    required this.isDown,
    required this.percentChange,
    required this.color,
    this.showPercentInFlyoutOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    IconData icon;
    String? suffix;
    if (isUp) {
      icon = Icons.arrow_drop_up;
      if (!showPercentInFlyoutOnly) {
        if (percentChange > 500) suffix = 'New!';
        else if (percentChange > 0) suffix = '+$percentChange%';
      }
    } else if (isDown) {
      icon = Icons.arrow_drop_down;
      if (!showPercentInFlyoutOnly) suffix = '$percentChange%';
    } else {
      icon = Icons.remove;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 28),
        if (suffix != null)
          Text(
            suffix,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
      ],
    );
  }
}

class _RegionTab {
  final String id;
  final String label;
  const _RegionTab({required this.id, required this.label});
}
