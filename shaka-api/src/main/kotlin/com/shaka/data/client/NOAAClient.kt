package com.shaka.data.client

import io.ktor.client.request.*
import io.ktor.client.statement.*
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.slf4j.LoggerFactory
import java.time.LocalDate

/**
 * Client for NOAA ERDDAP ocean data.
 * Free, no authentication required.
 * 
 * Data sources:
 * - NOAA CoastWatch ERDDAP: Sea Surface Temperature (SST)
 * - NOAA CoastWatch VIIRS: Chlorophyll-a concentration
 * - Uses Multi-scale Ultra-high Resolution (MUR) SST Analysis
 * 
 * ENTERPRISE PATTERNS:
 * - Uses shared HttpClient (HttpClientFactory.shared)
 * - Rate limited (3 req/sec via RateLimiters.noaa)
 * - Graceful fallback to regional estimates
 * 
 * API: https://coastwatch.pfeg.noaa.gov/erddap/griddap/
 */
class NOAAClient {
    
    private val logger = LoggerFactory.getLogger(NOAAClient::class.java)
    
    // Use shared HTTP client - DO NOT create a new one
    private val client: io.ktor.client.HttpClient get() = HttpClientFactory.shared

    companion object {
        // NOAA GeoPolar Blended SST day+night (5km global daily, analysed_sst).
        // Replaces jplMURSST41 on coastwatch.pfeg.noaa.gov: that host became
        // unreachable from Railway (verified Jun 2026: connect timeout from
        // the container while coastwatch.noaa.gov answers in 42ms), which
        // silently starved SST for ~3 months.
        private const val MUR_SST_URL = "https://coastwatch.noaa.gov/erddap/griddap/noaacwBLENDEDsstDNDaily.json"
        
        // Fallback: GeoPolar Blended SST day-only variant (same host/schema)
        private const val GHRSST_URL = "https://coastwatch.noaa.gov/erddap/griddap/noaacwBLENDEDsstDaily.json"
        
        // NOAA CoastWatch VIIRS Chlorophyll-a (daily, ~4km resolution)
        private const val VIIRS_CHL_URL = "https://coastwatch.noaa.gov/erddap/griddap/noaacwNPPVIIRSchlaDaily.json"
        
        // Alternative: NOAA-20 VIIRS chlorophyll (newer satellite)
        private const val NOAA20_CHL_URL = "https://coastwatch.noaa.gov/erddap/griddap/noaacwN20VIIRSchlaDaily.json"

        private val erddapJson = Json { ignoreUnknownKeys = true; isLenient = true }
    }

    /**
     * Get real Sea Surface Temperature from NOAA MUR SST dataset.
     * Returns temperature in Celsius, or null if no satellite data available.
     * 
     * MUR SST has a 1-2 day processing lag, so queries use (date - 2 days).
     * Returns null (not a regional estimate) when satellite data is unavailable
     * so callers can decide how to handle missing data honestly.
     * 
     * @param lat Latitude
     * @param lon Longitude  
     * @param date Date in YYYY-MM-DD format
     * @return SST in Celsius, or null if satellite data unavailable
     */
    suspend fun getSeaSurfaceTemperature(lat: Double, lon: Double, date: String): Double? {
        return try {
            RateLimiters.noaa.acquire()
            
            val sst = getMURSST(lat, lon, date) ?: getGHRSST(lat, lon, date)
            if (sst != null) {
                logger.info("NOAA satellite SST for ($lat, $lon): ${String.format("%.1f", sst)}°C / ${String.format("%.0f", sst * 9.0/5 + 32)}°F")
            } else {
                logger.info("NOAA satellite SST unavailable for ($lat, $lon) on $date")
            }
            sst
        } catch (e: Exception) {
            logger.warn("NOAA SST fetch failed for ($lat, $lon): ${e.message}")
            null
        }
    }

    /**
     * Get chlorophyll-a concentration from NOAA VIIRS satellite data.
     * Returns chlorophyll in mg/m³.
     */
    suspend fun getChlorophyll(lat: Double, lon: Double, date: String): Double? {
        return try {
            // Rate limit
            RateLimiters.noaa.acquire()
            
            // Try S-NPP VIIRS first, then NOAA-20 VIIRS as backup
            getVIIRSChlorophyll(lat, lon, date) ?: getNOAA20Chlorophyll(lat, lon, date)
        } catch (e: Exception) {
            logger.warn("NOAA Chlorophyll fetch failed for ($lat, $lon): ${e.message}")
            null
        }
    }

    /**
     * Query VIIRS chlorophyll dataset from NOAA NESDIS.
     */
    private suspend fun getVIIRSChlorophyll(lat: Double, lon: Double, date: String): Double? {
        return try {
            val latMin = lat - 0.1
            val latMax = lat + 0.1
            val lonMin = lon - 0.1
            val lonMax = lon + 0.1
            
            val url = "$VIIRS_CHL_URL?chlor_a[(last)][(0.0)][($latMin):($latMax)][($lonMin):($lonMax)]"
            
            logger.debug("Fetching VIIRS chlorophyll: $url")
            val response: String = client.get(url).bodyAsText()
            
            val chl = parseChlorophyllFromERDDAP(response)
            if (chl != null) {
                logger.info("VIIRS Chlorophyll for ($lat, $lon): ${String.format("%.3f", chl)} mg/m³")
            }
            chl
        } catch (e: Exception) {
            logger.debug("VIIRS chlorophyll unavailable: ${e.message}")
            null
        }
    }

    /**
     * Query NOAA-20 VIIRS chlorophyll as backup.
     */
    private suspend fun getNOAA20Chlorophyll(lat: Double, lon: Double, date: String): Double? {
        return try {
            val latMin = lat - 0.1
            val latMax = lat + 0.1
            val lonMin = lon - 0.1
            val lonMax = lon + 0.1
            
            val url = "$NOAA20_CHL_URL?chlor_a[(last)][(0.0)][($latMin):($latMax)][($lonMin):($lonMax)]"
            
            logger.debug("Fetching NOAA-20 chlorophyll: $url")
            val response: String = client.get(url).bodyAsText()
            
            val chl = parseChlorophyllFromERDDAP(response)
            if (chl != null) {
                logger.info("NOAA-20 Chlorophyll for ($lat, $lon): ${String.format("%.3f", chl)} mg/m³")
            }
            chl
        } catch (e: Exception) {
            logger.debug("NOAA-20 chlorophyll unavailable: ${e.message}")
            null
        }
    }

    /**
     * Parse chlorophyll value from ERDDAP JSON response.
     */
    private fun parseChlorophyllFromERDDAP(jsonResponse: String): Double? {
        return try {
            val regex = """"rows"\s*:\s*\[\s*\[([^\]]+)\]""".toRegex()
            val match = regex.find(jsonResponse)
            
            if (match != null) {
                val rowData = match.groupValues[1]
                val values = rowData.split(",").map { it.trim().replace("\"", "") }
                val chlValue = values.lastOrNull()?.toDoubleOrNull()
                
                if (chlValue != null && chlValue > 0 && chlValue < 100) {
                    logger.debug("Parsed chlorophyll: $chlValue mg/m³")
                    return chlValue
                }
            }
            null
        } catch (e: Exception) {
            logger.debug("Chlorophyll parsing failed: ${e.message}")
            null
        }
    }

    /**
     * Progressive SST fetch for background prefetch -- tries increasingly wider
     * bounding boxes to work around near-shore land masking.
     * NOT for the hot path (use getSeaSurfaceTemperature for that).
     */
    suspend fun getSeaSurfaceTemperatureProgressive(lat: Double, lon: Double, date: String): Double? {
        return try {
            val murRadii = listOf(0.05, 0.15, 0.25)
            for (radius in murRadii) {
                RateLimiters.noaa.acquire()
                val sst = getMURSSTWithRadius(lat, lon, date, radius)
                if (sst != null) {
                    if (radius > 0.05) logger.info("MUR SST found at expanded radius ±$radius for ($lat, $lon): ${String.format("%.1f", sst)}°C")
                    return sst
                }
            }

            val ghrsstRadii = listOf(0.1, 0.25, 0.5)
            for (radius in ghrsstRadii) {
                RateLimiters.noaa.acquire()
                val sst = getGHRSSTWithRadius(lat, lon, date, radius)
                if (sst != null) {
                    logger.info("GHRSST found at radius ±$radius for ($lat, $lon): ${String.format("%.1f", sst)}°C")
                    return sst
                }
            }

            logger.info("SST unavailable at all radii for ($lat, $lon) on $date")
            null
        } catch (e: Exception) {
            logger.warn("Progressive SST fetch failed for ($lat, $lon): ${e.message}")
            null
        }
    }

    /**
     * Query MUR SST dataset - Multi-scale Ultra-high Resolution SST.
     */
    private suspend fun getMURSST(lat: Double, lon: Double, date: String): Double? {
        return getMURSSTWithRadius(lat, lon, date, 0.05)
    }

    private suspend fun getMURSSTWithRadius(lat: Double, lon: Double, date: String, radius: Double): Double? {
        return try {
            val queryDate = LocalDate.parse(date).minusDays(2).toString()
            val dateTime = "${queryDate}T12:00:00Z"
            
            val latMin = lat - radius
            val latMax = lat + radius
            val lonMin = lon - radius
            val lonMax = lon + radius
            
            val url = "$MUR_SST_URL?analysed_sst[($dateTime)][($latMin):($latMax)][($lonMin):($lonMax)]"
            
            val response: String = client.get(url).bodyAsText()
            parseSSTFromERDDAP(response)
        } catch (e: Exception) {
            logger.info("MUR SST unavailable at ±$radius for ($lat, $lon): ${e.message}")
            null
        }
    }

    /**
     * Query GHRSST dataset - Global High Resolution SST.
     */
    private suspend fun getGHRSST(lat: Double, lon: Double, date: String): Double? {
        return getGHRSSTWithRadius(lat, lon, date, 0.1)
    }

    private suspend fun getGHRSSTWithRadius(lat: Double, lon: Double, date: String, radius: Double): Double? {
        return try {
            RateLimiters.noaa.acquire()
            
            val queryDate = LocalDate.parse(date).minusDays(2).toString()
            val latMin = lat - radius
            val latMax = lat + radius
            val lonMin = lon - radius
            val lonMax = lon + radius
            
            val url = "$GHRSST_URL?analysed_sst[(${queryDate}T12:00:00Z)][($latMin):($latMax)][($lonMin):($lonMax)]"
            
            val response: String = client.get(url).bodyAsText()
            parseSSTFromERDDAP(response)
        } catch (e: Exception) {
            logger.info("GHRSST unavailable at ±$radius for ($lat, $lon): ${e.message}")
            null
        }
    }

    /**
     * Parse SST from an ERDDAP griddap JSON table response. Averages all
     * non-null values across all rows in the bounding box for a more robust
     * reading (existing behavior; the progressive-bbox caller takes the first
     * radius that yields a non-null result).
     *
     * Response shape (verified live Jul 2026):
     *   {"table": {"columnNames": ["time","latitude","longitude","analysed_sst"],
     *              "rows": [["2026-07-16T12:00:00Z", 33.525, -118.475, 21.399994], ...]}}
     * Missing cells are JSON null.
     *
     * History: the previous regex-based parser (3022c8c, Mar 2026) structurally
     * could never capture a complete row — its capture group stopped at the
     * first ']' — so every HTTP-200 response parsed to null and SST silently
     * died for 5 months. Hence real JSON parsing and WARN (not debug) logs on
     * malformed input.
     *
     * Internal (not private) for direct fixture-based regression testing.
     */
    internal fun parseSSTFromERDDAP(jsonResponse: String): Double? {
        return try {
            val root = erddapJson.parseToJsonElement(jsonResponse).jsonObject
            val table = root["table"]?.jsonObject
            if (table == null) {
                logger.warn("SST parsing failed: ERDDAP response has no \"table\" object (first 200 chars: ${jsonResponse.take(200)})")
                return null
            }
            val columnNames = table["columnNames"]?.jsonArray?.map { it.jsonPrimitive.content }
            // The SST column is named analysed_sst in both blended datasets;
            // fall back to the last column (ERDDAP puts the data variable last).
            val sstIdx = columnNames?.indexOf("analysed_sst")?.takeIf { it >= 0 }
                ?: columnNames?.lastIndex?.takeIf { it >= 0 }
            val rows = table["rows"]?.jsonArray
            if (sstIdx == null || rows == null) {
                logger.warn("SST parsing failed: ERDDAP table missing columnNames/rows (columns=$columnNames)")
                return null
            }

            val sstValues = rows.mapNotNull { row ->
                val cell = row.jsonArray.getOrNull(sstIdx) as? JsonPrimitive ?: return@mapNotNull null
                val raw = cell.doubleOrNull ?: return@mapNotNull null  // JSON null / non-numeric -> skip
                val celsius = if (raw > 200) raw - 273.15 else raw     // defensive Kelvin conversion
                // Range check also drops NaN (comparisons with NaN are false).
                celsius.takeIf { it in -2.0..45.0 }
            }

            // Empty is a legitimate "no data in this bbox" (all cells null) —
            // quiet null so the progressive-bbox caller widens the search.
            if (sstValues.isEmpty()) return null
            sstValues.average()
        } catch (e: Exception) {
            logger.warn("SST parsing failed (malformed ERDDAP response): ${e.message}")
            null
        }
    }

}
