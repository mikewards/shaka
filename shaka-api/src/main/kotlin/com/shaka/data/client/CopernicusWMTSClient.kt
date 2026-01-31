package com.shaka.data.client

import io.ktor.client.request.*
import io.ktor.client.statement.*
import kotlinx.coroutines.delay
import org.slf4j.LoggerFactory
import java.time.LocalDate
import kotlin.math.floor
import kotlin.random.Random

/**
 * Client for Copernicus Marine WMTS service - L3 NRT (Near Real Time) data.
 * 
 * Product: OCEANCOLOUR_GLO_BGC_L3_NRT_009_101
 * This is the CORRECT product for daily satellite observations.
 * 
 * Provides ACTUAL MEASURED data (not interpolated/gap-filled):
 * - ZSD (Secchi disk depth) = underwater visibility in meters
 * - CHL (Chlorophyll-a) = plankton concentration in mg/m³
 * 
 * L3 = Level 3 = actual daily satellite passes
 * - Updated daily at 22:00 UTC
 * - May return null for cloud-covered areas (this is honest, not an estimate!)
 * - 4km resolution, global coverage
 * 
 * ENTERPRISE PATTERNS:
 * - Uses shared HttpClient (no connection pool proliferation)
 * - Rate limited (1 req/sec via RateLimiters.copernicus)
 * - Circuit breaker protected (fails fast when API is down)
 * - Smart retry with exponential backoff
 * 
 * @see https://data.marine.copernicus.eu/product/OCEANCOLOUR_GLO_BGC_L3_NRT_009_101/description
 */
class CopernicusWMTSClient {

    private val logger = LoggerFactory.getLogger(CopernicusWMTSClient::class.java)

    // Use shared HTTP client - DO NOT create a new one
    private val client = HttpClientFactory.shared
    
    // Circuit breaker for this API
    private val circuitBreaker = CircuitBreaker(
        name = "copernicus-wmts",
        failureThreshold = 5,
        successThreshold = 2,
        resetTimeoutMs = 120_000  // 2 minutes before retry after circuit opens
    )

    companion object {
        private const val WMTS_BASE = "https://wmts.marine.copernicus.eu/teroWmts"
        
        // L3 NRT (Near Real Time) - actual daily satellite observations
        // This is the CORRECT product - updated daily, real measurements
        private const val ZSD_LAYER = "OCEANCOLOUR_GLO_BGC_L3_NRT_009_101/cmems_obs-oc_glo_bgc-transp_nrt_l3-multi-4km_P1D_202311/ZSD"
        private const val CHL_LAYER = "OCEANCOLOUR_GLO_BGC_L3_NRT_009_101/cmems_obs-oc_glo_bgc-plankton_nrt_l3-multi-4km_P1D_202411/CHL"
        
        // Tile matrix level 8 gives good resolution (~16km tiles)
        private const val TILE_MATRIX_LEVEL = 8
        private const val TILES_X = 512  // Number of tiles at level 8
        private const val TILES_Y = 256
        private const val TILE_SIZE = 256
        
        // Retry configuration
        private const val MAX_RETRIES = 3
        private const val INITIAL_BACKOFF_MS = 1000L
        private const val MAX_BACKOFF_MS = 8000L
    }

    /**
     * Get real underwater visibility (Secchi disk depth) for a location.
     * Returns visibility in METERS - this is actual measured data, not an estimate!
     * 
     * @param lat Latitude
     * @param lon Longitude
     * @param date Date in YYYY-MM-DD format (uses most recent available if date not available)
     * @return Visibility in meters, or null if unavailable
     */
    suspend fun getVisibility(lat: Double, lon: Double, date: String): Double? {
        // Rate limit - wait for token
        RateLimiters.copernicus.acquire()
        
        return try {
            // Circuit breaker - fail fast if API is down
            circuitBreaker.execute {
                fetchVisibility(lat, lon, date)
            }
        } catch (e: CircuitBreakerOpenException) {
            logger.debug("Circuit breaker open for Copernicus WMTS - skipping request")
            null
        } catch (e: Exception) {
            logger.warn("Copernicus WMTS visibility request failed: ${e.message}")
            null
        }
    }
    
    private suspend fun fetchVisibility(lat: Double, lon: Double, date: String): Double? {
        // Calculate tile coordinates for EPSG:4326
        val tileWidth = 360.0 / TILES_X
        val tileHeight = 180.0 / TILES_Y
        
        val tileCol = floor((lon + 180.0) / tileWidth).toInt().coerceIn(0, TILES_X - 1)
        val tileRow = floor((90.0 - lat) / tileHeight).toInt().coerceIn(0, TILES_Y - 1)
        
        // Calculate pixel position within tile (0-255)
        val tileLonMin = -180.0 + (tileCol * tileWidth)
        val tileLatMax = 90.0 - (tileRow * tileHeight)
        
        val pixelX = ((lon - tileLonMin) / tileWidth * TILE_SIZE).toInt().coerceIn(0, TILE_SIZE - 1)
        val pixelY = ((tileLatMax - lat) / tileHeight * TILE_SIZE).toInt().coerceIn(0, TILE_SIZE - 1)
        
        // Build WMTS GetFeatureInfo request
        val url = buildString {
            append(WMTS_BASE)
            append("?SERVICE=WMTS")
            append("&VERSION=1.0.0")
            append("&REQUEST=GetFeatureInfo")
            append("&LAYER=$ZSD_LAYER")
            append("&STYLE=cmap:viridis")
            append("&FORMAT=image/png")
            append("&TILEMATRIXSET=EPSG:4326")
            append("&TILEMATRIX=$TILE_MATRIX_LEVEL")
            append("&TILEROW=$tileRow")
            append("&TILECOL=$tileCol")
            append("&I=$pixelX")
            append("&J=$pixelY")
            append("&INFOFORMAT=application/json")
            append("&TIME=${date}T00:00:00Z")
        }
        
        logger.debug("Fetching ZSD visibility: tile($tileCol,$tileRow) pixel($pixelX,$pixelY)")
        
        // Handle 400 errors gracefully - date may not be available yet
        val httpResponse = client.get(url)
        if (httpResponse.status.value == 400) {
            logger.debug("Copernicus returned 400 for date $date - data not yet available")
            return null
        }
        val response: String = httpResponse.bodyAsText()
        val visibility = parseZSDResponse(response)
        
        if (visibility != null) {
            logger.info("Copernicus ZSD for ($lat, $lon): ${String.format("%.1f", visibility)}m visibility")
        } else {
            logger.debug("Copernicus ZSD unavailable for ($lat, $lon)")
        }
        
        return visibility
    }

    /**
     * Get visibility for the most recent available satellite data.
     * Uses smart retry with exponential backoff instead of naive loop.
     * 
     * Copernicus L3 NRT has 1-2 day latency depending on time of day/processing.
     */
    suspend fun getLatestVisibility(lat: Double, lon: Double): VisibilityResult {
        // Check circuit breaker before starting
        if (!circuitBreaker.allowsRequests()) {
            logger.debug("Circuit breaker open - returning no data")
            return VisibilityResult(
                visibilityM = null,
                date = LocalDate.now().minusDays(1).toString(),
                dataSource = "Circuit breaker open",
                isActualMeasurement = false
            )
        }
        
        // Try yesterday first (most common success case)
        val yesterday = LocalDate.now().minusDays(1).toString()
        var visibility = getVisibility(lat, lon, yesterday)
        
        if (visibility != null) {
            return VisibilityResult(
                visibilityM = visibility,
                date = yesterday,
                dataSource = "Copernicus L3 NRT satellite",
                isActualMeasurement = true
            )
        }
        
        // If yesterday failed, try 2 days ago with backoff
        // Only try a few more days, not 7 (that was excessive)
        for (daysBack in 2..4) {
            // Exponential backoff between retries
            val backoffMs = INITIAL_BACKOFF_MS * (1 shl (daysBack - 2)) + Random.nextLong(500)
            delay(backoffMs.coerceAtMost(MAX_BACKOFF_MS))
            
            // Check circuit breaker again
            if (!circuitBreaker.allowsRequests()) {
                logger.debug("Circuit breaker opened during retry - stopping")
                break
            }
            
            val date = LocalDate.now().minusDays(daysBack.toLong()).toString()
            visibility = getVisibility(lat, lon, date)
            
            if (visibility != null) {
                logger.debug("Found visibility data from $date (${daysBack} days ago)")
                return VisibilityResult(
                    visibilityM = visibility,
                    date = date,
                    dataSource = "Copernicus L3 NRT satellite",
                    isActualMeasurement = true
                )
            }
        }
        
        // No data found
        return VisibilityResult(
            visibilityM = null,
            date = yesterday,
            dataSource = "No satellite data available",
            isActualMeasurement = false
        )
    }

    /**
     * Get chlorophyll-a concentration for a location.
     * Returns mg/m³ - actual satellite measurement.
     */
    suspend fun getChlorophyll(lat: Double, lon: Double, date: String): Double? {
        // Rate limit
        RateLimiters.copernicus.acquire()
        
        return try {
            circuitBreaker.execute {
                fetchChlorophyll(lat, lon, date)
            }
        } catch (e: CircuitBreakerOpenException) {
            logger.debug("Circuit breaker open for Copernicus WMTS - skipping chlorophyll request")
            null
        } catch (e: Exception) {
            logger.warn("Copernicus CHL request failed: ${e.message}")
            null
        }
    }
    
    private suspend fun fetchChlorophyll(lat: Double, lon: Double, date: String): Double? {
        val tileWidth = 360.0 / TILES_X
        val tileHeight = 180.0 / TILES_Y
        
        val tileCol = floor((lon + 180.0) / tileWidth).toInt().coerceIn(0, TILES_X - 1)
        val tileRow = floor((90.0 - lat) / tileHeight).toInt().coerceIn(0, TILES_Y - 1)
        
        val tileLonMin = -180.0 + (tileCol * tileWidth)
        val tileLatMax = 90.0 - (tileRow * tileHeight)
        
        val pixelX = ((lon - tileLonMin) / tileWidth * TILE_SIZE).toInt().coerceIn(0, TILE_SIZE - 1)
        val pixelY = ((tileLatMax - lat) / tileHeight * TILE_SIZE).toInt().coerceIn(0, TILE_SIZE - 1)
        
        val url = buildString {
            append(WMTS_BASE)
            append("?SERVICE=WMTS")
            append("&VERSION=1.0.0")
            append("&REQUEST=GetFeatureInfo")
            append("&LAYER=$CHL_LAYER")
            append("&STYLE=cmap:viridis")
            append("&FORMAT=image/png")
            append("&TILEMATRIXSET=EPSG:4326")
            append("&TILEMATRIX=$TILE_MATRIX_LEVEL")
            append("&TILEROW=$tileRow")
            append("&TILECOL=$tileCol")
            append("&I=$pixelX")
            append("&J=$pixelY")
            append("&INFOFORMAT=application/json")
            append("&TIME=${date}T00:00:00Z")
        }
        
        // Handle 400 errors gracefully - date may not be available yet (expected)
        // Don't let these trip the circuit breaker
        val httpResponse = client.get(url)
        if (httpResponse.status.value == 400) {
            logger.debug("Copernicus returned 400 for date $date - data not yet available")
            return null
        }
        val response: String = httpResponse.bodyAsText()
        return parseNumericValue(response, "milligram m-3")
    }

    /**
     * Get chlorophyll for the most recent available satellite data.
     * Uses smart retry with exponential backoff.
     */
    suspend fun getLatestChlorophyll(lat: Double, lon: Double): ChlorophyllResult {
        // Check circuit breaker before starting
        if (!circuitBreaker.allowsRequests()) {
            logger.debug("Circuit breaker open - returning no chlorophyll data")
            return ChlorophyllResult(
                chlorophyllMgM3 = null,
                date = LocalDate.now().minusDays(1).toString(),
                dataSource = "Circuit breaker open",
                isActualMeasurement = false
            )
        }
        
        // Try yesterday first (most common success case)
        val yesterday = LocalDate.now().minusDays(1).toString()
        var chl = getChlorophyll(lat, lon, yesterday)
        
        if (chl != null) {
            return ChlorophyllResult(
                chlorophyllMgM3 = chl,
                date = yesterday,
                dataSource = "Copernicus L3 NRT satellite",
                isActualMeasurement = true
            )
        }
        
        // Try 2-4 days ago with backoff
        for (daysBack in 2..4) {
            val backoffMs = INITIAL_BACKOFF_MS * (1 shl (daysBack - 2)) + Random.nextLong(500)
            delay(backoffMs.coerceAtMost(MAX_BACKOFF_MS))
            
            if (!circuitBreaker.allowsRequests()) {
                logger.debug("Circuit breaker opened during chlorophyll retry - stopping")
                break
            }
            
            val date = LocalDate.now().minusDays(daysBack.toLong()).toString()
            chl = getChlorophyll(lat, lon, date)
            
            if (chl != null) {
                logger.debug("Found chlorophyll data from $date (${daysBack} days ago)")
                return ChlorophyllResult(
                    chlorophyllMgM3 = chl,
                    date = date,
                    dataSource = "Copernicus L3 NRT satellite",
                    isActualMeasurement = true
                )
            }
        }
        
        return ChlorophyllResult(
            chlorophyllMgM3 = null,
            date = yesterday,
            dataSource = "No satellite data available",
            isActualMeasurement = false
        )
    }
    
    /**
     * Get circuit breaker status (for monitoring).
     */
    fun getCircuitBreakerStats(): Map<String, Any> = circuitBreaker.getStats()

    /**
     * Parse ZSD value from WMTS GetFeatureInfo JSON response.
     */
    private fun parseZSDResponse(jsonResponse: String): Double? {
        return parseNumericValue(jsonResponse, "m")
    }

    /**
     * Parse numeric value from WMTS GetFeatureInfo JSON response.
     * Handles null values properly (satellite couldn't measure this location).
     */
    private fun parseNumericValue(jsonResponse: String, expectedUnits: String): Double? {
        return try {
            // Check if value is null (satellite couldn't capture this location)
            if (jsonResponse.contains("\"value\":null") || jsonResponse.contains("\"value\": null")) {
                return null
            }
            
            // Response format: {"type":"FeatureCollection","features":[{"properties":{"value":35.5,"units":"m"}}]}
            val valueRegex = """"value"\s*:\s*([\d.]+)""".toRegex()
            val unitsRegex = """"units"\s*:\s*"([^"]+)"""".toRegex()
            
            val valueMatch = valueRegex.find(jsonResponse)
            val unitsMatch = unitsRegex.find(jsonResponse)
            
            if (valueMatch != null && unitsMatch?.groupValues?.get(1) == expectedUnits) {
                val value = valueMatch.groupValues[1].toDoubleOrNull()
                if (value != null && value > 0) {
                    return value
                }
            }
            
            null
        } catch (e: Exception) {
            logger.debug("Value parsing failed: ${e.message}")
            null
        }
    }

    /**
     * Result of visibility query - includes metadata about the measurement.
     */
    data class VisibilityResult(
        val visibilityM: Double?,           // Visibility in meters, null if unavailable
        val date: String,                   // Date of measurement
        val dataSource: String,             // Source attribution
        val isActualMeasurement: Boolean    // True if actual satellite data, false if unavailable
    )

    /**
     * Result of chlorophyll query - includes metadata about the measurement.
     */
    data class ChlorophyllResult(
        val chlorophyllMgM3: Double?,       // Chlorophyll in mg/m³, null if unavailable
        val date: String,                   // Date of measurement
        val dataSource: String,             // Source attribution
        val isActualMeasurement: Boolean    // True if actual satellite data
    )
}
