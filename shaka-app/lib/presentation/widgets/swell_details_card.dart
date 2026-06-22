import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/unit_converter.dart';
import '../../data/models/spot_models.dart';
import '../../data/services/unit_preference_service.dart';

class _ParsedSwell {
  final double heightFt;
  final int periodSec;
  final String cardinal;
  final double degrees;

  const _ParsedSwell({
    required this.heightFt,
    required this.periodSec,
    required this.cardinal,
    required this.degrees,
  });
}

const _cardinalToDegrees = <String, double>{
  'N': 0, 'NNE': 22.5, 'NE': 45, 'ENE': 67.5,
  'E': 90, 'ESE': 112.5, 'SE': 135, 'SSE': 157.5,
  'S': 180, 'SSW': 202.5, 'SW': 225, 'WSW': 247.5,
  'W': 270, 'WNW': 292.5, 'NW': 315, 'NNW': 337.5,
};

final _swellRegex = RegExp(r'([\d.]+)ft\s*@\s*(\d+)s\s+(\w+)');

// ── Satellite tile helpers ──────────────────────────────────────────────────

const _tileZoom = 14;
const _tileSize = 256.0;
const _arcgisBase =
    'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile';

int _lonToTileX(double lon, int z) =>
    ((lon + 180) / 360 * (1 << z)).floor();

int _latToTileY(double lat, int z) =>
    ((1 - log(tan(lat * pi / 180) + 1 / cos(lat * pi / 180)) / pi) / 2 *
            (1 << z))
        .floor();

double _lonToPixelX(double lon, int z) =>
    (lon + 180) / 360 * (1 << z) * 256;

double _latToPixelY(double lat, int z) =>
    (1 - log(tan(lat * pi / 180) + 1 / cos(lat * pi / 180)) / pi) / 2 *
    (1 << z) *
    256;

/// Returns 4 ArcGIS tile URLs forming a 2x2 grid centered on the spot.
List<String> _satelliteTileUrls(double lat, double lon) {
  const z = _tileZoom;
  final tx = _lonToTileX(lon, z);
  final ty = _latToTileY(lat, z);
  final localX = _lonToPixelX(lon, z) - tx * 256;
  final localY = _latToPixelY(lat, z) - ty * 256;

  // Pick the 2x2 quadrant that keeps the spot near the center
  final startTx = localX >= 128 ? tx : tx - 1;
  final startTy = localY >= 128 ? ty : ty - 1;

  return [
    '$_arcgisBase/$z/$startTy/$startTx',
    '$_arcgisBase/$z/$startTy/${startTx + 1}',
    '$_arcgisBase/$z/${startTy + 1}/$startTx',
    '$_arcgisBase/$z/${startTy + 1}/${startTx + 1}',
  ];
}

/// Pixel offset to translate the 2x2 grid so the spot is view-centered.
Offset _satelliteTileOffset(double lat, double lon, double viewWidth, double viewHeight) {
  const z = _tileZoom;
  final tx = _lonToTileX(lon, z);
  final ty = _latToTileY(lat, z);
  final localX = _lonToPixelX(lon, z) - tx * 256;
  final localY = _latToPixelY(lat, z) - ty * 256;

  final startTx = localX >= 128 ? tx : tx - 1;
  final startTy = localY >= 128 ? ty : ty - 1;

  final spotInGridX = _lonToPixelX(lon, z) - startTx * 256;
  final spotInGridY = _latToPixelY(lat, z) - startTy * 256;

  return Offset(viewWidth / 2 - spotInGridX, viewHeight / 2 - spotInGridY);
}

_ParsedSwell? _parseSwell(String s) {
  final m = _swellRegex.firstMatch(s);
  if (m == null) return null;
  final cardinal = m.group(3)!;
  final deg = _cardinalToDegrees[cardinal];
  if (deg == null) return null;
  return _ParsedSwell(
    heightFt: double.tryParse(m.group(1)!) ?? 0,
    periodSec: int.tryParse(m.group(2)!) ?? 0,
    cardinal: cardinal,
    degrees: deg,
  );
}

/// Expandable card for detailed swell & exposure data with compass visualization.
///
/// COLLAPSED: Shows the swell-at-spot value (e.g., "3.2ft @ 14s SW").
/// EXPANDED: Swell rows with directional badges, then a compass rose showing
/// all swell vectors and the spot's exposure arc.
class SwellDetailsCard extends StatefulWidget {
  final SpotConditions conditions;
  final Coordinates? coordinates;

  const SwellDetailsCard({
    super.key,
    required this.conditions,
    this.coordinates,
  });

  /// Pre-warm satellite tiles into Flutter's image cache (fire-and-forget).
  static void precacheTiles(BuildContext context, double lat, double lon) {
    for (final url in _satelliteTileUrls(lat, lon)) {
      precacheImage(NetworkImage(url), context);
    }
  }

  @override
  State<SwellDetailsCard> createState() => _SwellDetailsCardState();
}

class _SwellDetailsCardState extends State<SwellDetailsCard> {
  static const _cardColor = AppColors.darkSurface;
  static const _borderColor = AppColors.darkBorder;
  static const _primaryColor = AppColors.chartTideHigh;
  static const _secondaryColor = AppColors.chartTideLow;

  final _units = UnitPreferenceService();
  bool _detailsExpanded = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _units,
      builder: (context, _) {
        return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildExpandedContent(),
        ],
      ),
    );
      },
    );
  }

  Widget _buildHeader() {
    final swellValue = widget.conditions.swellHeightFt != null
        ? UnitConverter.formatSwell(widget.conditions.swellHeightFt, widget.conditions.swellPeriodSec, widget.conditions.swellDirection, _units.system)
        : (widget.conditions.swellCorrected ?? widget.conditions.swell);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              swellValue,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _showSwellWindInfo(context);
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Data sources',
                  style: TextStyle(color: AppColors.darkTextHint, fontSize: 11),
                ),
                SizedBox(width: 4),
                Icon(Icons.info_outline, size: 12, color: AppColors.darkTextHint),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedContent() {
    final c = widget.conditions;

    // ── Compass swell data (deduped by direction+category) ──
    final compassSwells = <(_ParsedSwell, Color)>[];
    void addCompass(_ParsedSwell? ps, Color color) {
      if (ps == null) return;
      if (!compassSwells.any((s) => s.$1.degrees == ps.degrees && s.$2 == color)) {
        compassSwells.add((ps, color));
      }
    }

    // ── Row items: (label, value, badge) ──
    final items = <(String, String, Widget?)>[];

    if (c.swellCorrected != null) {
      final ps = _parseSwell(c.swellCorrected!);
      addCompass(ps, _primaryColor);
      final primarySwellValue = c.swellHeightFt != null
          ? UnitConverter.formatSwell(c.swellHeightFt, c.swellPeriodSec, c.swellDirection, _units.system)
          : c.swellCorrected!;
      items.add(('Swell (at spot)', primarySwellValue,
          ps != null ? _SwellDirectionBadge(degrees: ps.degrees, color: _primaryColor) : null));
      if (c.swellCorrected != c.swell) {
        final ps2 = _parseSwell(c.swell);
        addCompass(ps2, _primaryColor);
        items.add(('Swell (open ocean)', c.swell,
            ps2 != null ? _SwellDirectionBadge(degrees: ps2.degrees, color: _primaryColor) : null));
      }
    } else {
      final ps = _parseSwell(c.swell);
      addCompass(ps, _primaryColor);
      final swellValue = c.swellHeightFt != null
          ? UnitConverter.formatSwell(c.swellHeightFt, c.swellPeriodSec, c.swellDirection, _units.system)
          : c.swell;
      items.add(('Swell', swellValue,
          ps != null ? _SwellDirectionBadge(degrees: ps.degrees, color: _primaryColor) : null));
    }

    if (c.secondarySwell != null) {
      if (c.secondarySwellCorrected != null) {
        final ps = _parseSwell(c.secondarySwellCorrected!);
        addCompass(ps, _secondaryColor);
        items.add(('2nd Swell (at spot)', c.secondarySwellCorrected!,
            ps != null ? _SwellDirectionBadge(degrees: ps.degrees, color: _secondaryColor) : null));
        if (c.secondarySwellCorrected != c.secondarySwell) {
          final ps2 = _parseSwell(c.secondarySwell!);
          addCompass(ps2, _secondaryColor);
          items.add(('2nd Swell (open ocean)', c.secondarySwell!,
              ps2 != null ? _SwellDirectionBadge(degrees: ps2.degrees, color: _secondaryColor) : null));
        }
      } else {
        final ps = _parseSwell(c.secondarySwell!);
        addCompass(ps, _secondaryColor);
        items.add(('2nd Swell', c.secondarySwell!,
            ps != null ? _SwellDirectionBadge(degrees: ps.degrees, color: _secondaryColor) : null));
      }
    }

    final windDir = _parseWindDirection(c.wind);
    final windValue = widget.conditions.windSpeedKts != null
        ? UnitConverter.formatWind(widget.conditions.windSpeedKts, widget.conditions.windDirectionCardinal, _units.system)
        : c.wind;
    items.add(('Wind', windValue,
        windDir != null ? _WindBadge(degrees: windDir) : null));

    if (c.exposureBearing != null) {
      items.add(('Exposure',
          'Faces ${_bearingToCardinal(c.exposureBearing!)} (${c.exposureWidth ?? 0}°)',
          _ExposureBadge(degrees: c.exposureBearing!.toDouble())));
    }

    final rowWidgets = <Widget>[
      for (int i = 0; i < items.length; i++)
        _buildRow(
          items[i].$1,
          items[i].$2,
          badge: items[i].$3,
          isLast: i == items.length - 1,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 1, color: Colors.white10),
          if (compassSwells.isNotEmpty) ...[
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 1.0,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewWidth = constraints.maxWidth;
                  final viewHeight = constraints.maxHeight;
                  final coords = widget.coordinates;
                  final tileUrls = coords != null
                      ? _satelliteTileUrls(coords.lat, coords.lon)
                      : null;
                  final tileOffset = coords != null
                      ? _satelliteTileOffset(coords.lat, coords.lon, viewWidth, viewHeight)
                      : null;

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: viewWidth,
                      height: viewHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          if (tileUrls != null && tileOffset != null)
                            for (int i = 0; i < 4; i++)
                              Positioned(
                                left: tileOffset.dx + (i % 2) * _tileSize,
                                top: tileOffset.dy + (i ~/ 2) * _tileSize,
                                child: Image.network(
                                  tileUrls[i],
                                  width: _tileSize,
                                  height: _tileSize,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      SizedBox(width: _tileSize, height: _tileSize),
                                ),
                              ),
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _SwellCompassPainter(
                                swells: compassSwells,
                                exposureBearing: c.exposureBearing?.toDouble(),
                                exposureWidth: c.exposureWidth?.toDouble(),
                                windDirection: _parseWindDirection(c.wind),
                                windLabel: _formatWindLabel(c.wind, _units.system),
                                unitSystem: _units.system,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
          // "Swell & Wind Details" expandable flyout
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _detailsExpanded = !_detailsExpanded);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Swell & Wind Details',
                      style: TextStyle(
                        color: AppColors.darkTextMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _detailsExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      size: 20,
                      color: Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: rowWidgets,
            ),
            crossFadeState:
                _detailsExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }

  Widget _buildRow(
    String label,
    String value, {
    Widget? badge,
    bool isLast = false,
  }) {
    return Container(
      padding: EdgeInsets.only(top: 10, bottom: isLast ? 4 : 10),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          SizedBox(width: 22, child: badge),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(color: AppColors.darkTextMuted, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _bearingToCardinal(int degrees) {
    const dirs = [
      'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
    ];
    return dirs[((degrees % 360) / 22.5).round() % 16];
  }

  static double? _parseWindDirection(String wind) {
    final parts = wind.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return _cardinalToDegrees[parts.last.toUpperCase()];
    }
    return null;
  }

  static String? _formatWindLabel(String wind, UnitSystem system) {
    final m = RegExp(r'(\d+)\s*(kts?|mph)', caseSensitive: false).firstMatch(wind);
    if (m == null) return null;
    final kts = double.tryParse(m.group(1)!) ?? 0;
    if (system == UnitSystem.metric) {
      return '${UnitConverter.knotsToKmh(kts).round()}km/h';
    }
    return '${m.group(1)}${m.group(2)}';
  }

  void _showSwellWindInfo(BuildContext context) {
    final c = widget.conditions;
    final infoCards = <Widget>[];

    // Primary swell
    if (c.swellCorrected != null) {
      infoCards.add(_buildInfoCard(
        'Swell (At Spot)',
        'Shaka Exposure Model',
        _retrievedBadge(c.swellRetrievedAt, 'Every 3 hours'),
        'Open-ocean swell scaled for local coastline. Headlands, coves, and reefs reduce wave height \u2014 a sheltered spot can see 50%+ less than offshore.',
      ));
      if (c.swellCorrected != c.swell) {
        infoCards.add(_buildInfoCard(
          'Swell (Open Ocean)',
          'Open-Meteo Marine + NDBC Buoys',
          _retrievedBadge(c.swellRetrievedAt, 'Hourly'),
          'Significant wave height in open water from NOAA WaveWatch III. Live NDBC buoy readings used when a buoy is nearby.',
        ));
      }
    } else {
      infoCards.add(_buildInfoCard(
        'Swell',
        'Open-Meteo Marine + NDBC Buoys',
        _retrievedBadge(c.swellRetrievedAt, 'Hourly'),
        'Significant wave height in open water from NOAA WaveWatch III. Live NDBC buoy readings used when a buoy is nearby.',
      ));
    }

    // Secondary swell
    if (c.secondarySwell != null) {
      if (c.secondarySwellCorrected != null) {
        infoCards.add(_buildInfoCard(
          '2nd Swell (At Spot)',
          'Shaka Exposure Model',
          _retrievedBadge(c.swellRetrievedAt, 'Every 3 hours'),
          'Secondary wave system exposure-corrected for local coastline sheltering.',
        ));
        if (c.secondarySwellCorrected != c.secondarySwell) {
          infoCards.add(_buildInfoCard(
            '2nd Swell (Open Ocean)',
            'Open-Meteo Marine API',
            _retrievedBadge(c.swellRetrievedAt, 'Hourly'),
            'Second wave system from a different direction. Can add energy to the primary swell or create cross-chop.',
          ));
        }
      } else {
        infoCards.add(_buildInfoCard(
          '2nd Swell',
          'Open-Meteo Marine API',
          _retrievedBadge(c.swellRetrievedAt, 'Hourly'),
          'Second wave system from a different direction. Can add energy to the primary swell or create cross-chop.',
        ));
      }
    }

    // Wind
    infoCards.add(_buildInfoCard(
      'Wind',
      'Open-Meteo Weather API (NOAA GFS)',
      _retrievedBadge(c.windRetrievedAt, 'Hourly'),
      '10-meter wind speed and direction. Offshore = clean, glassy surface. Onshore = chop and reduced visibility.',
    ));

    // Exposure
    if (c.exposureBearing != null) {
      infoCards.add(_buildInfoCard(
        'Exposure',
        'Shaka Coastal Analysis',
        'Computed once',
        'Which direction this spot faces open ocean and how wide the window is. Scans 16 compass bearings at 1\u20135 km to detect sheltering land.',
      ));
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
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
                  const Expanded(
                    child: Text(
                      'Swell & Wind',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppColors.darkTextMuted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'How ocean conditions are measured and calculated:',
                style: TextStyle(color: AppColors.darkTextMuted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ...infoCards,
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.explore, size: 16, color: AppColors.darkTextHint),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'The compass shows swell arrows (direction + relative size), the wind indicator, and the blue exposure arc where open ocean faces this spot.',
                        style: TextStyle(color: AppColors.darkTextMuted, fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Badge text: actual retrieval time when available, else the static fallback.
  static String _retrievedBadge(int? epochMs, String fallback) =>
      epochMs != null ? _formatRetrieved(epochMs) : fallback;

  static String _formatRetrieved(int epochMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMs).toLocal();
    final now = DateTime.now();
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    final time = '$hour12:$minute $ampm';
    final sameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (sameDay) return 'Retrieved $time';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return 'Retrieved ${months[dt.month - 1]} ${dt.day}, $time';
  }

  static Widget _buildInfoCard(String label, String source, String frequency, String description) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  frequency,
                  style: const TextStyle(
                    color: AppColors.darkTextMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            source,
            style: TextStyle(
              color: AppColors.success,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(
              color: AppColors.darkTextSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small circular badge with a rotated arrow showing swell source direction.
class _SwellDirectionBadge extends StatelessWidget {
  final double degrees;
  final Color color;

  const _SwellDirectionBadge({required this.degrees, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Transform.rotate(
        angle: (degrees + 180) * pi / 180,
        child: Icon(Icons.navigation, size: 13, color: color),
      ),
    );
  }
}

/// Small circular badge with a rotated wind icon showing wind source direction.
class _WindBadge extends StatelessWidget {
  final double degrees;
  static const _color = AppColors.chartWind;

  const _WindBadge({required this.degrees});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Transform.rotate(
        angle: (degrees + 90) * pi / 180,
        child: Icon(Icons.air, size: 13, color: _color),
      ),
    );
  }
}

/// Small circular badge showing the direction a spot faces (exposure).
class _ExposureBadge extends StatelessWidget {
  final double degrees;
  static const _color = AppColors.chartSwell;

  const _ExposureBadge({required this.degrees});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Transform.rotate(
        angle: degrees * pi / 180,
        child: Icon(Icons.navigation, size: 13, color: _color),
      ),
    );
  }
}

/// Compass rose showing swell arrows and exposure arc via CustomPainter.
/// All structural lines use the crosshair pattern: white border + black center.
class _SwellArrowGeometry {
  final _ParsedSwell swell;
  final Color color;
  final bool isPrimary;
  final double arrowLen;
  final Offset startPt;
  final Offset endPt;
  final double arrowAngle;
  final Offset rearBorderPt;
  final Path arrowPath;

  const _SwellArrowGeometry({
    required this.swell,
    required this.color,
    required this.isPrimary,
    required this.arrowLen,
    required this.startPt,
    required this.endPt,
    required this.arrowAngle,
    required this.rearBorderPt,
    required this.arrowPath,
  });
}

class _SwellCompassPainter extends CustomPainter {
  final List<(_ParsedSwell, Color)> swells;
  final double? exposureBearing;
  final double? exposureWidth;
  final double? windDirection;
  final String? windLabel;
  final UnitSystem unitSystem;

  _SwellCompassPainter({
    required this.swells,
    this.exposureBearing,
    this.exposureWidth,
    this.windDirection,
    this.windLabel,
    required this.unitSystem,
  });

  static const _shadowStyle = [
    Shadow(color: Color(0xFF000000), blurRadius: 4),
    Shadow(color: Color(0xCC000000), blurRadius: 8),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 24;

    if (exposureBearing != null && exposureWidth != null && exposureWidth! > 0) {
      _drawExposureArc(canvas, center, radius);
    }

    _drawReferenceRings(canvas, center, radius);
    _drawCenterCrosshair(canvas, center);
    _drawCardinalLabels(canvas, center, radius);
    _drawWindIndicator(canvas, center, radius);
    _drawSwellArrows(canvas, center, radius);
  }

  /// White border + black center — same pattern as the crosshair.
  void _drawReferenceRings(Canvas canvas, Offset center, double radius) {
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final centerPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (int i = 1; i <= 3; i++) {
      final r = radius * i / 3;
      canvas.drawCircle(center, r, borderPaint);
      canvas.drawCircle(center, r, centerPaint);
    }
  }

  void _drawCenterCrosshair(Canvas canvas, Offset center) {
    const gap = 8.0;
    const lineLen = 18.0;

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final centerPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    for (final paint in [borderPaint, centerPaint]) {
      canvas.drawLine(Offset(center.dx, center.dy - gap),
          Offset(center.dx, center.dy - gap - lineLen), paint);
      canvas.drawLine(Offset(center.dx, center.dy + gap),
          Offset(center.dx, center.dy + gap + lineLen), paint);
      canvas.drawLine(Offset(center.dx - gap, center.dy),
          Offset(center.dx - gap - lineLen, center.dy), paint);
      canvas.drawLine(Offset(center.dx + gap, center.dy),
          Offset(center.dx + gap + lineLen, center.dy), paint);
    }

    canvas.drawCircle(center, 3, Paint()..color = Colors.red);
  }

  void _drawCardinalLabels(Canvas canvas, Offset center, double radius) {
    const labels = ['N', 'E', 'S', 'W'];
    const bearings = [0.0, 90.0, 180.0, 270.0];

    for (int i = 0; i < labels.length; i++) {
      final b = bearings[i] * pi / 180;
      final offset = Offset(
        center.dx + (radius + 14) * sin(b),
        center.dy - (radius + 14) * cos(b),
      );

      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            shadows: _shadowStyle,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(canvas, Offset(offset.dx - tp.width / 2, offset.dy - tp.height / 2));
    }
  }

  void _drawExposureArc(Canvas canvas, Offset center, double radius) {
    final bearing = exposureBearing!;
    final width = exposureWidth!;

    final startAngle = (bearing - width / 2 - 90) * pi / 180;
    final sweepAngle = width * pi / 180;

    final fillPaint = Paint()
      ..color = AppColors.chartSwell.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final sectorPath = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
      )
      ..close();

    canvas.drawPath(sectorPath, fillPaint);

    final rect = Rect.fromCircle(center: center, radius: radius);

    // White border + black center pattern (matching crosshair/rings)
    canvas.drawArc(rect, startAngle, sweepAngle, false, Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5);

    canvas.drawArc(rect, startAngle, sweepAngle, false, Paint()
      ..color = AppColors.chartSwell.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
  }

  void _drawWindIndicator(Canvas canvas, Offset center, double radius) {
    if (windDirection == null) return;

    final b = windDirection! * pi / 180;
    final outerR = radius * 0.93;
    final pillCenter = Offset(
      center.dx + outerR * sin(b),
      center.dy - outerR * cos(b),
    );

    // Lay out icon + label to measure pill size
    final iconTp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.air.codePoint),
        style: TextStyle(
          fontFamily: Icons.air.fontFamily,
          package: Icons.air.fontPackage,
          fontSize: 18,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final labelText = windLabel ?? '';
    final labelTp = TextPainter(
      text: TextSpan(
        text: labelText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const hPad = 6.0;
    const gap = 3.0;
    final pillW = hPad + iconTp.width + gap + labelTp.width + hPad;
    final pillH = 24.0;
    final pillR = pillH / 2;

    // Radial angle so the pill extends outward from center
    final radialAngle = atan2(
      pillCenter.dy - center.dy,
      pillCenter.dx - center.dx,
    );

    canvas.save();
    canvas.translate(pillCenter.dx, pillCenter.dy);
    canvas.rotate(radialAngle);

    // Pill background + border (drawn in local coords, centered vertically).
    // The center-facing side gets a shallow point; the outer side stays rounded.
    final pillLeft = -pillW / 2;
    final pillRight = pillW / 2;
    final pointDepth = min(8.0, pillH * 0.5);
    final bodyLeft = pillLeft + pointDepth;
    final bodyRight = pillRight - pillR;
    final pointCtrlX = pillLeft + pointDepth * 0.35;
    final pointCtrlY = pillH * 0.26;
    final pillPath = Path()
      ..moveTo(pillLeft, 0)
      ..quadraticBezierTo(pointCtrlX, -pointCtrlY, bodyLeft, -pillH / 2)
      ..lineTo(bodyRight, -pillH / 2)
      ..arcToPoint(
        Offset(bodyRight, pillH / 2),
        radius: Radius.circular(pillR),
        clockwise: true,
      )
      ..lineTo(bodyLeft, pillH / 2)
      ..quadraticBezierTo(pointCtrlX, pointCtrlY, pillLeft, 0)
      ..close();
    canvas.drawPath(pillPath, Paint()
      ..color = AppColors.chartWind.withValues(alpha: 0.85));
    canvas.drawPath(pillPath, Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round);

    // Icon (rotated to face wind direction inside the pill)
    final iconRotation = (windDirection! + 90) * pi / 180 - radialAngle;
    final contentWidth = iconTp.width + gap + labelTp.width;
    final contentStart = pillLeft + (pillW - contentWidth) / 2;
    final iconX = contentStart + iconTp.width / 2;
    canvas.save();
    canvas.translate(iconX, 0);
    canvas.rotate(iconRotation);
    iconTp.paint(canvas, Offset(-iconTp.width / 2, -iconTp.height / 2));
    canvas.restore();

    // Label text (keep readable — flip if upside-down)
    final labelX = iconX + iconTp.width / 2 + gap;
    final needsFlip = radialAngle.abs() > pi / 2;
    if (needsFlip) {
      canvas.save();
      canvas.translate(labelX + labelTp.width / 2, 0);
      canvas.rotate(pi);
      labelTp.paint(canvas, Offset(-labelTp.width / 2, -labelTp.height / 2));
      canvas.restore();
    } else {
      labelTp.paint(canvas, Offset(labelX, -labelTp.height / 2));
    }

    canvas.restore();
  }

  void _drawSwellArrows(Canvas canvas, Offset center, double radius) {
    if (swells.isEmpty) return;

    // FIXED sizes — never change regardless of swell values.
    const double primaryLenFactor = 0.60;
    const double secondaryLenFactor = 0.33;
    final double primaryArrowLen = radius * primaryLenFactor;
    final double secondaryArrowLen = radius * secondaryLenFactor;
    final double tipR = radius * 0.10;
    final geometries = <_SwellArrowGeometry>[];

    for (int idx = 0; idx < swells.length; idx++) {
      final (swell, color) = swells[idx];
      final isPrimary = idx == 0;
      final b = swell.degrees * pi / 180;

      final barWidth = isPrimary ? 26.0 : 16.0;
      final halfW = barWidth / 2;

      final arrowLen = isPrimary ? primaryArrowLen : secondaryArrowLen;
      final outerR = tipR + arrowLen;

      final startPt = Offset(
        center.dx + outerR * sin(b),
        center.dy - outerR * cos(b),
      );
      final endPt = Offset(
        center.dx + tipR * sin(b),
        center.dy - tipR * cos(b),
      );

      final arrowAngle = atan2(endPt.dy - startPt.dy, endPt.dx - startPt.dx);
      final perpAngle = arrowAngle + pi / 2;

      final baseR = Offset(
        startPt.dx + halfW * cos(perpAngle),
        startPt.dy + halfW * sin(perpAngle),
      );
      final baseL = Offset(
        startPt.dx - halfW * cos(perpAngle),
        startPt.dy - halfW * sin(perpAngle),
      );

      final ctrl1R = Offset(
        endPt.dx + (startPt.dx - endPt.dx) * 0.25 + halfW * 0.8 * cos(perpAngle),
        endPt.dy + (startPt.dy - endPt.dy) * 0.25 + halfW * 0.8 * sin(perpAngle),
      );
      final ctrl2R = Offset(
        endPt.dx + (startPt.dx - endPt.dx) * 0.50 + halfW * cos(perpAngle),
        endPt.dy + (startPt.dy - endPt.dy) * 0.50 + halfW * sin(perpAngle),
      );
      final ctrl2L = Offset(
        endPt.dx + (startPt.dx - endPt.dx) * 0.50 - halfW * cos(perpAngle),
        endPt.dy + (startPt.dy - endPt.dy) * 0.50 - halfW * sin(perpAngle),
      );
      final ctrl1L = Offset(
        endPt.dx + (startPt.dx - endPt.dx) * 0.25 - halfW * 0.8 * cos(perpAngle),
        endPt.dy + (startPt.dy - endPt.dy) * 0.25 - halfW * 0.8 * sin(perpAngle),
      );

      final capDepth = halfW * 0.55;
      final backDx = -cos(arrowAngle);
      final backDy = -sin(arrowAngle);
      final baseCapCtrlR = Offset(
        baseR.dx + capDepth * backDx,
        baseR.dy + capDepth * backDy,
      );
      final baseCapCtrlL = Offset(
        baseL.dx + capDepth * backDx,
        baseL.dy + capDepth * backDy,
      );
      final rearBorderDepth = capDepth * 0.75;
      final rearBorderPt = Offset(
        startPt.dx + rearBorderDepth * backDx,
        startPt.dy + rearBorderDepth * backDy,
      );

      final arrowPath = Path()
        ..moveTo(endPt.dx, endPt.dy)
        ..cubicTo(ctrl1R.dx, ctrl1R.dy, ctrl2R.dx, ctrl2R.dy,
            baseR.dx, baseR.dy)
        ..cubicTo(baseCapCtrlR.dx, baseCapCtrlR.dy,
            baseCapCtrlL.dx, baseCapCtrlL.dy, baseL.dx, baseL.dy)
        ..cubicTo(ctrl2L.dx, ctrl2L.dy, ctrl1L.dx, ctrl1L.dy,
            endPt.dx, endPt.dy);

      geometries.add(_SwellArrowGeometry(
        swell: swell,
        color: color,
        isPrimary: isPrimary,
        arrowLen: arrowLen,
        startPt: startPt,
        endPt: endPt,
        arrowAngle: arrowAngle,
        rearBorderPt: rearBorderPt,
        arrowPath: arrowPath,
      ));
    }

    for (final geometry in geometries) {
      canvas.drawPath(geometry.arrowPath, Paint()
        ..color = Colors.white.withValues(alpha: geometry.isPrimary ? 0.5 : 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = geometry.isPrimary ? 3.0 : 2.5
        ..strokeJoin = StrokeJoin.round);

      canvas.drawPath(
          geometry.arrowPath, Paint()..color = geometry.color.withValues(alpha: 0.9));
    }

    final primaryGeometry = geometries.first;
    final primaryAxis = Offset(
      cos(primaryGeometry.arrowAngle),
      sin(primaryGeometry.arrowAngle),
    );
    const labelPad = 3.0;
    final projectedSecondaryRearBorders = geometries
        .skip(1)
        .map((geometry) => (geometry.rearBorderPt.dx - primaryGeometry.rearBorderPt.dx) *
                primaryAxis.dx +
            (geometry.rearBorderPt.dy - primaryGeometry.rearBorderPt.dy) *
                primaryAxis.dy)
        .where((distance) => distance > 0)
        .toList();
    final primaryOverlapLimit = projectedSecondaryRearBorders.isEmpty
        ? null
        : projectedSecondaryRearBorders.reduce(min) - labelPad;

    for (final geometry in geometries) {
      // --- Label ---
      final ht = geometry.swell.heightFt;
      final label = '${UnitConverter.formatSwellHeight(ht, unitSystem)} ${geometry.swell.periodSec}s';
      final axis = Offset(cos(geometry.arrowAngle), sin(geometry.arrowAngle));
      final rearToFrontSpan = (geometry.endPt.dx - geometry.rearBorderPt.dx) * axis.dx +
          (geometry.endPt.dy - geometry.rearBorderPt.dy) * axis.dy;
      final maxLabelSpan = geometry.isPrimary
          ? max(
              0.0,
              min(rearToFrontSpan - labelPad,
                  primaryOverlapLimit ?? (rearToFrontSpan - labelPad)) -
                  labelPad,
            )
          : max(0.0, rearToFrontSpan - labelPad * 2);

      var fontSize = geometry.isPrimary ? 13.0 : 10.0;
      late TextPainter tp;
      for (;;) {
        tp = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        if (tp.width <= maxLabelSpan || fontSize <= 0.5) break;
        fontSize -= 0.5;
      }

      var textAngle = geometry.arrowAngle;
      if (textAngle > pi / 2) textAngle -= pi;
      if (textAngle < -pi / 2) textAngle += pi;
      final flipped = (geometry.arrowAngle - textAngle).abs() > 0.1;

      const anchorPx = labelPad;
      final anchorPt = Offset(
        geometry.rearBorderPt.dx + axis.dx * anchorPx,
        geometry.rearBorderPt.dy + axis.dy * anchorPx,
      );

      canvas.save();
      canvas.translate(anchorPt.dx, anchorPt.dy);
      canvas.rotate(textAngle);
      if (flipped) {
        tp.paint(canvas, Offset(-tp.width, -tp.height / 2));
      } else {
        tp.paint(canvas, Offset(0, -tp.height / 2));
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SwellCompassPainter oldDelegate) {
    return swells.length != oldDelegate.swells.length ||
        exposureBearing != oldDelegate.exposureBearing ||
        exposureWidth != oldDelegate.exposureWidth ||
        windDirection != oldDelegate.windDirection ||
        windLabel != oldDelegate.windLabel ||
        unitSystem != oldDelegate.unitSystem;
  }
}
