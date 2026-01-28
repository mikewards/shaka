import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';

/// Date picker with Quiet Luxury styling.
/// 
/// Text-based, no icons - clean and minimal.
class DatePickerCard extends StatelessWidget {
  final DateTime selectedDate;
  final Function(DateTime) onDateSelected;

  const DatePickerCard({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isToday = _isSameDay(selectedDate, DateTime.now());
    final isTomorrow = _isSameDay(selectedDate, DateTime.now().add(const Duration(days: 1)));

    String dateLabel;
    if (isToday) {
      dateLabel = 'Today';
    } else if (isTomorrow) {
      dateLabel = 'Tomorrow';
    } else {
      dateLabel = DateFormat('EEEE, MMM d').format(selectedDate);
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _showDatePicker(context);
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                dateLabel,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            Text(
              '>',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _showDatePicker(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.oceanBlue,
              onPrimary: AppColors.textOnDark,
              surface: AppColors.surface,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      onDateSelected(picked);
    }
  }
}
