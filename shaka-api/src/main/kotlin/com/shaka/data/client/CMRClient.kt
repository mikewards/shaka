package com.shaka.data.client

import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import kotlinx.serialization.json.*
import org.slf4j.LoggerFactory
import java.time.Instant
import java.time.format.DateTimeFormatter

/**
 * Client for querying NASA CMR (Common Metadata Repository) for satellite observation timestamps.
 * 
 * CMR provides granule-level metadata including precise observation start/end times.
 * This is used to get the exact time when a satellite observed a specific location,
 * complementing the chlorophyll values from GIBS.
 * 
 * Note: Only PACE, NOAA-20, and NOAA-21 are available in NASA CMR.
 * Sentinel-3A/B data is managed by ESA and would require a different API.
 */
object CMRClient {
    
    private val logger = LoggerFactory.getLogger(CMRClient::class.java)
    private val httpClient = HttpClientFactory.shared
    private val json = Json { ignoreUnknownKeys = true }
    
    private const val CMR_BASE = "https://cmr.earthdata.nasa.gov/search/granules.json"
    
    /**
     * CMR Collection Concept IDs for each satellite's ocean color products.
     * These are the NRT (Near Real-Time) L2 collections that correspond to GIBS layers.
     */
    private val SATELLITE_COLLECTIONS = mapOf(
        "PACE" to "C3620139643-OB_CLOUD",      // PACE_OCI_L2_BGC_NRT
        "NOAA-20" to "C3396928895-OB_CLOUD",   // VIIRSJ1_L2_OC_NRT
        "NOAA-21" to "C3779578158-OB_CLOUD"    // VIIRSJ2_L2_OC_NRT
        // Sentinel-3A/B not in NASA CMR - would need ESA Copernicus API
    )
    
    /**
     * Get observation timestamps for all available satellites at a specific location and date.
     * 
     * @param lat Latitude in decimal degrees
     * @param lon Longitude in decimal degrees
     * @param date Date string in YYYY-MM-DD format
     * @return Map of satellite name to observation start time (or null if no granule found)
     */
    suspend fun getAllObservationTimes(
        lat: Double,
        lon: Double,
        date: String
    ): Map<String, Instant?> {
        val results = mutableMapOf<String, Instant?>()
        
        for ((satellite, collectionId) in SATELLITE_COLLECTIONS) {
            results[satellite] = getObservationTime(satellite, collectionId, lat, lon, date)
        }
        
        return results
    }
    
    /**
     * Get the observation time for a specific satellite at a location and date.
     * 
     * Queries CMR for granules covering the point on the given date and returns
     * the observation start time of the first matching granule.
     * 
     * @return Observation start time as Instant, or null if no granule found
     */
    private suspend fun getObservationTime(
        satellite: String,
        collectionId: String,
        lat: Double,
        lon: Double,
        date: String
    ): Instant? {
        try {
            // Build temporal range for the full day
            val nextDay = incrementDate(date)
            val temporal = "$date,$nextDay"
            
            val url = buildString {
                append(CMR_BASE)
                append("?collection_concept_id=$collectionId")
                append("&temporal=$temporal")
                append("&point=$lon,$lat")  // CMR uses lon,lat order
                append("&page_size=5")
                append("&sort_key=start_date")  // Get earliest pass first
            }
            
            val response = httpClient.get(url) {
                header("Client-Id", "shaka-api")
            }
            
            if (response.status != HttpStatusCode.OK) {
                logger.debug("CMR returned ${response.status} for $satellite at ($lat, $lon)")
                return null
            }
            
            val body = response.bodyAsText()
            val jsonResponse = json.parseToJsonElement(body).jsonObject
            val entries = jsonResponse["feed"]?.jsonObject?.get("entry")?.jsonArray
            
            if (entries.isNullOrEmpty()) {
                logger.debug("CMR: No $satellite granules for ($lat, $lon) on $date")
                return null
            }
            
            // Get the first granule's start time
            val firstEntry = entries[0].jsonObject
            val timeStart = firstEntry["time_start"]?.jsonPrimitive?.content
            
            if (timeStart != null) {
                val instant = parseIsoInstant(timeStart)
                logger.debug("CMR: $satellite observed ($lat, $lon) at $timeStart")
                return instant
            }
            
            return null
            
        } catch (e: Exception) {
            logger.debug("CMR error for $satellite at ($lat, $lon): ${e.message}")
            return null
        }
    }
    
    /**
     * Parse ISO 8601 timestamp to Instant.
     */
    private fun parseIsoInstant(timestamp: String): Instant {
        return Instant.parse(timestamp)
    }
    
    /**
     * Increment a date string by one day.
     * Simple implementation that handles month/year boundaries.
     */
    private fun incrementDate(date: String): String {
        val parts = date.split("-")
        val year = parts[0].toInt()
        val month = parts[1].toInt()
        val day = parts[2].toInt()
        
        val daysInMonth = when (month) {
            1, 3, 5, 7, 8, 10, 12 -> 31
            4, 6, 9, 11 -> 30
            2 -> if (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) 29 else 28
            else -> 31
        }
        
        return if (day < daysInMonth) {
            String.format("%04d-%02d-%02d", year, month, day + 1)
        } else if (month < 12) {
            String.format("%04d-%02d-01", year, month + 1)
        } else {
            String.format("%04d-01-01", year + 1)
        }
    }
    
    /**
     * Get list of supported satellites (those available in NASA CMR).
     */
    fun getSupportedSatellites(): List<String> = SATELLITE_COLLECTIONS.keys.toList()
}
