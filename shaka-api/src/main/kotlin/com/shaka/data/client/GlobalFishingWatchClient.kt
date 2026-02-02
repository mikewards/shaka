package com.shaka.data.client

import com.shaka.model.VesselActivity
import io.ktor.client.call.*
import io.ktor.client.request.*
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import org.slf4j.LoggerFactory

/**
 * Client for Global Fishing Watch API.
 * Provides vessel activity data worldwide - FREE tier available.
 * 
 * API Docs: https://globalfishingwatch.org/our-apis/documentation
 * 
 * The 4Wings API returns fishing effort data aggregated by grid cells.
 * We use this to count fishing vessels near a spot.
 */
class GlobalFishingWatchClient {

    private val logger = LoggerFactory.getLogger(GlobalFishingWatchClient::class.java)
    private val client = HttpClientFactory.shared
    
    companion object {
        // GFW API base URL
        private const val BASE_URL = "https://gateway.api.globalfishingwatch.org/v3"
        
        // Default search radius in nautical miles
        const val DEFAULT_RADIUS_NM = 10
        
        // Convert nautical miles to degrees (approximate)
        // 1 nautical mile ≈ 1/60 degree at equator
        private fun nmToDegrees(nm: Int): Double = nm / 60.0
    }
    
    /**
     * Get vessel activity near a spot.
     * 
     * @param lat Latitude of spot
     * @param lon Longitude of spot  
     * @param radiusNm Search radius in nautical miles (default 10nm)
     * @return VesselActivity with count of vessels and metadata
     */
    suspend fun getVesselActivity(
        lat: Double,
        lon: Double,
        radiusNm: Int = DEFAULT_RADIUS_NM
    ): VesselActivity? {
        return try {
            RateLimiters.globalFishingWatch.acquire()
            
            // Create bounding box around the spot
            val delta = nmToDegrees(radiusNm)
            val minLat = lat - delta
            val maxLat = lat + delta
            val minLon = lon - delta
            val maxLon = lon + delta
            
            // Use the vessels API to search for fishing vessels in the area
            // This endpoint returns vessels that have been active in an area
            val response: GFWVesselSearchResponse = client.get("$BASE_URL/vessels") {
                // Bounding box search
                parameter("where", "lat>=$minLat AND lat<=$maxLat AND lon>=$minLon AND lon<=$maxLon")
                parameter("datasets", "public-global-fishing-effort:latest")
                parameter("limit", 100)
                
                // GFW requires API key for some endpoints, but basic search is free
                header("Accept", "application/json")
            }.body()
            
            val count = response.entries?.size ?: 0
            
            logger.info("GFW: Found $count vessels within ${radiusNm}nm of ($lat, $lon)")
            
            VesselActivity(
                count = count,
                radiusNm = radiusNm,
                updatedAt = java.time.Instant.now().toString()
            )
            
        } catch (e: Exception) {
            logger.warn("GFW API failed for ($lat, $lon): ${e.message}")
            
            // Try alternative: use the fishing effort heatmap data
            try {
                getVesselActivityFromEffort(lat, lon, radiusNm)
            } catch (e2: Exception) {
                logger.warn("GFW effort API also failed: ${e2.message}")
                null
            }
        }
    }
    
    /**
     * Alternative: Get vessel activity from fishing effort data.
     * This uses the 4Wings API which aggregates fishing hours by grid cell.
     */
    private suspend fun getVesselActivityFromEffort(
        lat: Double,
        lon: Double,
        radiusNm: Int
    ): VesselActivity? {
        return try {
            RateLimiters.globalFishingWatch.acquire()
            
            val delta = nmToDegrees(radiusNm)
            
            // 4Wings API for fishing effort
            // Returns aggregated fishing hours which we can use to estimate activity
            val response: GFW4WingsResponse = client.get("$BASE_URL/4wings/report") {
                parameter("spatial-resolution", "low") // 0.1 degree grid
                parameter("temporal-resolution", "daily")
                parameter("datasets", "public-global-fishing-effort:latest")
                parameter("date-range", getDateRange()) // Last 7 days
                parameter("region", createGeoJSON(lat, lon, delta))
                
                header("Accept", "application/json")
            }.body()
            
            // Sum up fishing hours and estimate vessel count
            // Typically 1 vessel = ~8-12 fishing hours per day
            val totalHours = response.entries?.sumOf { it.value ?: 0.0 } ?: 0.0
            val estimatedVessels = (totalHours / 10.0).toInt().coerceAtLeast(0)
            
            logger.info("GFW 4Wings: $totalHours fishing hours = ~$estimatedVessels vessels near ($lat, $lon)")
            
            VesselActivity(
                count = estimatedVessels,
                radiusNm = radiusNm,
                updatedAt = java.time.Instant.now().toString()
            )
            
        } catch (e: Exception) {
            logger.warn("GFW 4Wings API failed: ${e.message}")
            null
        }
    }
    
    /**
     * Get date range for last 7 days in GFW format.
     */
    private fun getDateRange(): String {
        val end = java.time.LocalDate.now()
        val start = end.minusDays(7)
        return "$start,$end"
    }
    
    /**
     * Create GeoJSON polygon for bounding box.
     */
    private fun createGeoJSON(lat: Double, lon: Double, delta: Double): String {
        val minLat = lat - delta
        val maxLat = lat + delta
        val minLon = lon - delta
        val maxLon = lon + delta
        
        return """{"type":"Polygon","coordinates":[[[${minLon},${minLat}],[${maxLon},${minLat}],[${maxLon},${maxLat}],[${minLon},${maxLat}],[${minLon},${minLat}]]]}"""
    }
}

// GFW API Response models

@Serializable
data class GFWVesselSearchResponse(
    val entries: List<GFWVessel>? = null,
    val total: Int? = null
)

@Serializable
data class GFWVessel(
    val id: String? = null,
    val mmsi: String? = null,
    @SerialName("shipname")
    val shipName: String? = null,
    @SerialName("flag")
    val flagState: String? = null,
    @SerialName("geartype")
    val gearType: String? = null
)

@Serializable
data class GFW4WingsResponse(
    val entries: List<GFW4WingsEntry>? = null
)

@Serializable
data class GFW4WingsEntry(
    val date: String? = null,
    val value: Double? = null,
    @SerialName("fishing_hours")
    val fishingHours: Double? = null
)
