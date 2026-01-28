package com.shaka.data.client

import com.shaka.model.TideData
import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.engine.cio.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import kotlin.math.abs

/**
 * Client for NOAA CO-OPS (Center for Operational Oceanographic Products and Services).
 * Free, no authentication required.
 * 
 * Provides real-time tide predictions and water level data for US coastal waters.
 * Covers Hawaii, California, and all US coastlines.
 * 
 * API: https://api.tidesandcurrents.noaa.gov/api/prod/
 * Station list: https://tidesandcurrents.noaa.gov/stations.html
 */
class NOAATidesClient {
    
    private val logger = LoggerFactory.getLogger(NOAATidesClient::class.java)
    
    private val client = HttpClient(CIO) {
        install(ContentNegotiation) {
            json(Json {
                ignoreUnknownKeys = true
                isLenient = true
            })
        }
    }

    companion object {
        private const val COOPS_URL = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"
        
        // Key tide stations for Hawaii and California (most commonly used)
        // Full list at: https://tidesandcurrents.noaa.gov/stations.html
        val HAWAII_STATIONS = mapOf(
            "1612340" to "Honolulu, Oahu",
            "1615680" to "Kahului, Maui",
            "1617433" to "Kawaihae, Big Island",
            "1617760" to "Hilo, Big Island",
            "1611400" to "Nawiliwili, Kauai",
            "1619910" to "Sand Island, Midway"
        )
        
        val CALIFORNIA_STATIONS = mapOf(
            "9410230" to "La Jolla, San Diego",
            "9410660" to "Los Angeles",
            "9410840" to "Santa Monica",
            "9411340" to "Santa Barbara",
            "9412110" to "Port San Luis",
            "9413450" to "Monterey",
            "9414290" to "San Francisco",
            "9414750" to "Alameda",
            "9415020" to "Point Reyes",
            "9416841" to "Arena Cove"
        )
        
        val FLORIDA_STATIONS = mapOf(
            "8724580" to "Key West",
            "8723214" to "Virginia Key, Miami",
            "8722670" to "Lake Worth Pier",
            "8720218" to "Mayport, Jacksonville",
            "8726520" to "St. Petersburg",
            "8726384" to "Port Manatee"
        )
        
        // Station coordinates for distance calculations
        val STATION_COORDINATES = mapOf(
            // Hawaii
            "1612340" to Pair(21.3067, -157.867),  // Honolulu
            "1615680" to Pair(20.895, -156.4767),   // Kahului
            "1617433" to Pair(20.0367, -155.83),    // Kawaihae
            "1617760" to Pair(19.7303, -155.06),    // Hilo
            "1611400" to Pair(21.9544, -159.357),   // Nawiliwili
            // California
            "9410230" to Pair(32.8669, -117.257),   // La Jolla
            "9410660" to Pair(33.72, -118.272),     // Los Angeles
            "9410840" to Pair(34.0083, -118.5),     // Santa Monica
            "9411340" to Pair(34.408, -119.685),    // Santa Barbara
            "9412110" to Pair(35.1767, -120.76),    // Port San Luis
            "9413450" to Pair(36.605, -121.888),    // Monterey
            "9414290" to Pair(37.8067, -122.465),   // San Francisco
            "9415020" to Pair(37.9961, -122.976),   // Point Reyes
            // Florida
            "8724580" to Pair(24.5508, -81.808),    // Key West
            "8723214" to Pair(25.7317, -80.1617),   // Virginia Key
            "8726520" to Pair(27.7606, -82.627)     // St. Petersburg
        )
    }

    /**
     * Get tide predictions for a location on a specific date.
     * Finds the nearest tide station and returns predictions.
     * 
     * @param lat Latitude
     * @param lon Longitude
     * @param date Date in YYYY-MM-DD format
     * @return TideData with predictions, or estimated data if unavailable
     */
    suspend fun getTideData(lat: Double, lon: Double, date: String): TideData {
        return try {
            val stationId = findNearestStation(lat, lon)
            if (stationId != null) {
                getTidePredictions(stationId, date)
            } else {
                logger.debug("No nearby tide station found for ($lat, $lon)")
                estimateTideData(lat, lon, date)
            }
        } catch (e: Exception) {
            logger.warn("Tide data fetch failed: ${e.message}")
            estimateTideData(lat, lon, date)
        }
    }

    /**
     * Find the nearest NOAA tide station to a given location.
     * Returns station ID or null if no station within reasonable distance.
     */
    fun findNearestStation(lat: Double, lon: Double): String? {
        var nearestStation: String? = null
        var minDistance = Double.MAX_VALUE
        
        for ((stationId, coords) in STATION_COORDINATES) {
            val distance = haversineDistance(lat, lon, coords.first, coords.second)
            if (distance < minDistance) {
                minDistance = distance
                nearestStation = stationId
            }
        }
        
        // Only return if within 200km (tide predictions less accurate beyond this)
        return if (minDistance <= 200) nearestStation else null
    }

    /**
     * Get tide predictions from NOAA CO-OPS API for a specific station.
     */
    suspend fun getTidePredictions(stationId: String, date: String): TideData {
        try {
            // Format date for API (YYYYMMDD)
            val dateFormatted = date.replace("-", "")
            
            // Get high/low tide predictions for the day
            val url = buildString {
                append(COOPS_URL)
                append("?station=$stationId")
                append("&begin_date=$dateFormatted")
                append("&end_date=$dateFormatted")
                append("&product=predictions")
                append("&datum=MLLW")  // Mean Lower Low Water
                append("&time_zone=lst_ldt")  // Local time with DST
                append("&units=english")  // Feet
                append("&interval=hilo")  // High/Low only
                append("&format=json")
            }
            
            logger.debug("Fetching tides: $url")
            val response: String = client.get(url).bodyAsText()
            
            return parseTidePredictions(response, date)
        } catch (e: Exception) {
            logger.warn("Tide prediction fetch failed for station $stationId: ${e.message}")
            throw e
        }
    }

    /**
     * Parse tide predictions from NOAA CO-OPS JSON response.
     */
    private fun parseTidePredictions(jsonResponse: String, date: String): TideData {
        try {
            // Parse the predictions array
            val predictionsRegex = """"predictions"\s*:\s*\[(.*?)\]""".toRegex(RegexOption.DOT_MATCHES_ALL)
            val predictionsMatch = predictionsRegex.find(jsonResponse)
            
            if (predictionsMatch != null) {
                val predictionsJson = predictionsMatch.groupValues[1]
                
                // Extract individual predictions
                val predictionRegex = """\{\s*"t"\s*:\s*"([^"]+)"\s*,\s*"v"\s*:\s*"([^"]+)"\s*,\s*"type"\s*:\s*"([^"]+)"\s*\}""".toRegex()
                val predictions = predictionRegex.findAll(predictionsJson).toList()
                
                var nextHighTide = ""
                var nextLowTide = ""
                var currentHeight = 0.0
                var tideState = "unknown"
                
                val now = LocalDateTime.now()
                val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")
                
                for (pred in predictions) {
                    val time = pred.groupValues[1]  // "2026-01-28 05:42"
                    val height = pred.groupValues[2].toDoubleOrNull() ?: 0.0
                    val type = pred.groupValues[3]  // "H" or "L"
                    
                    try {
                        val predTime = LocalDateTime.parse(time, formatter)
                        
                        if (predTime.isAfter(now)) {
                            if (type == "H" && nextHighTide.isEmpty()) {
                                nextHighTide = "${predTime.format(DateTimeFormatter.ofPattern("h:mma"))} (${String.format("%.1f", height)}ft)"
                                // If next is high, we're rising
                                if (tideState == "unknown") tideState = "rising"
                            } else if (type == "L" && nextLowTide.isEmpty()) {
                                nextLowTide = "${predTime.format(DateTimeFormatter.ofPattern("h:mma"))} (${String.format("%.1f", height)}ft)"
                                // If next is low, we're falling
                                if (tideState == "unknown") tideState = "falling"
                            }
                        }
                        
                        // Estimate current height based on nearest prediction
                        if (abs(java.time.Duration.between(now, predTime).toMinutes()) < 180) {
                            currentHeight = height
                        }
                    } catch (e: Exception) {
                        logger.debug("Failed to parse prediction time: $time")
                    }
                }
                
                return TideData(
                    currentHeight = currentHeight,
                    nextHighTide = nextHighTide.ifEmpty { "N/A" },
                    nextLowTide = nextLowTide.ifEmpty { "N/A" },
                    tideState = tideState
                )
            }
            
            throw Exception("No predictions found in response")
        } catch (e: Exception) {
            logger.debug("Tide parsing failed: ${e.message}")
            throw e
        }
    }

    /**
     * Estimate tide data when no station is available.
     * Uses basic tidal patterns (not location-specific).
     */
    private fun estimateTideData(lat: Double, lon: Double, date: String): TideData {
        // Simple estimation based on lunar cycle (very approximate)
        val hour = LocalDateTime.now().hour
        val tideState = when {
            hour in 0..5 -> "low"
            hour in 6..11 -> "rising"
            hour in 12..17 -> "high"
            else -> "falling"
        }
        
        return TideData(
            currentHeight = if (tideState in listOf("high", "rising")) 4.5 else 1.5,
            nextHighTide = "Estimated",
            nextLowTide = "Estimated",
            tideState = tideState
        )
    }

    /**
     * Calculate distance between two points using Haversine formula.
     * Returns distance in kilometers.
     */
    private fun haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val R = 6371.0 // Earth's radius in km
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                Math.sin(dLon / 2) * Math.sin(dLon / 2)
        val c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        return R * c
    }
}
