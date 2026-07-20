import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../../core/theme/app_colors.dart';
import '../../../data/services/health_service.dart';
import 'ocean_forecast_screen.dart';
import 'gibs_imagery_screen.dart';

const _kWeatherCdnBase = 'https://shaka-weather-cdn.kcwn89.workers.dev';

class ChartsHubScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLon;
  final String? spotName;
  
  const ChartsHubScreen({
    super.key,
    this.initialLat,
    this.initialLon,
    this.spotName,
  });

  @override
  State<ChartsHubScreen> createState() => _ChartsHubScreenState();
}

class _ChartsHubScreenState extends State<ChartsHubScreen> {
  final _healthProvider = HealthProvider();
  String? _catalogJson;
  Uint8List? _windBytes;
  String? _windTimestamp;

  bool get _hasSpotContext => widget.spotName != null;

  @override
  void initState() {
    super.initState();
    _healthProvider.fetchHealth();
    _prefetchWeatherData();
  }

  Future<void> _prefetchWeatherData() async {
    try {
      final catalogResp = await http.get(
        Uri.parse('$_kWeatherCdnBase/catalog.json'),
      );
      if (catalogResp.statusCode != 200) return;
      _catalogJson = catalogResp.body;

      final catalog = jsonDecode(catalogResp.body) as Map<String, dynamic>;
      final windEntry = catalog['wind'] as Map<String, dynamic>?;
      final timestamps = (windEntry?['timestamps'] as List?)?.cast<String>();
      if (timestamps == null || timestamps.isEmpty) return;

      _windTimestamp = timestamps.first;
      final windResp = await http.get(
        Uri.parse('$_kWeatherCdnBase/wind/$_windTimestamp.webp'),
      );
      if (windResp.statusCode == 200) {
        _windBytes = windResp.bodyBytes;
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _healthProvider,
          builder: (context, _) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Spot context header (when opened from a spot)
                  if (_hasSpotContext) ...[
                    _buildSpotHeader(context),
                    const SizedBox(height: 16),
                  ] else
                    const SizedBox(height: 8),
                  
                  // Ocean Forecast Card (WeatherLayers GL)
                  Expanded(
                    child: _DataSourceCard(
                      title: 'Ocean Forecast',
                      subtitle: 'Animated wind, currents, waves, SST with 5-day forecast',
                      source: 'Copernicus CMEMS Forecast',
                      badge: '5-DAY',
                      badgeColor: const Color(0xFF00BCD4),
                      icon: Icons.air,
                      imagePath: 'assets/images/ocean_forecast_preview.jpg',
                      animatedOverlay: const _CurrentsFlowOverlay(),
                      fallbackColors: const [
                        Color(0xFF0D3B66),
                        Color(0xFF0E4D64),
                        Color(0xFF00BCD4),
                      ],
                      isAvailable: true,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(
                            builder: (context) => OceanForecastScreen(
                              initialLat: widget.initialLat,
                              initialLon: widget.initialLon,
                              spotName: widget.spotName,
                              prefetchedCatalogJson: _catalogJson,
                              prefetchedWindBytes: _windBytes,
                              prefetchedWindTimestamp: _windTimestamp,
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Satellite Card (GIBS)
                  Expanded(
                    child: _DataSourceCard(
                      title: 'Satellite Imagery',
                      subtitle: 'Higher resolution imagery from PACE, VIIRS, MODIS satellites',
                      source: 'NASA GIBS Near Real-Time',
                      badge: 'HIGH-RES',
                      badgeColor: AppColors.success,
                      icon: Icons.satellite_alt,
                      imagePath: 'assets/images/satellite_imagery_preview.png',
                      fallbackColors: const [
                        Color(0xFF1B5E20),
                        Color(0xFF2E7D32),
                        Color(0xFF4CAF50),
                      ],
                      isAvailable: _healthProvider.isGibsAvailable,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(
                            builder: (context) => GibsImageryScreen(
                              initialLat: widget.initialLat,
                              initialLon: widget.initialLon,
                              spotName: widget.spotName,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  

                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
  
  /// Build header showing which spot we're viewing data for
  Widget _buildSpotHeader(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ocean Data for',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 12,
                ),
              ),
              Text(
                widget.spotName!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Card widget for a data source option
class _DataSourceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String source;
  final String? badge;
  final Color? badgeColor;
  final IconData icon;
  final String imagePath;
  final List<Color> fallbackColors;
  final bool isAvailable;
  final VoidCallback onTap;

  /// Optional animated layer drawn on top of the preview image
  /// (e.g. drifting current particles for the Ocean Forecast card).
  final Widget? animatedOverlay;

  const _DataSourceCard({
    required this.title,
    required this.subtitle,
    required this.source,
    this.badge,
    this.badgeColor,
    required this.icon,
    required this.imagePath,
    required this.fallbackColors,
    this.isAvailable = true,
    required this.onTap,
    this.animatedOverlay,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isAvailable ? onTap : () => _showUnavailableMessage(context),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.15),
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              // Image background
              Positioned.fill(
                child: Image.asset(
                  imagePath,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    // Fallback to gradient if image fails
                    return Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: fallbackColors,
                        ),
                      ),
                    );
                  },
                ),
              ),

              if (animatedOverlay != null)
                Positioned.fill(
                  child: RepaintBoundary(child: animatedOverlay!),
                ),

              // Dark gradient overlay for text readability
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.5, 1.0],
                      colors: [
                        Colors.black.withOpacity(0.6),
                        Colors.black.withOpacity(0.2),
                        Colors.black.withOpacity(0.85),
                      ],
                    ),
                  ),
                ),
              ),
              
              // SOURCE at top-left - THE MASSIVE SELLING POINT!
              Positioned(
                top: 16,
                left: 16,
                right: 60,
                child: Text(
                  source.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    shadows: [
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
              
              // Icon in top right
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white.withOpacity(0.9),
                    size: 20,
                  ),
                ),
              ),
              
              // Content at bottom
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title row with badge
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                color: Colors.black54,
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: badgeColor ?? AppColors.info,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badge!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 14,
                        height: 1.3,
                        shadows: const [
                          Shadow(
                            color: Colors.black54,
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Unavailable overlay
              if (!isAvailable)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cloud_off,
                            color: AppColors.darkTextMuted,
                            size: 32,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Temporarily unavailable',
                            style: TextStyle(
                              color: AppColors.darkTextMuted,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _showUnavailableMessage(BuildContext context) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title is temporarily unavailable. Please try again later.'),
        backgroundColor: Colors.orange.shade800,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

/// Lightweight animated particle flow evoking the Ocean Forecast currents
/// layer. Particles drift along a fixed sinusoidal flow field and fade in/out
/// over their lifetime, mimicking WeatherLayers GL particle trails.
class _CurrentsFlowOverlay extends StatefulWidget {
  const _CurrentsFlowOverlay();

  @override
  State<_CurrentsFlowOverlay> createState() => _CurrentsFlowOverlayState();
}

class _CurrentsFlowOverlayState extends State<_CurrentsFlowOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _CurrentsFlowPainter(animation: _controller),
        isComplex: false,
        willChange: true,
      ),
    );
  }
}

class _CurrentsFlowPainter extends CustomPainter {
  final Animation<double> animation;

  // Fixed seed keeps the layout stable across rebuilds.
  static final List<_FlowParticle> _particles = _buildParticles();

  _CurrentsFlowPainter({required this.animation}) : super(repaint: animation);

  static List<_FlowParticle> _buildParticles() {
    final rng = math.Random(7);
    return List.generate(28, (_) => _FlowParticle(rng));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final p in _particles) {
      // Each particle loops on its own phase within the global cycle.
      final life = (t * p.speed + p.phase) % 1.0;

      // Fade in for the first 20% and out for the last 30% of the loop.
      double opacity;
      if (life < 0.2) {
        opacity = life / 0.2;
      } else if (life > 0.7) {
        opacity = (1.0 - life) / 0.3;
      } else {
        opacity = 1.0;
      }

      final startX = (p.originX + life * p.driftX) % 1.2 - 0.1;
      final baseY = p.originY + life * p.driftY;

      paint
        ..color = p.color.withValues(alpha: opacity * 0.55)
        ..strokeWidth = p.thickness;

      // Short sinusoidal trail behind the particle head.
      final path = Path();
      const segments = 6;
      for (var i = 0; i <= segments; i++) {
        final frac = i / segments;
        final x = (startX - frac * p.trailLength) * size.width;
        final y = (baseY +
                math.sin((startX - frac * p.trailLength) * p.waveFreq +
                        p.wavePhase) *
                    p.waveAmp) *
            size.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CurrentsFlowPainter oldDelegate) => false;
}

class _FlowParticle {
  final double originX;
  final double originY;
  final double driftX;
  final double driftY;
  final double speed;
  final double phase;
  final double trailLength;
  final double waveAmp;
  final double waveFreq;
  final double wavePhase;
  final double thickness;
  final Color color;

  _FlowParticle(math.Random rng)
      : originX = rng.nextDouble(),
        originY = 0.05 + rng.nextDouble() * 0.9,
        driftX = 0.25 + rng.nextDouble() * 0.35,
        driftY = (rng.nextDouble() - 0.5) * 0.08,
        speed = 1.0 + rng.nextDouble() * 2.0,
        phase = rng.nextDouble(),
        trailLength = 0.04 + rng.nextDouble() * 0.05,
        waveAmp = 0.01 + rng.nextDouble() * 0.03,
        waveFreq = 6 + rng.nextDouble() * 10,
        wavePhase = rng.nextDouble() * math.pi * 2,
        thickness = 1.0 + rng.nextDouble() * 1.4,
        color = _palette[rng.nextInt(_palette.length)];

  // Cyan/teal/white palette matching the currents velocity colormap.
  static const _palette = [
    Color(0xFFB2EBF2),
    Color(0xFF4DD0E1),
    Color(0xFF80DEEA),
    Color(0xFFE0F7FA),
    Color(0xFF26C6DA),
  ];
}
