import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/fishing_intel/models/fishing_intel_models.dart';
import '../../../features/fishing_intel/services/fishing_intel_service.dart';

/// Regional fishing reports with horizontal-scroll region chips.
/// SoCal is the first of many regions; add more to [_regions] as the backend supports them.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  static const _bgColor = Color(0xFF0D0D0D);
  static const _cardColor = Color(0xFF1A1A1A);
  static const _borderColor = Color(0xFF2A2A2A);

  /// Region list: SoCal first; add more here as backend supports them.
  static const _regions = [
    _Region(id: 'socal', label: 'SoCal'),
    // Future regions — just uncomment when ready:
    // _Region(id: 'norcal', label: 'NorCal'),
    // _Region(id: 'baja', label: 'Baja'),
    // _Region(id: 'hawaii', label: 'Hawaii'),
  ];

  String _selectedRegion = _regions.first.id;
  final _service = FishingIntelService();
  final Map<String, FishingIntelResponse?> _intelByRegion = {};
  final Map<String, bool> _loading = {};
  final Map<String, String?> _error = {};
  final Map<String, String?> _expandedSpeciesByRegion = {};

  @override
  void initState() {
    super.initState();
    for (final r in _regions) {
      _loadRegion(r.id);
    }
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

  // ─── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final regionLabel =
        _regions.firstWhere((r) => r.id == _selectedRegion).label;

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
      ),
      body: Column(
        children: [
          _buildRegionChips(),
          Expanded(
            child: _buildRegionContent(_selectedRegion, regionLabel),
          ),
        ],
      ),
    );
  }

  // ─── Region Chips ───────────────────────────────────────────────────

  Widget _buildRegionChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _regions.map((r) {
            final isSelected = r.id == _selectedRegion;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  if (!isSelected) {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedRegion = r.id);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.info.withOpacity(0.15)
                        : _cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? AppColors.info : _borderColor,
                    ),
                  ),
                  child: Text(
                    r.label,
                    style: TextStyle(
                      color: isSelected ? AppColors.info : Colors.white70,
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ─── Region Content ─────────────────────────────────────────────────

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
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        // ── Headline hero card (only for HOT / ON FIRE, not generic trending) ──
        if (intel.headline != null && intel.headline!.heatLevel >= 2) ...[
          _buildHeadlineCard(intel.headline!),
          const SizedBox(height: 24),
        ],
        // ── Insights ──
        if (intel.keyInsights.isNotEmpty) ...[
          _buildSectionHeader('INSIGHTS'),
          const SizedBox(height: 10),
          _buildInsightsCard(intel.keyInsights),
          const SizedBox(height: 24),
        ],
        // ── Catch numbers ──
        if (intel.speciesList.isNotEmpty) ...[
          _buildSectionHeader(
            'CATCH NUMBERS',
            trailing: _buildBadge('LAST 48HR'),
          ),
          const SizedBox(height: 10),
          ...intel.speciesList.asMap().entries.map((entry) {
            final index = entry.key;
            final s = entry.value;
            return Padding(
              padding: EdgeInsets.only(
                bottom: index < intel.speciesList.length - 1 ? 6 : 0,
              ),
              child: _buildSpeciesRow(s, regionId, intel),
            );
          }),
          const SizedBox(height: 20),
          _buildSourcesFooter(intel),
        ],
      ],
    );
  }

  // ─── Section Header ─────────────────────────────────────────────────

  /// Uppercase, letter-spaced section header matching SpotDetail / Profile patterns.
  Widget _buildSectionHeader(String title, {Widget? trailing}) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          trailing,
        ],
      ],
    );
  }

  /// Small muted pill badge (e.g. "LAST 48HR").
  Widget _buildBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _borderColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withOpacity(0.4),
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  // ─── Headline Hero Card ─────────────────────────────────────────────

  Widget _buildHeadlineCard(Headline headline) {
    // Heat-level color: 1=warm (info), 2=hot (warning), 3=on fire (red)
    final heatColor = headline.heatLevel >= 3
        ? const Color(0xFFEF4444)
        : headline.heatLevel == 2
            ? AppColors.warning
            : AppColors.info;
    final heatLabel = headline.heatLevel >= 3
        ? 'ON FIRE'
        : headline.heatLevel == 2
            ? 'HOT'
            : 'TRENDING';

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left accent bar — stretches to full card height
            Container(width: 3, color: heatColor),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Heat badge pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: heatColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        heatLabel,
                        style: TextStyle(
                          color: heatColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Main message
                    Text(
                      headline.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Bottom row: count badge + top landing
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _borderColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${headline.count24h} caught',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (headline.topLanding != null &&
                            headline.topLanding!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              headline.topLanding!,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Insights ───────────────────────────────────────────────────────

  /// Structured insight rows inside a card with dividers and icon accents.
  Widget _buildInsightsCard(List<String> keyInsights) {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: keyInsights.asMap().entries.map((entry) {
          final index = entry.key;
          final insight = entry.value;
          final isLast = index == keyInsights.length - 1;

          return Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon accent container
                    Container(
                      width: 24,
                      height: 24,
                      margin: const EdgeInsets.only(top: 1),
                      decoration: BoxDecoration(
                        color: AppColors.info.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.water_drop_outlined,
                          size: 13,
                          color: AppColors.info,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Insight text
                    Expanded(
                      child: Text(
                        insight,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Divider between rows (indented past the icon)
              if (!isLast)
                Container(
                  height: 1,
                  margin: const EdgeInsets.only(left: 50),
                  color: _borderColor,
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ─── Catch Numbers: Species Rows ────────────────────────────────────

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
                // Species name: up to 75% of tile width
                Expanded(
                  flex: 3,
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
                // Caret pinned at 75%, count + chevron right-aligned
                Expanded(
                  flex: 1,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 28,
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
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Flexible(
                              child: Text(
                                '${s.count24h}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              isExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              color: Colors.white38,
                              size: 20,
                            ),
                          ],
                        ),
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

  /// Flyout below selected species row: trend vs 5-day avg + counts.
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
    return Container(
      margin: const EdgeInsets.only(left: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'VS 5-DAY AVG',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: trendColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  changeText,
                  style: TextStyle(
                    color: trendColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: _borderColor),
          const SizedBox(height: 12),
          _buildFlyoutStatRow('Last 48 hours', '${s.count24h}'),
          const SizedBox(height: 8),
          _buildFlyoutStatRow('Trailing 5-day avg', '${s.countPrevious}'),
        ],
      ),
    );
  }

  Widget _buildFlyoutStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.55),
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ─── Sources Footer ─────────────────────────────────────────────────

  /// Structured sources footer: report count, source chips, methodology line.
  Widget _buildSourcesFooter(FishingIntelResponse intel) {
    final sources = intel.sourcesUsed.isNotEmpty
        ? intel.sourcesUsed
        : ['Regional reports'];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: report count left, freshness right
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${intel.totalReports} reports',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (intel.dataFreshness.isNotEmpty)
                Text(
                  _formatFreshness(intel.dataFreshness),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.35),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Row 2: source chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: sources.map((source) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _borderColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  source,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          // Row 3: methodology note
          Text(
            '48hr catch counts vs 5-day trailing average',
            style: TextStyle(
              color: Colors.white.withOpacity(0.25),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Narrative Card (kept for future use) ───────────────────────────

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
              child: const Text(
                'View source',
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

  /// Parse ISO-8601 dataFreshness timestamp into a human-readable label.
  String _formatFreshness(String raw) {
    try {
      final dt = DateTime.parse(raw);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 2) return 'Updated just now';
      if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes}m ago';
      if (diff.inHours < 24) return 'Updated ${diff.inHours}hr ago';
      if (diff.inDays == 1) return 'Updated yesterday';
      return 'Updated ${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
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

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// ─── Private Widgets ──────────────────────────────────────────────────

/// Ticker-style trend indicator: up green, down red, stable gray.
class _TrendArrow extends StatelessWidget {
  final bool isUp;
  final bool isDown;
  final int percentChange;
  final Color color;
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
        if (percentChange > 500) {
          suffix = 'New!';
        } else if (percentChange > 0) {
          suffix = '+$percentChange%';
        }
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
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
      ],
    );
  }
}

class _Region {
  final String id;
  final String label;
  const _Region({required this.id, required this.label});
}
