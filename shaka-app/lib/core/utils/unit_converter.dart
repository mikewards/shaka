import '../../data/services/unit_preference_service.dart';

/// Static utility class for unit conversion and formatting.
class UnitConverter {
  UnitConverter._();

  static const double _ftToM = 0.3048;
  static const double _mToFt = 3.28084;
  static const double _ktsToKmh = 1.852;
  static const double _miToKm = 1.60934;
  static const double _msToKts = 1.94384;

  // --- Temperature ---

  static double celsiusToFahrenheit(double c) => c * 9.0 / 5.0 + 32;

  static String formatTemperature(double? tempC, UnitSystem system) {
    if (tempC == null) return 'N/A';
    if (system == UnitSystem.metric) {
      return '${tempC.round()}°C';
    }
    return '${celsiusToFahrenheit(tempC).round()}°F';
  }

  static String formatTemperatureDual(double? tempC) {
    if (tempC == null) return 'N/A';
    final f = celsiusToFahrenheit(tempC).round();
    return '${tempC.round()}°C / $f°F';
  }

  // --- Swell / Wave Height ---

  static double feetToMeters(double ft) => ft * _ftToM;

  static String formatSwellHeight(double? heightFt, UnitSystem system) {
    if (heightFt == null) return 'N/A';
    if (system == UnitSystem.metric) {
      final m = feetToMeters(heightFt);
      return '${m.toStringAsFixed(1)}m';
    }
    final rounded = heightFt.roundToDouble() == heightFt
        ? '${heightFt.round()}'
        : heightFt.toStringAsFixed(1);
    return '${rounded}ft';
  }

  static String formatSwell(double? heightFt, double? periodSec, String? direction, UnitSystem system) {
    if (heightFt == null) return 'N/A';
    final height = formatSwellHeight(heightFt, system);
    final period = periodSec != null ? ' @ ${periodSec.round()}s' : '';
    final dir = direction != null ? ' $direction' : '';
    return '$height$period$dir';
  }

  // --- Wind Speed ---

  static double knotsToKmh(double kts) => kts * _ktsToKmh;

  static String formatWindSpeed(double? speedKts, UnitSystem system) {
    if (speedKts == null) return 'N/A';
    if (system == UnitSystem.metric) {
      return '${knotsToKmh(speedKts).round()} km/h';
    }
    return '${speedKts.round()} kts';
  }

  static String formatWind(double? speedKts, String? direction, UnitSystem system) {
    if (speedKts == null) return 'N/A';
    final speed = formatWindSpeed(speedKts, system);
    final dir = direction != null ? ' $direction' : '';
    return '$speed$dir';
  }

  // --- Tide Height ---

  static String formatTideHeight(double? heightFt, UnitSystem system) {
    if (heightFt == null) return '';
    if (system == UnitSystem.metric) {
      final m = feetToMeters(heightFt);
      return '${m.toStringAsFixed(2)} m';
    }
    return '${heightFt.toStringAsFixed(1)} ft';
  }

  static String formatTideHeightCompact(double heightFt, UnitSystem system) {
    if (system == UnitSystem.metric) {
      final m = feetToMeters(heightFt);
      return '${m.toStringAsFixed(2)}m';
    }
    return '${heightFt.toStringAsFixed(1)}ft';
  }

  // --- Depth ---

  static String formatDepth(double? depthM, UnitSystem system) {
    if (depthM == null) return 'N/A';
    if (system == UnitSystem.metric) {
      return '${depthM.toStringAsFixed(1)}m';
    }
    return '${(depthM * _mToFt).toStringAsFixed(0)}ft';
  }

  // --- Distance ---

  static String formatDistance(double? distanceMi, UnitSystem system) {
    if (distanceMi == null) return '';
    if (system == UnitSystem.metric) {
      return '${(distanceMi * _miToKm).toStringAsFixed(1)} km';
    }
    return '${distanceMi.toStringAsFixed(1)} mi';
  }

  // --- Chart values (m/s source) ---

  static String formatChartWind(double valueMs, UnitSystem system) {
    if (system == UnitSystem.imperial) {
      return '${(valueMs * _msToKts).toStringAsFixed(1)} kts';
    }
    return '${valueMs.toStringAsFixed(1)} m/s';
  }

  static String formatChartWaveHeight(double valueM, UnitSystem system) {
    if (system == UnitSystem.imperial) {
      return '${(valueM * _mToFt).toStringAsFixed(1)} ft';
    }
    return '${valueM.toStringAsFixed(1)} m';
  }

  static String formatChartSST(double valueC, UnitSystem system) {
    if (system == UnitSystem.imperial) {
      return '${celsiusToFahrenheit(valueC).round()}°F';
    }
    return '${valueC.toStringAsFixed(1)}°C';
  }

  // --- Unit labels for chart layers ---

  static String swellHeightUnit(UnitSystem system) =>
      system == UnitSystem.metric ? 'm' : 'ft';

  static String windSpeedUnit(UnitSystem system) =>
      system == UnitSystem.metric ? 'km/h' : 'kts';

  static String temperatureUnit(UnitSystem system) =>
      system == UnitSystem.metric ? '°C' : '°F';

  static String tideHeightUnit(UnitSystem system) =>
      system == UnitSystem.metric ? 'm' : 'ft';

  static String chartWindUnit(UnitSystem system) =>
      system == UnitSystem.metric ? 'm/s' : 'kts';

  static String chartWaveUnit(UnitSystem system) =>
      system == UnitSystem.metric ? 'm' : 'ft';

  static String chartSSTUnit(UnitSystem system) =>
      system == UnitSystem.metric ? '°C' : '°F';

  // --- Tide Y-axis value conversion (raw number for chart painting) ---

  static double convertTideValue(double heightFt, UnitSystem system) {
    if (system == UnitSystem.metric) return feetToMeters(heightFt);
    return heightFt;
  }
}
