import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/repositories/reports_preferences_repository.dart';
import '../../../features/fishing_intel/models/fishing_intel_models.dart';
import '../../../features/fishing_intel/services/fishing_intel_service.dart';
import '../../widgets/reports/manage_fish_sheet.dart';

/// Regional fishing reports with horizontal-scroll region chips.
/// SoCal is the first of many regions; add more to [_regions] as the backend supports them.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with TickerProviderStateMixin {
  static const _bgColor = Color(0xFF0D0D0D);
  static const _cardColor = Color(0xFF1A1A1A);
  static const _borderColor = Color(0xFF2A2A2A);
  static const _groupRadius = 12.0;
  static const _speciesRowHPad = 14.0;
  static const _speciesRowVPad = 12.0;
  static const _trendColumnWidth = 28.0;
  static const _trendToNameGap = 4.0;
  static const _separatorIndent =
      _speciesRowHPad + _trendColumnWidth + _trendToNameGap + 10.0;

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
  final _prefsRepo = ReportsPreferencesRepository();
  final Map<String, FishingIntelResponse?> _intelByRegion = {};
  final Map<String, bool> _loading = {};
  final Map<String, String?> _error = {};
  final Map<String, String?> _expandedSpeciesByRegion = {};
  final Map<String, ReportsPreferences> _prefsByRegion = {};

  @override
  void initState() {
    super.initState();
    for (final r in _regions) {
      _loadPrefs(r.id);
      _loadRegion(r.id);
    }
  }

  Future<void> _loadPrefs(String regionId) async {
    try {
      final prefs = await _prefsRepo.load(regionId);
      if (mounted) {
        setState(() {
          _prefsByRegion[regionId] = prefs;
        });
      }
    } catch (_) {
      // No-op: preferences are non-critical; default empty.
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
    final intel = _intelByRegion[_selectedRegion];
    final freshness = intel?.dataFreshness;
    final canManageFish = (intel?.speciesList.isNotEmpty ?? false);

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
        actions: [
          IconButton(
            onPressed: !canManageFish
                ? null
                : () async {
                    HapticFeedback.selectionClick();
                    final regionId = _selectedRegion;
                    final currentIntel = _intelByRegion[regionId];
                    if (currentIntel == null ||
                        currentIntel.speciesList.isEmpty) {
                      return;
                    }
                    final allSpecies =
                        currentIntel.speciesList.map((e) => e.species).toList();
                    final initialPrefs =
                        _prefsByRegion[regionId] ?? ReportsPreferences.empty;

                    final updated = await ManageFishSheet.show(
                      context: context,
                      regionId: regionId,
                      allSpecies: allSpecies,
                      prefsRepo: _prefsRepo,
                      initialPrefs: initialPrefs,
                    );
                    if (!mounted || updated == null) return;
                    setState(() {
                      _prefsByRegion[regionId] = updated;
                      // If the expanded species was hidden, collapse it.
                      final expanded = _expandedSpeciesByRegion[regionId];
                      if (expanded != null &&
                          updated.hiddenSpecies.contains(expanded)) {
                        _expandedSpeciesByRegion[regionId] = null;
                      }
                    });
                  },
            icon: Icon(
              Icons.tune,
              color: canManageFish ? Colors.white70 : Colors.white24,
            ),
            tooltip: 'Manage fish',
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          _buildRegionChips(freshness: freshness),
          Expanded(
            child: _buildRegionContent(_selectedRegion, regionLabel),
          ),
        ],
      ),
    );
  }

  // ─── Region Chips ───────────────────────────────────────────────────

  Widget _buildRegionChips({String? freshness}) {
    final freshnessLabel = freshness != null ? _formatFreshness(freshness) : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          Expanded(
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
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
          ),
          if (freshnessLabel.isNotEmpty) ...[
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.info,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  freshnessLabel,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
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

    final prefs = _prefsByRegion[regionId] ?? ReportsPreferences.empty;
    final speciesList = _applyPrefsToSpeciesList(intel.speciesList, prefs);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              [
                if (intel.keyInsights.isNotEmpty) ...[
                  _buildSectionHeader('INSIGHTS'),
                  const SizedBox(height: 10),
                  _buildInsightsCard(intel.keyInsights),
                  const SizedBox(height: 24),
                ],
                if (speciesList.isNotEmpty) ...[
                  _buildSectionHeader(
                    'CATCH NUMBERS',
                    trailing: _buildBadge('RECENT 3 DAYS'),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
        if (speciesList.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final s = speciesList[index];
                  final isFirst = index == 0;
                  final isLast = index == speciesList.length - 1;
                  return RepaintBoundary(
                    child: _buildSpeciesRow(
                      s,
                      regionId,
                      intel,
                      prefs: prefs,
                      isFirst: isFirst,
                      isLast: isLast,
                    ),
                  );
                },
                childCount: speciesList.length,
              ),
            ),
          ),
        if (speciesList.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            sliver: SliverToBoxAdapter(
              child: _buildSourcesFooter(intel),
            ),
          ),
      ],
    );
  }

  List<TrendingSpecies> _applyPrefsToSpeciesList(
    List<TrendingSpecies> raw,
    ReportsPreferences prefs,
  ) {
    if (raw.isEmpty) return raw;

    final hidden = prefs.hiddenSpecies;
    final pinned = prefs.pinnedSpecies;
    final visible = raw.where((s) => !hidden.contains(s.species)).toList();

    if (visible.isEmpty) return visible;

    final originalIndex = <String, int>{};
    for (var i = 0; i < raw.length; i++) {
      originalIndex[raw[i].species] = i;
    }

    final baseOrder = prefs.manualOrder.isNotEmpty
        ? prefs.manualOrder
        : raw.map((s) => s.species).toList();
    final orderIndex = <String, int>{};
    for (var i = 0; i < baseOrder.length; i++) {
      orderIndex[baseOrder[i]] = i;
    }

    visible.sort((a, b) {
      final aPinned = pinned.contains(a.species);
      final bPinned = pinned.contains(b.species);
      if (aPinned != bPinned) return aPinned ? -1 : 1;

      final aOrder = orderIndex[a.species];
      final bOrder = orderIndex[b.species];
      if (aOrder != null && bOrder != null) return aOrder.compareTo(bOrder);
      if (aOrder != null) return -1;
      if (bOrder != null) return 1;

      final aOrig = originalIndex[a.species] ?? 0;
      final bOrig = originalIndex[b.species] ?? 0;
      return aOrig.compareTo(bOrig);
    });

    return visible;
  }

  // ─── Freshness Banner ──────────────────────────────────────────────

  Widget _buildFreshnessBanner(String raw) {
    final label = _formatFreshness(raw);
    if (label.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: AppColors.info,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
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

  /// Small muted pill badge (e.g. "LAST 3 DAYS").
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

  // ─── Insights ───────────────────────────────────────────────────────

  /// Pick an icon based on insight content keywords.
  static IconData _insightIcon(String insight, int index) {
    final lower = insight.toLowerCase();
    if (lower.contains('bait') ||
        lower.contains('sardine') ||
        lower.contains('anchov')) {
      return Icons.set_meal_outlined;
    }
    if (lower.contains('wind') ||
        lower.contains('weather') ||
        lower.contains('swell') ||
        lower.contains('storm')) {
      return Icons.air;
    }
    if (lower.contains('hot') ||
        lower.contains('fire') ||
        lower.contains('firing') ||
        lower.contains('heat')) {
      return Icons.local_fire_department_outlined;
    }
    if (lower.contains('island') ||
        lower.contains('harbor') ||
        lower.contains('landing') ||
        lower.contains('catalina') ||
        lower.contains('clemente') ||
        lower.contains('coast')) {
      return Icons.place_outlined;
    }
    if (lower.contains('temp') ||
        lower.contains('degree') ||
        lower.contains('warm') ||
        lower.contains('cold')) {
      return Icons.thermostat_outlined;
    }
    // Cycle through defaults for visual variety
    const defaults = [Icons.phishing, Icons.waves, Icons.explore_outlined];
    return defaults[index % defaults.length];
  }

  /// Pick an icon tint color based on insight content keywords.
  static Color _insightIconColor(String insight, int index) {
    final lower = insight.toLowerCase();
    if (lower.contains('bait') ||
        lower.contains('sardine') ||
        lower.contains('anchov')) {
      return const Color(0xFFC9A66B); // amber
    }
    if (lower.contains('wind') ||
        lower.contains('weather') ||
        lower.contains('swell') ||
        lower.contains('storm')) {
      return const Color(0xFF7A9BB8); // blue-gray
    }
    if (lower.contains('hot') ||
        lower.contains('fire') ||
        lower.contains('firing') ||
        lower.contains('heat')) {
      return const Color(0xFFCB8B7A); // coral
    }
    if (lower.contains('island') ||
        lower.contains('harbor') ||
        lower.contains('landing') ||
        lower.contains('catalina') ||
        lower.contains('clemente') ||
        lower.contains('coast')) {
      return const Color(0xFF8FA98B); // sage green
    }
    if (lower.contains('temp') ||
        lower.contains('degree') ||
        lower.contains('warm') ||
        lower.contains('cold')) {
      return const Color(0xFF7A9BB8); // blue-gray
    }
    const defaults = [Color(0xFF7A9BB8), Color(0xFF6B8E7D), Color(0xFFC9A66B)];
    return defaults[index % defaults.length];
  }

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
          final icon = _insightIcon(insight, index);
          final iconColor = _insightIconColor(insight, index);

          return Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Icon accent container
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: iconColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Icon(
                          icon,
                          size: 13,
                          color: iconColor,
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
    FishingIntelResponse intel, {
    required ReportsPreferences prefs,
    required bool isFirst,
    required bool isLast,
  }) {
    final isUp = s.isUp;
    final isDown = s.isDown;
    final trendColor = isUp
        ? AppColors.success
        : isDown
            ? AppColors.error
            : Colors.white54;
    final isExpanded = _expandedSpeciesByRegion[regionId] == s.species;
    final isPinned = prefs.pinnedSpecies.contains(s.species);
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final expandDuration =
        disableAnimations ? Duration.zero : const Duration(milliseconds: 220);

    final borderRadius = BorderRadius.vertical(
      top: isFirst ? const Radius.circular(_groupRadius) : Radius.zero,
      bottom: isLast ? const Radius.circular(_groupRadius) : Radius.zero,
    );

    final cell = Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: borderRadius,
        border: Border(
          left: const BorderSide(color: _borderColor),
          right: const BorderSide(color: _borderColor),
          top:
              isFirst ? const BorderSide(color: _borderColor) : BorderSide.none,
          bottom:
              isLast ? const BorderSide(color: _borderColor) : BorderSide.none,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _expandedSpeciesByRegion[regionId] =
                      isExpanded ? null : s.species;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _speciesRowHPad,
                  vertical: _speciesRowVPad,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Trend indicator: fixed-width, vertically aligned across all rows
                    SizedBox(
                      width: _trendColumnWidth,
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
                    const SizedBox(width: _trendToNameGap),
                    // Species name: fills middle space
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
                    const SizedBox(width: 8),
                    // Count: right-aligned, never truncated
                    Text(
                      '${s.count24h}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isPinned) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.push_pin,
                        size: 14,
                        color: AppColors.info.withOpacity(0.9),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: expandDuration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: expandDuration,
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) {
                final fade = FadeTransition(opacity: animation, child: child);
                final slide = Tween<Offset>(
                  begin: const Offset(0, -0.02),
                  end: Offset.zero,
                ).animate(animation);
                return SlideTransition(position: slide, child: fade);
              },
              child: isExpanded
                  ? Padding(
                      key: ValueKey('flyout_${s.species}'),
                      padding: const EdgeInsets.fromLTRB(
                        _speciesRowHPad,
                        8,
                        _speciesRowHPad,
                        10,
                      ),
                      child: _buildSpeciesFlyout(s),
                    )
                  : const SizedBox.shrink(key: ValueKey('flyout_none')),
            ),
          ),
          if (!isLast)
            Container(
              height: 1,
              margin: const EdgeInsets.only(left: _separatorIndent),
              color: _borderColor,
            ),
        ],
      ),
    );

    return Slidable(
      key: ValueKey('species_${regionId}_${s.species}'),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.52,
        children: [
          SlidableAction(
            onPressed: (_) => _togglePinned(regionId, s.species),
            backgroundColor: const Color(0xFF2A2A2A),
            foregroundColor: Colors.white,
            icon: isPinned ? Icons.push_pin_outlined : Icons.push_pin,
            label: isPinned ? 'Unpin' : 'Pin',
          ),
          SlidableAction(
            onPressed: (_) => _hideSpecies(regionId, s.species),
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            icon: Icons.visibility_off_outlined,
            label: 'Hide',
          ),
        ],
      ),
      child: cell,
    );
  }

  Future<void> _togglePinned(String regionId, String species) async {
    final current = _prefsByRegion[regionId] ?? ReportsPreferences.empty;
    final pinned = {...current.pinnedSpecies};
    final wasPinned = pinned.contains(species);
    if (wasPinned) {
      pinned.remove(species);
    } else {
      pinned.add(species);
    }

    final updated = current.copyWith(pinnedSpecies: pinned);
    setState(() => _prefsByRegion[regionId] = updated);
    await _prefsRepo.savePinnedSpecies(regionId, pinned);

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(wasPinned ? 'Unpinned $species' : 'Pinned $species'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            final revertedPinned = {...pinned};
            if (wasPinned) {
              revertedPinned.add(species);
            } else {
              revertedPinned.remove(species);
            }
            final reverted = current.copyWith(pinnedSpecies: revertedPinned);
            if (!mounted) return;
            setState(() => _prefsByRegion[regionId] = reverted);
            await _prefsRepo.savePinnedSpecies(regionId, revertedPinned);
          },
        ),
      ),
    );
  }

  Future<void> _hideSpecies(String regionId, String species) async {
    final current = _prefsByRegion[regionId] ?? ReportsPreferences.empty;
    final hidden = {...current.hiddenSpecies}..add(species);
    final pinned = {...current.pinnedSpecies}..remove(species);

    final updated =
        current.copyWith(hiddenSpecies: hidden, pinnedSpecies: pinned);
    setState(() {
      _prefsByRegion[regionId] = updated;
      if (_expandedSpeciesByRegion[regionId] == species) {
        _expandedSpeciesByRegion[regionId] = null;
      }
    });

    await _prefsRepo.saveHiddenSpecies(regionId, hidden);
    await _prefsRepo.savePinnedSpecies(regionId, pinned);

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Hid $species'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            final revertedHidden = {...hidden}..remove(species);
            final revertedPinned = {...current.pinnedSpecies};
            final reverted = current.copyWith(
                hiddenSpecies: revertedHidden, pinnedSpecies: revertedPinned);
            if (!mounted) return;
            setState(() => _prefsByRegion[regionId] = reverted);
            await _prefsRepo.saveHiddenSpecies(regionId, revertedHidden);
            await _prefsRepo.savePinnedSpecies(regionId, revertedPinned);
          },
        ),
      ),
    );
  }

  /// Flyout below selected species row: trend vs prior 3 days + counts.
  Widget _buildSpeciesFlyout(TrendingSpecies s) {
    final isUp = s.isUp;
    final isDown = s.isDown;
    final trendColor = isUp
        ? AppColors.success
        : isDown
            ? AppColors.error
            : Colors.white54;
    String changeText;
    if (s.percentChange > 500) {
      changeText = 'New!';
    } else {
      final sign = s.percentChange > 0 ? '+' : '';
      changeText = '$sign${s.percentChange}%';
    }
    return Container(
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
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: trendColor.withValues(alpha: 0.15),
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
              const SizedBox(width: 8),
              Text(
                'VS PREVIOUS 3 DAYS',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: _borderColor),
          const SizedBox(height: 12),
          _buildFlyoutStatRow('Recent 3 days', '${s.count24h}'),
          const SizedBox(height: 8),
          _buildFlyoutStatRow('Previous 3 days', '${s.countPrevious}'),
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
    final sources =
        intel.sourcesUsed.isNotEmpty ? intel.sourcesUsed : ['Regional reports'];

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
          // Row 1: report count
          Text(
            '${intel.totalReports} reports analyzed',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          // Row 2: source chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: sources.map((source) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            'Recent 3 days vs previous 3 days (excludes today)',
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
