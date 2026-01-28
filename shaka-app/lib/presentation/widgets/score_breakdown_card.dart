import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/spot_models.dart';

/// Explanation for each score component
class _ScoreExplanation {
  final String title;
  final String weight;
  final String description;
  final List<String> factors;
  final Map<String, String> thresholds;

  const _ScoreExplanation({
    required this.title,
    required this.weight,
    required this.description,
    required this.factors,
    required this.thresholds,
  });
}

const _scoreExplanations = {
  'visibility': _ScoreExplanation(
    title: 'Visibility Score',
    weight: '25%',
    description: 'Water clarity is the most important factor for spearfishing. This score estimates how far you can see underwater.',
    factors: [
      'Chlorophyll-a concentration (algae levels)',
      'Sea surface temperature',
      'Recent weather conditions',
      'Satellite imagery analysis',
    ],
    thresholds: {
      '100': '25m+ visibility (crystal clear)',
      '80-99': '15-25m visibility (excellent)',
      '60-79': '7-15m visibility (good)',
      '40-59': '3-7m visibility (moderate)',
      '0-39': 'Under 3m (poor)',
    },
  ),
  'weather': _ScoreExplanation(
    title: 'Weather Score',
    weight: '20%',
    description: 'Surface conditions affect your comfort and safety getting in and out of the water.',
    factors: [
      'Wind speed and direction',
      'Precipitation (rain)',
      'Cloud cover',
      'Air temperature',
    ],
    thresholds: {
      '100': 'Calm winds (<5 knots), no rain',
      '80-99': 'Light winds (5-10 knots)',
      '60-79': 'Moderate winds (10-15 knots)',
      '40-59': 'Strong winds (15-20 knots)',
      '0-39': 'Challenging conditions',
    },
  ),
  'swell': _ScoreExplanation(
    title: 'Swell Score',
    weight: '15%',
    description: 'Wave height and period affect underwater visibility and entry/exit safety.',
    factors: [
      'Wave height (feet)',
      'Wave period (seconds)',
      'Swell direction',
      'Wind waves vs ground swell',
    ],
    thresholds: {
      '100': 'Flat (0-1 ft)',
      '80-99': 'Small (1-2 ft)',
      '60-79': 'Moderate (2-4 ft)',
      '40-59': 'Choppy (4-6 ft)',
      '0-39': 'Large swell (6+ ft)',
    },
  ),
  'fishActivity': _ScoreExplanation(
    title: 'Fish Activity Score',
    weight: '15%',
    description: 'Predicts how active fish will be based on natural cycles and recent reports.',
    factors: [
      'Moon phase (new/full moon = best)',
      'Seasonal patterns',
      'Recent community sightings',
      'Water temperature trends',
    ],
    thresholds: {
      '100': 'Peak activity expected',
      '80-99': 'Very good activity',
      '60-79': 'Good activity',
      '40-59': 'Moderate activity',
      '0-39': 'Lower activity expected',
    },
  ),
  'safety': _ScoreExplanation(
    title: 'Safety Score',
    weight: '15%',
    description: 'Assesses potential hazards and risks at the dive site.',
    factors: [
      'Current strength',
      'Known hazards (rocks, boats)',
      'Shark activity level',
      'Emergency access',
    ],
    thresholds: {
      '100': 'Minimal risks',
      '80-99': 'Low risk',
      '60-79': 'Moderate caution advised',
      '40-59': 'Higher risk - experience needed',
      '0-39': 'Significant hazards present',
    },
  ),
  'accessibility': _ScoreExplanation(
    title: 'Accessibility Score',
    weight: '10%',
    description: 'How easy it is to access and dive the spot.',
    factors: [
      'Shore vs boat access',
      'Parking availability',
      'Permits required',
      'Entry difficulty',
    ],
    thresholds: {
      '100': 'Easy shore access, parking available',
      '80-99': 'Good access',
      '60-79': 'Moderate difficulty or boat required',
      '40-59': 'Challenging access or permit needed',
      '0-39': 'Difficult access',
    },
  ),
};

/// Score breakdown card with clean row-based layout.
/// Shows each scoring component with its weight and value.
/// Tap any row for detailed explanation.
class ScoreBreakdownCard extends StatelessWidget {
  final ScoreBreakdown breakdown;

  const ScoreBreakdownCard({super.key, required this.breakdown});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Score Breakdown',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _showAllExplanations(context);
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'How it works',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ScoreRow(
            label: 'Visibility',
            score: breakdown.visibility,
            weight: '25%',
            explanationKey: 'visibility',
          ),
          _ScoreRow(
            label: 'Weather',
            score: breakdown.weather,
            weight: '20%',
            explanationKey: 'weather',
          ),
          _ScoreRow(
            label: 'Swell',
            score: breakdown.swell,
            weight: '15%',
            explanationKey: 'swell',
          ),
          _ScoreRow(
            label: 'Fish Activity',
            score: breakdown.fishActivity,
            weight: '15%',
            explanationKey: 'fishActivity',
          ),
          _ScoreRow(
            label: 'Safety',
            score: breakdown.safety,
            weight: '15%',
            explanationKey: 'safety',
          ),
          _ScoreRow(
            label: 'Accessibility',
            score: breakdown.accessibility,
            weight: '10%',
            explanationKey: 'accessibility',
            isLast: true,
          ),
        ],
      ),
    );
  }

  void _showAllExplanations(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'How Scores Work',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    color: AppColors.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Each factor is scored 0-100, then combined using weighted averages to create the overall Shaka Score.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 20),
              ..._scoreExplanations.entries.map((e) => _buildExplanationCard(
                context,
                e.value,
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExplanationCard(BuildContext context, _ScoreExplanation exp) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                exp.title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.oceanBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  exp.weight,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.oceanBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            exp.description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final String label;
  final int score;
  final String weight;
  final String explanationKey;
  final bool isLast;

  const _ScoreRow({
    required this.label,
    required this.score,
    required this.weight,
    required this.explanationKey,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _showExplanation(context);
      },
      child: Container(
        padding: EdgeInsets.only(
          top: 12,
          bottom: isLast ? 4 : 12,
        ),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(
                    color: AppColors.border.withOpacity(0.2),
                  ),
                ),
        ),
        child: Row(
          children: [
            // Label with info icon
            Expanded(
              flex: 3,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.info_outline,
                    size: 12,
                    color: AppColors.textMuted.withOpacity(0.5),
                  ),
                ],
              ),
            ),
            // Weight badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: AppColors.border.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                weight,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 10,
                ),
              ),
            ),
            // Progress bar
            Expanded(
              flex: 4,
              child: _ScoreBar(score: score),
            ),
            const SizedBox(width: 12),
            // Score value
            SizedBox(
              width: 32,
              child: Text(
                '$score',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.getScoreColor(score),
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showExplanation(BuildContext context) {
    final explanation = _scoreExplanations[explanationKey];
    if (explanation == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    explanation.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.oceanBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    explanation.weight,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.oceanBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  color: AppColors.textMuted,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Current score highlight
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.getScoreColor(score).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text(
                    '$score',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.getScoreColor(score),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _getScoreDescription(score),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              explanation.description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Factors considered:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...explanation.factors.map((factor) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(color: AppColors.textMuted)),
                  Expanded(
                    child: Text(
                      factor,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 16),
            Text(
              'Score thresholds:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...explanation.thresholds.entries.map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 50,
                    child: Text(
                      e.key,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e.value,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _getScoreDescription(int score) {
    if (score >= 90) return 'Excellent conditions';
    if (score >= 75) return 'Good conditions';
    if (score >= 60) return 'Fair conditions';
    if (score >= 40) return 'Below average';
    return 'Poor conditions';
  }
}

class _ScoreBar extends StatelessWidget {
  final int score;

  const _ScoreBar({required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: AppColors.border.withOpacity(0.2),
        borderRadius: BorderRadius.circular(3),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: score / 100,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.getScoreColor(score),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}
