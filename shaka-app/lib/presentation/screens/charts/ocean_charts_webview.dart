import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../widgets/dynamic_ocean_legend.dart';

/// Saved ocean chart snapshot
class SavedSnapshot {
  final String id;
  final String name;
  final DateTime savedAt;
  final DateTime dataDate;
  final String imagePath;
  final double centerLat;
  final double centerLon;
  final double zoom;
  final List<String> layers;

  SavedSnapshot({
    required this.id,
    required this.name,
    required this.savedAt,
    required this.dataDate,
    required this.imagePath,
    required this.centerLat,
    required this.centerLon,
    required this.zoom,
    required this.layers,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'savedAt': savedAt.toIso8601String(),
    'dataDate': dataDate.toIso8601String(),
    'imagePath': imagePath,
    'centerLat': centerLat,
    'centerLon': centerLon,
    'zoom': zoom,
    'layers': layers,
  };

  factory SavedSnapshot.fromJson(Map<String, dynamic> json) => SavedSnapshot(
    id: json['id'],
    name: json['name'],
    savedAt: DateTime.parse(json['savedAt']),
    dataDate: DateTime.parse(json['dataDate']),
    imagePath: json['imagePath'],
    centerLat: json['centerLat'],
    centerLon: json['centerLon'],
    zoom: json['zoom'],
    layers: List<String>.from(json['layers']),
  );

  String get formattedDate {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dataDate.month - 1]} ${dataDate.day}, ${dataDate.year}';
  }
}

/// Ocean Charts screen using Copernicus WebView
/// Provides high-quality rendering online with snapshot saving for offline use
class OceanChartsWebView extends StatefulWidget {
  final double? initialLat;
  final double? initialLon;
  final String? spotName;
  
  const OceanChartsWebView({
    super.key,
    this.initialLat,
    this.initialLon,
    this.spotName,
  });

  @override
  State<OceanChartsWebView> createState() => _OceanChartsWebViewState();
}

class _OceanChartsWebViewState extends State<OceanChartsWebView> {
  WebViewController? _controller;
  final GlobalKey _webViewKey = GlobalKey();
  bool _isLoading = true;
  bool _isOnline = true;
  bool _isSaving = false;
  List<SavedSnapshot> _savedSnapshots = [];
  
  // Layer opacity (for WebView layers)
  double _opacity = 1.0;
  
  // View settings (will be initialized from widget params or defaults)
  late double _centerLat;
  late double _centerLon;
  late double _zoom;
  DateTime _dataDate = DateTime.now().subtract(const Duration(hours: 1));
  
  // Selected date for the date picker (date only, no time)
  late DateTime _selectedDate;
  // Selected hour (0-23)
  int _selectedHour = DateTime.now().hour;
  
  // Single active layer - defaults to currents
  // Only ONE layer at a time for reliability - no complex multi-layer encoding
  String? _activeLayerId = 'cur';
  
  // Legend data extracted from Copernicus via JavaScript
  String? _legendGradientCss;
  List<String> _legendTicks = [];
  
  // Layer metadata extracted from Copernicus
  String? _layerDate;
  String? _layerTime;
  String? _layerSource;
  
  /// Format the layer date/time from Copernicus (UTC) to user's local time
  /// Returns empty string if data is invalid (e.g., "fix 00:00" for future dates)
  String _formatLayerDateTime() {
    if (_layerDate == null || _layerDate!.isEmpty) return '';
    
    // Check for invalid time data (e.g., "fix 00:00" appears for future dates with no data)
    if (_layerTime != null && _layerTime!.toLowerCase().contains('fix')) return '';
    
    try {
      // Parse DD/MM/YYYY format
      final parts = _layerDate!.split('/');
      if (parts.length != 3) return '';
      
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);
      
      // Parse time HH:MM (Copernicus times are UTC)
      int hour = 0;
      int minute = 0;
      if (_layerTime != null && _layerTime!.isNotEmpty) {
        final timeParts = _layerTime!.split(':');
        if (timeParts.length >= 2) {
          hour = int.parse(timeParts[0]);
          minute = int.parse(timeParts[1]);
        }
      }
      
      // Create UTC datetime and convert to local
      final utcDateTime = DateTime.utc(year, month, day, hour, minute);
      final localDateTime = utcDateTime.toLocal();
      
      // Format as "Jan 28, 2026 8:00 PM"
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final monthName = months[localDateTime.month - 1];
      
      // Format hour for 12-hour clock
      final hour12 = localDateTime.hour == 0 ? 12 : 
                     (localDateTime.hour > 12 ? localDateTime.hour - 12 : localDateTime.hour);
      final amPm = localDateTime.hour >= 12 ? 'PM' : 'AM';
      final minuteStr = localDateTime.minute.toString().padLeft(2, '0');
      
      // Get timezone abbreviation
      final tzName = localDateTime.timeZoneName;
      
      return '$monthName ${localDateTime.day}, ${localDateTime.year} $hour12:$minuteStr $amPm $tzName';
    } catch (e) {
      // If parsing fails, return empty (don't show invalid data)
      return '';
    }
  }
  
  /// Check if we have valid layer data (not a future date with no data)
  bool get _hasValidLayerData {
    // Check if the time contains "fix" which indicates no data
    if (_layerTime != null && _layerTime!.toLowerCase().contains('fix')) return false;
    // Check if we have a valid formatted date
    return _formatLayerDateTime().isNotEmpty;
  }
  
  // Layer info with Copernicus product/dataset/variable paths
  // These are used to construct the layers URL parameter
  // timeInterval: hours between available timestamps (all are hourly now)
  // shortName: compact name for UI buttons
  // Order: Currents first (default), then others
  static const Map<String, Map<String, dynamic>> _layerInfo = {
    'cur': {
      'name': 'Currents',
      'shortName': 'Currents',
      'icon': Icons.sync_alt,
      'color': Color(0xFF00BCD4),
      'desc': 'Current speed/direction',
      'product': 'GLOBAL_ANALYSISFORECAST_PHY_001_024',
      'dataset': 'cmems_mod_glo_phy-cur_anfc_0.083deg_PT6H-i',
      'variable': 'sea_water_velocity',
      'colormap': 'speed',
      'vectorStyle': 'solidAndVector',
      'timeInterval': 1,
    },
    'sst': {
      'name': 'Sea Surface Temp',
      'shortName': 'Sea Temp',
      'icon': Icons.thermostat,
      'color': Color(0xFFFF6B35),
      'desc': 'Water temperature',
      'product': 'SST_GLO_SST_L4_NRT_OBSERVATIONS_010_001',
      'dataset': 'cmems_obs-sst_glo_phy-sst_nrt_diurnal-oi-0.25deg_P1D-m',
      'variable': 'analysed_sst',
      'colormap': 'thermal',
      'timeInterval': 1,
    },
    'waves': {
      'name': 'Swell Wave Height',
      'shortName': 'Waves',
      'icon': Icons.waves,
      'color': Color(0xFF3F51B5),
      'desc': 'Significant wave height',
      'product': 'GLOBAL_ANALYSISFORECAST_WAV_001_027',
      'dataset': 'cmems_mod_glo_wav_anfc_0.083deg_PT3H-i',
      'variable': 'VHM0',
      'colormap': 'amp',
      'timeInterval': 1,
    },
    'sal': {
      'name': 'Salinity',
      'shortName': 'Salinity',
      'icon': Icons.water_drop,
      'color': Color(0xFF009688),
      'desc': 'Sea water salinity',
      'product': 'GLOBAL_ANALYSISFORECAST_PHY_001_024',
      'dataset': 'cmems_mod_glo_phy-so_anfc_0.083deg_P1D-m',
      'variable': 'so',
      'colormap': 'dense',
      'timeInterval': 1,
    },
    'wind': {
      'name': 'Wind',
      'shortName': 'Wind',
      'icon': Icons.air,
      'color': Color(0xFF607D8B),
      'desc': 'Surface wind speed',
      'product': 'WIND_GLO_PHY_L4_NRT_012_004',
      'dataset': 'cmems_obs-wind_glo_phy_nrt_l4_0.125deg_PT1H',
      'variable': 'wind',
      'colormap': 'speed',
      'vectorStyle': 'solidAndVector',
      'timeInterval': 1,
    },
    'chl': {
      'name': 'Chlorophyll',
      'shortName': 'Chlorophyll',
      'icon': Icons.grass,
      'color': Color(0xFF4CAF50),
      'desc': 'Phytoplankton / bait',
      'product': 'OCEANCOLOUR_GLO_BGC_L3_NRT_009_101',
      'dataset': 'cmems_obs-oc_glo_bgc-plankton_nrt_l3-multi-4km_P1D',
      'variable': 'CHL',
      'colormap': 'algae',
      'timeInterval': 1,
    },
    'phyto': {
      'name': 'Phytoplankton',
      'shortName': 'Phyto',
      'icon': Icons.eco,
      'color': Color(0xFF8BC34A),
      'desc': 'Phytoplankton concentration',
      'product': 'GLOBAL_ANALYSISFORECAST_BGC_001_028',
      'dataset': 'cmems_mod_glo_bgc-bio_anfc_0.25deg_P1D-m',
      'variable': 'phyc',
      'colormap': 'algae',
      'timeInterval': 24, // Daily
    },
    'zoo': {
      'name': 'Zooplankton',
      'shortName': 'Zoo',
      'icon': Icons.pest_control,
      'color': Color(0xFFCDDC39),
      'desc': 'Zooplankton concentration',
      'product': 'GLOBAL_ANALYSISFORECAST_BGC_001_028',
      'dataset': 'cmems_mod_glo_bgc-bio_anfc_0.25deg_P1D-m',
      'variable': 'zooc',
      'colormap': 'tempo',
      'timeInterval': 24, // Daily
    },
  };

  @override
  void initState() {
    super.initState();
    
    // Initialize center from spot coordinates or default to Hawaii
    _centerLat = widget.initialLat ?? 21.3;
    _centerLon = widget.initialLon ?? -157.8;
    _zoom = (widget.initialLat != null && widget.initialLon != null) ? 8.0 : 6.0;
    
    // Initialize selected date to today
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _selectedHour = now.hour; // Default to current hour
    _dataDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _selectedHour);
    _checkConnectivity();
    _loadSavedSnapshots();
  }
  
  // Check if opened from a spot
  bool get _hasSpotContext => widget.spotName != null;

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    setState(() {
      _isOnline = result != ConnectivityResult.none;
    });
    
    if (_isOnline) {
      _initWebView();
    }
    
    // Listen for connectivity changes
    Connectivity().onConnectivityChanged.listen((result) {
      final wasOnline = _isOnline;
      setState(() {
        _isOnline = result != ConnectivityResult.none;
      });
      
      if (_isOnline && !wasOnline) {
        _initWebView();
      }
    });
  }

  void _initWebView() {
    final url = _buildCopernicusUrl();
    
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            setState(() => _isLoading = true);
            // Inject CSS EARLY to hide UI elements before they render
            _injectEarlyHidingCss();
          },
          onPageFinished: (_) {
            // Don't set _isLoading = false here - wait for customizations to complete
            // This prevents the flickering of controls before they're hidden
            _injectCustomizations();
          },
          onWebResourceError: (error) {
            debugPrint('WebView error: ${error.description}');
          },
        ),
      )
      ..addJavaScriptChannel(
        'LegendChannel',
        onMessageReceived: (message) {
          try {
            final data = jsonDecode(message.message);
            setState(() {
              _legendGradientCss = data['gradient'] as String?;
              _legendTicks = List<String>.from(data['ticks'] ?? []);
              _layerDate = data['date'] as String?;
              _layerTime = data['time'] as String?;
              _layerSource = data['source'] as String?;
            });
          } catch (e) {
            debugPrint('Error parsing legend data: $e');
          }
        },
      )
      ..addJavaScriptChannel(
        'NetworkChannel',
        onMessageReceived: (message) {
          try {
            final data = jsonDecode(message.message);
            
            // Special handling for timestamp discovery
            if (data['type'] == 'TIMESTAMP_DISCOVERY') {
              debugPrint('');
              debugPrint('');
              debugPrint('########## TIMESTAMP DISCOVERY ##########');
              final found = data['found'] as List<dynamic>?;
              if (found != null) {
                for (var item in found) {
                  debugPrint('---');
                  debugPrint('Source: ${item['source']}');
                  item.forEach((key, value) {
                    if (key != 'source') {
                      debugPrint('  $key: $value');
                    }
                  });
                }
              }
              debugPrint('#########################################');
              debugPrint('');
              debugPrint('');
              return;
            }
            
            // Regular network call logging
            debugPrint('');
            debugPrint('========== NETWORK CALL ==========');
            debugPrint('Type: ${data['type']}');
            debugPrint('Method: ${data['method']}');
            debugPrint('URL: ${data['url']}');
            debugPrint('Status: ${data['status']}');
            if (data['requestBody'] != null) {
              debugPrint('Request Body: ${data['requestBody']}');
            }
            if (data['responseBody'] != null) {
              debugPrint('Response Body: ${data['responseBody']}');
            }
            debugPrint('===================================');
            debugPrint('');
          } catch (e) {
            debugPrint('Raw: ${message.message}');
          }
        },
      )
      ..addJavaScriptChannel(
        'CustomizationsChannel',
        onMessageReceived: (message) {
          // When customizations are complete, hide the loading overlay
          if (message.message == 'done') {
            setState(() => _isLoading = false);
          }
        },
      )
      ..loadRequest(Uri.parse(url));
    
    setState(() {});
  }

  /// Inject CSS early (on page start) to hide UI elements before they render
  /// This prevents flickering of controls
  Future<void> _injectEarlyHidingCss() async {
    if (_controller == null) return;
    
    const cssCode = '''
      (function() {
        // Create style element immediately to hide UI before render
        var style = document.createElement('style');
        style.id = 'early-hide-css';
        style.textContent = `
          /* Hide specific UI elements - be careful not to hide map container */
          [class*="toolbar"]:not([class*="map"]),
          [class*="Toolbar"]:not([class*="map"]),
          [class*="time-input"], [class*="TimeInput"],
          [class*="wk-time-elevation"],
          [role="toolbar"], [role="menu"], [role="dialog"],
          nav, aside, header, footer {
            opacity: 0 !important;
            visibility: hidden !important;
            pointer-events: none !important;
          }
          /* Black background to prevent white flash */
          html, body {
            background: #000 !important;
          }
          /* Disable tap highlight on touch */
          *, *::before, *::after {
            -webkit-tap-highlight-color: transparent !important;
            -webkit-touch-callout: none !important;
          }
        `;
        // Insert at start of head or body
        var target = document.head || document.documentElement;
        if (target) {
          target.insertBefore(style, target.firstChild);
        }
      })();
    ''';
    
    await _controller!.runJavaScript(cssCode);
  }

  /// Inject JavaScript to hide Copernicus UI except the date/time slider
  Future<void> _injectCustomizations() async {
    if (_controller == null) return;
    
    // JavaScript that hides UI, scales timeline, and intercepts network calls
    const jsCode = '''
      // ============ NETWORK INTERCEPTION ============
      // Intercept XMLHttpRequest to capture API calls
      (function() {
        if (window._networkInterceptorInstalled) return;
        window._networkInterceptorInstalled = true;
        
        var originalXhrOpen = XMLHttpRequest.prototype.open;
        var originalXhrSend = XMLHttpRequest.prototype.send;
        
        XMLHttpRequest.prototype.open = function(method, url) {
          this._interceptUrl = url;
          this._interceptMethod = method;
          return originalXhrOpen.apply(this, arguments);
        };
        
        XMLHttpRequest.prototype.send = function(body) {
          var xhr = this;
          var url = this._interceptUrl;
          var method = this._interceptMethod;
          
          this.addEventListener('load', function() {
            try {
              NetworkChannel.postMessage(JSON.stringify({
                type: 'xhr',
                method: method,
                url: url,
                status: xhr.status,
                requestBody: body ? String(body).substring(0, 1000) : null,
                responseBody: xhr.responseText ? xhr.responseText.substring(0, 3000) : null
              }));
            } catch(e) {}
          });
          
          return originalXhrSend.apply(this, arguments);
        };
        
        // Intercept fetch API
        var originalFetch = window.fetch;
        window.fetch = function(input, init) {
          var url = typeof input === 'string' ? input : input.url;
          var method = (init && init.method) || 'GET';
          var body = init && init.body;
          
          return originalFetch.apply(this, arguments).then(function(response) {
            var cloned = response.clone();
            cloned.text().then(function(responseBody) {
              try {
                NetworkChannel.postMessage(JSON.stringify({
                  type: 'fetch',
                  method: method,
                  url: url,
                  status: response.status,
                  requestBody: body ? String(body).substring(0, 1000) : null,
                  responseBody: responseBody ? responseBody.substring(0, 3000) : null
                }));
              } catch(e) {}
            });
            return response;
          });
        };
      })();
      // ============ END NETWORK INTERCEPTION ============
      
      (function() {
        var mapCanvas = null;
        var timelineElement = null;
        var timelineScaled = false;
        
        // Fix white lines - set black background on html/body
        document.documentElement.style.cssText = 'background: #000 !important;';
        document.body.style.cssText = 'background: #000 !important;';
        
        function findMapCanvas() {
          var canvases = document.querySelectorAll('canvas');
          for (var i = 0; i < canvases.length; i++) {
            var c = canvases[i];
            if (c.offsetWidth > window.innerWidth * 0.5 && c.offsetHeight > window.innerHeight * 0.5) {
              mapCanvas = c;
              return c;
            }
          }
          return null;
        }
        
        function findTimeline() {
          var selectors = [
            '[class*="timeline"]', '[class*="Timeline"]',
            '[class*="time-slider"]', '[class*="TimeSlider"]',
            '[class*="player"]', '[class*="Player"]',
            '[aria-label*="time"]', '[aria-label*="Time"]'
          ];
          
          for (var i = 0; i < selectors.length; i++) {
            var els = document.querySelectorAll(selectors[i]);
            for (var j = 0; j < els.length; j++) {
              var el = els[j];
              var rect = el.getBoundingClientRect();
              if (rect.width > window.innerWidth * 0.3 && rect.height > 30 && rect.height < 150) {
                timelineElement = el;
                return el;
              }
            }
          }
          
          document.querySelectorAll('*').forEach(function(el) {
            var rect = el.getBoundingClientRect();
            if (rect.bottom > window.innerHeight - 120 && 
                rect.width > window.innerWidth * 0.5 &&
                rect.height > 40 && rect.height < 120) {
              var text = el.innerText || '';
              if (text.match(/\\d{4}/) || text.match(/\\d{2}:\\d{2}/)) {
                timelineElement = el;
              }
            }
          });
          return timelineElement;
        }
        
        function scaleTimeline() {
          // Timeline scaling removed - we now hide native timeline and use Flutter picker
        }
        
        function isPartOfMap(el) {
          if (!el || !mapCanvas) return false;
          if (el === mapCanvas) return true;
          if (el.contains(mapCanvas)) return true;
          var parent = mapCanvas.parentElement;
          while (parent) {
            if (parent === el) return true;
            parent = parent.parentElement;
          }
          return false;
        }
        
        function isPartOfTimeline(el) {
          if (!el || !timelineElement) return false;
          if (el === timelineElement) return true;
          if (el.contains(timelineElement)) return true;
          if (timelineElement.contains(el)) return true;
          return false;
        }
        
        function hideUI() {
          findMapCanvas();
          
          // Hide native Copernicus timeline completely - we use Flutter picker instead
          var timelineContainer = document.querySelector('[class*="time-input-and-controls"]');
          if (timelineContainer) {
            timelineContainer.style.cssText = 'display: none !important;';
          }
          // Also hide by other selectors
          document.querySelectorAll('[class*="time-input"], [class*="TimeInput"], .wk-time-elevation').forEach(function(el) {
            el.style.cssText = 'display: none !important;';
          });
          
          // Hide elements in corners, toolbars at top, sidebars
          document.querySelectorAll('*').forEach(function(el) {
            if (el === mapCanvas || el.tagName === 'CANVAS') return;
            if (el.contains(mapCanvas)) return;
            if (isPartOfTimeline(el)) return;
            
            var style = window.getComputedStyle(el);
            var pos = style.position;
            
            if (pos === 'fixed' || pos === 'absolute') {
              var rect = el.getBoundingClientRect();
              
              if (rect.width > window.innerWidth * 0.8 && rect.height > window.innerHeight * 0.8) return;
              
              var inCorner = (rect.left < 100 || rect.right > window.innerWidth - 100) &&
                            (rect.top < 100 || rect.bottom > window.innerHeight - 100);
              
              var isTopToolbar = (rect.width > window.innerWidth * 0.5) && 
                                (rect.height < 100) && (rect.top < 80);
              
              var isSidebar = (rect.height > window.innerHeight * 0.5) && (rect.width < 400);
              
              if (inCorner || isTopToolbar || isSidebar) {
                el.style.cssText = 'display: none !important;';
              }
            }
          });
          
          // Hide buttons/controls except timeline
          document.querySelectorAll('button, [role="button"], [role="toolbar"], [role="navigation"], [role="menu"], [role="dialog"], nav, aside, header, footer').forEach(function(el) {
            if (!isPartOfMap(el) && !el.contains(mapCanvas) && !isPartOfTimeline(el)) {
              el.style.cssText = 'display: none !important;';
            }
          });
          
          // Hide by aria-labels
          document.querySelectorAll('[aria-label*="zoom"], [aria-label*="compass"], [aria-label*="north"], [aria-label*="south"], [aria-label*="pole"], [aria-label*="Pole"], [aria-label*="search"], [aria-label*="menu"], [aria-label*="layer"], [aria-label*="tool"], [aria-label*="draw"], [aria-label*="settings"]').forEach(function(el) {
            if (!isPartOfTimeline(el)) {
              el.style.cssText = 'display: none !important;';
            }
          });
          
          // Aggressively hide North/South Pole markers at top-middle and bottom-middle
          document.querySelectorAll('div, span, svg, img').forEach(function(el) {
            if (isPartOfTimeline(el)) return;
            
            var text = (el.innerText || el.textContent || '').trim();
            var rect = el.getBoundingClientRect();
            var centerX = window.innerWidth / 2;
            var elCenterX = rect.left + rect.width / 2;
            var isHorizontallyCenter = Math.abs(elCenterX - centerX) < 150;
            var isAtTop = rect.top < 100;
            var isAtBottom = rect.bottom > window.innerHeight - 150;
            
            // Hide small elements with just "N" or "S" text at top or bottom center
            if ((text === 'N' || text === 'S' || text === 'n' || text === 's') && 
                rect.width < 80 && rect.height < 80) {
              if (isHorizontallyCenter && (isAtTop || isAtBottom)) {
                el.style.cssText = 'display: none !important; visibility: hidden !important;';
                // Also hide parent containers
                var parent = el.parentElement;
                for (var i = 0; i < 3 && parent; i++) {
                  if (parent.offsetWidth < 100 && parent.offsetHeight < 100) {
                    parent.style.cssText = 'display: none !important;';
                  }
                  parent = parent.parentElement;
                }
              }
            }
            
            // Hide small circular/square elements at top-center or bottom-center (pole icons)
            if (rect.width < 60 && rect.height < 60 && rect.width > 10) {
              if (isHorizontallyCenter && (isAtTop || isAtBottom)) {
                el.style.cssText = 'display: none !important;';
              }
            }
          });
          
          // Close dialogs, accept cookies
          document.querySelectorAll('[aria-label*="close"], [aria-label*="Close"]').forEach(function(btn) {
            if (!isPartOfTimeline(btn)) try { btn.click(); } catch(e) {}
          });
          document.querySelectorAll('button').forEach(function(btn) {
            var text = (btn.innerText || '').toLowerCase();
            if ((text.includes('accept') || text.includes('agree')) && !isPartOfTimeline(btn)) {
              try { btn.click(); } catch(e) {}
            }
          });
        }
        
        // Extract legend data (gradient CSS and tick values) and send to Flutter
        function extractLegendData() {
          // Find gradient div - look for the div with inline linear-gradient style
          var gradientEl = document.querySelector('.gradient-wrapper .gradient') ||
                           document.querySelector('[class*="gradient"]:not(svg):not([class*="wrapper"])');
          
          var gradient = '';
          if (gradientEl && gradientEl.style && gradientEl.style.background) {
            gradient = gradientEl.style.background;
          }
          
          // Find tick values from the SVG
          var ticks = [];
          document.querySelectorAll('.wk-layer-ticks .tick-text').forEach(function(t) {
            var text = (t.textContent || '').trim();
            if (text && text !== '') ticks.push(text);
          });
          
          // Find date/time from subtitle
          var date = '';
          var time = '';
          var dateEl = document.querySelector('[class*="subtitle-item"][class*="date"]');
          if (dateEl) {
            var timeEl = dateEl.querySelector('[class*="time"]');
            time = timeEl ? (timeEl.textContent || '').trim() : '';
            // Get full text, remove time portion to get just the date
            var fullText = (dateEl.textContent || '').trim();
            date = fullText.replace(time, '').trim();
          }
          
          // Find source interval (e.g., "Global hourly")
          var source = '';
          var sourceEl = document.querySelector('[class*="subtitle-item"][class*="disambiguate"]');
          if (sourceEl) {
            source = (sourceEl.textContent || '').trim();
          }
          
          // Send to Flutter if we have any data
          if (gradient || ticks.length > 0 || date || source) {
            try {
              LegendChannel.postMessage(JSON.stringify({
                gradient: gradient,
                ticks: ticks,
                date: date,
                time: time,
                source: source
              }));
            } catch(e) {
              console.log('LegendChannel not available:', e);
            }
          }
        }
        
        hideUI();
        // Signal to Flutter that initial customizations are complete
        // Use a small delay to ensure hideUI has finished executing
        setTimeout(function() {
          if (window.CustomizationsChannel) {
            CustomizationsChannel.postMessage('done');
          }
        }, 100);
        setTimeout(hideUI, 500);
        setTimeout(hideUI, 1000);
        setTimeout(hideUI, 2000);
        setTimeout(hideUI, 3000);
        setTimeout(hideUI, 5000);
        setInterval(hideUI, 2000);
        
        // Extract legend data after page loads
        setTimeout(extractLegendData, 2000);
        setTimeout(extractLegendData, 4000);
        setTimeout(extractLegendData, 6000);
        
        var observer = new MutationObserver(function() { hideUI(); });
        observer.observe(document.body, { childList: true, subtree: true });
        
        // Re-extract legend when DOM changes (layer switch)
        var legendObserver = new MutationObserver(function() {
          setTimeout(extractLegendData, 500);
        });
        legendObserver.observe(document.body, { childList: true, subtree: true });
        
        // ============ TIMESTAMP DISCOVERY ============
        // Search for where Copernicus stores available timestamps
        function discoverTimestamps() {
          var found = [];
          
          // 1. Search window/global variables for arrays with date-like strings or large numbers (timestamps)
          for (var key in window) {
            try {
              var val = window[key];
              if (Array.isArray(val) && val.length > 0) {
                var sample = String(val[0]);
                // Check for ISO dates or large numbers (epoch ms)
                if (sample.match(/^\\d{4}-\\d{2}-\\d{2}/) || sample.match(/T\\d{2}:\\d{2}/) || 
                    (typeof val[0] === 'number' && val[0] > 1600000000000 && val[0] < 2000000000000)) {
                  found.push({source: 'window.' + key, count: val.length, sample: val.slice(0,5)});
                }
              }
            } catch(e) {}
          }
          
          // 2. Deep search for React state containing time data
          var reactRoot = document.getElementById('root') || document.getElementById('__next');
          if (reactRoot) {
            found.push({source: 'React root element', id: reactRoot.id, hasReactRoot: !!reactRoot._reactRootContainer});
            
            // Try to find React fiber
            var keys = Object.keys(reactRoot);
            var reactKey = keys.find(function(k) { return k.startsWith('__reactFiber') || k.startsWith('__reactInternalInstance'); });
            if (reactKey) {
              found.push({source: 'React fiber key', key: reactKey});
              
              // Try to traverse fiber to find state
              try {
                var fiber = reactRoot[reactKey];
                var visited = new Set();
                var queue = [fiber];
                var stateFound = [];
                var maxDepth = 50;
                var depth = 0;
                
                while (queue.length > 0 && depth < maxDepth) {
                  var current = queue.shift();
                  depth++;
                  if (!current || visited.has(current)) continue;
                  visited.add(current);
                  
                  // Check memoizedState for time-related data
                  if (current.memoizedState) {
                    var stateStr = JSON.stringify(current.memoizedState);
                    if (stateStr && (stateStr.includes('time') || stateStr.includes('Time') || 
                        stateStr.includes('1769') || stateStr.includes('availab'))) {
                      stateFound.push({type: 'memoizedState', preview: stateStr.substring(0,300)});
                    }
                  }
                  
                  // Check pendingProps for layer config
                  if (current.pendingProps) {
                    var propsStr = JSON.stringify(current.pendingProps);
                    if (propsStr && propsStr.length < 5000 && (propsStr.includes('layer') || propsStr.includes('Layer'))) {
                      stateFound.push({type: 'pendingProps', preview: propsStr.substring(0,500)});
                    }
                  }
                  
                  // Traverse children
                  if (current.child) queue.push(current.child);
                  if (current.sibling) queue.push(current.sibling);
                  if (current.return) queue.push(current.return);
                }
                
                if (stateFound.length > 0) {
                  found.push({source: 'React state search', statesFound: stateFound.slice(0,5)});
                }
              } catch(e) {
                found.push({source: 'React fiber error', error: e.message});
              }
            }
          }
          
          // 3. Look for data attributes on timeline elements
          var timeline = document.querySelector('[class*="time-input"], [class*="timeline"], [class*="TimeInput"]');
          if (timeline) {
            var attrs = {};
            for (var i = 0; i < timeline.attributes.length; i++) {
              var attr = timeline.attributes[i];
              if (attr.name.startsWith('data-')) {
                attrs[attr.name] = attr.value.substring(0, 100);
              }
            }
            found.push({source: 'Timeline element found', className: timeline.className, attrCount: Object.keys(attrs).length, attrs: attrs});
          }
          
          // 4. Search for __NEXT_DATA__ or similar hydration data
          var nextData = document.getElementById('__NEXT_DATA__');
          if (nextData) {
            found.push({source: '__NEXT_DATA__', preview: nextData.textContent.substring(0,500)});
          }
          
          // 5. Look for any script tags with JSON data
          var jsonScripts = document.querySelectorAll('script[type="application/json"]');
          jsonScripts.forEach(function(s, i) {
            found.push({source: 'JSON script #' + i, preview: s.textContent.substring(0,300)});
          });
          
          // 6. Search for common global variable names
          var commonNames = ['__COPERNICUS__', '__VIEWER__', '__LAYER_DATA__', 'layerConfig', 'timeConfig', 
                            '__PRELOADED_STATE__', '__INITIAL_STATE__', 'store', '__store', 'appState'];
          commonNames.forEach(function(name) {
            if (window[name]) {
              found.push({source: 'window.' + name, type: typeof window[name], preview: JSON.stringify(window[name]).substring(0,500)});
            }
          });
          
          // 7. Look for layer domains in the timeline SVG (these show time ranges)
          var layerDomains = document.querySelectorAll('.wk-layer-domain, .wk-layer-domains line');
          if (layerDomains.length > 0) {
            var domainInfo = [];
            layerDomains.forEach(function(d) {
              domainInfo.push({
                x1: d.getAttribute('x1'),
                x2: d.getAttribute('x2'),
                title: d.querySelector('title') ? d.querySelector('title').textContent : null
              });
            });
            found.push({source: 'Layer domains in SVG', count: layerDomains.length, domains: domainInfo});
          }
          
          // 8. Look for tick marks on the timeline (these map to dates)
          var ticks = document.querySelectorAll('.wk-ticks .tick, .tick');
          if (ticks.length > 0) {
            var tickInfo = [];
            ticks.forEach(function(t, i) {
              if (i < 10) { // First 10 ticks
                var transform = t.getAttribute('transform');
                var text = t.querySelector('text');
                tickInfo.push({
                  transform: transform,
                  label: text ? text.textContent : null
                });
              }
            });
            found.push({source: 'Timeline ticks', count: ticks.length, firstTen: tickInfo});
          }
          
          // 9. Directly access timeline component's React fiber
          var timelineSvg = document.querySelector('svg.wk-time-elevation, [class*="time-input"] svg');
          if (timelineSvg) {
            var svgKeys = Object.keys(timelineSvg);
            var fiberKey = svgKeys.find(function(k) { return k.startsWith('__reactFiber'); });
            if (fiberKey) {
              try {
                var fiber = timelineSvg[fiberKey];
                // Walk up to find the container component with props
                var current = fiber;
                for (var i = 0; i < 20 && current; i++) {
                  if (current.memoizedProps) {
                    var props = current.memoizedProps;
                    // Look for arrays of timestamps or scale config
                    var propKeys = Object.keys(props);
                    propKeys.forEach(function(pk) {
                      var pval = props[pk];
                      if (Array.isArray(pval) && pval.length > 0) {
                        var sample = pval[0];
                        // Check if it looks like timestamps (epoch ms)
                        if (typeof sample === 'number' && sample > 1500000000000) {
                          found.push({source: 'Timeline props.' + pk, count: pval.length, firstFive: pval.slice(0,5), lastFive: pval.slice(-5)});
                        }
                      }
                      // Look for scale/domain objects
                      if (pval && typeof pval === 'object' && (pval.domain || pval.range)) {
                        found.push({source: 'Timeline props.' + pk + ' (scale)', domain: pval.domain ? pval.domain() : null, range: pval.range ? pval.range() : null});
                      }
                    });
                  }
                  current = current.return;
                }
              } catch(e) {
                found.push({source: 'Timeline fiber error', error: e.message});
              }
            }
          }
          
          // 10. Look for D3 scales attached to timeline elements
          var axisGroup = document.querySelector('.wk-axis-x, [class*="axis-x"]');
          if (axisGroup) {
            var axisKeys = Object.keys(axisGroup);
            found.push({source: 'Axis element keys', keys: axisKeys.slice(0,20)});
            // D3 often attaches __data__ to elements
            if (axisGroup.__data__) {
              found.push({source: 'Axis __data__', data: JSON.stringify(axisGroup.__data__).substring(0,500)});
            }
            // Try to access React props for D3 scale
            var propsKey = axisKeys.find(function(k) { return k.startsWith('__reactProps'); });
            if (propsKey) {
              var props = axisGroup[propsKey];
              found.push({source: 'Axis React props keys', keys: Object.keys(props || {})});
              // Look for scale in props
              if (props) {
                for (var pk in props) {
                  var pval = props[pk];
                  if (pval && typeof pval === 'function') {
                    // D3 scales have domain() and range() methods
                    if (pval.domain && pval.range) {
                      try {
                        var domain = pval.domain();
                        var range = pval.range();
                        found.push({
                          source: 'D3 Scale found in props.' + pk,
                          domainType: typeof domain[0],
                          domain: domain.map(function(d) { return d instanceof Date ? d.toISOString() : d; }),
                          range: range
                        });
                      } catch(e) {}
                    }
                  }
                }
              }
            }
          }
          
          // 10b. Look for D3 scale in the SVG's React fiber
          var timeInputSvg = document.querySelector('svg.wk-time-elevation');
          if (timeInputSvg) {
            var svgKeys = Object.keys(timeInputSvg);
            var fiberKey = svgKeys.find(function(k) { return k.startsWith('__reactFiber'); });
            if (fiberKey) {
              var fiber = timeInputSvg[fiberKey];
              var current = fiber;
              // Walk up looking for props with scale
              for (var i = 0; i < 30 && current; i++) {
                if (current.memoizedProps) {
                  var mp = current.memoizedProps;
                  var mpKeys = Object.keys(mp);
                  mpKeys.forEach(function(mk) {
                    var mv = mp[mk];
                    if (mv && typeof mv === 'function' && mv.domain && mv.range) {
                      try {
                        var d = mv.domain();
                        var r = mv.range();
                        found.push({
                          source: 'D3 Scale in fiber props.' + mk,
                          domainType: typeof d[0],
                          domain: d.map(function(x) { return x instanceof Date ? x.toISOString() : (typeof x === 'number' && x > 1500000000000 ? new Date(x).toISOString() : x); }),
                          range: r
                        });
                      } catch(e) {}
                    }
                    // Also look for arrays that might be timestamps
                    if (Array.isArray(mv) && mv.length > 0 && typeof mv[0] === 'number' && mv[0] > 1500000000000) {
                      found.push({
                        source: 'Timestamp array in fiber props.' + mk,
                        count: mv.length,
                        first5: mv.slice(0,5).map(function(t) { return new Date(t).toISOString(); }),
                        last5: mv.slice(-5).map(function(t) { return new Date(t).toISOString(); })
                      });
                    }
                  });
                }
                current = current.return;
              }
            }
          }
          
          // 11. Search for redux/zustand stores
          if (window.__REDUX_DEVTOOLS_EXTENSION__) {
            found.push({source: 'Redux DevTools detected'});
          }
          if (window.__ZUSTAND__) {
            found.push({source: 'Zustand detected', preview: JSON.stringify(window.__ZUSTAND__).substring(0,500)});
          }
          
          // 12. Look at the thumb/slider position to understand current time
          var thumb = document.querySelector('.wk-thumb, [class*="thumb"]');
          if (thumb) {
            var transform = thumb.getAttribute('transform');
            found.push({source: 'Timeline thumb position', transform: transform});
          }
          
          // 13. Decode the layers URL parameter to see layer config
          try {
            var urlParams = new URLSearchParams(window.location.search);
            var layersParam = urlParams.get('layers');
            if (layersParam) {
              // The layers param is base64-gzip encoded JSON
              // Try to decode it (browser has atob for base64)
              try {
                // Replace URL-safe chars
                var b64 = layersParam.replace(/-/g, '+').replace(/_/g, '/').replace(/\\./g, '=');
                var decoded = atob(b64);
                // It's gzip compressed, try to find readable parts
                var readable = '';
                for (var i = 0; i < decoded.length && i < 500; i++) {
                  var c = decoded.charCodeAt(i);
                  if (c >= 32 && c < 127) readable += decoded[i];
                }
                found.push({source: 'Layers URL param (partial decode)', readable: readable.substring(0,300)});
              } catch(e) {
                found.push({source: 'Layers URL param raw', value: layersParam.substring(0,200)});
              }
            }
            
            // Check the 't' parameter (timestamp in epoch ms)
            var tParam = urlParams.get('t');
            if (tParam) {
              var timestamp = parseInt(tParam);
              found.push({source: 'URL t param (current time)', epoch: tParam, date: new Date(timestamp).toISOString()});
            }
          } catch(e) {}
          
          // 14. Look for wk (viewer kit) global objects
          for (var key in window) {
            if (key.startsWith('wk') || key.startsWith('Wk') || key.startsWith('WK')) {
              found.push({source: 'window.' + key, type: typeof window[key]});
            }
          }
          
          // 15. Check for layer store/state by searching all globals more aggressively
          for (var key in window) {
            try {
              var val = window[key];
              if (val && typeof val === 'object' && val.layers) {
                var layersStr = JSON.stringify(val.layers);
                if (layersStr.length > 10) {
                  found.push({source: 'window.' + key + '.layers', preview: layersStr.substring(0,500)});
                }
              }
              if (val && typeof val === 'object' && val.getState && typeof val.getState === 'function') {
                try {
                  var state = val.getState();
                  var stateStr = JSON.stringify(state);
                  if (stateStr.includes('time') || stateStr.includes('layer')) {
                    found.push({source: 'window.' + key + '.getState()', preview: stateStr.substring(0,500)});
                  }
                } catch(e2) {}
              }
            } catch(e) {}
          }
          
          // Send findings to Flutter
          try {
            NetworkChannel.postMessage(JSON.stringify({
              type: 'TIMESTAMP_DISCOVERY',
              found: found
            }));
          } catch(e) {
            console.log('NetworkChannel error:', e);
          }
        }
        
        // Run discovery after page loads
        setTimeout(discoverTimestamps, 5000);
        setTimeout(discoverTimestamps, 10000);
        setTimeout(discoverTimestamps, 15000);
        // ============ END TIMESTAMP DISCOVERY ============
      })();
    ''';
    
    await _controller!.runJavaScript(jsCode);
  }

  // PRE-VERIFIED layer URL parameters - each tested in browser before adding here.
  // Only ONE layer active at a time for reliability.
  // These exact strings are copied from working Copernicus URLs - DO NOT modify.
  static const Map<String, String> _verifiedLayerParams = {
    // Wind layer with arrows - verified working 2024-01-29
    'wind': 'H4sIAArZemkAA5XSXU.CMBQG4P.S6wFt9yHjDlGBBJE4EkOMOSldGUu6lXQFnIT.bjdAlJCoF7s5a3vO_7SvO6TMUuieUjouUGe3d5BaMZ6aEnVw0.cdJFkp9DBGHdQfPd12R9Add0ezaBg9PD3f97rRFG77PcCYAKbtFs9EVkCmYkikgnnCG6uFAZYvOOAm9WORwITcNTKgmLqEtPhSIgd9DPNYvNuODkqrTiCxrUqVRJxJgToLJgthC2myNH2t1qt6nsNerqTSGTuUjNA506Utb5hci8c0r2IQlwZh6HshCdvEx4F7_s1sT7cZtmlwE9SfG2Li2SGKQRrHwm42ei32zhWl31kmg9mRxbtgWS3LBl.rEwtuuz9cPBy0CsFgy2wc2Aip6vtwUGFKKSZMm5RLYeeohjtWIyUruSPUyZOeQekfQK82.ZfFy3B8BxakDj.yYPw8BUyodTgZqHnR2Kb5FwTk2oD0LAM5Po8pGVQKFN_0qoXfnod7juNei3Pd5yJkfeb_7ROZ.vqP_gIAAA--',
    // Currents layer - Sea water velocity m/s - verified working 2024-01-29 (updated colors)
    'cur': 'H4sIABDhe2kAAxWOywrCMBAA.2XPVVMVld6q_CgULdaLiCwhWWth20gSH7X0363XYWDm0oLxd7IrY6x2ELVdACwbsomGCLbpYRmnGO.j9Jwn_eZwXK.i.ITZ7oxChCjG05GqqHJYGY0FG3zcG5T1TaEYisVEU4HZKdwNKhz3rpiNHEl8S08WX8RGlb6BAL5JrekDUTgXAZT.MPKs52yKXEkmiG6SHQXgfMOUSetLxdTfevuk7voDQw8zzsQAAAA-',
    // Chlorophyll - verified working 2024-01-29
    'chl': 'H4sIAKuae2kAAzWPy26DMBRE._WuCbHNo5gdoS1Cok1Vuqmq6so15iEZjAypSqP8e0iiLGZzRqOZ_TqCmVtlU2NsNUF8PDlgRiG7eYGYuEHggBaLsnkFMWTFfpcUmLwmxWeZl8.796c0KT9wl6VICEXCoq3sVT9hbypstMGfRm7GekYx1BKJy4JKNfhGHzc9MsI8Srey1eDAfz5U6g9inzjQXapQkxVr05RSaAVxLfSkVtA17ZxZcxivg25habSxvbihWdlB2GXFv0If1Es3XH5Qj4WcBz6nPKIBCb27LdZSz_URCx.CqzxOqH.6PgP1m9AhGAEAAA--',
    // Sea Surface Temperature - verified working 2024-01-29
    'sst': 'H4sIADCbe2kAAx2OTQuCQBQA.8s7W61aEd5MKgVJSS8S8Vjc9QN2fbJ6yMT.nnUdBmaeM9DYSBMQGTGANy8WKD5JEwnw4BYnZz9G._7HRRZl1_RxCfwsxzQskDEbmbPflVrqATUJrBVh30zIu6pEtmUnV8ga09wONxqd1WXH3doaOYEFn6gT8g3egVnQ.lqo3BUrqrOSKwlexdUgLShJkdG8.._0XSVNR7C8vmFF3SG4AAAA',
    // Swell Wave Height - verified working 2024-01-29
    'waves': 'H4sIAH_be2kAAxXOywqCQBSA4Xc5a6vRosLdFF0Eu9CIEhGHwTmaMDow2sXEd8_2._b.bh2Y5kF2bYxVNfhd74CWLdlAgQ_78LTiIfIjD68iENvTZbPmIsKEx8iYi8xbTNKSyhpLozDXBt.yhbLKUmRjtpwqyvEcTfejAj3mzVx3Eu8PDEXiggPfoFL0AX.OHCj_N9SzIWuTi1RqAj_TuiYH6qbVdJa2KVJNA7GxT_rvP2FFTs65AAAA',
    // Salinity - verified working 2024-01-29 (updated colors)
    'sal': 'H4sIAFfhe2kAA72PzWrCQBSF3_Wup3Vii0p2qbRNINTQuJFSLsPMNQ7cZMrM9CeVvLsRFwruXZ6PA_d8H3twcUd_6Zw3AdL9IIBVT74wkMJruXrKSszesnJTF.XL6v15mdVrrPINSpmgnD5OdEttwNYZbNjh165H1W01ynu5eDDUYLVO8rsWp2NXziaBFP6qSB5.iJ22sQcB.0Vn6A.SZC4F2OMw8mzk7JpaKyZIt4oDCQixZ6qUj1YzjW_j.x6pDbk1hrpTHsStldylwuKsML9WGD4PeFnu1HEBAAA-',
    // Phytoplankton - verified working 2024-01-29
    'phyto': 'H4sIAHfme2kAAxXNwQqCMBgA4Hf5z5qbEYi3aSWCZLQuEfGztjmDzYl6yMR3r67f5bsv4KdWD7n3gxohXdYArJj1UCpIoajqjFXITqy68ZIf68shZ.yKWZEjIRRJnETSaTei8wqN9fg0MuybCUXXSCSbeKe0wTPdhw5jEm8pjfp2lhDAp_yUfkNKSQCv.4U2_bH1hkthNaSNsKNeH193v5KWoQAAAA--',
    // Zooplankton - verified working 2024-01-29
    'zoo': 'H4sIAJ7me2kAAxXNQQuCMBQA4P.yzpZzFJQ3tRJBMrJLRDzWNle07YV6KMX.Xl2_y3cZgfq7bjOiVnUQj1MAVnx0WyiIIS_rNCkx2SfluS7qXXXcZkl9wjTPkLEIGV_F0mnXoSOFxhLejJy9rPDPnjwK30hkc75U2uAh2swccsYXURQORBICGAqv9BtizgJ4.EO06x9bMrUUVkPcCNvp6foFyQgxHqYAAAA-',
  };

  String _buildCopernicusUrl() {
    final timestamp = _dataDate.millisecondsSinceEpoch;
    
    var url = 'https://data.marine.copernicus.eu/viewer/expert?'
        'view=viewer'
        '&crs=epsg%3A4326'
        '&t=$timestamp'
        '&z=0'
        '&center=${_centerLon}%2C${_centerLat}'
        '&zoom=${_zoom.toStringAsFixed(1)}'
        '&basemap=dark';
    
    // Add layers param - either the selected layer or empty array to clear Copernicus cache
    if (_activeLayerId != null && _verifiedLayerParams.containsKey(_activeLayerId)) {
      url += '&layers=${_verifiedLayerParams[_activeLayerId]}';
    } else {
      // Empty layers array (base64 of "[]") to explicitly show no data layers
      url += '&layers=W10%3D';
    }
    
    return url;
  }

  Future<void> _loadSavedSnapshots() async {
    final prefs = await SharedPreferences.getInstance();
    final snapshotsJson = prefs.getStringList('ocean_snapshots') ?? [];
    
    setState(() {
      _savedSnapshots = snapshotsJson
          .map((json) => SavedSnapshot.fromJson(jsonDecode(json)))
          .toList()
        ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    });
  }

  Future<void> _saveSnapshot() async {
    if (_controller == null || _isSaving) return;
    
    setState(() => _isSaving = true);
    
    try {
      // Capture screenshot using RepaintBoundary
      final RenderRepaintBoundary? boundary = 
          _webViewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      
      if (boundary == null) {
        throw Exception('Could not find WebView to capture');
      }
      
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData == null) {
        throw Exception('Failed to capture screenshot');
      }
      
      final Uint8List imageBytes = byteData.buffer.asUint8List();
      
      // Generate unique ID
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      
      // Save image to app directory
      final directory = await getApplicationDocumentsDirectory();
      final imagePath = '${directory.path}/ocean_snapshot_$id.png';
      final file = File(imagePath);
      await file.writeAsBytes(imageBytes);
      
      // Create snapshot metadata
      final snapshot = SavedSnapshot(
        id: id,
        name: 'Ocean View ${_savedSnapshots.length + 1}',
        savedAt: DateTime.now(),
        dataDate: _dataDate,
        imagePath: imagePath,
        centerLat: _centerLat,
        centerLon: _centerLon,
        zoom: _zoom,
        layers: ['sst'], // TODO: Track actual enabled layers
      );
      
      // Save to preferences
      final prefs = await SharedPreferences.getInstance();
      final snapshotsJson = prefs.getStringList('ocean_snapshots') ?? [];
      snapshotsJson.add(jsonEncode(snapshot.toJson()));
      await prefs.setStringList('ocean_snapshots', snapshotsJson);
      
      // Update local state
      setState(() {
        _savedSnapshots.insert(0, snapshot);
        _isSaving = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved "${snapshot.name}" for offline viewing'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _deleteSnapshot(SavedSnapshot snapshot) async {
    // Delete image file
    final file = File(snapshot.imagePath);
    if (await file.exists()) {
      await file.delete();
    }
    
    // Remove from preferences
    final prefs = await SharedPreferences.getInstance();
    final snapshotsJson = prefs.getStringList('ocean_snapshots') ?? [];
    snapshotsJson.removeWhere((json) {
      final s = SavedSnapshot.fromJson(jsonDecode(json));
      return s.id == snapshot.id;
    });
    await prefs.setStringList('ocean_snapshots', snapshotsJson);
    
    // Update local state
    setState(() {
      _savedSnapshots.removeWhere((s) => s.id == snapshot.id);
    });
  }

  void _viewSnapshot(SavedSnapshot snapshot) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _SnapshotViewer(snapshot: snapshot),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}';
  }

  void _showLayerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.3,
          maxChildSize: 0.75,
          builder: (context, scrollController) => Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 8),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.layers, color: Colors.white),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Data Layers',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      // Show active layer or "None"
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _activeLayerId != null 
                              ? Colors.blue.withOpacity(0.2)
                              : Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _activeLayerId != null 
                              ? (_layerInfo[_activeLayerId]?['name'] as String? ?? 'Active')
                              : 'None',
                          style: TextStyle(
                            color: _activeLayerId != null ? Colors.blue : Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white12, height: 1),
                // Layer options - single select (radio)
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _layerInfo.length,
                    itemBuilder: (context, index) {
                      final entry = _layerInfo.entries.elementAt(index);
                      final id = entry.key;
                      final info = entry.value;
                      final isSelected = _activeLayerId == id;
                      final isAvailable = _verifiedLayerParams.containsKey(id);
                      
                      return ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? (info['color'] as Color).withOpacity(0.2)
                                : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            info['icon'] as IconData,
                            color: isSelected 
                                ? info['color'] as Color 
                                : (isAvailable ? Colors.white38 : Colors.white12),
                            size: 20,
                          ),
                        ),
                        title: Text(
                          info['name'] as String,
                          style: TextStyle(
                            color: isSelected 
                                ? Colors.white 
                                : (isAvailable ? Colors.white70 : Colors.white30),
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          isAvailable 
                              ? info['desc'] as String
                              : 'Coming soon',
                          style: TextStyle(
                            color: isAvailable ? Colors.white38 : Colors.white24,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Radio<String?>(
                          value: id,
                          groupValue: _activeLayerId,
                          activeColor: info['color'] as Color,
                          onChanged: isAvailable 
                              ? (value) {
                                  setModalState(() => _activeLayerId = value);
                                  setState(() {});
                                  _reloadViewerWithNewDate();
                                  Navigator.pop(context); // Auto-close after selection
                                }
                              : null,
                        ),
                        enabled: isAvailable,
                        onTap: isAvailable 
                            ? () {
                                setModalState(() => _activeLayerId = id);
                                setState(() {});
                                _reloadViewerWithNewDate();
                                Navigator.pop(context); // Auto-close after selection
                              }
                            : null,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDatePicker() async {
    final nowUtc = DateTime.now().toUtc();
    // Allow dates from 2020 to 10 days in the future (for forecasts)
    final futureDate = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day + 10);
    
    final picked = await showDatePicker(
      context: context,
      initialDate: _dataDate,
      firstDate: DateTime.utc(2020, 1, 1),
      lastDate: futureDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF5B9BD5),
              onPrimary: Colors.white,
              surface: Color(0xFF1A1A1A),
              onSurface: Colors.white,
              secondary: Color(0xFF5B9BD5),
              onSecondary: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF1A1A1A),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF5B9BD5), // Bright Cancel/OK buttons
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null && picked != _dataDate) {
      setState(() {
        _dataDate = picked;
      });
      _reloadViewerWithNewDate();
    }
  }

  /// Reload the Copernicus viewer with the new date
  void _reloadViewerWithNewDate() {
    if (_controller != null && _isOnline) {
      // Show loading overlay immediately before starting navigation
      setState(() => _isLoading = true);
      final url = _buildCopernicusUrl();
      _controller!.loadRequest(Uri.parse(url));
    }
  }

  /// Update WebView layer opacity via JavaScript
  void _updateWebViewOpacity(double opacity) {
    setState(() => _opacity = opacity);
    
    if (_controller != null) {
      // Inject JS to modify canvas opacity
      _controller!.runJavaScript('''
        (function() {
          var canvases = document.querySelectorAll('canvas');
          canvases.forEach(function(c) {
            c.style.opacity = '$opacity';
          });
        })();
      ''');
    }
  }
  
  /// Show layer info bottom sheet
  void _showLayerInfo() {
    final layerInfo = _activeLayerId != null ? _layerInfo[_activeLayerId] : null;
    if (layerInfo == null) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).padding.bottom + 16,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Title
            Row(
              children: [
                Icon(
                  layerInfo['icon'] as IconData,
                  color: layerInfo['color'] as Color,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    layerInfo['name'] as String,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              layerInfo['desc'] as String,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            _LayerInfoRow(label: 'Product', value: layerInfo['product'] as String),
            _LayerInfoRow(label: 'Dataset', value: layerInfo['dataset'] as String),
            _LayerInfoRow(label: 'Variable', value: layerInfo['variable'] as String),
            _LayerInfoRow(label: 'Source', value: 'Copernicus Marine Service'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showSavedSnapshots() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 16),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Title
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.offline_pin, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Saved Snapshots',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // List
              Expanded(
                child: _savedSnapshots.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.photo_library_outlined, 
                                 color: Colors.white38, size: 48),
                            SizedBox(height: 16),
                            Text(
                              'No saved snapshots',
                              style: TextStyle(color: Colors.white54),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Tap "Save" to capture the current view\nfor offline use',
                              style: TextStyle(color: Colors.white38, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _savedSnapshots.length,
                        itemBuilder: (context, index) {
                          final snapshot = _savedSnapshots[index];
                          return _SnapshotCard(
                            snapshot: snapshot,
                            onTap: () {
                              Navigator.pop(context);
                              _viewSnapshot(snapshot);
                            },
                            onDelete: () => _deleteSnapshot(snapshot),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Black background fill to eliminate any white lines
          Positioned.fill(
            child: Container(color: Colors.black),
          ),
          // Main content with bottom padding for Android nav controls
          if (_isOnline && _controller != null)
            Positioned.fill(
              bottom: MediaQuery.of(context).padding.bottom + 48,
              child: ClipRect(
                child: RepaintBoundary(
                  key: _webViewKey,
                  child: WebViewWidget(controller: _controller!),
                ),
              ),
            )
          else if (!_isOnline)
            _buildOfflineView()
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          
          // Loading overlay - spinner only
          if (_isLoading && _isOnline)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          
          // Top bar with back button and info pill
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: _buildTopBar(),
          ),
          
          // Floating action buttons on map (left side - vertically stacked)
          if (_isOnline && _controller != null)
            Positioned(
              left: 16,
              bottom: MediaQuery.of(context).padding.bottom + 100,
              child: _buildFloatingButtons(),
            ),
          
          // Bottom controls (opacity/legend only)
          if (_isOnline && _controller != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomControls(),
            ),
        ],
      ),
    );
  }

  /// Build top bar with back button and info pill (matches GIBS style)
  Widget _buildTopBar() {
    final layerInfo = _activeLayerId != null ? _layerInfo[_activeLayerId] : null;
    final layerColor = layerInfo?['color'] as Color? ?? Colors.white;
    
    return Row(
      children: [
        // Back button - floating pill style
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
          ),
        ),
        const Spacer(),
        // Date and layer info - floating pill (tappable to change date)
        if (_hasValidLayerData)
          GestureDetector(
            onTap: _showDatePicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Layer color dot
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: layerColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Date/time (and spot name if available)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_hasSpotContext)
                        Text(
                          widget.spotName!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      Text(
                        _formatLayerDateTime(),
                        style: TextStyle(
                          color: _hasSpotContext ? Colors.white70 : Colors.white,
                          fontSize: _hasSpotContext ? 11 : 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Build bottom controls (opacity/legend only - buttons are floating)
  Widget _buildBottomControls() {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Opacity slider (~50% width)
          Expanded(
            flex: 1,
            child: _buildOpacityRow(),
          ),
          const SizedBox(width: 12),
          // Legend (~50% width)
          Expanded(
            flex: 1,
            child: _buildLegendSection(),
          ),
        ],
      ),
    );
  }
  
  /// Floating buttons on the map (vertically stacked)
  Widget _buildFloatingButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Layers button
        _buildFloatingButton(
          icon: Icons.layers_outlined,
          onTap: _showLayerSheet,
        ),
        const SizedBox(height: 8),
        // Save snapshot button
        _buildFloatingButton(
          icon: _isSaving ? Icons.hourglass_empty : Icons.save_alt,
          onTap: _isOnline && !_isSaving ? _saveSnapshot : () {},
          enabled: _isOnline && !_isSaving,
        ),
        const SizedBox(height: 8),
        // Saved snapshots button with badge
        _buildFloatingButton(
          icon: Icons.offline_pin,
          onTap: _showSavedSnapshots,
          badgeCount: _savedSnapshots.length,
        ),
      ],
    );
  }
  
  Widget _buildFloatingButton({
    required IconData icon,
    required VoidCallback onTap,
    int badgeCount = 0,
    bool enabled = true,
  }) {
    return GestureDetector(
      onTap: enabled ? () {
        HapticFeedback.lightImpact();
        onTap();
      } : null,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Stack(
          children: [
            Center(
              child: Icon(icon, color: enabled ? Colors.white : Colors.white38, size: 24),
            ),
            if (badgeCount > 0)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Color(0xFF5B9BD5),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      badgeCount > 9 ? '9+' : '$badgeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  /// Build save buttons (right-aligned, icon-only, equal width)
  Widget _buildSaveButtons() {
    const buttonWidth = 44.0;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Save snapshot button
        GestureDetector(
          onTap: _isOnline && !_isSaving ? () {
            HapticFeedback.lightImpact();
            _saveSnapshot();
          } : null,
          child: Container(
            width: buttonWidth,
            height: buttonWidth,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Icon(
                _isSaving ? Icons.hourglass_empty : Icons.save_alt,
                color: _isOnline && !_isSaving ? Colors.white : Colors.white38,
                size: 20,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Saved snapshots button
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            _showSavedSnapshots();
          },
          child: Stack(
            children: [
              Container(
                width: buttonWidth,
                height: buttonWidth,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(Icons.offline_pin, color: Colors.white, size: 20),
                ),
              ),
              // Badge for count
              if (_savedSnapshots.isNotEmpty)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      _savedSnapshots.length > 9 ? '9+' : _savedSnapshots.length.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
  

  /// Build opacity slider row
  Widget _buildOpacityRow() {
    final layerInfo = _activeLayerId != null ? _layerInfo[_activeLayerId] : null;
    final layerColor = layerInfo?['color'] as Color? ?? Colors.blue;
    
    return Row(
      children: [
        const Icon(Icons.opacity, color: Colors.white54, size: 16),
        Expanded(
          child: SliderTheme(
            data: const SliderThemeData(trackHeight: 3),
            child: Slider(
              value: _opacity,
              activeColor: layerColor,
              inactiveColor: Colors.white24,
              onChanged: _updateWebViewOpacity,
            ),
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            '${(_opacity * 100).round()}%',
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ),
      ],
    );
  }
  
  
  /// Build legend section
  Widget _buildLegendSection() {
    if (!_hasValidLayerData || (_legendGradientCss == null && _legendTicks.isEmpty)) {
      return const SizedBox.shrink();
    }
    
    return DynamicOceanLegend(
      gradientCss: _legendGradientCss,
      ticks: _legendTicks,
      compact: true,
    );
  }

  /// Build the date selector showing today +/- 3 days
  Widget _buildDateSelector() {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    
    // Generate 7 days: 3 days ago, 2 days ago, yesterday, today, tomorrow, +2, +3
    final dates = List.generate(7, (i) {
      return todayDate.subtract(Duration(days: 3 - i));
    });
    
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: dates.map((date) {
          final isSelected = _selectedDate.year == date.year && 
                            _selectedDate.month == date.month && 
                            _selectedDate.day == date.day;
          
          // Format: "Mon" for weekday, "28" for day
          const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
          final weekday = weekdays[date.weekday - 1];
          final dayNum = date.day.toString();
          
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => _onDateSelected(date),
              child: Container(
                width: 48,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? Colors.blue : Colors.white24,
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      weekday,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dayNum,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white,
                        fontSize: 16,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Build the time selector showing available time slots based on layer interval
  Widget _buildTimeSelector(int intervalHours) {
    // Generate time slots based on interval
    // For hourly: 0, 1, 2, ... 23
    // All hours are shown - Copernicus has forecast data for future dates
    final now = DateTime.now();
    final isToday = _selectedDate.year == now.year && 
                   _selectedDate.month == now.month && 
                   _selectedDate.day == now.day;
    
    List<int> hours = [];
    for (int h = 0; h < 24; h += intervalHours) {
      // For today, only show hours up to current hour (no future hours today)
      if (isToday && h > now.hour) continue;
      hours.add(h);
    }
    
    // If no hours available, show all hours as fallback
    if (hours.isEmpty) {
      for (int h = 0; h < 24; h += intervalHours) {
        hours.add(h);
      }
    }
    
    // Find closest valid hour to currently selected
    int closestHour = hours.first;
    for (final h in hours) {
      if ((h - _selectedHour).abs() < (closestHour - _selectedHour).abs()) {
        closestHour = h;
      }
    }
    // Update if needed (without setState to avoid loop)
    if (!hours.contains(_selectedHour)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedHour != closestHour) {
          _onTimeSelected(closestHour);
        }
      });
    }
    
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: hours.map((hour) {
          final isSelected = _selectedHour == hour;
          // Format hour: "12 AM", "1 PM", etc.
          final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
          final amPm = hour >= 12 ? 'PM' : 'AM';
          final label = '$hour12 $amPm';
          
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: GestureDetector(
              onTap: () => _onTimeSelected(hour),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? Colors.blue : Colors.white24,
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Handle time selection
  void _onTimeSelected(int hour) {
    setState(() {
      _selectedHour = hour;
      _dataDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, hour);
    });
    _reloadWithNewTimestamp();
  }

  /// Handle date selection
  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate = date;
      // Update _dataDate with selected date and current hour
      _dataDate = DateTime(date.year, date.month, date.day, _selectedHour);
    });
    // Reload the WebView with the new timestamp
    _reloadWithNewTimestamp();
  }

  /// Reload WebView with current _dataDate timestamp
  void _reloadWithNewTimestamp() {
    if (_controller == null) return;
    // Show loading overlay IMMEDIATELY before starting navigation
    // This prevents flickering of controls during page reload
    setState(() => _isLoading = true);
    final url = _buildCopernicusUrl();
    _controller!.loadRequest(Uri.parse(url));
  }

  Widget _buildOfflineView() {
    return Container(
      color: const Color(0xFF0D0D0D),
      child: _savedSnapshots.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off, color: Colors.white38, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'You\'re offline',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'No saved snapshots available',
                    style: TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 24),
                  TextButton.icon(
                    icon: const Icon(Icons.info_outline),
                    label: const Text('Save views when online for offline access'),
                    onPressed: null,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white38,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Header
                Padding(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 60,
                    left: 16,
                    right: 16,
                    bottom: 16,
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.offline_pin, color: Colors.orange),
                      SizedBox(width: 8),
                      Text(
                        'Offline Mode - Viewing Saved Snapshots',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ],
                  ),
                ),
                // Grid of saved snapshots
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 1.5,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _savedSnapshots.length,
                    itemBuilder: (context, index) {
                      final snapshot = _savedSnapshots[index];
                      return GestureDetector(
                        onTap: () => _viewSnapshot(snapshot),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(
                                  File(snapshot.imagePath),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: Colors.grey.shade900,
                                    child: const Icon(Icons.broken_image, color: Colors.white38),
                                  ),
                                ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: [
                                          Colors.black.withOpacity(0.8),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                    child: Text(
                                      snapshot.formattedDate,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
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
    );
  }
}

/// Card for displaying a saved snapshot in the list
class _SnapshotCard extends StatelessWidget {
  final SavedSnapshot snapshot;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SnapshotCard({
    required this.snapshot,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF2A2A2A),
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 80,
                  height: 60,
                  child: Image.file(
                    File(snapshot.imagePath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade800,
                      child: const Icon(Icons.broken_image, color: Colors.white38, size: 24),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      snapshot.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Data: ${snapshot.formattedDate}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    Text(
                      'Saved: ${_formatSavedDate(snapshot.savedAt)}',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              // Delete button
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.white38),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF2A2A2A),
                      title: const Text('Delete Snapshot?', 
                          style: TextStyle(color: Colors.white)),
                      content: Text(
                        'Remove "${snapshot.name}"?',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            onDelete();
                          },
                          child: const Text('Delete', 
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatSavedDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    
    return '${date.month}/${date.day}/${date.year}';
  }
}

/// Full-screen snapshot viewer
class _SnapshotViewer extends StatelessWidget {
  final SavedSnapshot snapshot;

  const _SnapshotViewer({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Image
          InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: Image.file(
                File(snapshot.imagePath),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image, color: Colors.white38, size: 64),
                      SizedBox(height: 16),
                      Text('Image not found', style: TextStyle(color: Colors.white54)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top,
                left: 8,
                right: 16,
                bottom: 8,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          snapshot.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Data from ${snapshot.formattedDate}',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.offline_pin, color: Colors.orange, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Saved',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Pinch to zoom hint
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            child: const Center(
              child: Text(
                'Pinch to zoom',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Toolbar button widget
class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool highlighted;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: highlighted 
              ? (enabled ? Colors.blue.withOpacity(0.3) : Colors.blue.withOpacity(0.1))
              : Colors.white.withOpacity(enabled ? 0.1 : 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: highlighted 
                ? (enabled ? Colors.blue : Colors.blue.withOpacity(0.3))
                : (enabled ? Colors.white24 : Colors.white12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon, 
              color: enabled ? Colors.white : Colors.white38, 
              size: 16,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: enabled ? Colors.white : Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Square action button (matches GIBS style)
class _SquareButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final int? badgeCount;

  const _SquareButton({
    required this.icon,
    this.onTap,
    this.badgeCount,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    
    return GestureDetector(
      onTap: () {
        if (enabled) {
          HapticFeedback.lightImpact();
          onTap!();
        }
      },
      child: AspectRatio(
        aspectRatio: 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(enabled ? 0.1 : 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: enabled ? Colors.white24 : Colors.white12),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, color: enabled ? Colors.white : Colors.white38, size: 22),
              if (badgeCount != null && badgeCount! > 0)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      badgeCount! > 9 ? '9+' : badgeCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
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
}

/// Layer info row for bottom sheet
class _LayerInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _LayerInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact circular button for the floating action bar
class _FloatingActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final int? badgeCount;

  const _FloatingActionButton({
    required this.icon,
    this.onTap,
    required this.tooltip,
    this.badgeCount,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: enabled ? Colors.white.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                icon,
                color: enabled ? Colors.white : Colors.white38,
                size: 20,
              ),
              if (badgeCount != null && badgeCount! > 0)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      badgeCount! > 9 ? '9+' : badgeCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
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
}

class _VerticalToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool highlighted;
  final int? badgeCount;

  const _VerticalToolbarButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.highlighted = false,
    this.badgeCount,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: highlighted 
              ? (enabled ? Colors.blue.withOpacity(0.4) : Colors.blue.withOpacity(0.15))
              : Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: highlighted 
                ? (enabled ? Colors.blue : Colors.blue.withOpacity(0.3))
                : (enabled ? Colors.white30 : Colors.white12),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon, 
              color: enabled ? Colors.white : Colors.white38, 
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: enabled ? Colors.white : Colors.white38,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.clip,
            ),
            if (badgeCount != null && badgeCount! > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
