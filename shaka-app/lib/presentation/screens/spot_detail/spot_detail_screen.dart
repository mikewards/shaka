import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/spot_models.dart';
import '../../bloc/search_bloc.dart';
import '../../widgets/shaka_score_badge.dart';
import '../../widgets/score_breakdown_card.dart';
import '../../widgets/conditions_card.dart';
import '../../widgets/section_header.dart';

class SpotDetailScreen extends StatefulWidget {
  final String spotId;
  final String date;
  final SpotSummary? preloadedSpot; // Optional: show immediately while loading full detail

  const SpotDetailScreen({
    super.key,
    required this.spotId,
    required this.date,
    this.preloadedSpot,
  });

  @override
  State<SpotDetailScreen> createState() => _SpotDetailScreenState();
}

class _SpotDetailScreenState extends State<SpotDetailScreen> {
  bool _hasLoaded = false;

  // Dark theme colors
  static const _bgColor = Color(0xFF0D0D0D);
  static const _cardColor = Color(0xFF1A1A1A);
  static const _borderColor = Color(0xFF2A2A2A);

  @override
  void initState() {
    super.initState();
    // Load full detail in background
    _loadSpotDetail();
  }

  void _loadSpotDetail() {
    if (_hasLoaded) return;
    _hasLoaded = true;
    context.read<SearchBloc>().add(LoadSpotDetail(
      spotId: widget.spotId,
      date: widget.date,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: BlocBuilder<SearchBloc, SearchState>(
        builder: (context, state) {
          // Full detail loaded - show it
          if (state is SpotDetailSuccess) {
            return _buildContent(state.spot);
          }

          // Error state
          if (state is SearchError) {
            return _buildError(state.message);
          }

          // While loading: show preloaded summary if available
          if (widget.preloadedSpot != null) {
            return _buildPreloadedContent(widget.preloadedSpot!);
          }

          // No preloaded data - show spinner
          return _buildLoadingState();
        },
      ),
    );
  }

  /// Show preloaded SpotSummary data while full detail loads
  Widget _buildPreloadedContent(SpotSummary spot) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 140,
          pinned: true,
          backgroundColor: _bgColor,
          leading: IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1E3A5F), _bgColor],
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            spot.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  spot.access.toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                spot.bestTimeOfDay,
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Score badge
                    Container(
                      width: 56,
                      height: 56,
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
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),

                // Conditions from preloaded data
                _buildSectionHeader('CONDITIONS'),
                const SizedBox(height: 10),
                ConditionsCard(conditions: spot.conditions),

                const SizedBox(height: 24),

                // Loading indicator for additional data
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _borderColor),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF5B9BD5),
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Loading full details...',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Fish preview
                if (spot.expectedFish.isNotEmpty) ...[
                  _buildSectionHeader('FISH'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: spot.expectedFish.map((fish) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _cardColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _borderColor),
                      ),
                      child: Text(
                        fish,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    )).toList(),
                  ),
                ],

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Color _getScoreColor(int score) {
    if (score >= 80) return const Color(0xFF4CAF50);
    if (score >= 60) return const Color(0xFF00BCD4);
    if (score >= 40) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  Widget _buildLoadingState() {
    return SafeArea(
      child: Column(
        children: [
          // Header with back button
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back, color: Colors.white70),
                ),
                const Spacer(),
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
                    color: Color(0xFF5B9BD5),
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

  Widget _buildContent(SpotDetail spot) {
    return CustomScrollView(
      slivers: [
        // App Bar - Dark with gradient
        SliverAppBar(
          expandedHeight: 140,
          pinned: true,
          backgroundColor: _bgColor,
          leading: IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              context.pop();
            },
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF1E3A5F),
                    _bgColor,
                  ],
                ),
              ),
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            spot.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  spot.access.type.toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                spot.bestTimeOfDay,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    ShakaScoreBadge(
                      score: spot.score.overall,
                      confidence: spot.score.confidence,
                      size: ShakaScoreSize.large,
                      showLabel: true,
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Description
                Text(
                  spot.description,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 24),

                // Conditions
                _buildSectionHeader('CONDITIONS'),
                const SizedBox(height: 10),
                ConditionsCard(conditions: spot.conditions),
                
                const SizedBox(height: 12),
                
                // Ocean Charts button
                OutlinedButton.icon(
                  onPressed: () => context.push('/charts'),
                  icon: const Icon(Icons.layers_outlined, size: 18),
                  label: const Text('View Ocean Charts'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF5B9BD5),
                    side: const BorderSide(color: Color(0xFF5B9BD5)),
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Score Breakdown
                _buildSectionHeader('SCORE BREAKDOWN'),
                const SizedBox(height: 10),
                ScoreBreakdownCard(breakdown: spot.score.breakdown),

                const SizedBox(height: 24),

                // Expected Fish
                _buildSectionHeader('FISH'),
                const SizedBox(height: 10),
                _buildFishList(spot.expectedFish),

                const SizedBox(height: 24),

                // Gear
                _buildSectionHeader('GEAR'),
                const SizedBox(height: 10),
                _buildGearList(spot.gearRecommendations),

                const SizedBox(height: 24),

                // Risks
                _buildSectionHeader('RISKS'),
                const SizedBox(height: 10),
                _buildRisksList(spot.risks),

                const SizedBox(height: 24),

                // How to Get There
                _buildSectionHeader('ACCESS'),
                const SizedBox(height: 10),
                _buildAccessInfo(spot.access),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

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

  Widget _buildFishList(List<FishInfo> fish) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: fish.map((f) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _borderColor),
          ),
          child: Text(
            f.localName ?? f.name,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildGearList(List<GearItem> gear) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: gear.map((g) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  g.essential ? '•' : '○',
                  style: TextStyle(
                    color: g.essential ? Colors.white : Colors.white54,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    g.item,
                    style: TextStyle(
                      color: g.essential ? Colors.white : Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRisksList(List<RiskInfo> risks) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: risks.map((r) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber, color: Colors.orange, size: 16),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    r.risk,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAccessInfo(AccessInfo access) {
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
            access.directions,
            style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          Text(
            access.parkingInfo,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
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
                    const Icon(Icons.error_outline, color: Colors.white38, size: 48),
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
                      style: const TextStyle(color: Colors.white54, fontSize: 14),
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
                        style: TextStyle(color: Color(0xFF5B9BD5), fontSize: 15),
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
}
