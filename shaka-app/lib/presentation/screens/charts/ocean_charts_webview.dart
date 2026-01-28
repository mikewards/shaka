import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  const OceanChartsWebView({super.key});

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
  
  // Default view settings
  double _centerLat = 21.3;
  double _centerLon = -157.8;
  double _zoom = 6.0;
  DateTime _dataDate = DateTime.now().subtract(const Duration(days: 1));
  
  // Available Copernicus Marine layers
  // Note: Layer control currently requires using the viewer's built-in layer panel
  // These are shown for reference - actual layer selection happens in the Copernicus UI
  static const Map<String, Map<String, dynamic>> _availableLayers = {
    'sst': {'name': 'Sea Surface Temp', 'icon': Icons.thermostat, 'color': Color(0xFFFF6B35), 'desc': 'Water temperature'},
    'chl': {'name': 'Chlorophyll', 'icon': Icons.grass, 'color': Color(0xFF4CAF50), 'desc': 'Phytoplankton / bait'},
    'zsd': {'name': 'Visibility', 'icon': Icons.visibility, 'color': Color(0xFF2196F3), 'desc': 'Water clarity (Secchi)'},
    'waves': {'name': 'Wave Height', 'icon': Icons.waves, 'color': Color(0xFF3F51B5), 'desc': 'Significant wave height'},
    'wind': {'name': 'Wind', 'icon': Icons.air, 'color': Color(0xFF607D8B), 'desc': 'Surface wind speed'},
    'cur': {'name': 'Currents', 'icon': Icons.sync_alt, 'color': Color(0xFF00BCD4), 'desc': 'Current speed/direction'},
    'mld': {'name': 'Mixed Layer Depth', 'icon': Icons.layers, 'color': Color(0xFF673AB7), 'desc': 'Thermocline depth'},
    'sal': {'name': 'Salinity', 'icon': Icons.water_drop, 'color': Color(0xFF009688), 'desc': 'Sea water salinity'},
    'o2': {'name': 'Dissolved Oxygen', 'icon': Icons.bubble_chart, 'color': Color(0xFFE91E63), 'desc': 'Oxygen levels'},
    'ssh': {'name': 'Sea Height', 'icon': Icons.trending_up, 'color': Color(0xFF9C27B0), 'desc': 'Height anomaly'},
  };

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _loadSavedSnapshots();
  }

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
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) {
            setState(() => _isLoading = false);
            // Inject CSS/JS to customize the viewer after page loads
            _injectCustomizations();
          },
          onWebResourceError: (error) {
            debugPrint('WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(url));
    
    setState(() {});
  }

  /// Inject JavaScript to hide ALL Copernicus UI elements by position and structure
  /// Uses aggressive DOM manipulation since CSS class names are dynamically generated
  Future<void> _injectCustomizations() async {
    if (_controller == null) return;
    
    // JavaScript that aggressively hides UI by analyzing element positions and roles
    const jsCode = '''
      (function() {
        // Track the map canvas element
        var mapCanvas = null;
        
        function findMapCanvas() {
          // Find the actual map canvas
          var canvases = document.querySelectorAll('canvas');
          for (var i = 0; i < canvases.length; i++) {
            var c = canvases[i];
            // The map canvas is usually large and covers most of the viewport
            if (c.offsetWidth > window.innerWidth * 0.5 && c.offsetHeight > window.innerHeight * 0.5) {
              mapCanvas = c;
              return c;
            }
          }
          return null;
        }
        
        function isPartOfMap(el) {
          if (!el || !mapCanvas) return false;
          // Check if element is the canvas or contains it
          if (el === mapCanvas) return true;
          if (el.contains(mapCanvas)) return true;
          // Check if element is inside the map container
          var parent = mapCanvas.parentElement;
          while (parent) {
            if (parent === el) return true;
            if (parent.contains(el) && el.contains(mapCanvas)) return true;
            parent = parent.parentElement;
          }
          return false;
        }
        
        function hideUI() {
          findMapCanvas();
          
          // Get all direct children of body
          var bodyChildren = document.body.children;
          for (var i = 0; i < bodyChildren.length; i++) {
            var child = bodyChildren[i];
            // Keep the element that contains the map, hide everything else
            if (!isPartOfMap(child) && !child.contains(mapCanvas)) {
              child.style.cssText = 'display: none !important; visibility: hidden !important;';
            }
          }
          
          // Hide elements positioned in corners (controls, toolbars)
          var allElements = document.querySelectorAll('*');
          allElements.forEach(function(el) {
            if (el === mapCanvas || el.tagName === 'CANVAS') return;
            if (el.contains(mapCanvas)) return;
            
            var style = window.getComputedStyle(el);
            var pos = style.position;
            
            // Hide fixed/absolute positioned elements (UI overlays)
            if (pos === 'fixed' || pos === 'absolute') {
              var rect = el.getBoundingClientRect();
              
              // Skip if it's the map container itself
              if (rect.width > window.innerWidth * 0.8 && rect.height > window.innerHeight * 0.8) {
                return;
              }
              
              // Hide elements in corners (controls)
              var inCorner = (rect.left < 100 || rect.right > window.innerWidth - 100) &&
                            (rect.top < 100 || rect.bottom > window.innerHeight - 100);
              
              // Hide elements that look like toolbars (full width at top or bottom)
              var isToolbar = (rect.width > window.innerWidth * 0.5) && 
                             (rect.height < 100) &&
                             (rect.top < 80 || rect.bottom > window.innerHeight - 80);
              
              // Hide sidebars (narrow, full height)
              var isSidebar = (rect.height > window.innerHeight * 0.5) &&
                             (rect.width < 400) &&
                             (rect.left < 50 || rect.right > window.innerWidth - 50);
              
              if (inCorner || isToolbar || isSidebar) {
                el.style.cssText = 'display: none !important; visibility: hidden !important; opacity: 0 !important; pointer-events: none !important;';
              }
            }
          });
          
          // Hide buttons, icons, controls by role
          document.querySelectorAll('button, [role="button"], [role="toolbar"], [role="navigation"], [role="menu"], [role="dialog"], [role="alertdialog"], nav, aside, header, footer').forEach(function(el) {
            if (!isPartOfMap(el) && !el.contains(mapCanvas)) {
              el.style.cssText = 'display: none !important;';
            }
          });
          
          // Hide by aria-labels - but KEEP layer controls visible
          document.querySelectorAll('[aria-label*="zoom"], [aria-label*="Zoom"], [aria-label*="compass"], [aria-label*="Compass"], [aria-label*="north"], [aria-label*="North"], [aria-label*="search"], [aria-label*="Search"], [aria-label*="menu"], [aria-label*="Menu"], [aria-label*="tool"], [aria-label*="Tool"], [aria-label*="draw"], [aria-label*="Draw"], [aria-label*="measure"], [aria-label*="settings"], [aria-label*="Settings"]').forEach(function(el) {
            el.style.cssText = 'display: none !important;';
          });
          
          // Hide North Pole and South Pole labels
          document.querySelectorAll('*').forEach(function(el) {
            var text = (el.innerText || el.textContent || '').toLowerCase().trim();
            if (text === 'north pole' || text === 'south pole' || 
                text === 'northpole' || text === 'southpole' ||
                text === 'n pole' || text === 's pole') {
              el.style.cssText = 'display: none !important;';
            }
          });
          
          // Remove any right border/line artifacts
          document.body.style.cssText += 'overflow: hidden !important; margin: 0 !important; padding: 0 !important;';
          document.documentElement.style.cssText += 'overflow: hidden !important; margin: 0 !important; padding: 0 !important;';
          
          // Hide any thin vertical lines on edges
          allElements.forEach(function(el) {
            var rect = el.getBoundingClientRect();
            // Very thin element on right edge
            if (rect.width <= 2 && rect.height > 100 && rect.right >= window.innerWidth - 5) {
              el.style.cssText = 'display: none !important;';
            }
          });
          
          // Hide SVG icons (often used for controls)
          document.querySelectorAll('svg').forEach(function(svg) {
            var parent = svg.parentElement;
            if (parent && (parent.tagName === 'BUTTON' || parent.getAttribute('role') === 'button')) {
              parent.style.cssText = 'display: none !important;';
            }
          });
          
          // Click any close buttons on dialogs
          document.querySelectorAll('[aria-label*="close"], [aria-label*="Close"]').forEach(function(btn) {
            try { btn.click(); } catch(e) {}
          });
          
          // Accept cookie/consent dialogs
          document.querySelectorAll('button').forEach(function(btn) {
            var text = (btn.innerText || '').toLowerCase();
            if (text.includes('accept') || text.includes('agree') || text === 'ok') {
              try { btn.click(); } catch(e) {}
            }
          });
        }
        
        // Run immediately and repeatedly
        hideUI();
        setTimeout(hideUI, 500);
        setTimeout(hideUI, 1000);
        setTimeout(hideUI, 2000);
        setTimeout(hideUI, 3000);
        setTimeout(hideUI, 5000);
        setInterval(hideUI, 2000);
        
        // Also run on any DOM changes
        var observer = new MutationObserver(function(mutations) {
          hideUI();
        });
        observer.observe(document.body, { childList: true, subtree: true });
      })();
    ''';
    
    await _controller!.runJavaScript(jsCode);
  }

  String _buildCopernicusUrl() {
    // Build Copernicus MyOcean Viewer URL
    final timestamp = _dataDate.millisecondsSinceEpoch;
    
    // The viewer loads with its default layer (usually SST)
    // Users can add/remove layers using the Copernicus layer panel
    return 'https://data.marine.copernicus.eu/viewer/expert?'
        'view=viewer'
        '&crs=epsg%3A4326'
        '&t=$timestamp'
        '&z=0'
        '&center=${_centerLon}%2C${_centerLat}'
        '&zoom=${_zoom.toStringAsFixed(1)}'
        '&basemap=dark';
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
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.85,
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
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.layers, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Available Layers',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // Info banner
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Use the Copernicus layer panel on the map to toggle layers',
                        style: TextStyle(color: Colors.blue, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              // Scrollable layer info list
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _availableLayers.length,
                  itemBuilder: (context, index) {
                    final entry = _availableLayers.entries.elementAt(index);
                    final info = entry.value;
                    
                    return ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: (info['color'] as Color).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          info['icon'] as IconData,
                          color: info['color'] as Color,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        info['name'] as String,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        info['desc'] as String,
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
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
              primary: Colors.blue,
              onPrimary: Colors.white,
              surface: Color(0xFF1A1A1A),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF1A1A1A),
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
      final url = _buildCopernicusUrl();
      _controller!.loadRequest(Uri.parse(url));
    }
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
          // Main content
          if (_isOnline && _controller != null)
            RepaintBoundary(
              key: _webViewKey,
              child: WebViewWidget(controller: _controller!),
            )
          else if (!_isOnline)
            _buildOfflineView()
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          
          // Loading overlay
          if (_isLoading && _isOnline)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Loading Copernicus Viewer...',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          
          // Top bar with back button
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                left: 8,
                right: 8,
                bottom: 8,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.black.withOpacity(0.0),
                  ],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Expanded(
                    child: Text(
                      'Ocean Charts',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Bottom toolbar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.9),
                      Colors.black.withOpacity(0.0),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    // Layers button
                    Expanded(
                      child: _ToolbarButton(
                        icon: Icons.layers,
                        label: 'Layers',
                        onTap: _showLayerSheet,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Date button
                    Expanded(
                      child: _ToolbarButton(
                        icon: Icons.calendar_today,
                        label: _formatDate(_dataDate),
                        onTap: _showDatePicker,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Save button
                    Expanded(
                      child: _ToolbarButton(
                        icon: _isSaving ? Icons.hourglass_empty : Icons.save_alt,
                        label: 'Save',
                        onTap: _isOnline && !_isSaving ? _saveSnapshot : null,
                        highlighted: true,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Saved snapshots button
                    Expanded(
                      child: _ToolbarButton(
                        icon: Icons.offline_pin,
                        label: '${_savedSnapshots.length}',
                        onTap: _showSavedSnapshots,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
