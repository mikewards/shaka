import 'package:flutter/material.dart';

/// Represents an ocean data layer that can be displayed on the chart
class OceanLayer {
  final String id;
  final String name;
  final String shortName;
  final String wmtsLayer;
  final String style;
  final String unit;
  final IconData icon;
  final Color color;
  final double minValue;
  final double maxValue;
  final String description;
  final Duration updateFrequency;

  const OceanLayer({
    required this.id,
    required this.name,
    required this.shortName,
    required this.wmtsLayer,
    required this.style,
    required this.unit,
    required this.icon,
    required this.color,
    required this.minValue,
    required this.maxValue,
    required this.description,
    required this.updateFrequency,
  });

  /// Pre-defined ocean layers from Copernicus Marine Service
  /// Updated Jan 28, 2026 with verified dataset versions from data.marine.copernicus.eu
  /// Layer format: PRODUCT_ID/DATASET_ID/VARIABLE_ID
  static const sst = OceanLayer(
    id: 'sst',
    name: 'Sea Surface Temperature',
    shortName: 'SST',
    wmtsLayer: 'GLOBAL_ANALYSISFORECAST_PHY_001_024/cmems_mod_glo_phy-thetao_anfc_0.083deg_PT6H-i_202406/thetao',
    style: 'cmap:thermal',
    unit: '°F',
    icon: Icons.thermostat,
    color: Color(0xFFFF6B35),
    minValue: 50,
    maxValue: 86,
    description: 'Water temperature at the surface',
    updateFrequency: Duration(hours: 6),
  );

  static const chlorophyll = OceanLayer(
    id: 'chl',
    name: 'Chlorophyll-a',
    shortName: 'CHL',
    // OLCI sensor dataset 202511 - has data through Jan 27+ (more current than multi-sensor 202411)
    wmtsLayer: 'OCEANCOLOUR_GLO_BGC_L3_NRT_009_101/cmems_obs-oc_glo_bgc-plankton_nrt_l3-olci-4km_P1D_202511/CHL',
    style: 'cmap:algae,logScale',
    unit: 'mg/m³',
    icon: Icons.grass,
    color: Color(0xFF4CAF50),
    minValue: 0.01,
    maxValue: 10,
    description: 'Phytoplankton concentration',
    updateFrequency: Duration(days: 1),
  );

  static const visibility = OceanLayer(
    id: 'zsd',
    name: 'Water Visibility',
    shortName: 'VIS',
    // Transparency dataset - Secchi disk depth (ZSD)
    wmtsLayer: 'OCEANCOLOUR_GLO_BGC_L3_NRT_009_101/cmems_obs-oc_glo_bgc-transp_nrt_l3-multi-4km_P1D_202311/ZSD',
    style: 'cmap:ice',
    unit: 'm',
    icon: Icons.visibility,
    color: Color(0xFF2196F3),
    minValue: 0,
    maxValue: 50,
    description: 'Underwater visibility depth',
    updateFrequency: Duration(days: 1),
  );

  static const seaHeight = OceanLayer(
    id: 'ssh',
    name: 'Sea Surface Height',
    shortName: 'SSH',
    // Sea level L4 NRT - 0.25deg daily (verified active dataset)
    wmtsLayer: 'SEALEVEL_GLO_PHY_L4_NRT_008_046/cmems_obs-sl_glo_phy-ssh_nrt_allsat-l4-duacs-0.25deg_P1D_202411/adt',
    style: 'cmap:balance',
    unit: 'm',
    icon: Icons.waves,
    color: Color(0xFF9C27B0),
    minValue: -0.5,
    maxValue: 0.5,
    description: 'Sea surface height anomaly',
    updateFrequency: Duration(days: 1),
  );

  static const currents = OceanLayer(
    id: 'cur',
    name: 'Ocean Currents',
    shortName: 'CUR',
    wmtsLayer: 'GLOBAL_ANALYSISFORECAST_PHY_001_024/cmems_mod_glo_phy-cur_anfc_0.083deg_PT6H-i_202406/sea_water_velocity',
    style: 'vectorStyle:solidAndVector,cmap:speed',
    unit: 'm/s',
    icon: Icons.air,
    color: Color(0xFF00BCD4),
    minValue: 0,
    maxValue: 2,
    description: 'Current speed and direction',
    updateFrequency: Duration(hours: 6),
  );

  // Wind - hourly blended scatterometer + model wind
  static const wind = OceanLayer(
    id: 'wind',
    name: 'Wind (10m)',
    shortName: 'WIND',
    // Global Ocean Wind L4 NRT - hourly blended product with vector wind data
    // vectorStyle options: solid (color only), solidAndVector (color + arrows), vector (arrows only)
    wmtsLayer: 'WIND_GLO_PHY_L4_NRT_012_004/cmems_obs-wind_glo_phy_nrt_l4_0.125deg_PT1H_202207/wind',
    style: 'vectorStyle:solidAndVector,cmap:speed',
    unit: 'm/s',
    icon: Icons.air,
    color: Color(0xFF607D8B),
    minValue: 0,
    maxValue: 25,
    description: 'Surface wind speed and direction at 10m',
    updateFrequency: Duration(hours: 1),
  );

  // Wave Height - 3-hourly forecast
  static const waves = OceanLayer(
    id: 'waves',
    name: 'Wave Height',
    shortName: 'WAVES',
    wmtsLayer: 'GLOBAL_ANALYSISFORECAST_WAV_001_027/cmems_mod_glo_wav_anfc_0.083deg_PT3H-i_202411/VHM0',
    style: 'cmap:amp',
    unit: 'm',
    icon: Icons.waves,
    color: Color(0xFF3F51B5),
    minValue: 0,
    maxValue: 8,
    description: 'Significant wave height',
    updateFrequency: Duration(hours: 3),
  );

  // Salinity - daily
  static const salinity = OceanLayer(
    id: 'sal',
    name: 'Salinity',
    shortName: 'SAL',
    wmtsLayer: 'GLOBAL_ANALYSISFORECAST_PHY_001_024/cmems_mod_glo_phy-so_anfc_0.083deg_P1D-m_202406/so',
    style: 'cmap:haline',
    unit: 'PSU',
    icon: Icons.water_drop,
    color: Color(0xFF009688),
    minValue: 30,
    maxValue: 40,
    description: 'Sea water salinity',
    updateFrequency: Duration(days: 1),
  );

  // Mixed Layer Depth - daily (thermocline indicator)
  static const mixedLayerDepth = OceanLayer(
    id: 'mld',
    name: 'Mixed Layer Depth',
    shortName: 'MLD',
    wmtsLayer: 'GLOBAL_ANALYSISFORECAST_PHY_001_024/cmems_mod_glo_phy_anfc_0.083deg_P1D-m_202406/mlotst',
    style: 'cmap:deep',
    unit: 'm',
    icon: Icons.layers,
    color: Color(0xFF673AB7),
    minValue: 0,
    maxValue: 200,
    description: 'Thermocline depth - fish often stack here',
    updateFrequency: Duration(days: 1),
  );

  // Dissolved Oxygen - daily biogeochemistry
  static const oxygen = OceanLayer(
    id: 'o2',
    name: 'Dissolved Oxygen',
    shortName: 'O2',
    wmtsLayer: 'GLOBAL_ANALYSISFORECAST_BGC_001_028/cmems_mod_glo_bgc-bio_anfc_0.25deg_P1D-m_202311/o2',
    style: 'cmap:ice',
    unit: 'mmol/m³',
    icon: Icons.bubble_chart,
    color: Color(0xFFE91E63),
    minValue: 150,
    maxValue: 350,
    description: 'Oxygen levels - fish avoid low-O2 zones',
    updateFrequency: Duration(days: 1),
  );

  // Bathymetry uses GEBCO WMS - handled separately in ocean_charts_screen
  static const bathymetry = OceanLayer(
    id: 'bathy',
    name: 'Bathymetry',
    shortName: 'DEPTH',
    wmtsLayer: 'GEBCO', // Special marker - uses GEBCO WMS instead
    style: 'gebco_latest_2',
    unit: 'm',
    icon: Icons.terrain,
    color: Color(0xFF795548),
    minValue: 0,
    maxValue: 6000,
    description: 'Ocean floor depth',
    updateFrequency: Duration(days: 365),
  );

  /// All available layers - ordered by importance for fishing
  static const List<OceanLayer> all = [
    sst,           // Temperature affects fish behavior
    chlorophyll,   // Food chain indicator
    visibility,    // Spearfishing visibility
    waves,         // Safety / conditions
    wind,          // Safety / conditions
    currents,      // Fish congregation points
    mixedLayerDepth, // Thermocline - where fish stack
    salinity,      // Species preferences
    oxygen,        // Fish habitat suitability
    seaHeight,     // Currents / upwelling
    bathymetry,    // Depth / structure
  ];

  /// Get layer by ID
  static OceanLayer? byId(String id) {
    try {
      return all.firstWhere((layer) => layer.id == id);
    } catch (_) {
      return null;
    }
  }
}

/// State of a layer in the chart
class LayerState {
  final OceanLayer layer;
  final bool enabled;
  final double opacity;

  const LayerState({
    required this.layer,
    this.enabled = false,
    this.opacity = 1.0,
  });

  LayerState copyWith({
    bool? enabled,
    double? opacity,
  }) {
    return LayerState(
      layer: layer,
      enabled: enabled ?? this.enabled,
      opacity: opacity ?? this.opacity,
    );
  }
}
