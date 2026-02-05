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
    val accessibility: Int
)

@Serializable
data class SpotSummary(
    val id: String,
    val name: String,
    val coordinates: Coordinates,
    val shakaScore: Int,
    val confidence: Int,
    val conditions: SpotConditions,
    val expectedFish: List<String>,
    val gearRecommendations: List<String>,
    val risks: List<String>,
    val bestTimeOfDay: String,
    val satelliteReadings: GibsSatelliteReadings? = null  // Include cached GIBS data
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
    val satelliteReadings: GibsSatelliteReadings? = null,
    val regulations: RegulationInfo? = null,
    // NEW: Raw intel data for fishermen to interpret
    val vessels: VesselActivity? = null,      // Boats nearby from Global Fishing Watch
    val solunar: SolunarData? = null,         // Moon phase + feeding periods
    val waterContext: WaterContext? = null    // Chlorophyll trend + SST breaks
)

@Serializable
data class RegulationInfo(
    val regulatoryAgency: String,           // e.g., "DLNR Division of Aquatic Resources"
    val regulationsUrl: String,             // Link to official regulations page
    val licensingUrl: String? = null,       // Link to licensing page (if separate)
    val note: String? = null,               // e.g., "Spearfishing prohibited"
    val mpaStatus: MPAStatus? = null        // From ProtectedSeas API
)

@Serializable
data class MPAStatus(
    val isProtected: Boolean,
    val isInsideMPA: Boolean = false,       // True if spot is inside MPA boundary (not just nearby)
    val siteName: String? = null,           // e.g., "Hanauma Bay MLCD"
    val designation: String? = null,        // e.g., "Marine Life Conservation District"
    val spearfishingStatus: Int,            // 0=Allowed, 1=Prohibited, 2=Restricted, 3=Unknown
    val protectionLevel: Int,               // 1-5 Level of Fishing Protection
    val speciesOfConcern: String? = null,   // Protected species from ProtectedSeas
    val purpose: String? = null,            // Description of why area is protected
    val detailsUrl: String? = null          // navigator_link to full details
)

/**
 * Satellite imagery data for a spot.
 * 
 * IMPORTANT: The color fields are for DISPLAY ONLY - they show what the satellite captured
 * but may include sediment, kelp, or bottom reflectance in coastal areas.
 * 
 * For actual chlorophyll measurements, use noaaErddapChlorophyll which comes from
 * NOAA CoastWatch ERDDAP - a reliable numerical data source.
 */
@Serializable
data class GibsSatelliteReadings(
    // Satellite imagery colors (display only - may include sediment/kelp contamination)
    val paceTodayColor: String? = null,            // RGB hex "#RRGGBB" from PACE satellite
    val paceYesterdayColor: String? = null,
    val noaa20TodayColor: String? = null,          // RGB hex from NOAA-20 VIIRS
    val noaa20YesterdayColor: String? = null,
    val noaa21TodayColor: String? = null,          // RGB hex from NOAA-21 VIIRS
    val noaa21YesterdayColor: String? = null,
    val sentinel3aTodayColor: String? = null,      // RGB hex from Sentinel-3A OLCI
    val sentinel3aYesterdayColor: String? = null,
    val sentinel3bTodayColor: String? = null,      // RGB hex from Sentinel-3B OLCI
    val sentinel3bYesterdayColor: String? = null,
    // Observation timestamps (when the satellite passed over this location)
    val paceObservationTime: String? = null,       // ISO 8601 timestamp
    val noaa20ObservationTime: String? = null,
    val noaa21ObservationTime: String? = null,
    val dataDate: String? = null,                  // The date that "today" refers to
    // ACTUAL MEASURED CHLOROPHYLL from NOAA ERDDAP (trusted numerical data)
    val noaaErddapChlorophyll: Double? = null,     // mg/m³ - THE reliable chlorophyll value
    val noaaErddapFetchTime: String? = null        // When we fetched this data
)

@Serializable
data class AccessInfo(
    val directions: String,
    val parkingInfo: String,
    val permitRequired: Boolean = false
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
    val tideState: String,
    val nextHighTideTime: Long? = null,  // Epoch millis for next high tide
    val nextLowTideTime: Long? = null    // Epoch millis for next low tide
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

// ============================================
// FISHING INTEL MODELS
// Raw data for fishermen to interpret - no scores!
// ============================================

/**
 * Vessel activity from Global Fishing Watch.
 * Shows how many fishing boats are operating nearby.
 */
@Serializable
data class VesselActivity(
    val count: Int,                    // "8 vessels"
    val radiusNm: Int,                 // "within 10nm"
    val updatedAt: String              // ISO timestamp
)

/**
 * Solunar data - moon phase and feeding periods.
 * Fishermen have used solunar tables for decades.
 */
@Serializable
data class SolunarData(
    val moonPhase: String,             // "waning_gibbous", "full_moon", etc.
    val illumination: Int,             // 0-100 percent
    val majorPeriods: List<TimePeriod>,// ~2hr periods around moon overhead/underfoot
    val minorPeriods: List<TimePeriod>,// ~1hr periods around moonrise/moonset
    val dayRating: Int? = null,        // 0-100 overall day rating (optional)
    val hourlyRating: Map<String, Int>? = null // Hour-by-hour rating (optional)
)

/**
 * A time period (start to end).
 */
@Serializable
data class TimePeriod(
    val start: String,                 // "14:34" (24hr format)
    val end: String                    // "16:34"
)

/**
 * Enhanced water context with trends and nearby readings.
 * Allows fishermen to spot temperature breaks and chlorophyll spikes.
 */
@Serializable
data class WaterContext(
    val chlorophyll: ChlorophyllContext?,
    val sstNearby: List<SSTReading>?   // readings at N/S/E/W for break detection
)

/**
 * Chlorophyll with 7-day trend.
 * Rising chlorophyll = plankton bloom = bait = fish!
 */
@Serializable
data class ChlorophyllContext(
    val current: Double,               // 0.42 mg/m³
    val avg7day: Double,               // 0.15 mg/m³
    val trend: String                  // "rising", "falling", "stable"
)

/**
 * SST reading at a nearby point.
 * Temperature breaks are where fish congregate.
 */
@Serializable
data class SSTReading(
    val direction: String,             // "E", "W", "N", "S"
    val distanceNm: Int,               // 5
    val tempC: Double                  // 24.5
)

// ============================================
// USER SPOTS MODELS
// ============================================

@Serializable
data class CreateUserSpotRequest(
    val name: String,
    val latitude: Double,
    val longitude: Double
)

@Serializable
data class UserSpotResponse(
    val id: String,
    val name: String,
    val coordinates: Coordinates,
    val region: String,
    val country: String,
    val createdAt: String,
    val isUserSpot: Boolean = true,  // Always true, used by frontend to show "Saved" badge
    val shakaScore: Int? = null  // Latest score from cache (null if not yet calculated)
)

@Serializable
data class UserSpotListResponse(
    val spots: List<UserSpotResponse>,
    val count: Int,
    val limit: Int = 100
)

@Serializable
data class UserSpotDetailResponse(
    val spot: SpotDetail,
    val isUserSpot: Boolean = true
)
