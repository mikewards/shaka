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
  
  // Layer states - matches our original ocean charts
  final Map<String, bool> _layerStates = {
    'sst': true,      // Sea Surface Temperature
    'chl': false,     // Chlorophyll
    'zsd': false,     // Water Visibility (Secchi Depth)
    'ssh': false,     // Sea Surface Height
    'currents': false, // Ocean Currents
    'wind': false,    // Wind
  };
  
  // Layer display info
  static const Map<String, Map<String, dynamic>> _layerInfo = {
    'sst': {'name': 'Sea Surface Temp', 'icon': Icons.thermostat, 'color': Color(0xFFFF6B35)},
    'chl': {'name': 'Chlorophyll', 'icon': Icons.eco, 'color': Color(0xFF4CAF50)},
    'zsd': {'name': 'Visibility', 'icon': Icons.visibility, 'color': Color(0xFF2196F3)},
    'ssh': {'name': 'Sea Height', 'icon': Icons.waves, 'color': Color(0xFF9C27B0)},
    'currents': {'name': 'Currents', 'icon': Icons.sync_alt, 'color': Color(0xFF00BCD4)},
    'wind': {'name': 'Wind', 'icon': Icons.air, 'color': Color(0xFF78909C)},
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

  /// Inject CSS and JavaScript to hide Copernicus UI elements
  /// We provide our own controls overlaid on top
  Future<void> _injectCustomizations() async {
    if (_controller == null) return;
    
    // More targeted CSS - only hide specific UI elements, not the map
    const customCSS = '''
      /* Hide the Copernicus control panels and toolbars */
      .maplibregl-ctrl-group,
      .maplibregl-ctrl-top-left,
      .maplibregl-ctrl-top-right,
      .maplibregl-ctrl-bottom-left,
      .maplibregl-ctrl-bottom-right,
      .mapboxgl-ctrl-group,
      .mapboxgl-ctrl-top-left,
      .mapboxgl-ctrl-top-right,
      .mapboxgl-ctrl-bottom-left,
      .mapboxgl-ctrl-bottom-right {
        display: none !important;
      }
      
      /* Hide navigation controls (zoom, compass) */
      .maplibregl-ctrl-nav,
      .mapboxgl-ctrl-nav,
      .maplibregl-ctrl-zoom,
      .mapboxgl-ctrl-zoom,
      .maplibregl-ctrl-compass,
      .mapboxgl-ctrl-compass {
        display: none !important;
      }
      
      /* Hide attribution */
      .maplibregl-ctrl-attrib,
      .mapboxgl-ctrl-attrib {
        display: none !important;
      }
      
      /* Hide any fixed/absolute positioned UI overlays */
      div[style*="position: fixed"]:not([class*="map"]),
      div[style*="position: absolute"]:not([class*="map"]):not([class*="canvas"]) {
        /* Be careful here - only hide if clearly UI */
      }
      
      /* Hide specific Copernicus UI elements by common patterns */
      [data-testid],
      [class*="MuiDrawer"],
      [class*="MuiAppBar"],
      [class*="MuiToolbar"],
      [class*="MuiPaper"]:not([class*="map"]),
      [class*="MuiDialog"],
      [class*="MuiModal"],
      [class*="MuiBackdrop"],
      [class*="MuiSnackbar"],
      [class*="MuiAlert"],
      [class*="MuiMenu"],
      [class*="MuiPopover"],
      [class*="MuiFab"],
      [class*="MuiSpeedDial"] {
        display: none !important;
        visibility: hidden !important;
      }
      
      /* Hide cookie/consent banners */
      [class*="cookie"],
      [class*="Cookie"],
      [class*="consent"],
      [class*="Consent"],
      [class*="gdpr"],
      [class*="GDPR"],
      [id*="cookie"],
      [id*="consent"] {
        display: none !important;
      }
      
      /* Make sure the map canvas stays visible and fullscreen */
      .maplibregl-canvas,
      .mapboxgl-canvas {
        display: block !important;
        visibility: visible !important;
        opacity: 1 !important;
      }
    ''';
    
    // JavaScript to apply CSS and hide specific elements
    final jsCode = '''
      (function() {
        // Create and inject style
        var existingStyle = document.getElementById('shaka-custom-css');
        if (existingStyle) existingStyle.remove();
        
        var style = document.createElement('style');
        style.id = 'shaka-custom-css';
        style.type = 'text/css';
        style.innerHTML = `$customCSS`;
        document.head.appendChild(style);
        
        // Function to hide specific UI elements
        function hideUI() {
          // Hide Material UI components (Copernicus uses MUI)
          document.querySelectorAll('[class*="MuiDrawer"], [class*="MuiAppBar"], [class*="MuiToolbar"], [class*="MuiFab"], [class*="MuiSpeedDial"]').forEach(function(el) {
            el.style.display = 'none';
          });
          
          // Hide any dialogs/modals
          document.querySelectorAll('[role="dialog"], [role="alertdialog"], [class*="MuiDialog"], [class*="MuiModal"]').forEach(function(el) {
            el.style.display = 'none';
          });
          
          // Hide backdrop/overlay
          document.querySelectorAll('[class*="MuiBackdrop"], [class*="backdrop"], [class*="overlay"]').forEach(function(el) {
            if (!el.classList.contains('maplibregl-canvas') && !el.classList.contains('mapboxgl-canvas')) {
              el.style.display = 'none';
            }
          });
          
          // Try to close any open dialogs by clicking close buttons
          document.querySelectorAll('[aria-label="close"], [aria-label="Close"], button[class*="close"]').forEach(function(btn) {
            try { btn.click(); } catch(e) {}
          });
          
          // Accept cookies if there's a consent dialog
          document.querySelectorAll('button').forEach(function(btn) {
            var text = btn.innerText || btn.textContent || '';
            if (text.toLowerCase().includes('accept') || text.toLowerCase().includes('agree') || text.toLowerCase().includes('ok')) {
              if (btn.closest('[class*="cookie"]') || btn.closest('[class*="consent"]') || btn.closest('[class*="Cookie"]')) {
                try { btn.click(); } catch(e) {}
              }
            }
          });
        }
        
        // Run multiple times to catch dynamically loaded content
        hideUI();
        setTimeout(hideUI, 1000);
        setTimeout(hideUI, 2000);
        setTimeout(hideUI, 4000);
        
        // Keep checking periodically
        setInterval(hideUI, 3000);
      })();
    ''';
    
    await _controller!.runJavaScript(jsCode);
  }

  String _buildCopernicusUrl() {
    // Build Copernicus MyOcean Viewer URL
    final timestamp = _dataDate.millisecondsSinceEpoch;
    
    // Get enabled layers and build product IDs
    // Copernicus product IDs for each layer type
    final productIds = <String>[];
    
    if (_layerStates['sst'] == true) {
      productIds.add('SST_GLO_SST_L4_NRT_OBSERVATIONS_010_001');
    }
    if (_layerStates['chl'] == true) {
      productIds.add('OCEANCOLOUR_GLO_BGC_L3_NRT_009_101');
    }
    if (_layerStates['zsd'] == true) {
      productIds.add('OCEANCOLOUR_GLO_BGC_L3_NRT_009_101'); // ZSD from same product
    }
    if (_layerStates['ssh'] == true) {
      productIds.add('SEALEVEL_GLO_PHY_L4_NRT_008_046');
    }
    if (_layerStates['currents'] == true) {
      productIds.add('GLOBAL_ANALYSISFORECAST_PHY_001_024');
    }
    if (_layerStates['wind'] == true) {
      productIds.add('WIND_GLO_PHY_L4_NRT_012_004');
    }
    
    // Build URL - the viewer will open with product selection
    // Using the viewer without pre-encoded layers for simplicity
    // The CSS injection will hide their layer UI, but the map will show selected products
    var url = 'https://data.marine.copernicus.eu/viewer/expert?'
        'view=viewer'
        '&crs=epsg%3A4326'
        '&t=$timestamp'
        '&z=0'
        '&center=${_centerLon}%2C${_centerLat}'
        '&zoom=${_zoom.toStringAsFixed(1)}'
        '&basemap=dark';
    
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
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                    Icon(Icons.layers, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Data Layers',
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
              // Layer toggles
              ..._layerInfo.entries.map((entry) {
                final id = entry.key;
                final info = entry.value;
                final isEnabled = _layerStates[id] ?? false;
                
                return ListTile(
                  leading: Icon(
                    info['icon'] as IconData,
                    color: isEnabled ? info['color'] as Color : Colors.white38,
                  ),
                  title: Text(
                    info['name'] as String,
                    style: TextStyle(
                      color: isEnabled ? Colors.white : Colors.white54,
                      fontWeight: isEnabled ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  trailing: Switch(
                    value: isEnabled,
                    activeColor: info['color'] as Color,
                    onChanged: (value) {
                      setModalState(() {
                        _layerStates[id] = value;
                      });
                      setState(() {});
                      // Reload WebView with new layers
                      _reloadWithCurrentSettings();
                    },
                  ),
                  onTap: () {
                    setModalState(() {
                      _layerStates[id] = !isEnabled;
                    });
                    setState(() {});
                    _reloadWithCurrentSettings();
                  },
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showDatePicker() async {
    final nowUtc = DateTime.now().toUtc();
    final yesterday = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day - 1);
    
    final picked = await showDatePicker(
      context: context,
      initialDate: _dataDate,
      firstDate: DateTime.utc(2020, 1, 1),
      lastDate: yesterday,
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
      _reloadWithCurrentSettings();
    }
  }

  void _reloadWithCurrentSettings() {
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
                  // Connection status
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _isOnline ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isOnline ? Colors.green : Colors.orange,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isOnline ? Icons.wifi : Icons.wifi_off,
                          color: _isOnline ? Colors.green : Colors.orange,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isOnline ? 'Live' : 'Offline',
                          style: TextStyle(
                            color: _isOnline ? Colors.green : Colors.orange,
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
