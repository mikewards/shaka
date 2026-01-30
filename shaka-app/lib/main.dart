import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/theme/app_theme.dart';
import 'data/api/shaka_api_client.dart';
import 'data/models/spot_models.dart';
import 'data/repositories/spot_repository.dart';
import 'presentation/bloc/search_bloc.dart';
import 'presentation/shell/main_shell.dart';
import 'presentation/screens/home/home_screen.dart';
import 'presentation/screens/explore/explore_screen.dart';
import 'presentation/screens/profile/profile_screen.dart';
import 'presentation/screens/results/results_screen.dart';
import 'presentation/screens/spot_detail/spot_detail_screen.dart';
import 'presentation/screens/charts/ocean_charts_webview.dart';
import 'package:go_router/go_router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Set status bar style for dark theme
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0D0D0D),
      systemNavigationBarIconBrightness: Brightness.light,
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
        theme: AppTheme.darkTheme,
        debugShowCheckedModeBanner: false,
        routerConfig: _router,
      ),
    );
  }
}

// Navigation keys for preserving state across tab switches
final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKeyHome = GlobalKey<NavigatorState>(debugLabel: 'home');
final _shellNavigatorKeyExplore = GlobalKey<NavigatorState>(debugLabel: 'explore');
final _shellNavigatorKeyCharts = GlobalKey<NavigatorState>(debugLabel: 'charts');
final _shellNavigatorKeyProfile = GlobalKey<NavigatorState>(debugLabel: 'profile');

final _router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/explore', // Start on Explore (not Home)
  routes: [
    // Main shell with bottom navigation
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
        // Home tab (Favorites feed - coming soon)
        StatefulShellBranch(
          navigatorKey: _shellNavigatorKeyHome,
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        // Charts tab (preserved Ocean Charts!)
        StatefulShellBranch(
          navigatorKey: _shellNavigatorKeyCharts,
          routes: [
            GoRoute(
              path: '/charts',
              builder: (context, state) => const OceanChartsWebView(),
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
  ],
);
