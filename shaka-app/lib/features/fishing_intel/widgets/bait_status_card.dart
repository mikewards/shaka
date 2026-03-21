import 'package:flutter/material.dart';
import '../models/fishing_intel_models.dart';
import '../../../core/theme/app_colors.dart';

class BaitStatusCard extends StatelessWidget {
  final List<BaitStatus> baitStatus;
  
  const BaitStatusCard({required this.baitStatus, super.key});
  
  static const _cardColor = AppColors.darkSurface;
  static const _borderColor = AppColors.darkBorder;
  
  Color _statusColor(String status) {
    final lower = status.toLowerCase();
    if (lower.contains('loaded') || lower.contains('plenty')) {
      return AppColors.success;
    } else if (lower.contains('limited') || lower.contains('low')) {
      return AppColors.scoreBelowAvg;
    } else if (lower.contains('none') || lower.contains('out')) {
      return AppColors.error;
    }
    return AppColors.info;
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: baitStatus.map((b) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _statusColor(b.status),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${b.location} - ${b.baitType}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      b.status,
                      style: TextStyle(
                        color: _statusColor(b.status),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        )).toList(),
      ),
    );
  }
}
