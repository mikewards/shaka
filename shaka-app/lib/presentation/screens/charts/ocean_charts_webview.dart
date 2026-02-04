import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../widgets/dynamic_ocean_legend.dart';

/// Ocean Charts screen using Copernicus WebView
/// Provides high-quality ocean data visualization
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
  bool _isLoading = true;
  bool _isOnline = true;
  
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
  
  // Fallback timer - if legend data not received within timeout, hide loading
  Timer? _loadingFallbackTimer;
  
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
  }
  
  @override
  void dispose() {
    _loadingFallbackTimer?.cancel();
    super.dispose();
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
            // Cancel fallback timer since we received data
            _loadingFallbackTimer?.cancel();
            _loadingFallbackTimer = null;
            setState(() {
              _legendGradientCss = data['gradient'] as String?;
              _legendTicks = List<String>.from(data['ticks'] ?? []);
              _layerDate = data['date'] as String?;
              _layerTime = data['time'] as String?;
              _layerSource = data['source'] as String?;
              // Hide loading now that we have legend data
              _isLoading = false;
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
          // When customizations are complete, start fallback timer
          // Legend data will set _isLoading = false when received
          // If no legend data within 5 seconds, hide loading anyway (shows warning)
          if (message.message == 'done') {
            _loadingFallbackTimer?.cancel();
            _loadingFallbackTimer = Timer(const Duration(seconds: 5), () {
              if (mounted && _isLoading) {
                setState(() => _isLoading = false);
              }
            });
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
    // Currents layer - Sea water velocity m/s - verified working 2026-02-04
    'cur': 'H4sIABSPg2kAAxWOywqCQBRA._WurcaKCHcWPQQpyTYRcRlmbipcnZiZHib_e7Y9HDjn2oHxJdm1MVY7iLo_AJYt2URDBLv0uIpTjA9xesmTfHs8bdZxfsZsf0EhQhTT_UTVVDusjcaCDT7KFmVzVyjGYjnTVGB2DvejGqeDKxYTRxLf0pPFF7FRlW8hgG.SaPpAtBABVP8ucjhgNkWuJBNEd8mOAnC_Zcqk9ZViGma9fVJ._wHpZZ3DwwAAAA--',
    // Sea Surface Temperature - verified working 2026-02-04
    'sst': 'H4sIAK6Og2kAAx2OywqCQBRA._WuLUd7EO5MKgVJSTcScRmc8QEzXhldZOK.Z20PB855zkBjI01AZMQA3rxYoPgkTSTAg1ucnP0Y.bsfF1mUXZPHJfCzHNOwQMYcZO7eLrXUA2oSWCvCvpmQd1WJbMtOOyFrTHMn3Gh0V5cd7bU1cgILPlEn5Bu8A7Og.bVQsRUrqrOSKwlexdUgLShJkdG8.._0XSVNR7C8vscNpV_4AAAA',
    // Swell Wave Height - verified working 2026-02-04
    'waves': 'H4sIAEWPg2kAAxXOywqCQBSA4Xc5a6ujBYW7KboIdqGJIiIOg3M0YXRgtIuJ755t.83.3Vqw9YPdwlqnKwjbzgOjGnaRhhDW8X4uYhI7EV9lJFf743Ih5Iku4kyIPmEwHSUFFxUVVlNmLL3Vi1SZJoRDnI01Z3Q4jTeDnAIMJr4.Om_2SPLigwffqNT8gXCKHuT.Gxnss7GZTJRhCFNlKvagqhvDB_XqPDHcE2v35O7_A3ox1Qi5AAAA',
    // Salinity - verified working 2026-02-04
    'sal': 'H4sIAHKPg2kAAxXNQQuCMBiA4f.ynS2nRchuSyoFSWleJOJjuKnB5mLrkIn.Pbu_vPDcZ7DvQbnUWic90HkJQItJuVwChUtRHlmB7MqKhuf8XN5OKeM1VlmDhERI4n3YGmU8Giux1xZfw4Ri7FokW5LspOqxqqNsYzBeX3IIvYUAvvko1QdoQgJ4.h3U0Zq17XkrtALaCe3V8vgB94exMZ0AAAA-',
    // Wind layer with arrows - verified working 2026-02-04
    'wind': 'H4sIAJ_Pg2kAAy2ObUvDMBSF.8v9XLc09s1_VdgKcxYdiIhcYnNtA3fNSFK1jv13M93Hczic53k9gg0DuVtrnfZQH08JsJrJNRpqeG62d7jaPGC7fsFNhtvHHYpUohDZstvT3qN991dfZtTYs8XDMOPoAnKGYpHKXFOP7S5doxRSinJ5HkICP82o6RvqG5GAOWOQRazZ9k_dYoL6Q7GnBHyYmVrlgumYoltwU2zZ9ENYOTsd.hQvn5_KJ7o3I9Tx9D_oiJDVIs8KkVZFVVyXZV7mp7dfqWE4avMAAAA-',
    // Chlorophyll - verified working 2026-02-04
    'chl': 'H4sIAMGNg2kAAxXNQQuCMBQA4P.yzo4285K3WmGCaFidIh5Tp4lPJ3NBJf736vpdvtsMxj20lcbYaoJwXjwg9dY2riCETB62qcyS7JpjlGS4iyQmAab5BTnfoOD_qux1P6EpJmZKbMhg0ZRsJDV0zgw4WIcUsEaNtdWa9U9yLQu6Hk9ijz7310Ks5DEBDz7xUOkXhAH3oP3fSOLHZJpzqUhDWCua9HL.AtXYSlGxAAAA',
    // Phytoplankton - verified working 2026-02-04
    'phyto': 'H4sIANKPg2kAAxXNwQqCMBgA4Hf5z5abEcRu00oEyWhdIuJnbXMGmxP1kInvXl2.y3efIYyN6bMQej0Am5cInJxMX2hgkJdVykvkJ17eRCGO1eWQcXHFNM_QEIok2cXKGz_gDxqtC.i0atXVI8q2VkjWyVYbi2e6X3lMSLKhNO6aSUEEn6LV5g2MEhLB65_hoz93wQolnQFWSzeY5fEF7LCNeaIAAAA-',
    // Zooplankton - verified working 2026-02-04
    'zoo': 'H4sIAO2Pg2kAAxXNQQuCMBQA4P.yzpqbFIQ3tRJBMrJLRDzWNle07YV6KMX.Xl2.y3eZgIa77nKiTvWQTHMAVnx0VypIoKjqLK0w3afVuSmbXX3c5mlzwqzIkTGOLF5H0mnXoyOFxhLejAxfVvjnQB6FbyWyRbxS2uCBb0KHMYuXnEcjkYQAxtIr.YaEcxbA4z_iZT_3ZBoprIakFbbX8.ULMd7jd6cAAAA-',
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
            colorScheme: ColorScheme.dark(
              primary: AppColors.info,
              onPrimary: Colors.white,
              surface: const Color(0xFF1A1A1A),
              onSurface: Colors.white,
              secondary: AppColors.info,
              onSecondary: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF1A1A1A),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.info,
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
                child: WebViewWidget(controller: _controller!),
              ),
            )
          else if (!_isOnline)
            _buildOfflineView()
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          
          // Loading overlay - opaque, only covers WebView area
          if (_isLoading && _isOnline)
            Positioned.fill(
              bottom: MediaQuery.of(context).padding.bottom + 48,
              child: Container(
                color: Colors.black,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),
          
          // Top bar with back button and info pill
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: _buildTopBar(),
          ),
          
          // Floating action buttons - LEFT side (Layers only)
          if (_isOnline && _controller != null)
            Positioned(
              left: 16,
              bottom: MediaQuery.of(context).padding.bottom + 80,
              child: _buildLeftFloatingButtons(),
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
        // Back button - matches floating button size (48x48)
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: const Center(
              child: Icon(Icons.arrow_back, color: Colors.white, size: 24),
            ),
          ),
        ),
        const Spacer(),
        // Date and layer info - same height as back button (48px)
        // Always show date picker so user can select a different date if today has no data
        // Only show warning state when NOT loading AND data is invalid
        GestureDetector(
          onTap: _showDatePicker,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (!_isLoading && !_hasValidLayerData) ? Colors.orange.withOpacity(0.6) : Colors.white24,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Warning icon when no data (after loading), otherwise layer color dot
                if (!_isLoading && !_hasValidLayerData)
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 12)
                else
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: layerColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                const SizedBox(width: 8),
                // Date/time (and spot name if available) or warning message
                if (_hasValidLayerData) ...[
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
                ] else
                  Text(
                    _isLoading ? 'Loading...' : 'Try another date',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
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
  
  /// Left floating buttons (Layers only)
  Widget _buildLeftFloatingButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Layers button
        _buildFloatingButton(
          icon: Icons.layers_outlined,
          onTap: _showLayerSheet,
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
                  decoration: BoxDecoration(
                    color: AppColors.info,
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

  /// Build opacity slider row
  Widget _buildOpacityRow() {
    final layerInfo = _activeLayerId != null ? _layerInfo[_activeLayerId] : null;
    final layerColor = layerInfo?['color'] as Color? ?? AppColors.info;
    
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
          width: 38,
          child: Text(
            '${(_opacity * 100).round()}%',
            style: const TextStyle(color: Colors.white54, fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.visible,
          ),
        ),
      ],
    );
  }
  
  
  /// Build legend section
  Widget _buildLegendSection() {
    // Hide legend when no valid data or no legend info
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
                  color: isSelected ? AppColors.info : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? AppColors.info : Colors.white24,
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
                  color: isSelected ? AppColors.info : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? AppColors.info : Colors.white24,
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
      child: Center(
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
              'Connect to the internet to view ocean data',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
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
              ? (enabled ? AppColors.info.withOpacity(0.3) : AppColors.info.withOpacity(0.1))
              : Colors.white.withOpacity(enabled ? 0.1 : 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: highlighted 
                ? (enabled ? AppColors.info : AppColors.info.withOpacity(0.3))
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
                    decoration: BoxDecoration(
                      color: AppColors.info,
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
                    decoration: BoxDecoration(
                      color: AppColors.info,
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
              ? (enabled ? AppColors.info.withOpacity(0.4) : AppColors.info.withOpacity(0.15))
              : Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: highlighted 
                ? (enabled ? AppColors.info : AppColors.info.withOpacity(0.3))
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
                  color: AppColors.info,
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
