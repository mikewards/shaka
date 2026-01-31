package com.shaka.data.client

import io.ktor.client.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import kotlinx.serialization.json.*
import org.slf4j.LoggerFactory
import java.time.LocalDate

/**
 * Standalone ERDDAP client for fetching 300m resolution chlorophyll data.
 * 
 * This is an ADDITIONAL data source for comparison with existing Copernicus data.
 * It does NOT replace or modify any existing Copernicus logic.
 * 
 * NOAA CoastWatch ERDDAP provides 216 geographic sectors (AA through RL),
 * each covering approximately 20° longitude x 15° latitude at 300m resolution.
 * 
 * Data characteristics:
 * - Resolution: 300m (0.0025 degrees) - 13x better than 4km global
 * - Latency: ~1 day (vs 2-11 days for other products)
 * - Coverage: 90-day rolling window
 * - Source: Sentinel-3A OLCI satellite
 */
object ERDDAPSectorClient {
    
    private val logger = LoggerFactory.getLogger(ERDDAPSectorClient::class.java)
    private val httpClient = HttpClientFactory.shared
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }
    
    private const val BASE_URL = "https://coastwatch.noaa.gov/erddap/griddap"
    
    /**
     * Result from an ERDDAP chlorophyll query.
     */
    data class ERDDAPResult(
        val chlorophyll: Double,
        val sector: String,
        val dataDate: String,
        val source: String = "ERDDAP 300m OLCI"
    )
    
    /**
     * Calculate the NOAA CoastWatch sector code for a given coordinate.
     * 
     * Grid structure:
     * - First letter (A-R): 18 longitude bands, each 20° wide (-180 to +180)
     * - Second letter (A-L): 12 latitude bands, each 15° wide (-90 to +90)
     * 
     * Examples:
     * - Hawaii (21°N, -158°W) -> BH
     * - Florida (25°N, -80°W) -> FH
     * - California (33°N, -118°W) -> DI
     * - Australia (-34°S, 151°E) -> QD
     */
    fun getSectorCode(lat: Double, lon: Double): String {
        // Normalize longitude to -180 to 180 range
        val normalizedLon = when {
            lon > 180 -> lon - 360
            lon < -180 -> lon + 360
            else -> lon
        }
        
        // Calculate longitude band (A-R, 18 bands of 20° each)
        val lonBand = ((normalizedLon + 180) / 20).toInt().coerceIn(0, 17)
        
        // Calculate latitude band (A-L, 12 bands of 15° each)
        val latBand = ((lat + 90) / 15).toInt().coerceIn(0, 11)
        
        return "${('A' + lonBand)}${('A' + latBand)}"
    }
    
    /**
     * Fetch chlorophyll data for a location from the 300m ERDDAP sector dataset.
     * 
     * Tries today first, then progressively older dates (T-0 to T-7).
     * 300m sector data can have gaps due to cloud cover, so we check up to 7 days.
     * 
     * @param lat Latitude in degrees (-90 to 90)
     * @param lon Longitude in degrees (-180 to 180)
     * @param date Optional date string (YYYY-MM-DD), defaults to today
     * @return ERDDAPResult with chlorophyll value and metadata, or null if unavailable
     */
    suspend fun getChlorophyll(lat: Double, lon: Double, date: String? = null): ERDDAPResult? {
        val sector = getSectorCode(lat, lon)
        val datasetId = "noaacwS3AOLCIchlaSector${sector}Daily"
        val baseDate = if (date != null) LocalDate.parse(date) else LocalDate.now()
        
        logger.debug("Querying ERDDAP sector $sector for ($lat, $lon)")
        
        // Try T-0 through T-7 (today through 7 days ago)
        // 300m sector data is sensitive to cloud cover, so we check more days
        for (daysBack in 0..7) {
            val queryDate = baseDate.minusDays(daysBack.toLong())
            val result = fetchFromERDDAP(datasetId, lat, lon, queryDate.toString(), sector)
            if (result != null) {
                return result
            }
        }
        
        logger.debug("No ERDDAP data available for sector $sector at ($lat, $lon) in last 7 days")
        return null
    }
    
    /**
     * Internal method to fetch chlorophyll from a specific ERDDAP dataset and date.
     */
    private suspend fun fetchFromERDDAP(
        datasetId: String, 
        lat: Double, 
        lon: Double, 
        date: String,
        sector: String
    ): ERDDAPResult? {
        // ERDDAP query format: chlor_a[(time)][(altitude)][(lat)][(lon)]
        val url = "$BASE_URL/$datasetId.json?" +
            "chlor_a[(${date}T12:00:00Z)][(0.0)][($lat)][($lon)]"
        
        return try {
            val response = httpClient.get(url)
            val statusCode = response.status.value
            
            when {
                statusCode == 404 -> {
                    // Dataset doesn't cover this location or date
                    logger.debug("ERDDAP 404 for $datasetId on $date - location not in sector coverage")
                    null
                }
                statusCode == 400 -> {
                    // Bad request - usually means date out of range
                    logger.debug("ERDDAP 400 for $datasetId on $date - date not available")
                    null
                }
                statusCode != 200 -> {
                    logger.warn("ERDDAP returned $statusCode for $datasetId")
                    null
                }
                else -> {
                    parseERDDAPResponse(response.bodyAsText(), date, sector)
                }
            }
        } catch (e: Exception) {
            logger.warn("ERDDAP request failed for $datasetId: ${e.message}")
            null
        }
    }
    
    /**
     * Parse the ERDDAP JSON response to extract chlorophyll value.
     * 
     * Response format:
     * {
     *   "table": {
     *     "columnNames": ["time", "altitude", "latitude", "longitude", "chlor_a"],
     *     "rows": [["2026-01-29T12:00:00Z", 0.0, 21.65, -158.07, 0.2434]]
     *   }
     * }
     */
    private fun parseERDDAPResponse(responseBody: String, date: String, sector: String): ERDDAPResult? {
        return try {
            val jsonObject = json.parseToJsonElement(responseBody).jsonObject
            val table = jsonObject["table"]?.jsonObject ?: return null
            val columnNames = table["columnNames"]?.jsonArray ?: return null
            val rows = table["rows"]?.jsonArray ?: return null
            
            if (rows.isEmpty()) {
                logger.debug("ERDDAP returned empty rows for sector $sector on $date")
                return null
            }
            
            // Find the chlor_a column index
            val chlorAIndex = columnNames.indexOfFirst { 
                it.jsonPrimitive.content == "chlor_a" 
            }
            if (chlorAIndex == -1) {
                logger.warn("chlor_a column not found in ERDDAP response")
                return null
            }
            
            // Get the value from the first row
            val firstRow = rows[0].jsonArray
            val chlorValue = firstRow[chlorAIndex]
            
            // Handle null/NaN values
            if (chlorValue is JsonNull) {
                logger.debug("ERDDAP returned null chlor_a for sector $sector on $date")
                return null
            }
            
            val value = chlorValue.jsonPrimitive.doubleOrNull
            if (value == null || value.isNaN()) {
                logger.debug("ERDDAP returned NaN chlor_a for sector $sector on $date")
                return null
            }
            
            ERDDAPResult(
                chlorophyll = value,
                sector = sector,
                dataDate = date,
                source = "ERDDAP 300m OLCI Sector $sector"
            )
        } catch (e: Exception) {
            logger.warn("Failed to parse ERDDAP response: ${e.message}")
            null
        }
    }
    
    /**
     * Get sector information for a location (useful for debugging).
     */
    fun getSectorInfo(lat: Double, lon: Double): Map<String, Any> {
        val sector = getSectorCode(lat, lon)
        val lonBand = ((lon + 180) / 20).toInt().coerceIn(0, 17)
        val latBand = ((lat + 90) / 15).toInt().coerceIn(0, 11)
        
        return mapOf(
            "sector" to sector,
            "datasetId" to "noaacwS3AOLCIchlaSector${sector}Daily",
            "lonBand" to lonBand,
            "latBand" to latBand,
            "lonRange" to "${-180 + lonBand * 20}° to ${-180 + (lonBand + 1) * 20}°",
            "latRange" to "${-90 + latBand * 15}° to ${-90 + (latBand + 1) * 15}°"
        )
    }
}
