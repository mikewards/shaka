import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/spot_models.dart';
import '../../bloc/search_bloc.dart';
import '../../widgets/spot_card.dart';
import '../../widgets/shaka_score_badge.dart';

class ResultsScreen extends StatefulWidget {
  final double lat;
  final double lon;
  final String date;
  final String locationName;

  const ResultsScreen({
    super.key,
    required this.lat,
    required this.lon,
    required this.date,
    required this.locationName,
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  bool _isMapView = false;

  @override
  void initState() {
    super.initState();
    _loadSpots();
  }

  void _loadSpots() {
    context.read<SearchBloc>().add(SearchSpots(
      lat: widget.lat,
      lon: widget.lon,
      date: widget.date,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Column(
          children: [
            Text(
              widget.locationName.isNotEmpty ? widget.locationName : 'Results',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              widget.date,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_isMapView ? Icons.list : Icons.map_outlined),
            onPressed: () {
              setState(() {
                _isMapView = !_isMapView;
              });
            },
          ),
        ],
      ),
      body: BlocBuilder<SearchBloc, SearchState>(
        builder: (context, state) {
          if (state is SearchLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (state is SearchError) {
            return _buildError(state.message);
          }

          if (state is SearchSuccess) {
            if (state.response.spots.isEmpty) {
              return _buildEmpty();
            }
            return _isMapView
                ? _buildMapView(state.response.spots)
                : _buildListView(state.response.spots);
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildListView(List<SpotSummary> spots) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: spots.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final spot = spots[index];
        return SpotCard(
          spot: spot,
          onTap: () {
            context.push(
              '/spot/${spot.id}',
              extra: {'date': widget.date},
            );
          },
        );
      },
    );
  }

  Widget _buildMapView(List<SpotSummary> spots) {
    // Placeholder for map view - would use flutter_map
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.map,
            size: 64,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 16),
          Text(
            'Map View',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '${spots.length} spots found',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () {
              setState(() {
                _isMapView = false;
              });
            },
            child: const Text('View as List'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              'No spots found',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Try expanding your search radius or selecting a different location.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
            Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: _loadSpots,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
