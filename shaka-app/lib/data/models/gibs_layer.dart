import 'package:flutter/material.dart';

/// Categories for GIBS satellite imagery layers
/// Order determines display order in the layer picker
enum GibsLayerCategory {
  chlorophyll,
  seaSurfaceTemp,
  trueColor;

  String get displayName {
    switch (this) {
      case GibsLayerCategory.chlorophyll:
        return 'Chlorophyll';
      case GibsLayerCategory.seaSurfaceTemp:
        return 'Sea Surface Temperature';
      case GibsLayerCategory.trueColor:
        return 'True Color';
    }
  }
}

/// Represents a NASA GIBS satellite imagery layer
class GibsLayer {
  final String id;
  final String name;
  final String shortName;
  final String description;
  final String resolution;
  final int maxZoom;
  final GibsLayerCategory category;
  final Color color;
  final IconData icon;
  final String format;
  
  /// Associated orbit track layer IDs (ascending/descending)
  final String? orbitTrackAscending;
  final String? orbitTrackDescending;
  
  /// Typical equator crossing time (local solar time)
  final String? equatorCrossingTime;
  
  /// Satellite platform name for display
  final String? satellite;
  
  /// Start date when data became available
  final DateTime? dataStartDate;
  
  /// Legend colors for the color scale (left to right)
  final List<Color>? legendColors;
  
  /// Legend labels (min to max)
  final List<String>? legendLabels;
  
  /// Legend unit (e.g., "mg/m³", "°C")
  final String? legendUnit;

  const GibsLayer({
    required this.id,
    required this.name,
    required this.shortName,
    required this.description,
    required this.resolution,
    required this.maxZoom,
    required this.category,
    required this.color,
    required this.icon,
    this.format = 'png',
    this.orbitTrackAscending,
    this.orbitTrackDescending,
    this.equatorCrossingTime,
    this.satellite,
    this.dataStartDate,
    this.legendColors,
    this.legendLabels,
    this.legendUnit,
  });
  
  /// Whether this layer has legend data available
  bool get hasLegend => legendColors != null && legendColors!.isNotEmpty;
  
  /// Whether this layer has orbit track data available
  bool get hasOrbitTrack => orbitTrackAscending != null || orbitTrackDescending != null;

  /// Default layer to show when opening GIBS viewer
  static GibsLayer get defaultLayer => modisTerraTrueColor;

  /// Get all layers for a specific category
  static List<GibsLayer> byCategory(GibsLayerCategory category) {
    return allLayers.where((layer) => layer.category == category).toList();
  }

  /// All available GIBS layers
  static List<GibsLayer> get allLayers => [
        // True Color layers
        modisTerraTrueColor,
        modisAquaTrueColor,
        viirsTrueColor,
        // Sea Surface Temperature layers
        murSST,
        g1SST,
        // Chlorophyll layers (ordered by data quality/recency)
        paceChlorophyll,
        noaa20Chlorophyll,
        noaa21Chlorophyll,
        sentinel3aChlorophyll,
        sentinel3bChlorophyll,
      ];

  // ==================== True Color Layers ====================
  // Note: maxZoom corresponds to GoogleMapsCompatible_Level{N} in EPSG:3857

  static final modisTerraTrueColor = GibsLayer(
    id: 'MODIS_Terra_CorrectedReflectance_TrueColor',
    name: 'MODIS Terra True Color',
    shortName: 'Terra True Color',
    description:
        'True color imagery from the MODIS instrument aboard NASA\'s Terra satellite. '
        'Shows Earth as the human eye would see it from space. Updated daily.',
    resolution: '250m',
    maxZoom: 9, // GoogleMapsCompatible_Level9
    category: GibsLayerCategory.trueColor,
    color: Color(0xFF4CAF50),
    icon: Icons.satellite_alt,
    format: 'jpg',
    satellite: 'Terra',
    orbitTrackAscending: 'OrbitTracks_Terra_Ascending',
    orbitTrackDescending: 'OrbitTracks_Terra_Descending',
    equatorCrossingTime: '~10:30 local',
    dataStartDate: DateTime(2000, 2, 24),
  );

  static final modisAquaTrueColor = GibsLayer(
    id: 'MODIS_Aqua_CorrectedReflectance_TrueColor',
    name: 'MODIS Aqua True Color',
    shortName: 'Aqua True Color',
    description:
        'True color imagery from the MODIS instrument aboard NASA\'s Aqua satellite. '
        'Captures afternoon passes with different lighting than Terra.',
    resolution: '250m',
    maxZoom: 9, // GoogleMapsCompatible_Level9
    category: GibsLayerCategory.trueColor,
    color: Color(0xFF2196F3),
    icon: Icons.satellite_alt,
    format: 'jpg',
    satellite: 'Aqua',
    orbitTrackAscending: 'OrbitTracks_Aqua_Ascending',
    orbitTrackDescending: 'OrbitTracks_Aqua_Descending',
    equatorCrossingTime: '~13:30 local',
    dataStartDate: DateTime(2002, 7, 4),
  );

  static final viirsTrueColor = GibsLayer(
    id: 'VIIRS_NOAA20_CorrectedReflectance_TrueColor',
    name: 'VIIRS NOAA-20 True Color',
    shortName: 'VIIRS True Color',
    description:
        'True color imagery from the VIIRS instrument aboard NOAA-20. '
        'Higher resolution and more recent data than MODIS.',
    resolution: '250m',
    maxZoom: 9, // GoogleMapsCompatible_Level9
    category: GibsLayerCategory.trueColor,
    color: Color(0xFF9C27B0),
    icon: Icons.satellite_alt,
    format: 'jpg',
    satellite: 'NOAA-20',
    orbitTrackAscending: 'OrbitTracks_NOAA-20_Ascending',
    orbitTrackDescending: 'OrbitTracks_NOAA-20_Descending',
    equatorCrossingTime: '~13:30 local',
    dataStartDate: DateTime(2017, 11, 29),
  );

  // ==================== Sea Surface Temperature Layers ====================
  // SST products are composites from multiple satellites, no single orbit track

  // SST color scale: cold (blue) -> warm (red)
  static const _sstLegendColors = [
    Color(0xFF0000FF), // Blue - cold
    Color(0xFF00FFFF), // Cyan
    Color(0xFF00FF00), // Green
    Color(0xFFFFFF00), // Yellow
    Color(0xFFFF8000), // Orange
    Color(0xFFFF0000), // Red - hot
  ];
  
  static final murSST = GibsLayer(
    id: 'GHRSST_L4_MUR_Sea_Surface_Temperature',
    name: 'MUR Sea Surface Temperature',
    shortName: 'MUR SST',
    description:
        'Multi-scale Ultra-high Resolution (MUR) SST analysis. '
        'Combines data from multiple satellites for gap-free global coverage. '
        'Excellent for identifying currents and upwelling zones.',
    resolution: '1km',
    maxZoom: 7, // GoogleMapsCompatible_Level7
    category: GibsLayerCategory.seaSurfaceTemp,
    color: Color(0xFFFF5722),
    icon: Icons.thermostat,
    satellite: 'Multi-satellite',
    dataStartDate: DateTime(2002, 6, 1),
    legendColors: _sstLegendColors,
    legendLabels: ['-2°C', '10°C', '20°C', '35°C'],
    legendUnit: '°C',
  );

  static final g1SST = GibsLayer(
    id: 'GHRSST_L4_G1SST_Sea_Surface_Temperature',
    name: 'G1SST Sea Surface Temperature',
    shortName: 'G1SST',
    description:
        'Global 1km SST (G1SST) analysis from JPL. '
        'Near real-time SST with high spatial resolution. '
        'Great for identifying thermal fronts and fish aggregation zones.',
    resolution: '1km',
    maxZoom: 7, // GoogleMapsCompatible_Level7
    category: GibsLayerCategory.seaSurfaceTemp,
    color: Color(0xFFE91E63),
    icon: Icons.thermostat,
    satellite: 'Multi-satellite',
    dataStartDate: DateTime(2010, 6, 9),
    legendColors: _sstLegendColors,
    legendLabels: ['-2°C', '10°C', '20°C', '35°C'],
    legendUnit: '°C',
  );

  // ==================== Chlorophyll Layers ====================
  // Updated to use currently active satellite data sources
  // Ordered by data quality and recency
  
  // Chlorophyll color scale: low (purple/blue) -> high (red/brown)
  // Based on standard ocean color chlorophyll-a visualization
  static const _chlorophyllLegendColors = [
    Color(0xFF4400AA), // Purple - very low
    Color(0xFF0044FF), // Blue - low
    Color(0xFF00AAFF), // Light blue
    Color(0xFF00FFAA), // Cyan-green
    Color(0xFF00FF00), // Green - medium
    Color(0xFFAAFF00), // Yellow-green
    Color(0xFFFFFF00), // Yellow
    Color(0xFFFFAA00), // Orange
    Color(0xFFFF4400), // Red-orange - high
    Color(0xFF880000), // Dark red - very high
  ];

  /// PACE OCI - Newest and highest quality hyperspectral ocean color sensor
  static final paceChlorophyll = GibsLayer(
    id: 'OCI_PACE_Chlorophyll_a',
    name: 'PACE OCI Chlorophyll-a',
    shortName: 'PACE Chlorophyll',
    description:
        'Ocean chlorophyll from NASA\'s PACE satellite (launched Feb 2024). '
        'Hyperspectral ocean color provides the most detailed phytoplankton data. '
        'Best for identifying productive fishing areas and water quality.',
    resolution: '1km',
    maxZoom: 7, // GoogleMapsCompatible_Level7
    category: GibsLayerCategory.chlorophyll,
    color: Color(0xFF2196F3),
    icon: Icons.grass,
    satellite: 'PACE',
    orbitTrackAscending: 'OrbitTracks_PACE_Ascending',
    orbitTrackDescending: 'OrbitTracks_PACE_Descending',
    equatorCrossingTime: '~13:00 local',
    dataStartDate: DateTime(2024, 2, 25),
    legendColors: _chlorophyllLegendColors,
    legendLabels: ['<0.01', '~0.5', '20+'],
    legendUnit: 'mg/m³',
  );

  /// NOAA-20 VIIRS - Primary operational afternoon chlorophyll
  static final noaa20Chlorophyll = GibsLayer(
    id: 'VIIRS_NOAA20_Chlorophyll_a',
    name: 'NOAA-20 VIIRS Chlorophyll-a',
    shortName: 'NOAA-20 Chlorophyll',
    description:
        'Ocean chlorophyll from VIIRS aboard NOAA-20. '
        'Excellent continuity and coverage with afternoon passes. '
        'Great for tracking daily chlorophyll changes.',
    resolution: '1km',
    maxZoom: 7, // GoogleMapsCompatible_Level7
    category: GibsLayerCategory.chlorophyll,
    color: Color(0xFF4CAF50),
    icon: Icons.grass,
    satellite: 'NOAA-20',
    orbitTrackAscending: 'OrbitTracks_NOAA-20_Ascending',
    orbitTrackDescending: 'OrbitTracks_NOAA-20_Descending',
    equatorCrossingTime: '~13:30 local',
    dataStartDate: DateTime(2017, 12, 13),
    legendColors: _chlorophyllLegendColors,
    legendLabels: ['<0.01', '~0.5', '20+'],
    legendUnit: 'mg/m³',
  );

  /// NOAA-21 VIIRS - Newest VIIRS, backup to NOAA-20
  static final noaa21Chlorophyll = GibsLayer(
    id: 'VIIRS_NOAA21_Chlorophyll_a',
    name: 'NOAA-21 VIIRS Chlorophyll-a',
    shortName: 'NOAA-21 Chlorophyll',
    description:
        'Ocean chlorophyll from VIIRS aboard NOAA-21 (launched 2022). '
        'Latest VIIRS sensor with improved calibration. '
        'Complements NOAA-20 for better temporal coverage.',
    resolution: '1km',
    maxZoom: 7, // GoogleMapsCompatible_Level7
    category: GibsLayerCategory.chlorophyll,
    color: Color(0xFF8BC34A),
    icon: Icons.grass,
    satellite: 'NOAA-21',
    orbitTrackAscending: 'OrbitTracks_NOAA-21_Ascending',
    orbitTrackDescending: 'OrbitTracks_NOAA-21_Descending',
    equatorCrossingTime: '~13:30 local',
    dataStartDate: DateTime(2023, 3, 31),
    legendColors: _chlorophyllLegendColors,
    legendLabels: ['<0.01', '~0.5', '20+'],
    legendUnit: 'mg/m³',
  );

  /// Sentinel-3A OLCI - Morning pass provides different time of day
  static final sentinel3aChlorophyll = GibsLayer(
    id: 'S3A_OLCI_Chlorophyll_a',
    name: 'Sentinel-3A OLCI Chlorophyll-a',
    shortName: 'Sentinel-3A Chlorophyll',
    description:
        'Ocean chlorophyll from ESA\'s Sentinel-3A OLCI sensor. '
        'Morning passes (~10:00 local) complement afternoon satellites. '
        'Useful for seeing chlorophyll at different times of day.',
    resolution: '1km',
    maxZoom: 7, // GoogleMapsCompatible_Level7
    category: GibsLayerCategory.chlorophyll,
    color: Color(0xFF009688),
    icon: Icons.grass,
    satellite: 'Sentinel-3A',
    orbitTrackAscending: 'OrbitTracks_Sentinel-3A_Ascending',
    orbitTrackDescending: 'OrbitTracks_Sentinel-3A_Descending',
    equatorCrossingTime: '~10:00 local',
    dataStartDate: DateTime(2016, 4, 25),
    legendColors: _chlorophyllLegendColors,
    legendLabels: ['<0.01', '~0.5', '20+'],
    legendUnit: 'mg/m³',
  );

  /// Sentinel-3B OLCI - Backup morning pass
  static final sentinel3bChlorophyll = GibsLayer(
    id: 'S3B_OLCI_Chlorophyll_a',
    name: 'Sentinel-3B OLCI Chlorophyll-a',
    shortName: 'Sentinel-3B Chlorophyll',
    description:
        'Ocean chlorophyll from ESA\'s Sentinel-3B OLCI sensor. '
        'Works in tandem with Sentinel-3A for improved revisit time. '
        'Morning passes provide alternative viewing geometry.',
    resolution: '1km',
    maxZoom: 7, // GoogleMapsCompatible_Level7
    category: GibsLayerCategory.chlorophyll,
    color: Color(0xFF00BCD4),
    icon: Icons.grass,
    satellite: 'Sentinel-3B',
    orbitTrackAscending: 'OrbitTracks_Sentinel-3B_Ascending',
    orbitTrackDescending: 'OrbitTracks_Sentinel-3B_Descending',
    equatorCrossingTime: '~10:00 local',
    dataStartDate: DateTime(2018, 5, 14),
    legendColors: _chlorophyllLegendColors,
    legendLabels: ['<0.01', '~0.5', '20+'],
    legendUnit: 'mg/m³',
  );
}

/// Preset layer combinations for quick multi-layer selection
class GibsLayerPreset {
  final String id;
  final String name;
  final String description;
  final List<GibsLayer> layers;
  final IconData icon;
  final Color color;

  const GibsLayerPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.layers,
    required this.icon,
    required this.color,
  });

  /// All available presets
  static List<GibsLayerPreset> get allPresets => [
    fullCoverage,
    afternoonSatellites,
    morningSatellites,
  ];

  /// Full coverage - all chlorophyll satellites combined for maximum coverage
  static final fullCoverage = GibsLayerPreset(
    id: 'full_coverage',
    name: 'Full Coverage',
    description: 'All 5 chlorophyll satellites combined for maximum coverage',
    layers: [
      GibsLayer.paceChlorophyll,
      GibsLayer.noaa20Chlorophyll,
      GibsLayer.noaa21Chlorophyll,
      GibsLayer.sentinel3aChlorophyll,
      GibsLayer.sentinel3bChlorophyll,
    ],
    icon: Icons.layers,
    color: Color(0xFF2196F3),
  );

  /// Afternoon satellites - PACE + NOAA-20/21 (US afternoon passes)
  static final afternoonSatellites = GibsLayerPreset(
    id: 'afternoon',
    name: 'Afternoon',
    description: 'PACE + NOAA-20/21 afternoon passes',
    layers: [
      GibsLayer.paceChlorophyll,
      GibsLayer.noaa20Chlorophyll,
      GibsLayer.noaa21Chlorophyll,
    ],
    icon: Icons.wb_sunny,
    color: Color(0xFFFF9800),
  );

  /// Morning satellites - Sentinel-3A/B (European morning passes)
  static final morningSatellites = GibsLayerPreset(
    id: 'morning',
    name: 'Morning',
    description: 'Sentinel-3A/B morning passes',
    layers: [
      GibsLayer.sentinel3aChlorophyll,
      GibsLayer.sentinel3bChlorophyll,
    ],
    icon: Icons.wb_twilight,
    color: Color(0xFF9C27B0),
  );
}
