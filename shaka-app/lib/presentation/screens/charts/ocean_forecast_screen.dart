import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

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

class OceanForecastScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLon;
  final String? spotName;

  const OceanForecastScreen({
    super.key,
    this.initialLat,
    this.initialLon,
    this.spotName,
  });

  @override
  State<OceanForecastScreen> createState() => _OceanForecastScreenState();
}

class _OceanForecastScreenState extends State<OceanForecastScreen> {
  WebViewController? _controller;
  bool _mapReady = false;
  bool _isLoading = true;
  bool _playing = false;
  String _activeLayer = 'wind';
  int _timeIndex = 0;
  List<String> _timestamps = [];
  String? _errorMessage;
  Set<String> _availableLayers = {};

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _initWebView() async {
    final html = await rootBundle.loadString('assets/html/weather_map.html');

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0D0D0D))
      ..addJavaScriptChannel(
        'ReadyChannel',
        onMessageReceived: (_) => _onMapReady(),
      )
      ..addJavaScriptChannel(
        'CatalogChannel',
        onMessageReceived: (msg) {
          try {
            final data = jsonDecode(msg.message) as Map<String, dynamic>;
            final vars = (data['variables'] as List?)?.cast<String>() ?? [];
            final ts = (data['timestamps'] as List?)?.cast<String>() ?? [];
            setState(() {
              _availableLayers = vars.toSet();
              _timestamps = ts;
              if (vars.isNotEmpty) {
                _activeLayer = _kLayers.keys.firstWhere(
                  (k) => vars.contains(k),
                  orElse: () => _activeLayer,
                );
              }
              if (data['noData'] == true || vars.isEmpty) {
                _errorMessage = 'Forecast data not yet available';
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
            final ts = (data['timestamps'] as List?)?.cast<String>() ?? [];
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
            setState(() => _playing = data['playing'] as bool? ?? false);
          } catch (_) {}
        },
      )
      ..addJavaScriptChannel(
        'TapChannel',
        onMessageReceived: (msg) {
          // Future: show point value
        },
      )
      ..addJavaScriptChannel(
        'DebugChannel',
        onMessageReceived: (msg) {
          try {
            final data = jsonDecode(msg.message) as Map<String, dynamic>;
            debugPrint('JS: ${data['error'] ?? msg.message}');
          } catch (_) {
            debugPrint('JS: ${msg.message}');
          }
        },
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          final configJson = jsonEncode({
            'baseUrl': _kApiBase,
            'weatherCdnUrl': _kWeatherCdnBase,
            'lat': widget.initialLat ?? 23.0,
            'lng': widget.initialLon ?? -108.0,
            'zoom': widget.initialLat != null ? 6 : 4,
          });
          _controller?.runJavaScript('initMap($configJson)');
        },
        onWebResourceError: (error) {
          debugPrint('WebView error: ${error.description}');
        },
      ))
      ..loadHtmlString(html, baseUrl: _kApiBase);

    setState(() {});
  }

  void _onMapReady() {
    setState(() => _mapReady = true);
  }

  void _selectLayer(String key) {
    if (key == _activeLayer) return;
    final hasData = _availableLayers.isEmpty || _availableLayers.contains(key);
    setState(() {
      _isLoading = hasData;
      _activeLayer = key;
      _timeIndex = 0;
      _timestamps = [];
      _errorMessage = hasData ? null : 'No data available for this layer yet';
    });
    _controller?.runJavaScript("setLayer('$key')");
  }

  void _onTimeSliderChanged(double value) {
    final idx = value.round();
    if (idx == _timeIndex) return;
    setState(() => _timeIndex = idx);
    _controller?.runJavaScript('setTimeIndex($idx)');
  }

  void _togglePlayback() {
    if (_playing) {
      _controller?.runJavaScript('pause()');
    } else {
      _controller?.runJavaScript('play()');
    }
  }

  String _formatTimestamp(String ts) {
    try {
      final dt = DateTime.parse(ts);
      final local = dt.toLocal();
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      final day = local.day;
      final month = months[local.month - 1];
      final hour = local.hour.toString().padLeft(2, '0');
      return '$month $day ${hour}:00';
    } catch (_) {
      return ts;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Stack(
        children: [
          if (_controller != null)
            Positioned.fill(
              child: WebViewWidget(controller: _controller!),
            ),

          // Top safe area gradient
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: MediaQuery.of(context).padding.top + 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
              ),
            ),
          ),

          // Layer label
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Text(
                  _kLayers[_activeLayer]?.label ?? _activeLayer,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                12, 10, 12,
                MediaQuery.of(context).padding.bottom + 10,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.85),
                    Colors.black.withOpacity(0.5),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.7, 1.0],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Time controls
                  if (_timestamps.isNotEmpty) ...[
                    Row(
                      children: [
                        GestureDetector(
                          onTap: _togglePlayback,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _playing ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              activeTrackColor: _kLayers[_activeLayer]?.color ?? Colors.cyan,
                              inactiveTrackColor: Colors.white.withOpacity(0.15),
                              thumbColor: Colors.white,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              trackHeight: 3,
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                            ),
                            child: Slider(
                              value: _timeIndex.toDouble().clamp(0, (_timestamps.length - 1).toDouble()),
                              min: 0,
                              max: (_timestamps.length - 1).toDouble().clamp(0, double.infinity),
                              divisions: _timestamps.length > 1 ? _timestamps.length - 1 : null,
                              onChanged: _onTimeSliderChanged,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 72,
                          child: Text(
                            _timeIndex < _timestamps.length
                                ? _formatTimestamp(_timestamps[_timeIndex])
                                : '--',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Layer chips
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _kLayers.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (context, index) {
                        final key = _kLayers.keys.elementAt(index);
                        final meta = _kLayers[key]!;
                        final isActive = key == _activeLayer;
                        final hasData = _availableLayers.isEmpty || _availableLayers.contains(key);
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _selectLayer(key);
                          },
                          child: Opacity(
                            opacity: hasData ? 1.0 : 0.45,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? meta.color.withOpacity(0.3)
                                    : Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isActive
                                      ? meta.color.withOpacity(0.6)
                                      : Colors.white.withOpacity(0.1),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(meta.icon, size: 14,
                                    color: isActive ? meta.color : Colors.white54),
                                  const SizedBox(width: 5),
                                  Text(
                                    meta.label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                                      color: isActive ? Colors.white : Colors.white70,
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
                ],
              ),
            ),
          ),

          // Loading overlay
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: const Color(0xFF0D0D0D).withOpacity(0.7),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white54,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),

          // Error message
          if (_errorMessage != null && !_isLoading)
            Positioned(
              top: MediaQuery.of(context).padding.top + 56,
              left: 24, right: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade900.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.white70, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
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
