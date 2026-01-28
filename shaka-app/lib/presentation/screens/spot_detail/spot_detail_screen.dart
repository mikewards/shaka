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

  const SpotDetailScreen({
    super.key,
    required this.spotId,
    required this.date,
  });

  @override
  State<SpotDetailScreen> createState() => _SpotDetailScreenState();
}

class _SpotDetailScreenState extends State<SpotDetailScreen> {
  bool _hasLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasLoaded) {
        _hasLoaded = true;
        _loadSpotDetail();
      }
    });
  }

  void _loadSpotDetail() {
    debugPrint('🔍 Loading spot detail: ${widget.spotId}');
    context.read<SearchBloc>().add(LoadSpotDetail(
      spotId: widget.spotId,
      date: widget.date,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<SearchBloc, SearchState>(
        builder: (context, state) {
          debugPrint('🔄 SpotDetailState: ${state.runtimeType}');
          
          if (state is SpotDetailLoading) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.oceanBlue,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Loading spot details...',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            );
          }

          if (state is SearchError) {
            return _buildError(state.message);
          }

          if (state is SpotDetailSuccess) {
            return _buildContent(state.spot);
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildContent(SpotDetail spot) {
    return CustomScrollView(
      slivers: [
        // App Bar - Minimal, warm gradient
        SliverAppBar(
          expandedHeight: 180,
          pinned: true,
          leading: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Center(
              child: TextButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  context.pop();
                },
                child: Text(
                  'Back',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textOnDark.withOpacity(0.9),
                  ),
                ),
              ),
            ),
          ),
          leadingWidth: 80,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.oceanBlue,
                    AppColors.oceanBlueLight,
                  ],
                ),
              ),
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
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
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.getAccessColor(spot.access.type)
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  spot.access.type.toUpperCase(),
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppColors.getAccessColor(spot.access.type),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                spot.bestTimeOfDay,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.textMuted,
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

                const SizedBox(height: 24),

                // Description
                Text(
                  spot.description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.6,
                  ),
                ),

                const SizedBox(height: 32),

                // Conditions
                const SectionHeader(title: 'CONDITIONS'),
                const SizedBox(height: 14),
                ConditionsCard(conditions: spot.conditions),

                const SizedBox(height: 32),

                // Score Breakdown
                const SectionHeader(title: 'SCORE'),
                const SizedBox(height: 14),
                ScoreBreakdownCard(breakdown: spot.score.breakdown),

                const SizedBox(height: 32),

                // Expected Fish
                const SectionHeader(title: 'FISH'),
                const SizedBox(height: 14),
                _buildFishList(spot.expectedFish),

                const SizedBox(height: 32),

                // Gear
                const SectionHeader(title: 'GEAR'),
                const SizedBox(height: 14),
                _buildGearList(spot.gearRecommendations),

                const SizedBox(height: 32),

                // Risks
                const SectionHeader(title: 'RISKS'),
                const SizedBox(height: 14),
                _buildRisksList(spot.risks),

                const SizedBox(height: 32),

                // How to Get There
                const SectionHeader(title: 'ACCESS'),
                const SizedBox(height: 14),
                _buildAccessInfo(spot.access),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFishList(List<FishInfo> fish) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: fish.map((f) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border.withOpacity(0.5)),
          ),
          child: Text(
            f.localName ?? f.name,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildGearList(List<GearItem> gear) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Column(
        children: gear.map((g) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  g.essential ? '•' : '○',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: g.essential ? AppColors.textPrimary : AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    g.item,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: g.essential ? AppColors.textPrimary : AppColors.textSecondary,
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Column(
        children: risks.map((r) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '—',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    r.risk,
                    style: Theme.of(context).textTheme.bodyMedium,
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            access.directions,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text(
            access.parkingInfo,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Unable to load',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            TextButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                _loadSpotDetail();
              },
              child: Text(
                'Retry',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.oceanBlue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
