import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'core/theme/app_theme.dart';
import 'data/api/shaka_api_client.dart';
import 'data/models/spot_models.dart';
import 'data/repositories/spot_repository.dart';
import 'data/services/health_service.dart';
import 'data/services/map_background_service.dart';
import 'presentation/bloc/search_bloc.dart';
import 'presentation/shell/main_shell.dart';
import 'presentation/screens/explore/explore_screen.dart';
import 'presentation/screens/profile/profile_screen.dart';
import 'presentation/screens/results/results_screen.dart';
import 'presentation/screens/spot_detail/spot_detail_screen.dart';
import 'presentation/screens/charts/charts_hub_screen.dart';
import 'presentation/screens/charts/gibs_imagery_screen.dart';
import 'presentation/screens/charts/ocean_charts_webview.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set status bar style for dark theme
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0D0D0D),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Start the app FIRST, then initialize services in background
  runApp(const ShakaApp());
  
  // Initialize services AFTER app starts (non-blocking)
  Future.microtask(() {
    HealthProvider().checkHealthInBackground();
    MapBackgroundService().init();
  });
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
        theme: AppTheme.darkTheme,
        debugShowCheckedModeBanner: false,
        routerConfig: _router,
      ),
    );
  }
}

// Navigation keys for preserving state across tab switches
final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKeyExplore = GlobalKey<NavigatorState>(debugLabel: 'explore');
final _shellNavigatorKeyCharts = GlobalKey<NavigatorState>(debugLabel: 'charts');
final _shellNavigatorKeyProfile = GlobalKey<NavigatorState>(debugLabel: 'profile');

final _router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/explore',
  routes: [
    // Main shell with bottom navigation (3 tabs)
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return MainShell(navigationShell: navigationShell);
      },
      branches: [
        // Explore tab (PRIMARY - map with spots)
        StatefulShellBranch(
          navigatorKey: _shellNavigatorKeyExplore,
          routes: [
            GoRoute(
              path: '/explore',
              builder: (context, state) => const ExploreScreen(),
            ),
          ],
        ),
        // Charts tab
        StatefulShellBranch(
          navigatorKey: _shellNavigatorKeyCharts,
          routes: [
            GoRoute(
              path: '/charts',
              builder: (context, state) => const ChartsHubScreen(),
            ),
          ],
        ),
        // Profile tab
        StatefulShellBranch(
          navigatorKey: _shellNavigatorKeyProfile,
          routes: [
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    ),
    
    // Routes that push on top of the shell (full-screen)
    GoRoute(
      path: '/results',
      parentNavigatorKey: _rootNavigatorKey,
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
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final spotId = state.pathParameters['id'] ?? '';
        final extra = state.extra as Map<String, dynamic>?;
        return SpotDetailScreen(
          spotId: spotId,
          date: extra?['date'] ?? '',
          preloadedSpot: extra?['spot'] as SpotSummary?,
        );
      },
    ),
    
    // Full-screen chart routes (when opened from spot detail)
    GoRoute(
      path: '/charts/hub',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return ChartsHubScreen(
          initialLat: extra?['lat'] as double?,
          initialLon: extra?['lon'] as double?,
          spotName: extra?['spotName'] as String?,
        );
      },
    ),
    GoRoute(
      path: '/charts/gibs',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return GibsImageryScreen(
          initialLat: extra?['lat'] as double?,
          initialLon: extra?['lon'] as double?,
          spotName: extra?['spotName'] as String?,
        );
      },
    ),
    GoRoute(
      path: '/charts/copernicus',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return OceanChartsWebView(
          initialLat: extra?['lat'] as double?,
          initialLon: extra?['lon'] as double?,
          spotName: extra?['spotName'] as String?,
        );
      },
    ),
  ],
);
