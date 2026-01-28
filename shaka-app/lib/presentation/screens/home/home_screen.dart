import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../widgets/shaka_button.dart';
import '../../widgets/location_picker.dart';
import '../../widgets/date_picker.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  double? _selectedLat;
  double? _selectedLon;
  String _locationName = '';
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              
              // Logo / Title
              Text(
                'SHAKA',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 4,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Find your\nnext dive',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  height: 1.1,
                ),
              ),
              
              const SizedBox(height: 48),

              // Location Picker
              Text(
                'WHERE',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 2,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              LocationPicker(
                selectedLocationName: _locationName,
                onLocationSelected: (lat, lon, name) {
                  setState(() {
                    _selectedLat = lat;
                    _selectedLon = lon;
                    _locationName = name;
                  });
                },
              ),

              const SizedBox(height: 32),

              // Date Picker
              Text(
                'WHEN',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 2,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              DatePickerCard(
                selectedDate: _selectedDate,
                onDateSelected: (date) {
                  setState(() {
                    _selectedDate = date;
                  });
                },
              ),

              const Spacer(),

              // Search Button
              ShakaButton(
                label: 'Find Spots',
                onPressed: _canSearch ? _onSearch : null,
                isExpanded: true,
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canSearch => _selectedLat != null && _selectedLon != null;

  void _onSearch() {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    context.push(
      '/results',
      extra: {
        'lat': _selectedLat,
        'lon': _selectedLon,
        'date': dateStr,
        'locationName': _locationName,
      },
    );
  }
}
