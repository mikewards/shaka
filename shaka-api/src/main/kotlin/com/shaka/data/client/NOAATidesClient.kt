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
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Client for NOAA CO-OPS (Center for Operational Oceanographic Products and Services).
 * Free, no authentication required.
 * 
 * Dynamically discovers all ~3,400 NOAA tide prediction stations via the Metadata API
 * on first use, then caches the full station list in memory. Falls back to a small
 * hardcoded set if the metadata API is unavailable.
 * 
 * API: https://api.tidesandcurrents.noaa.gov/api/prod/
 * Metadata API: https://api.tidesandcurrents.noaa.gov/mdapi/prod/
 */
class NOAATidesClient {
    
    private val logger = LoggerFactory.getLogger(NOAATidesClient::class.java)
    
    private val client = HttpClient(CIO) {
        engine {
            requestTimeout = 15_000 // 15 seconds (metadata API can be slow)
        }
        install(ContentNegotiation) {
            json(Json {
                ignoreUnknownKeys = true
                isLenient = true
            })
        }
    }

    /**
     * Represents a NOAA tide prediction station with its coordinates and timezone.
     */
    data class StationInfo(
        val id: String,
        val name: String,
        val lat: Double,
        val lon: Double,
        val timezoneCorrHours: Int  // UTC offset in hours (e.g., -10 for Hawaii, -5 for EST)
    )

    companion object {
        private const val COOPS_URL = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"
        private const val METADATA_URL = "https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json?type=tidepredictions&units=english"
        
        // Maximum distance (km) to consider a station relevant for a spot.
        // With ~3,400 stations covering all US coasts, most spots will be much closer.
        private const val MAX_STATION_DISTANCE_KM = 200.0
        
        // Cached station list -- loaded once from NOAA Metadata API, persists for app lifetime.
        @Volatile
        private var cachedStations: List<StationInfo>? = null
        private val stationLoadLock = Any()
        
        // Hardcoded fallback stations (used only if Metadata API is unreachable)
        private val FALLBACK_STATIONS = listOf(
            // Hawaii
            StationInfo("1612340", "Honolulu", 21.3067, -157.867, -10),
            StationInfo("1615680", "Kahului", 20.895, -156.4767, -10),
            StationInfo("1617433", "Kawaihae", 20.0367, -155.83, -10),
            StationInfo("1617760", "Hilo", 19.7303, -155.06, -10),
            StationInfo("1611400", "Nawiliwili", 21.9544, -159.357, -10),
            // California
            StationInfo("9410230", "La Jolla", 32.8669, -117.257, -8),
            StationInfo("9410660", "Los Angeles", 33.72, -118.272, -8),
            StationInfo("9410840", "Santa Monica", 34.0083, -118.5, -8),
            StationInfo("9411340", "Santa Barbara", 34.408, -119.685, -8),
            StationInfo("9412110", "Port San Luis", 35.1767, -120.76, -8),
            StationInfo("9413450", "Monterey", 36.605, -121.888, -8),
            StationInfo("9414290", "San Francisco", 37.8067, -122.465, -8),
            StationInfo("9415020", "Point Reyes", 37.9961, -122.976, -8),
            // Florida
            StationInfo("8724580", "Key West", 24.5508, -81.808, -5),
            StationInfo("8723214", "Virginia Key", 25.7317, -80.1617, -5),
            StationInfo("8726520", "St. Petersburg", 27.7606, -82.627, -5)
        )
    }

    /**
     * Get the full list of NOAA tide prediction stations.
     * Fetches from the Metadata API on first call, then returns cached list.
     * Falls back to hardcoded stations if the API is unreachable.
     */
    private suspend fun getStations(): List<StationInfo> {
        cachedStations?.let { return it }
        
        return synchronized(stationLoadLock) {
            // Double-check after acquiring lock
            cachedStations?.let { return it }
            
            try {
                val stations = fetchStationsFromMetadataApi()
                cachedStations = stations
                logger.info("Loaded ${stations.size} NOAA tide prediction stations from Metadata API")
                stations
            } catch (e: Exception) {
                logger.warn("Failed to load NOAA stations from Metadata API, using ${FALLBACK_STATIONS.size} hardcoded fallback stations: ${e.message}")
                cachedStations = FALLBACK_STATIONS
                FALLBACK_STATIONS
            }
        }
    }

    /**
     * Fetch all tide prediction stations from the NOAA CO-OPS Metadata API.
     * Returns ~3,400 stations with coordinates and timezone info.
     */
    private suspend fun fetchStationsFromMetadataApi(): List<StationInfo> {
        val response: String = client.get(METADATA_URL).bodyAsText()
        
        // Parse the station list from JSON using regex (lightweight, no full JSON tree)
        val stations = mutableListOf<StationInfo>()
        
        // Match each station object in the array
        val stationRegex = """\{\s*"state"\s*:.*?"id"\s*:\s*"([^"]+)".*?"name"\s*:\s*"([^"]+)".*?"lat"\s*:\s*([-\d.]+).*?"lng"\s*:\s*([-\d.]+).*?\}""".toRegex(RegexOption.DOT_MATCHES_ALL)
        // Also need to extract timezonecorr from each station block
        val blockRegex = """\{[^{}]*"id"\s*:\s*"([^"]+)"[^{}]*\}""".toRegex(RegexOption.DOT_MATCHES_ALL)
        
        for (blockMatch in blockRegex.findAll(response)) {
            val block = blockMatch.value
            
            val id = Regex(""""id"\s*:\s*"([^"]+)"""").find(block)?.groupValues?.get(1) ?: continue
            val name = Regex(""""name"\s*:\s*"([^"]+)"""").find(block)?.groupValues?.get(1) ?: continue
            val lat = Regex(""""lat"\s*:\s*([-\d.eE+]+)""").find(block)?.groupValues?.get(1)?.toDoubleOrNull() ?: continue
            val lon = Regex(""""lng"\s*:\s*([-\d.eE+]+)""").find(block)?.groupValues?.get(1)?.toDoubleOrNull() ?: continue
            val tzCorr = Regex(""""timezonecorr"\s*:\s*([-\d]+)""").find(block)?.groupValues?.get(1)?.toIntOrNull() ?: continue
            
            stations.add(StationInfo(id, name, lat, lon, tzCorr))
        }
        
        if (stations.isEmpty()) {
            throw Exception("Parsed 0 stations from NOAA Metadata API response (${response.length} chars)")
        }
        
        return stations
    }

    /**
     * Get tide predictions for a location on a specific date.
     * Finds the nearest tide station and returns predictions.
     * 
     * @param lat Latitude
     * @param lon Longitude
     * @param date Date in YYYY-MM-DD format
     * @return TideData with real predictions, or null-valued data if no nearby station
     */
    suspend fun getTideData(lat: Double, lon: Double, date: String): TideData {
        return try {
            val station = findNearestStationInfo(lat, lon)
            if (station != null) {
                getTidePredictions(station, date)
            } else {
                logger.debug("No nearby tide station found for ($lat, $lon)")
                noTideData()
            }
        } catch (e: Exception) {
            logger.warn("Tide data fetch failed for ($lat, $lon): ${e.message}")
            noTideData()
        }
    }

    /**
     * Find the nearest NOAA tide station to a given location.
     * Returns station ID or null if no station within reasonable distance.
     * 
     * Public API for callers that just need the station ID (e.g., DataPrefetchJobs).
     */
    fun findNearestStation(lat: Double, lon: Double): String? {
        // Use the cached station list (or fallback) for synchronous callers.
        // If stations haven't been loaded yet, use fallback.
        val stations = cachedStations ?: FALLBACK_STATIONS
        return findNearestInList(lat, lon, stations)?.id
    }

    /**
     * Find the nearest station with full metadata (id, coordinates, timezone).
     * Uses the dynamically-loaded full station list when available.
     */
    private suspend fun findNearestStationInfo(lat: Double, lon: Double): StationInfo? {
        val stations = getStations()
        return findNearestInList(lat, lon, stations)
    }
    
    /**
     * Find the nearest station in a given list within MAX_STATION_DISTANCE_KM.
     */
    private fun findNearestInList(lat: Double, lon: Double, stations: List<StationInfo>): StationInfo? {
        var nearest: StationInfo? = null
        var minDistance = Double.MAX_VALUE
        
        for (station in stations) {
            val distance = haversineDistance(lat, lon, station.lat, station.lon)
            if (distance < minDistance) {
                minDistance = distance
                nearest = station
            }
        }
        
        return if (minDistance <= MAX_STATION_DISTANCE_KM) nearest else null
    }

    /**
     * Get tide predictions from NOAA CO-OPS API for a specific station.
     */
    private suspend fun getTidePredictions(station: StationInfo, date: String): TideData {
        try {
            // Fetch today + tomorrow so there are always future predictions,
            // even when queried late in the evening after the last tide of the day.
            val startDate = LocalDate.parse(date)
            val endDate = startDate.plusDays(1)
            val beginFormatted = startDate.format(DateTimeFormatter.BASIC_ISO_DATE)
            val endFormatted = endDate.format(DateTimeFormatter.BASIC_ISO_DATE)
            
            // Get high/low tide predictions for today and tomorrow
            val url = buildString {
                append(COOPS_URL)
                append("?station=${station.id}")
                append("&begin_date=$beginFormatted")
                append("&end_date=$endFormatted")
                append("&product=predictions")
                append("&datum=MLLW")  // Mean Lower Low Water
                append("&time_zone=lst_ldt")  // Local time with DST
                append("&units=english")  // Feet
                append("&interval=hilo")  // High/Low only
                append("&format=json")
            }
            
            logger.debug("Fetching tides from station ${station.id} (${station.name}): $url")
            val response: String = client.get(url).bodyAsText()
            
            // Use the station's exact timezone offset from NOAA metadata
            val stationOffset = ZoneOffset.ofHours(station.timezoneCorrHours)
            return parseTidePredictions(response, stationOffset)
        } catch (e: Exception) {
            logger.warn("Tide prediction fetch failed for station ${station.id} (${station.name}): ${e.message}")
            throw e
        }
    }

    /**
     * Parse tide predictions from NOAA CO-OPS JSON response.
     * 
     * @param stationOffset The station's timezone offset from NOAA metadata (timezonecorr).
     *   NOAA returns times in station-local time (lst_ldt), so we need the station's timezone
     *   to correctly compare against "now" and convert to epoch millis.
     */
    private fun parseTidePredictions(jsonResponse: String, stationOffset: ZoneOffset): TideData {
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
                var nextHighTideTime: LocalDateTime? = null
                var nextLowTideTime: LocalDateTime? = null
                var currentHeight = 0.0
                var tideState = "unknown"
                
                // Use the station's timezone so the comparison matches the NOAA lst_ldt times
                val now = LocalDateTime.now(stationOffset)
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
                                nextHighTideTime = predTime  // Preserve the timestamp
                                // If next is high, we're rising
                                if (tideState == "unknown") tideState = "rising"
                            } else if (type == "L" && nextLowTide.isEmpty()) {
                                nextLowTide = "${predTime.format(DateTimeFormatter.ofPattern("h:mma"))} (${String.format("%.1f", height)}ft)"
                                nextLowTideTime = predTime  // Preserve the timestamp
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
                
                // Convert LocalDateTime to epoch millis using the station's timezone offset
                return TideData(
                    currentHeight = currentHeight,
                    nextHighTide = nextHighTide.ifEmpty { "N/A" },
                    nextLowTide = nextLowTide.ifEmpty { "N/A" },
                    tideState = tideState,
                    nextHighTideTime = nextHighTideTime?.atZone(stationOffset)?.toInstant()?.toEpochMilli(),
                    nextLowTideTime = nextLowTideTime?.atZone(stationOffset)?.toInstant()?.toEpochMilli()
                )
            }
            
            throw Exception("No predictions found in response")
        } catch (e: Exception) {
            logger.debug("Tide parsing failed: ${e.message}")
            throw e
        }
    }

    /**
     * Return honest "no data available" instead of fabricated estimates.
     * Used when no NOAA station is within range or when the API fails.
     */
    private fun noTideData(): TideData {
        return TideData(
            currentHeight = 0.0,
            nextHighTide = "No station nearby",
            nextLowTide = "No station nearby",
            tideState = "unknown"
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
