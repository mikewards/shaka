import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/api/shaka_api_client.dart';
import '../../../data/models/spot_models.dart';
import '../../bloc/search_bloc.dart';
import '../../widgets/conditions_card.dart';
import '../../widgets/satellite_readings_card.dart';

class SpotDetailScreen extends StatefulWidget {
  final String spotId;
  final String date;
  final SpotSummary? preloadedSpot;
  final bool isUserSpot;

  const SpotDetailScreen({
    super.key,
    required this.spotId,
    required this.date,
    this.preloadedSpot,
    this.isUserSpot = false,
  });

  @override
  State<SpotDetailScreen> createState() => _SpotDetailScreenState();
}

class _SpotDetailScreenState extends State<SpotDetailScreen>
    with SingleTickerProviderStateMixin {
  bool _hasLoaded = false;
  late TabController _tabController;

  // Dark theme colors
  static const _bgColor = Color(0xFF0D0D0D);
  static const _cardColor = Color(0xFF1A1A1A);
  static const _borderColor = Color(0xFF2A2A2A);

  // User spot handling
  final _apiClient = ShakaApiClient();
  SpotDetail? _userSpotDetail;
  bool _userSpotLoading = false;
  String? _userSpotError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSpotDetail();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadSpotDetail() {
    if (_hasLoaded) return;
    _hasLoaded = true;
    
    if (widget.isUserSpot) {
      _loadUserSpotDetail();
    } else {
      context.read<SearchBloc>().add(LoadSpotDetail(
            spotId: widget.spotId,
            date: widget.date,
          ));
    }
  }

  Future<void> _loadUserSpotDetail() async {
    setState(() => _userSpotLoading = true);
    try {
      final response = await _apiClient.getUserSpotDetail(
        spotId: widget.spotId,
        date: widget.date,
      );
      if (mounted) {
        setState(() {
          _userSpotDetail = response.spot;
          _userSpotLoading = false;
        });
        // If MPA hasn't been checked yet, poll in background until it is
        if (response.spot.regulations?.mpaChecked == false) {
          _pollForMPA();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _userSpotError = e.toString();
          _userSpotLoading = false;
        });
      }
    }
  }

  /// Re-fetch spot detail in background until MPA data arrives.
  /// Same pattern as _fetchMissingScores() on the GIBS map for shaka scores.
  Future<void> _pollForMPA() async {
    while (mounted) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      try {
        final response = await _apiClient.getUserSpotDetail(
          spotId: widget.spotId,
          date: widget.date,
        );
        if (response.spot.regulations?.mpaChecked == true) {
          if (mounted) {
            setState(() => _userSpotDetail = response.spot);
          }
          return; // MPA data arrived, stop polling
        }
      } catch (_) {
        // Ignore errors, will retry on next poll
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Handle user spot case separately
    if (widget.isUserSpot) {
      return Scaffold(
        backgroundColor: _bgColor,
        body: _buildUserSpotContent(),
      );
    }

    return Scaffold(
      backgroundColor: _bgColor,
      body: BlocBuilder<SearchBloc, SearchState>(
        builder: (context, state) {
          if (state is SpotDetailSuccess) {
            return _buildTabbedContent(state.spot);
          }

          if (state is SearchError) {
            return _buildError(state.message);
          }

          if (widget.preloadedSpot != null) {
            return _buildPreloadedContent(widget.preloadedSpot!);
          }

          return _buildLoadingState();
        },
      ),
    );
  }

  Widget _buildUserSpotContent() {
    if (_userSpotLoading) {
      return _buildLoadingState();
    }
    
    if (_userSpotError != null) {
      return _buildError(_userSpotError!);
    }
    
    if (_userSpotDetail != null) {
      return _buildTabbedContent(_userSpotDetail!);
    }
    
    return _buildLoadingState();
  }

  /// Full tabbed content when SpotDetail is loaded
  Widget _buildTabbedContent(SpotDetail spot) {
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [
          // Header with back button and spot info
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: _bgColor,
            leading: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: IconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  context.pop();
                },
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHeader(spot),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: _buildTabBar(),
            ),
          ),
        ];
      },
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCurrentTab(spot),
          _buildForecastTab(spot),
          _buildGuideTab(spot),
        ],
      ),
    );
  }

  Widget _buildHeader(SpotDetail spot) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E3A5F), _bgColor],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(56, 80, 20, 60),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  spot.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  spot.bestTimeOfDay,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          // Score badge
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _getScoreColor(spot.score.overall).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _getScoreColor(spot.score.overall),
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                '${spot.score.overall}',
                style: TextStyle(
                  color: _getScoreColor(spot.score.overall),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: _bgColor,
      child: TabBar(
        controller: _tabController,
        indicatorColor: AppColors.info,
        indicatorWeight: 3,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white54,
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        tabs: const [
          Tab(text: 'Conditions'),
          Tab(text: 'Forecast'),
          Tab(text: 'Regulations'),
        ],
      ),
    );
  }

  /// CURRENT TAB - Live conditions, score breakdown, risks
  Widget _buildCurrentTab(SpotDetail spot) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Conditions
        _buildSectionHeader('CONDITIONS'),
        const SizedBox(height: 10),
        ConditionsCard(conditions: spot.conditions),

        const SizedBox(height: 20),

        // Satellite Readings (Visibility)
        if (spot.satelliteReadings != null && spot.satelliteReadings!.hasAnyData) ...[
          _buildSectionHeader('VISIBILITY (CHLOROPHYLL-A) SATELLITE READINGS'),
          const SizedBox(height: 10),
          SatelliteReadingsCard(readings: spot.satelliteReadings),
          const SizedBox(height: 20),
        ],

        // Score Breakdown
        _buildSectionHeader('SCORE BREAKDOWN'),
        const SizedBox(height: 10),
        _buildScoreBreakdown(spot.score.breakdown),

        const SizedBox(height: 20),

        // Risks
        if (spot.risks.isNotEmpty) ...[
          _buildSectionHeader('RISKS'),
          const SizedBox(height: 10),
          _buildRisksList(spot.risks),
        ],

        const SizedBox(height: 24),

        // Ocean Charts section
        _buildSectionHeader('OCEAN DATA'),
        const SizedBox(height: 10),
        Row(
          children: [
            // Satellite Imagery button
            Expanded(
              child: _buildChartButton(
                icon: Icons.satellite_alt,
                label: 'Satellite',
                sublabel: 'NASA GIBS',
                color: const Color(0xFF4CAF50),
                onTap: () {
                  HapticFeedback.lightImpact();
                  context.push('/charts/gibs', extra: {
                    'lat': spot.coordinates.lat,
                    'lon': spot.coordinates.lon,
                    'spotName': spot.name,
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            // Ocean Conditions button
            Expanded(
              child: _buildChartButton(
                icon: Icons.waves,
                label: 'Conditions',
                sublabel: 'Copernicus',
                color: AppColors.info,
                onTap: () {
                  HapticFeedback.lightImpact();
                  context.push('/charts/copernicus', extra: {
                    'lat': spot.coordinates.lat,
                    'lon': spot.coordinates.lon,
                    'spotName': spot.name,
                  });
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 40),
      ],
    );
  }

  /// FORECAST TAB - Multi-day forecast
  Widget _buildForecastTab(SpotDetail spot) {
    if (spot.forecast.isEmpty) {
      return const Center(
        child: Text(
          'Forecast data unavailable',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      physics: const ClampingScrollPhysics(),
      itemCount: spot.forecast.length,
      itemBuilder: (context, index) {
        final day = spot.forecast[index];
        return _buildForecastCard(day, index == 0);
      },
    );
  }

  Widget _buildForecastCard(DayForecast day, bool isToday) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        children: [
          // Date
          SizedBox(
            width: 70,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isToday ? 'Today' : _formatDate(day.date),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _formatWeekday(day.date),
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),

          // Score
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getScoreColor(day.shakaScore).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: _getScoreColor(day.shakaScore), width: 1.5),
            ),
            child: Center(
              child: Text(
                '${day.shakaScore}',
                style: TextStyle(
                  color: _getScoreColor(day.shakaScore),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          const SizedBox(width: 14),

          // Conditions summary with icons
          Expanded(
            child: Row(
              children: [
                _buildForecastCondition(Icons.visibility, day.conditions.visibility.split(' ').first),
                const SizedBox(width: 10),
                _buildForecastCondition(Icons.waves, day.conditions.swell.split('@').first.trim()),
                const SizedBox(width: 10),
                _buildForecastCondition(Icons.air, day.conditions.wind),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForecastCondition(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white54, size: 14),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// REGULATIONS TAB - MPA warnings, regulations, fish info
  Widget _buildGuideTab(SpotDetail spot) {
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const ClampingScrollPhysics(),
      children: [
        // Regulations
        if (spot.regulations != null) ...[
          _buildRegulationsInfo(spot.regulations!),
          const SizedBox(height: 24),
        ],

        // Expected Fish
        if (spot.expectedFish.isNotEmpty) ...[
          _buildSectionHeader('FISH'),
          const SizedBox(height: 10),
          _buildFishList(spot.expectedFish),
          const SizedBox(height: 24),
        ],

        const SizedBox(height: 40),
      ],
    );
  }

  // ============ HELPER WIDGETS ============

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.white.withOpacity(0.5),
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }
  
  /// Build a chart shortcut button
  Widget _buildChartButton({
    required IconData icon,
    required String label,
    required String sublabel,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              sublabel,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreBreakdown(ScoreBreakdown breakdown) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          _buildScoreRow('Visibility', breakdown.visibility),
          _buildScoreRow('Weather', breakdown.weather),
          _buildScoreRow('Swell', breakdown.swell),
          _buildScoreRow('Fish Activity', breakdown.fishActivity),
          _buildScoreRow('Accessibility', breakdown.accessibility, isLast: true),
        ],
      ),
    );
  }

  Widget _buildScoreRow(String label, int score, {bool isLast = false}) {
    return Container(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10, top: isLast ? 0 : 0),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Colors.white10)),
      ),
      margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Row(
            children: [
              Container(
                width: 80,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: score / 100,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _getScoreColor(score),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 30,
                child: Text(
                  '$score',
                  style: TextStyle(
                    color: _getScoreColor(score),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRisksList(List<RiskInfo> risks) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: risks
            .map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber,
                          color: AppColors.warning, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          r.risk,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildFishList(List<FishInfo> fish) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: fish
          .map((f) => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _cardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _borderColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      f.name,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    if (f.likelihood == 'very likely') ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.star, color: Colors.amber, size: 14),
                    ],
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _buildAccessInfo(AccessInfo access) {
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
          Text(
            access.directions,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 10),
          Text(
            access.parkingInfo,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildRegulationsInfo(RegulationInfo regulations) {
    final mpa = regulations.mpaStatus;
    
    // Determine MPA status color and text based on isInsideMPA
    Color statusColor;
    String statusText;
    IconData? statusIcon;
    String? detailText;
    
    if (mpa == null && !regulations.mpaChecked) {
      // MPA check hasn't run yet -- show loading state (not the false "No Restrictions")
      statusColor = Colors.grey;
      statusText = 'Checking MPA restrictions...';
      statusIcon = null; // will render a spinner instead
    } else if (mpa == null || mpa.spearfishingStatus == 0) {
      // MPA was checked, no restrictions found (safe to show green)
      statusColor = AppColors.success;
      statusText = 'No MPA restrictions nearby';
      statusIcon = Icons.check_circle;
    } else if (mpa.isInsideMPA) {
      // INSIDE a restricted area - RED warning
      statusColor = AppColors.error;
      statusIcon = Icons.block;
      if (mpa.spearfishingStatus == 1) {
        statusText = 'RESTRICTED AREA - FREEDIVING ONLY';
        detailText = 'This spot is inside "${mpa.siteName}". Spearfishing is prohibited.';
      } else {
        statusText = 'RESTRICTED AREA - CHECK REGULATIONS';
        detailText = 'This spot is inside "${mpa.siteName}". Special regulations apply.';
      }
    } else {
      // NEARBY a restricted area - ORANGE warning
      statusColor = AppColors.warning;
      if (mpa.spearfishingStatus == 1) {
        statusText = 'MARINE SANCTUARY NEARBY';
        statusIcon = Icons.warning_amber;
        detailText = '"${mpa.siteName}" is within 1.5km';
      } else if (mpa.spearfishingStatus == 2) {
        statusText = 'RESTRICTED AREA NEARBY';
        statusIcon = Icons.warning;
        detailText = '"${mpa.siteName}" is within 1.5km';
      } else {
        statusText = 'Verify local regulations';
        statusIcon = Icons.help_outline;
      }
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // MPA Protection Status Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: statusColor.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (statusIcon != null)
                    Icon(statusIcon, color: statusColor, size: 20)
                  else
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: statusColor,
                      ),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              if (mpa != null && mpa.siteName != null) ...[
                const SizedBox(height: 8),
                Text(
                  detailText ?? '"${mpa.siteName!}" is within 1.5km',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                if (mpa.designation != null)
                  Text(
                    mpa.designation!,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                if (mpa.isInsideMPA && mpa.spearfishingStatus == 1) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.block, color: AppColors.error, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Spearfishing is NOT allowed here. Freedive only or find another spot.',
                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (!mpa.isInsideMPA && mpa.spearfishingStatus == 1) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Spearfishing is PROHIBITED inside sanctuary boundaries.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: AppColors.warning, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Know exactly where the sanctuary begins and ends before entering the water.',
                            style: TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
              if (mpa?.detailsUrl != null) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => _launchUrl(mpa!.detailsUrl!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.map, color: AppColors.info, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'View official boundary map',
                          style: TextStyle(color: AppColors.info, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Regulatory Agency Info
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                regulations.regulatoryAgency,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (regulations.note != null) ...[
                const SizedBox(height: 6),
                Text(
                  regulations.note!,
                  style: TextStyle(
                    color: AppColors.warning,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _launchUrl(regulations.regulationsUrl),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.public, color: AppColors.info, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Regulations',
                              style:
                                  TextStyle(color: AppColors.info, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (regulations.licensingUrl != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _launchUrl(regulations.licensingUrl!),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.card_membership,
                                  color: AppColors.success, size: 16),
                              SizedBox(width: 6),
                              Text(
                                'Licenses',
                                style: TextStyle(
                                    color: AppColors.success, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatFreshness(String isoDate) {
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
      return 'recently';
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ============ PRELOADED & LOADING STATES ============

  Widget _buildPreloadedContent(SpotSummary spot) {
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: _bgColor,
            leading: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: _buildPreloadedHeader(spot),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: _buildTabBar(),
            ),
          ),
        ];
      },
      body: TabBarView(
        controller: _tabController,
        children: [
          // Current tab with preloaded data (includes cached satellite readings)
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSectionHeader('CONDITIONS'),
              const SizedBox(height: 10),
              ConditionsCard(conditions: spot.conditions),
              const SizedBox(height: 20),
              // Satellite readings from cache (instant!)
              if (spot.satelliteReadings != null && spot.satelliteReadings!.hasAnyData) ...[
                _buildSectionHeader('VISIBILITY (CHLOROPHYLL-A) SATELLITE READINGS'),
                const SizedBox(height: 10),
                SatelliteReadingsCard(readings: spot.satelliteReadings),
                const SizedBox(height: 20),
              ],
              // Loading indicator for remaining data
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _borderColor),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.info,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Loading forecast & details...',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Forecast tab - loading
          const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.info,
            ),
          ),
          // Guide tab with fish preview
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (spot.expectedFish.isNotEmpty) ...[
                _buildSectionHeader('FISH'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: spot.expectedFish
                      .map((fish) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _cardColor,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: _borderColor),
                            ),
                            child: Text(
                              fish,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                            ),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreloadedHeader(SpotSummary spot) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E3A5F), _bgColor],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(56, 80, 20, 60),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  spot.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  spot.bestTimeOfDay,
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _getScoreColor(spot.shakaScore).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _getScoreColor(spot.shakaScore),
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                '${spot.shakaScore}',
                style: TextStyle(
                  color: _getScoreColor(spot.shakaScore),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back, color: Colors.white70),
                ),
              ],
            ),
          ),
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.info,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Loading spot...',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back, color: Colors.white70),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.white38, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'Unable to load',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        _hasLoaded = false;
                        _loadSpotDetail();
                      },
                      child: const Text(
                        'Retry',
                        style:
                            TextStyle(color: AppColors.info, fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============ UTILITIES ============

  Color _getScoreColor(int score) => AppColors.getScoreColor(score);

  String _formatDate(String date) {
    try {
      final d = DateTime.parse(date);
      return '${d.month}/${d.day}';
    } catch (e) {
      return date;
    }
  }

  String _formatWeekday(String date) {
    try {
      final d = DateTime.parse(date);
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[d.weekday - 1];
    } catch (e) {
      return '';
    }
  }
}
