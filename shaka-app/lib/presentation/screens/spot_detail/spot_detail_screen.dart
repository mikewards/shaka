import 'package:flutter/material.dart';
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
  @override
  void initState() {
    super.initState();
    _loadSpotDetail();
  }

  void _loadSpotDetail() {
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
          if (state is SpotDetailLoading) {
            return const Center(child: CircularProgressIndicator());
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
        // App Bar with Hero Image
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          leading: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            ),
            onPressed: () => context.pop(),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.oceanBlue,
                    AppColors.oceanBlueLight,
                  ],
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.waves,
                  size: 80,
                  color: Colors.white.withOpacity(0.3),
                ),
              ),
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
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
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.getAccessColor(spot.access.type)
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  spot.access.type.toUpperCase(),
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppColors.getAccessColor(spot.access.type),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Best: ${spot.bestTimeOfDay}',
                                style: Theme.of(context).textTheme.bodySmall,
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
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Description
                Text(
                  spot.description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),

                const SizedBox(height: 24),

                // Conditions
                const SectionHeader(title: 'CONDITIONS'),
                const SizedBox(height: 12),
                ConditionsCard(conditions: spot.conditions),

                const SizedBox(height: 24),

                // Score Breakdown
                const SectionHeader(title: 'SCORE BREAKDOWN'),
                const SizedBox(height: 12),
                ScoreBreakdownCard(breakdown: spot.score.breakdown),

                const SizedBox(height: 24),

                // Expected Fish
                const SectionHeader(title: 'EXPECTED FISH'),
                const SizedBox(height: 12),
                _buildFishList(spot.expectedFish),

                const SizedBox(height: 24),

                // Gear
                const SectionHeader(title: 'GEAR CHECKLIST'),
                const SizedBox(height: 12),
                _buildGearList(spot.gearRecommendations),

                const SizedBox(height: 24),

                // Risks
                const SectionHeader(title: 'WHAT COULD GO WRONG'),
                const SizedBox(height: 12),
                _buildRisksList(spot.risks),

                const SizedBox(height: 24),

                // How to Get There
                const SectionHeader(title: 'HOW TO GET THERE'),
                const SizedBox(height: 12),
                _buildAccessInfo(spot.access),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
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
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.phishing, size: 16, color: AppColors.oceanBlue),
              const SizedBox(width: 8),
              Text(
                f.localName ?? f.name,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildGearList(List<GearItem> gear) {
    return Column(
      children: gear.map((g) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(
                g.essential ? Icons.check_circle : Icons.circle_outlined,
                size: 20,
                color: g.essential ? AppColors.success : AppColors.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  g.item,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRisksList(List<RiskInfo> risks) {
    return Column(
      children: risks.map((r) {
        final severityColor = r.severity == 'high'
            ? AppColors.error
            : r.severity == 'moderate'
                ? AppColors.warning
                : AppColors.textMuted;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: severityColor.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: severityColor.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber, size: 20, color: severityColor),
              const SizedBox(width: 12),
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
    );
  }

  Widget _buildAccessInfo(AccessInfo access) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.directions, color: AppColors.oceanBlue),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  access.directions,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.local_parking, color: AppColors.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  access.parkingInfo,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              'Could not load spot details',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: _loadSpotDetail,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
