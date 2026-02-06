import 'package:flutter/material.dart';
import '../models/fishing_intel_models.dart';

class BaitStatusCard extends StatelessWidget {
  final List<BaitStatus> baitStatus;
  
  const BaitStatusCard({required this.baitStatus, super.key});
  
  static const _cardColor = Color(0xFF1A1A1A);
  static const _borderColor = Color(0xFF2A2A2A);
  
  Color _statusColor(String status) {
    final lower = status.toLowerCase();
    if (lower.contains('loaded') || lower.contains('plenty')) {
      return Colors.green;
    } else if (lower.contains('limited') || lower.contains('low')) {
      return Colors.orange;
    } else if (lower.contains('none') || lower.contains('out')) {
      return Colors.red;
    }
    return Colors.blue;
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
