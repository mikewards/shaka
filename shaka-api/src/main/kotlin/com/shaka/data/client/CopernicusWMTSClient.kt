package com.shaka.data.client

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
import kotlin.math.floor

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
 * API: WMTS GetFeatureInfo
 * Free, no authentication required.
 * 
 * @see https://data.marine.copernicus.eu/product/OCEANCOLOUR_GLO_BGC_L3_NRT_009_101/description
 */
class CopernicusWMTSClient {

    private val logger = LoggerFactory.getLogger(CopernicusWMTSClient::class.java)

    private val client = HttpClient(CIO) {
        install(ContentNegotiation) {
            json(Json {
                ignoreUnknownKeys = true
                isLenient = true
            })
        }
    }

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
        return try {
            // Calculate tile coordinates for EPSG:4326
            // At level 8: 512 tiles x 256 tiles covering -180 to 180, -90 to 90
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
                // Use most recent time - data has 1-2 day latency
                append("&TIME=${date}T00:00:00Z")
            }
            
            logger.debug("Fetching ZSD visibility: tile($tileCol,$tileRow) pixel($pixelX,$pixelY)")
            
            val response: String = client.get(url).bodyAsText()
            val visibility = parseZSDResponse(response)
            
            if (visibility != null) {
                logger.info("Copernicus ZSD for ($lat, $lon): ${String.format("%.1f", visibility)}m visibility")
            } else {
                logger.debug("Copernicus ZSD unavailable for ($lat, $lon)")
            }
            
            visibility
        } catch (e: Exception) {
            logger.warn("Copernicus WMTS request failed: ${e.message}")
            null
        }
    }

    /**
     * Get visibility for the most recent available date.
     * L3 NRT data typically available from yesterday (1 day latency).
     * 
     * Returns null if satellite couldn't capture data (clouds, etc.)
     * This is HONEST - we don't make up numbers!
     */
    suspend fun getLatestVisibility(lat: Double, lon: Double): VisibilityResult {
        val today = LocalDate.now()
        
        // Try yesterday first (most recent typically available)
        for (daysBack in 1..3) {
            val date = today.minusDays(daysBack.toLong()).toString()
            val visibility = getVisibility(lat, lon, date)
            if (visibility != null) {
                return VisibilityResult(
                    visibilityM = visibility,
                    date = date,
                    dataSource = "Copernicus L3 NRT satellite (OCEANCOLOUR_GLO_BGC_L3_NRT_009_101)",
                    isActualMeasurement = true
                )
            }
        }
        
        // No data available - be honest about it!
        return VisibilityResult(
            visibilityM = null,
            date = today.minusDays(1).toString(),
            dataSource = "No satellite data available (cloud cover or land mask)",
            isActualMeasurement = false
        )
    }

    /**
     * Get chlorophyll-a concentration for a location.
     * Returns mg/m³ - actual satellite measurement.
     */
    suspend fun getChlorophyll(lat: Double, lon: Double, date: String): Double? {
        return try {
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
            
            val response: String = client.get(url).bodyAsText()
            parseNumericValue(response, "milligram m-3")
        } catch (e: Exception) {
            logger.warn("Copernicus CHL request failed: ${e.message}")
            null
        }
    }

    /**
     * Get chlorophyll for most recent available date.
     */
    suspend fun getLatestChlorophyll(lat: Double, lon: Double): ChlorophyllResult {
        val today = LocalDate.now()
        
        for (daysBack in 1..3) {
            val date = today.minusDays(daysBack.toLong()).toString()
            val chl = getChlorophyll(lat, lon, date)
            if (chl != null) {
                return ChlorophyllResult(
                    chlorophyllMgM3 = chl,
                    date = date,
                    dataSource = "Copernicus L3 NRT satellite (OCEANCOLOUR_GLO_BGC_L3_NRT_009_101)",
                    isActualMeasurement = true
                )
            }
        }
        
        return ChlorophyllResult(
            chlorophyllMgM3 = null,
            date = today.minusDays(1).toString(),
            dataSource = "No satellite data available (cloud cover or land mask)",
            isActualMeasurement = false
        )
    }

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
