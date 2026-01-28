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

  /// All available layers
  static const List<OceanLayer> all = [sst, chlorophyll, visibility, seaHeight, currents, bathymetry];

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
