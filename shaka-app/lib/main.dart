import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/theme/app_theme.dart';
import 'data/api/shaka_api_client.dart';
import 'data/repositories/spot_repository.dart';
import 'presentation/bloc/search_bloc.dart';
import 'presentation/screens/home/home_screen.dart';
import 'presentation/screens/results/results_screen.dart';
import 'presentation/screens/spot_detail/spot_detail_screen.dart';
import 'presentation/screens/charts/ocean_charts_webview.dart';
import 'package:go_router/go_router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Set status bar style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const ShakaApp());
}

class ShakaApp extends StatelessWidget {
  const ShakaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final apiClient = ShakaApiClient();
    final spotRepository = SpotRepository(apiClient);

    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => SearchBloc(spotRepository),
        ),
      ],
      child: MaterialApp.router(
        title: 'Shaka',
        theme: AppTheme.lightTheme,
        debugShowCheckedModeBanner: false,
        routerConfig: _router,
      ),
    );
  }
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/results',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return ResultsScreen(
          lat: extra?['lat'] ?? 0.0,
          lon: extra?['lon'] ?? 0.0,
          date: extra?['date'] ?? '',
          locationName: extra?['locationName'] ?? '',
        );
      },
    ),
    GoRoute(
      path: '/spot/:id',
      builder: (context, state) {
        final spotId = state.pathParameters['id'] ?? '';
        final extra = state.extra as Map<String, dynamic>?;
        return SpotDetailScreen(
          spotId: spotId,
          date: extra?['date'] ?? '',
        );
      },
    ),
    GoRoute(
      path: '/charts',
      builder: (context, state) {
        return const OceanChartsWebView();
      },
    ),
  ],
);
