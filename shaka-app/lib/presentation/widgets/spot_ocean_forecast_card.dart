import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/unit_converter.dart';
import '../../data/services/unit_preference_service.dart';

const _kApiBase = 'https://shaka-production.up.railway.app';
const _kWeatherCdnBase = 'https://shaka-weather-cdn.kcwn89.workers.dev';

const _kLayers = <String, _LayerMeta>{
  'wind': _LayerMeta('Wind', 'm/s', Icons.air, Color(0xFF70D6FF)),
  'currents': _LayerMeta('Currents', 'm/s', Icons.waves, Color(0xFF5E60CE)),
  'waves': _LayerMeta('Wave Height', 'm', Icons.tsunami, Color(0xFF62B6CB)),
  'sst': _LayerMeta('SST', '°C', Icons.thermostat, Color(0xFFEF476F)),
  'salinity': _LayerMeta('Salinity', 'PSU', Icons.water_drop, Color(0xFF48BFE3)),
  'chlorophyll': _LayerMeta('Chlorophyll', 'mg/m³', Icons.grass, Color(0xFF40916C)),
  'phytoplankton': _LayerMeta('Phyto', 'mmol/m³', Icons.eco, Color(0xFF74C69D)),
  'zooplankton': _LayerMeta('Zoo', 'mmol/m³', Icons.pest_control, Color(0xFFC77DFF)),
};

class _LayerMeta {
  final String label;
  final String unit;
  final IconData icon;
  final Color color;
  const _LayerMeta(this.label, this.unit, this.icon, this.color);
}

class SpotOceanForecastCard extends StatefulWidget {
  final double lat;
  final double lon;

  const SpotOceanForecastCard({
    super.key,
    required this.lat,
    required this.lon,
  });

  @override
  State<SpotOceanForecastCard> createState() => _SpotOceanForecastCardState();
}

class _SpotOceanForecastCardState extends State<SpotOceanForecastCard> {
  WebViewController? _controller;
  bool _isLoading = true;
  bool _playing = false;
  String _activeLayer = 'wind';
  int _timeIndex = 0;
  List<String> _timestamps = [];
  String? _errorMessage;
  Set<String> _availableLayers = {};

  double? _probeValue;
  double? _probeDirection;
  VoidCallback? _unitListener;
  Timer? _scrubDebounce;

  @override
  void initState() {
    super.initState();
    _unitListener = () {
      if (mounted) {
        setState(() {});
        _controller?.runJavaScript(
          'if (typeof setUnitSystem === "function") setUnitSystem("${UnitPreferenceService().system.name}");',
        );
      }
    };
    UnitPreferenceService().addListener(_unitListener!);
    _initWebView();
  }

  @override
  void dispose() {
    _scrubDebounce?.cancel();
    if (_unitListener != null) {
      UnitPreferenceService().removeListener(_unitListener!);
    }
    super.dispose();
  }

  Future<void> _initWebView() async {
    final html =
        await rootBundle.loadString('assets/html/spot_ocean_map.html');

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.darkBackground)
      ..addJavaScriptChannel(
        'ReadyChannel',
        onMessageReceived: (_) {},
      )
      ..addJavaScriptChannel(
        'CatalogChannel',
        onMessageReceived: (msg) {
          try {
            final data = jsonDecode(msg.message) as Map<String, dynamic>;
            final vars =
                (data['variables'] as List?)?.cast<String>() ?? [];
            if (!mounted) return;
            setState(() {
              _availableLayers = vars.toSet();
              if (vars.isNotEmpty) {
                _activeLayer = _kLayers.keys.firstWhere(
                  (k) => vars.contains(k),
                  orElse: () => _activeLayer,
                );
              }
              if (data['noData'] == true || vars.isEmpty) {
                _errorMessage = 'Ocean forecast data not yet available';
                _isLoading = false;
              }
            });
          } catch (_) {}
        },
      )
      ..addJavaScriptChannel(
        'LayerChannel',
        onMessageReceived: (msg) {
          try {
            final data = jsonDecode(msg.message) as Map<String, dynamic>;
            final ts =
                (data['timestamps'] as List?)?.cast<String>() ?? [];
            if (!mounted) return;
            setState(() {
              _activeLayer = data['layer'] as String? ?? _activeLayer;
              _timestamps = ts;
              _timeIndex = (data['timeIndex'] as int?) ?? 0;
              _isLoading = false;
              if (ts.isNotEmpty) _errorMessage = null;
            });
          } catch (_) {}
        },
      )
      ..addJavaScriptChannel(
        'TimeChannel',
        onMessageReceived: (msg) {
          try {
            final data = jsonDecode(msg.message) as Map<String, dynamic>;
            if (!mounted) return;
            setState(() {
              _timeIndex = (data['timeIndex'] as int?) ?? _timeIndex;
            });
          } catch (_) {}
        },
      )
      ..addJavaScriptChannel(
        'PlaybackChannel',
        onMessageReceived: (msg) {
          try {
            final data = jsonDecode(msg.message) as Map<String, dynamic>;
            if (!mounted) return;
            setState(() => _playing = data['playing'] as bool? ?? false);
          } catch (_) {}
        },
      )
      ..addJavaScriptChannel(
        'ProbeChannel',
        onMessageReceived: (msg) {
          try {
            final data = jsonDecode(msg.message) as Map<String, dynamic>;
            if (!mounted) return;
            setState(() {
              _probeValue = (data['value'] as num?)?.toDouble();
              _probeDirection = (data['direction'] as num?)?.toDouble();
            });
          } catch (_) {}
        },
      )
      ..addJavaScriptChannel(
        'DebugChannel',
        onMessageReceived: (msg) {
          debugPrint('SpotOceanMap JS: ${msg.message}');
        },
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => _onPageFinished(),
        onWebResourceError: (error) {
          debugPrint('SpotOceanMap error: ${error.description}');
        },
      ))
      ..loadHtmlString(html, baseUrl: _kApiBase);

    if (_controller!.platform is WebKitWebViewController) {
      (_controller!.platform as WebKitWebViewController)
          .setInspectable(kDebugMode);
    }

    if (mounted) setState(() {});
  }

  Future<void> _onPageFinished() async {
    final configJson = jsonEncode({
      'baseUrl': _kApiBase,
      'weatherCdnUrl': _kWeatherCdnBase,
      'lat': widget.lat,
      'lng': widget.lon,
      'zoom': 8,
    });
    await _controller?.runJavaScript('initMap($configJson)');
    await _controller?.runJavaScript(
      'if (typeof setUnitSystem === "function") setUnitSystem("${UnitPreferenceService().system.name}");',
    );
  }

  void _selectLayer(String key) {
    if (key == _activeLayer) return;
    final hasData =
        _availableLayers.isEmpty || _availableLayers.contains(key);
    setState(() {
      _isLoading = hasData;
      _activeLayer = key;
      _timeIndex = 0;
      _timestamps = [];
      _probeValue = null;
      _probeDirection = null;
      _errorMessage =
          hasData ? null : 'No data available for this layer yet';
    });
    _controller?.runJavaScript("setLayer('$key')");
  }

  void _onTimeSliderChanged(double value) {
    final idx = value.round();
    if (idx == _timeIndex) return;
    setState(() => _timeIndex = idx);
    _scrubDebounce?.cancel();
    _scrubDebounce = Timer(const Duration(milliseconds: 150), () {
      _controller?.runJavaScript('setTimeIndex($idx)');
    });
  }

  void _togglePlayback() {
    if (_playing) {
      _controller?.runJavaScript('pause()');
    } else {
      setState(() {
        _probeValue = null;
        _probeDirection = null;
      });
      _controller?.runJavaScript('play()');
    }
  }

  String _formatTimestamp(String ts) {
    try {
      final dt = DateTime.parse(ts);
      final local = dt.toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${months[local.month - 1]} ${local.day} ${local.hour.toString().padLeft(2, '0')}:00';
    } catch (_) {
      return ts;
    }
  }

  static String _degreesToCardinal(double deg) {
    const dirs = [
      'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
    ];
    final idx = ((deg % 360 + 360) % 360 / 22.5 + 0.5).floor() % 16;
    return dirs[idx];
  }

  String _formatProbeValue() {
    if (_probeValue == null) return '';
    final system = UnitPreferenceService().system;
    final isVector = _activeLayer == 'wind' || _activeLayer == 'currents';
    String formatted;
    switch (_activeLayer) {
      case 'wind':
      case 'currents':
        formatted = UnitConverter.formatChartWind(_probeValue!, system);
        break;
      case 'waves':
        formatted =
            UnitConverter.formatChartWaveHeight(_probeValue!, system);
        break;
      case 'sst':
        formatted = UnitConverter.formatChartSST(_probeValue!, system);
        break;
      default:
        final unit = _kLayers[_activeLayer]?.unit ?? '';
        final valStr = _probeValue!.abs() < 10
            ? _probeValue!.toStringAsFixed(1)
            : _probeValue!.toStringAsFixed(0);
        formatted = '$valStr $unit';
    }
    if (isVector && _probeDirection != null) {
      return '$formatted ${_degreesToCardinal(_probeDirection!)}';
    }
    return formatted;
  }

  @override
  Widget build(BuildContext context) {
    final layerColor = _kLayers[_activeLayer]?.color ?? Colors.cyan;

    return Container(
      margin: const EdgeInsets.only(top: 20),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(
              children: [
                Icon(Icons.public, color: layerColor, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Ocean Forecast',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (_probeValue != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: layerColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: layerColor.withOpacity(0.4)),
                    ),
                    child: Text(
                      _formatProbeValue(),
                      style: TextStyle(
                        color: layerColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Layer toggle pills
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: _kLayers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final key = _kLayers.keys.elementAt(index);
                final meta = _kLayers[key]!;
                final isActive = key == _activeLayer;
                final hasData = _availableLayers.isEmpty ||
                    _availableLayers.contains(key);
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _selectLayer(key);
                  },
                  child: Opacity(
                    opacity: hasData ? 1.0 : 0.45,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isActive
                            ? meta.color.withOpacity(0.25)
                            : Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isActive
                              ? meta.color.withOpacity(0.5)
                              : Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(meta.icon,
                              size: 13,
                              color: isActive
                                  ? meta.color
                                  : Colors.white54),
                          const SizedBox(width: 4),
                          Text(
                            meta.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isActive
                                  ? Colors.white
                                  : Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 10),

          // Map WebView
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(14),
            ),
            child: SizedBox(
              height: 260,
              child: Stack(
                children: [
                  if (_controller != null)
                    WebViewWidget(
                      controller: _controller!,
                      gestureRecognizers: const <Factory<
                          OneSequenceGestureRecognizer>>{},
                    ),

                  // Loading overlay
                  if (_isLoading)
                    Container(
                      color: AppColors.darkBackground,
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white38,
                          strokeWidth: 2,
                        ),
                      ),
                    ),

                  // Error overlay
                  if (_errorMessage != null && !_isLoading)
                    Container(
                      color: AppColors.darkBackground,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: AppColors.darkTextMuted,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),

                  // Time controls overlay at bottom
                  if (_timestamps.isNotEmpty && !_isLoading)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.8),
                              Colors.black.withOpacity(0.4),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.7, 1.0],
                          ),
                        ),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: _togglePlayback,
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  _playing
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SliderTheme(
                                data: SliderThemeData(
                                  activeTrackColor: layerColor,
                                  inactiveTrackColor:
                                      Colors.white.withOpacity(0.12),
                                  thumbColor: Colors.white,
                                  thumbShape:
                                      const RoundSliderThumbShape(
                                          enabledThumbRadius: 5),
                                  trackHeight: 2.5,
                                  overlayShape:
                                      const RoundSliderOverlayShape(
                                          overlayRadius: 12),
                                ),
                                child: Slider(
                                  value: _timeIndex.toDouble().clamp(
                                      0,
                                      (_timestamps.length - 1)
                                          .toDouble()),
                                  min: 0,
                                  max: (_timestamps.length - 1)
                                      .toDouble()
                                      .clamp(0, double.infinity),
                                  divisions: _timestamps.length > 1
                                      ? _timestamps.length - 1
                                      : null,
                                  onChanged: _onTimeSliderChanged,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 68,
                              child: Text(
                                _timeIndex < _timestamps.length
                                    ? _formatTimestamp(
                                        _timestamps[_timeIndex])
                                    : '--',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
