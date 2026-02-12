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
    weight: '35%',
    description: 'Water clarity is the most important factor for spearfishing. Based on satellite chlorophyll-a concentration — lower chlorophyll means clearer water.',
    factors: [
      'Chlorophyll-a concentration in mg/m³ (from satellite)',
    ],
    thresholds: {
      '100': '< 0.1 mg/m³ (ultra-clear open ocean)',
      '85': '0.1–0.3 mg/m³ (clear tropical)',
      '65': '0.3–0.5 mg/m³ (average ocean)',
      '45': '0.5–1.0 mg/m³ (below average)',
      '25': '1–3 mg/m³ (murky coastal)',
      '0-10': '3+ mg/m³ (poor to algae bloom)',
    },
  ),
  'weather': _ScoreExplanation(
    title: 'Wind Score',
    weight: '22%',
    description: 'Wind speed affects surface conditions, comfort, and safety getting in and out of the water.',
    factors: [
      'Wind speed in km/h (from Open-Meteo forecast)',
    ],
    thresholds: {
      '100': 'Calm winds (<5 km/h)',
      '80-99': 'Light winds (5-10 km/h)',
      '60-79': 'Moderate winds (10-15 km/h)',
      '40-59': 'Strong winds (15-20 km/h)',
      '0-39': 'Very strong winds (20+ km/h)',
    },
  ),
  'swell': _ScoreExplanation(
    title: 'Swell Score',
    weight: '28%',
    description: 'Wave height affects underwater conditions, surge, and entry/exit safety.',
    factors: [
      'Wave height in meters (from Open-Meteo marine forecast)',
    ],
    thresholds: {
      '100': 'Flat (0-1 ft)',
      '80-99': 'Small (1-2 ft)',
      '60-79': 'Moderate (2-4 ft)',
      '40-59': 'Choppy (4-6 ft)',
      '0-39': 'Large swell (6+ ft)',
    },
  ),
  'solunar': _ScoreExplanation(
    title: 'Solunar Score',
    weight: '15%',
    description: 'Based on the Solunar API day rating (0-5 scale), which factors in moon transit, altitude, and feeding period quality. Professional fishermen have used solunar tables for decades.',
    factors: [
      'Solunar day rating (0-5 from api.solunar.org)',
      'Moon phase fallback when API data unavailable',
    ],
    thresholds: {
      '90': 'Excellent (day rating 5)',
      '80': 'Very good (day rating 4)',
      '65': 'Good (day rating 3)',
      '55': 'Average (day rating 2)',
      '40': 'Below average (day rating 1)',
      '30': 'Poor (day rating 0)',
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
            weight: '35%',
            explanationKey: 'visibility',
          ),
          _ScoreRow(
            label: 'Wind',
            score: breakdown.weather,
            weight: '22%',
            explanationKey: 'weather',
          ),
          _ScoreRow(
            label: 'Swell',
            score: breakdown.swell,
            weight: '28%',
            explanationKey: 'swell',
          ),
          _ScoreRow(
            label: 'Solunar',
            score: breakdown.solunar,
            weight: '15%',
            explanationKey: 'solunar',
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
