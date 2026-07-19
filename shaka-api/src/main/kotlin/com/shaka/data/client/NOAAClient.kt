package com.shaka.data.client

import io.ktor.client.request.*
import io.ktor.client.statement.*
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
     * Parse SST from ERDDAP JSON response. Averages all non-null values across
     * all rows in the bounding box for a more robust reading.
     */
    private fun parseSSTFromERDDAP(jsonResponse: String): Double? {
        return try {
            val rowsRegex = """"rows"\s*:\s*\[([^\]]*(?:\[[^\]]*\][^\]]*)*)\]""".toRegex()
            val rowsMatch = rowsRegex.find(jsonResponse) ?: return null
            val rowsBlock = rowsMatch.groupValues[1]

            val rowRegex = """\[([^\]]+)\]""".toRegex()
            val sstValues = mutableListOf<Double>()

            for (row in rowRegex.findAll(rowsBlock)) {
                val values = row.groupValues[1].split(",").map { it.trim() }
                val raw = values.lastOrNull()?.toDoubleOrNull() ?: continue
                val celsius = if (raw > 200) raw - 273.15 else raw
                if (celsius in -2.0..45.0) sstValues += celsius
            }

            if (sstValues.isEmpty()) return null
            sstValues.average()
        } catch (e: Exception) {
            logger.debug("SST parsing failed: ${e.message}")
            null
        }
    }

}
