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
        // Narrative insights
        if (intel.narrativeInsights.isNotEmpty) ...[
          ...intel.narrativeInsights.map((insight) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildNarrativeCard(insight),
              )),
          const SizedBox(height: 20),
        ],
        if (intel.hasData && intel.narrativeInsights.isEmpty) ...[
          Text(
            'Light activity — no standout bite.',
            style: TextStyle(
                color: Colors.grey[500], fontSize: 14, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 16),
        ],
        // Last 24hr catch numbers
        if (intel.speciesList.isNotEmpty) ...[
          Text(
            'Last 24hr » Catch Numbers',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ...intel.speciesList.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _buildSpeciesRow(s),
              )),
          const SizedBox(height: 16),
        ],
        // Attribution
        Text(
          '${intel.totalReports} reports from ${intel.sourcesUsed.join(", ")}',
          style: TextStyle(color: Colors.grey[600], fontSize: 11),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        // More regions coming soon
        Center(
          child: Text(
            'More regions coming soon',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ),
      ],
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

  Widget _buildSpeciesRow(TrendingSpecies s) {
    final isUp = s.isUp;
    final isDown = s.isDown;
    final primaryColor = isUp
        ? const Color(0xFF22C55E)
        : isDown
            ? const Color(0xFFEF4444)
            : Colors.white.withOpacity(0.5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.species,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  s.primaryLabel,
                  style: TextStyle(
                      color: primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                ),
                if (s.secondaryLabel.isNotEmpty)
                  Text(
                    s.secondaryLabel,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.4), fontSize: 11),
                  ),
              ],
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

class _RegionTab {
  final String id;
  final String label;
  const _RegionTab({required this.id, required this.label});
}
