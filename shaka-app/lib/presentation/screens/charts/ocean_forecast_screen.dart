import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

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

class _PaletteStop {
  final double value;
  final Color color;
  const _PaletteStop(this.value, this.color);
}

/// Mirrors the JS LAYERS[key].palette definitions in weather_map.html.
/// Currents uses the VELOCITY_BG_PALETTE mapped to real-world current speeds.
const _kLayerPalettes = <String, List<_PaletteStop>>{
  'wind': [
    _PaletteStop(0, Color(0xFF334455)),
    _PaletteStop(3, Color(0xFF1A6B8A)),
    _PaletteStop(6, Color(0xFF0077B6)),
    _PaletteStop(10, Color(0xFFCC8800)),
    _PaletteStop(15, Color(0xFFCC3333)),
    _PaletteStop(25, Color(0xFF991111)),
  ],
  'currents': [
    _PaletteStop(0, Color(0xFF000033)),
    _PaletteStop(0.2, Color(0xFF0000FF)),
    _PaletteStop(0.5, Color(0xFF00FFFF)),
    _PaletteStop(1.0, Color(0xFF88FF00)),
    _PaletteStop(1.5, Color(0xFFFFFF00)),
    _PaletteStop(2.0, Color(0xFFFF8800)),
    _PaletteStop(3.0, Color(0xFFFF00FF)),
  ],
  'waves': [
    _PaletteStop(0, Color(0xFF0D1B2A)),
    _PaletteStop(0.5, Color(0xFF1B4965)),
    _PaletteStop(1, Color(0xFF62B6CB)),
    _PaletteStop(2, Color(0xFFBEE9E8)),
    _PaletteStop(3, Color(0xFFFFD166)),
    _PaletteStop(5, Color(0xFFEF476F)),
    _PaletteStop(10, Color(0xFFD62828)),
    _PaletteStop(15, Color(0xFF6A040F)),
  ],
  'sst': [
    _PaletteStop(-2, Color(0xFF023E8A)),
    _PaletteStop(5, Color(0xFF0077B6)),
    _PaletteStop(10, Color(0xFF00B4D8)),
    _PaletteStop(15, Color(0xFF48CAE4)),
    _PaletteStop(20, Color(0xFF90E0EF)),
    _PaletteStop(22, Color(0xFFADE8F4)),
    _PaletteStop(25, Color(0xFFFFD166)),
    _PaletteStop(28, Color(0xFFF77F00)),
    _PaletteStop(30, Color(0xFFEF476F)),
    _PaletteStop(35, Color(0xFFD00000)),
  ],
  'salinity': [
    _PaletteStop(20, Color(0xFF7400B8)),
    _PaletteStop(25, Color(0xFF5E60CE)),
    _PaletteStop(30, Color(0xFF5390D9)),
    _PaletteStop(33, Color(0xFF48BFE3)),
    _PaletteStop(35, Color(0xFF56CFE1)),
    _PaletteStop(36, Color(0xFF64DFDF)),
    _PaletteStop(37, Color(0xFF72EFDD)),
    _PaletteStop(38, Color(0xFF80FFDB)),
    _PaletteStop(40, Color(0xFFF0FFF0)),
  ],
  'chlorophyll': [
    _PaletteStop(0, Color(0xFF0D1B2A)),
    _PaletteStop(0.05, Color(0xFF1B263B)),
    _PaletteStop(0.1, Color(0xFF003566)),
    _PaletteStop(0.3, Color(0xFF006D77)),
    _PaletteStop(0.5, Color(0xFF40916C)),
    _PaletteStop(1, Color(0xFF74C69D)),
    _PaletteStop(3, Color(0xFFE9C46A)),
    _PaletteStop(5, Color(0xFFF4A261)),
    _PaletteStop(10, Color(0xFFE76F51)),
    _PaletteStop(20, Color(0xFF9B2226)),
  ],
  'phytoplankton': [
    _PaletteStop(0, Color(0xFF0D1B2A)),
    _PaletteStop(0.1, Color(0xFF003566)),
    _PaletteStop(0.5, Color(0xFF006D77)),
    _PaletteStop(1, Color(0xFF40916C)),
    _PaletteStop(2, Color(0xFF74C69D)),
    _PaletteStop(3, Color(0xFFB5E48C)),
    _PaletteStop(5, Color(0xFFE9C46A)),
    _PaletteStop(10, Color(0xFFE76F51)),
  ],
  'zooplankton': [
    _PaletteStop(0, Color(0xFF10002B)),
    _PaletteStop(0.1, Color(0xFF3C096C)),
    _PaletteStop(0.3, Color(0xFF5A189A)),
    _PaletteStop(0.5, Color(0xFF7B2CBF)),
    _PaletteStop(1, Color(0xFFC77DFF)),
    _PaletteStop(2, Color(0xFFE0AAFF)),
    _PaletteStop(3, Color(0xFFFFD6FF)),
    _PaletteStop(5, Color(0xFFFFF0F5)),
  ],
};

class OceanForecastScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLon;
  final String? spotName;
  final String? prefetchedCatalogJson;
  final Uint8List? prefetchedWindBytes;
  final String? prefetchedWindTimestamp;

  const OceanForecastScreen({
    super.key,
    this.initialLat,
    this.initialLon,
    this.spotName,
    this.prefetchedCatalogJson,
    this.prefetchedWindBytes,
    this.prefetchedWindTimestamp,
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

  double? _probeValue;
  double? _probeDirection;
  Timer? _probeDismissTimer;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  @override
  void dispose() {
    _probeDismissTimer?.cancel();
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
        'ProbeChannel',
        onMessageReceived: (msg) {
          try {
            final data = jsonDecode(msg.message) as Map<String, dynamic>;
            setState(() {
              _probeValue = (data['value'] as num?)?.toDouble();
              _probeDirection = (data['direction'] as num?)?.toDouble();
            });
            _probeDismissTimer?.cancel();
            _probeDismissTimer = Timer(const Duration(seconds: 4), () {
              if (mounted) setState(() { _probeValue = null; _probeDirection = null; });
            });
          } catch (_) {}
        },
      )
      ..addJavaScriptChannel(
        'TapChannel',
        onMessageReceived: (msg) {
          setState(() { _probeValue = null; _probeDirection = null; });
          _probeDismissTimer?.cancel();
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
        onPageFinished: (_) => _onPageFinished(),
        onWebResourceError: (error) {
          debugPrint('WebView error: ${error.description}');
        },
      ))
      ..loadHtmlString(html, baseUrl: _kApiBase);

    if (_controller!.platform is WebKitWebViewController) {
      (_controller!.platform as WebKitWebViewController).setInspectable(true);
    }

    setState(() {});
  }

  Future<void> _onPageFinished() async {
    if (widget.prefetchedCatalogJson != null) {
      await _controller?.runJavaScript(
        '_injectCatalog(${widget.prefetchedCatalogJson})',
      );
    }
    if (widget.prefetchedWindBytes != null &&
        widget.prefetchedWindTimestamp != null) {
      final b64 = base64Encode(widget.prefetchedWindBytes!);
      await _controller?.runJavaScript(
        "_injectTexture('wind','${widget.prefetchedWindTimestamp}','$b64')",
      );
    }
    final configJson = jsonEncode({
      'baseUrl': _kApiBase,
      'weatherCdnUrl': _kWeatherCdnBase,
      'lat': widget.initialLat ?? 23.0,
      'lng': widget.initialLon ?? -108.0,
      'zoom': widget.initialLat != null ? 6 : 4,
    });
    await _controller?.runJavaScript('initMap($configJson)');
  }

  void _onMapReady() {
    setState(() => _mapReady = true);
  }

  void _selectLayer(String key) {
    if (key == _activeLayer) return;
    final hasData = _availableLayers.isEmpty || _availableLayers.contains(key);
    _probeDismissTimer?.cancel();
    setState(() {
      _isLoading = hasData;
      _activeLayer = key;
      _timeIndex = 0;
      _timestamps = [];
      _probeValue = null;
      _probeDirection = null;
      _errorMessage = hasData ? null : 'No data available for this layer yet';
    });
    _controller?.runJavaScript("setLayer('$key');_clearProbeMarker()");
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
      _probeDismissTimer?.cancel();
      setState(() { _probeValue = null; _probeDirection = null; });
      _controller?.runJavaScript('play();_clearProbeMarker()');
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

  static String _degreesToCardinal(double deg) {
    const dirs = ['N','NNE','NE','ENE','E','ESE','SE','SSE',
                  'S','SSW','SW','WSW','W','WNW','NW','NNW'];
    final idx = ((deg % 360 + 360) % 360 / 22.5 + 0.5).floor() % 16;
    return dirs[idx];
  }

  String _formatProbeValue() {
    if (_probeValue == null) return '';
    final unit = _kLayers[_activeLayer]?.unit ?? '';
    final valStr = _probeValue!.abs() < 10
        ? _probeValue!.toStringAsFixed(1)
        : _probeValue!.toStringAsFixed(0);
    final isVector = _activeLayer == 'wind' || _activeLayer == 'currents';
    if (isVector && _probeDirection != null) {
      return '$valStr $unit ${_degreesToCardinal(_probeDirection!)}';
    }
    return '$valStr $unit';
  }

  Widget _buildProbeChip() {
    final text = _formatProbeValue();
    return Container(
      key: ValueKey('probe_$text'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (_kLayers[_activeLayer]?.color ?? Colors.cyan).withOpacity(0.5),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  String _formatTickValue(double val) {
    if (val.abs() < 1 && val != 0) return val.toStringAsFixed(1);
    if (val == val.roundToDouble()) return val.toInt().toString();
    return val.toStringAsFixed(1);
  }

  Widget _buildLegendBar() {
    final palette = _kLayerPalettes[_activeLayer];
    if (palette == null || palette.isEmpty) return const SizedBox.shrink();
    final unit = _kLayers[_activeLayer]?.unit ?? '';

    final colors = palette.map((s) => s.color).toList();
    final minVal = palette.first.value;
    final maxVal = palette.last.value;
    final range = maxVal - minVal;

    final stops = range > 0
        ? palette.map((s) => (s.value - minVal) / range).toList()
        : null;

    const tickCount = 5;
    final tickLabels = List.generate(tickCount, (i) {
      final val = minVal + range * i / (tickCount - 1);
      return _formatTickValue(val);
    });

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 10,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors, stops: stops),
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (int i = 0; i < tickLabels.length; i++)
              Text(
                i == tickLabels.length - 1
                    ? '${tickLabels[i]} $unit'
                    : tickLabels[i],
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ],
    );
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

          // Probe value chip
          Positioned(
            top: MediaQuery.of(context).padding.top + 46,
            left: 0, right: 0,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _probeValue != null
                    ? _buildProbeChip()
                    : const SizedBox.shrink(),
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
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: KeyedSubtree(
                      key: ValueKey(_activeLayer),
                      child: _buildLegendBar(),
                    ),
                  ),
                  const SizedBox(height: 8),

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
