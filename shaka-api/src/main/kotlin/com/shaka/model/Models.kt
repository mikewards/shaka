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
    val currentStrength: String = ""
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
    val imageUrl: String? = null
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
    val chlorophyllA: Double?,
    val turbidity: Double?,
    val visibility: Double?,
    val dataSource: String
)
