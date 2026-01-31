package com.shaka.model

import kotlinx.serialization.Serializable

@Serializable
data class Coordinates(
    val lat: Double,
    val lon: Double
)

@Serializable
data class SpotConditions(
    val visibility: String,
    val waterTemp: String,
    val swell: String,
    val wind: String,
    val tideState: String = "",
    val currentStrength: String = "",
    // Data freshness indicators (from prefetch cache)
    val dataUpdatedMinutesAgo: Int? = null,      // "Updated 23 min ago"
    val satelliteDataDate: String? = null         // "Satellite: Jan 27"
)

@Serializable
data class ShakaScore(
    val overall: Int,
    val confidence: Int,
    val breakdown: ScoreBreakdown
)

@Serializable
data class ScoreBreakdown(
    val visibility: Int,
    val weather: Int,
    val swell: Int,
    val fishActivity: Int,
    val accessibility: Int,
    val safety: Int
)

@Serializable
data class SpotSummary(
    val id: String,
    val name: String,
    val coordinates: Coordinates,
    val shakaScore: Int,
    val confidence: Int,
    val access: String,
    val conditions: SpotConditions,
    val expectedFish: List<String>,
    val gearRecommendations: List<String>,
    val risks: List<String>,
    val bestTimeOfDay: String
)

@Serializable
data class SpotDetail(
    val id: String,
    val name: String,
    val description: String,
    val coordinates: Coordinates,
    val score: ShakaScore,
    val access: AccessInfo,
    val conditions: SpotConditions,
    val forecast: List<DayForecast>,
    val expectedFish: List<FishInfo>,
    val gearRecommendations: List<GearItem>,
    val risks: List<RiskInfo>,
    val communityReports: List<CommunityReport>,
    val bestTimeOfDay: String,
    val imageUrl: String? = null,
    val satelliteReadings: GibsSatelliteReadings? = null
)

@Serializable
data class GibsSatelliteReadings(
    val paceToday: Double? = null,
    val paceYesterday: Double? = null,
    val noaa20Today: Double? = null,
    val noaa20Yesterday: Double? = null,
    val noaa21Today: Double? = null,
    val noaa21Yesterday: Double? = null,
    val sentinel3aToday: Double? = null,
    val sentinel3aYesterday: Double? = null,
    val sentinel3bToday: Double? = null,
    val sentinel3bYesterday: Double? = null,
    val paceObservationTime: String? = null,      // ISO 8601 timestamp
    val noaa20ObservationTime: String? = null,
    val noaa21ObservationTime: String? = null,
    val dataDate: String? = null                   // The date that "today" refers to
)

@Serializable
data class AccessInfo(
    val type: String,
    val directions: String,
    val parkingInfo: String,
    val permitRequired: Boolean = false,
    val boatLaunchNearby: Boolean = false
)

@Serializable
data class DayForecast(
    val date: String,
    val shakaScore: Int,
    val confidence: Int,
    val conditions: SpotConditions
)

@Serializable
data class FishInfo(
    val name: String,
    val localName: String? = null,
    val likelihood: String,
    val seasonalNotes: String? = null
)

@Serializable
data class GearItem(
    val item: String,
    val reason: String,
    val essential: Boolean = false
)

@Serializable
data class RiskInfo(
    val risk: String,
    val severity: String,
    val mitigation: String
)

@Serializable
data class CommunityReport(
    val source: String,
    val date: String,
    val summary: String,
    val url: String? = null
)

@Serializable
data class SearchRequest(
    val lat: Double,
    val lon: Double,
    val radiusKm: Int = 50,
    val date: String
)

@Serializable
data class SearchResponse(
    val spots: List<SpotSummary>,
    val searchCenter: Coordinates,
    val radiusKm: Int,
    val date: String
)

@Serializable
data class SpotSearchResult(
    val id: String,
    val name: String,
    val region: String,
    val coordinates: Coordinates,
    val access: String,
    val shakaScore: Int = 0
)

@Serializable
data class BatchSpotsResponse(
    val spots: List<SpotSummary>,
    val date: String,
    val fetchedAt: String
)

@Serializable
data class RegionInfo(
    val id: String,
    val name: String,
    val spotCount: Int,
    val centerLat: Double = 0.0,
    val centerLon: Double = 0.0
)

@Serializable
data class WeatherData(
    val temperature: Double,
    val windSpeed: Double,
    val windDirection: Int,
    val precipitation: Double,
    val cloudCover: Int,
    val visibility: Double
)

@Serializable
data class OceanData(
    val waveHeight: Double,
    val wavePeriod: Double,
    val waveDirection: Int,
    val waterTemperature: Double,
    val swellHeight: Double,
    val swellDirection: Int
)

@Serializable
data class TideData(
    val currentHeight: Double,
    val nextHighTide: String,
    val nextLowTide: String,
    val tideState: String
)

@Serializable
data class WaterQuality(
    val chlorophyllA: Double?,        // mg/m³ - algae indicator (0.1-0.5 clear, 1-5 productive, >10 bloom)
    val turbidity: Double?,           // NTU - Total Suspended Matter (0-1 clear, 1-5 moderate, >5 murky)
    val visibility: Double?,          // meters - estimated underwater visibility
    val seaSurfaceTemp: Double?,      // °C - from NOAA or Copernicus
    val dataSource: String,           // Source attribution
    val chlorophyllCategory: String = categorizeChlorophyll(chlorophyllA),
    val turbidityCategory: String = categorizeTurbidity(turbidity),
    val visibilityCategory: String = categorizeVisibility(visibility)
) {
    companion object {
        fun categorizeChlorophyll(chl: Double?): String = when {
            chl == null -> "unknown"
            chl < 0.3 -> "excellent"     // Very clear, oligotrophic
            chl < 0.5 -> "good"          // Clear tropical/subtropical
            chl < 1.0 -> "moderate"      // Slightly productive
            chl < 3.0 -> "productive"    // Upwelling/coastal enrichment
            chl < 10.0 -> "high"         // Very productive
            else -> "bloom"              // Algae bloom conditions
        }
        
        fun categorizeTurbidity(turb: Double?): String = when {
            turb == null -> "unknown"
            turb < 1.0 -> "clear"        // Excellent clarity
            turb < 2.0 -> "good"         // Good visibility
            turb < 4.0 -> "moderate"     // Some suspended particles
            turb < 8.0 -> "murky"        // Reduced visibility
            else -> "poor"               // Very turbid
        }
        
        fun categorizeVisibility(vis: Double?): String = when {
            vis == null -> "unknown"
            vis >= 30.0 -> "exceptional" // Crystal clear (30m+)
            vis >= 20.0 -> "excellent"   // Very good (20-30m)
            vis >= 15.0 -> "good"        // Good (15-20m)
            vis >= 10.0 -> "moderate"    // Average (10-15m)
            vis >= 5.0 -> "fair"         // Below average (5-10m)
            else -> "poor"               // Poor (<5m)
        }
    }
}
