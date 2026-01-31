package com.shaka.data.client

import io.ktor.client.request.*
import io.ktor.client.statement.*
import org.slf4j.LoggerFactory

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
    private val client = HttpClientFactory.shared

    companion object {
        // NOAA CoastWatch ERDDAP - MUR SST (0.01° resolution, daily)
        private const val MUR_SST_URL = "https://coastwatch.pfeg.noaa.gov/erddap/griddap/jplMURSST41.json"
        
        // NOAA GHRSST Level 4 (alternative, global coverage)
        private const val GHRSST_URL = "https://coastwatch.pfeg.noaa.gov/erddap/griddap/nceiPH53sstd1day.json"
        
        // NOAA CoastWatch VIIRS Chlorophyll-a (daily, ~4km resolution)
        private const val VIIRS_CHL_URL = "https://coastwatch.noaa.gov/erddap/griddap/noaacwNPPVIIRSchlaDaily.json"
        
        // Alternative: NOAA-20 VIIRS chlorophyll (newer satellite)
        private const val NOAA20_CHL_URL = "https://coastwatch.noaa.gov/erddap/griddap/noaacwN20VIIRSchlaDaily.json"
    }

    /**
     * Get real Sea Surface Temperature from NOAA MUR SST dataset.
     * Returns temperature in Celsius.
     * 
     * Falls back to regional climatological estimate if satellite data unavailable.
     * 
     * @param lat Latitude
     * @param lon Longitude  
     * @param date Date in YYYY-MM-DD format
     * @return SST in Celsius (always returns a value, never null)
     */
    suspend fun getSeaSurfaceTemperature(lat: Double, lon: Double, date: String): Double {
        return try {
            // Rate limit
            RateLimiters.noaa.acquire()
            
            // Try MUR SST first (best resolution for coastal waters)
            val sst = getMURSST(lat, lon, date) ?: getGHRSST(lat, lon, date)
            if (sst != null) {
                logger.info("NOAA SST for ($lat, $lon): ${String.format("%.1f", sst)}°C")
                sst
            } else {
                logger.info("NOAA SST unavailable for ($lat, $lon), using regional estimate")
                getRegionalSSTEstimate(lat, lon, date)
            }
        } catch (e: Exception) {
            logger.warn("NOAA SST fetch failed for ($lat, $lon): ${e.message}")
            // Return regional estimate as fallback
            getRegionalSSTEstimate(lat, lon, date)
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
     * Query MUR SST dataset - Multi-scale Ultra-high Resolution SST.
     */
    private suspend fun getMURSST(lat: Double, lon: Double, date: String): Double? {
        return try {
            val dateTime = "${date}T12:00:00Z"
            
            val latMin = lat - 0.05
            val latMax = lat + 0.05
            val lonMin = lon - 0.05
            val lonMax = lon + 0.05
            
            val url = "$MUR_SST_URL?analysed_sst[($dateTime)][($latMin):($latMax)][($lonMin):($lonMax)]"
            
            val response: String = client.get(url).bodyAsText()
            parseSSTFromERDDAP(response)
        } catch (e: Exception) {
            logger.debug("MUR SST unavailable: ${e.message}")
            null
        }
    }

    /**
     * Query GHRSST dataset - Global High Resolution SST.
     */
    private suspend fun getGHRSST(lat: Double, lon: Double, date: String): Double? {
        return try {
            // Rate limit second attempt
            RateLimiters.noaa.acquire()
            
            val latMin = lat - 0.1
            val latMax = lat + 0.1
            val lonMin = lon - 0.1
            val lonMax = lon + 0.1
            
            val url = "$GHRSST_URL?sea_surface_temperature[($date)][($latMin):($latMax)][($lonMin):($lonMax)]"
            
            val response: String = client.get(url).bodyAsText()
            parseSSTFromERDDAP(response)
        } catch (e: Exception) {
            logger.debug("GHRSST unavailable: ${e.message}")
            null
        }
    }

    /**
     * Parse SST value from ERDDAP JSON response.
     */
    private fun parseSSTFromERDDAP(jsonResponse: String): Double? {
        return try {
            val regex = """"rows"\s*:\s*\[\s*\[([^\]]+)\]""".toRegex()
            val match = regex.find(jsonResponse)
            
            if (match != null) {
                val rowData = match.groupValues[1]
                val values = rowData.split(",").map { it.trim() }
                val sstValue = values.lastOrNull()?.toDoubleOrNull()
                
                if (sstValue != null) {
                    // MUR SST is in Kelvin, convert to Celsius
                    if (sstValue > 200) {
                        return sstValue - 273.15
                    }
                    return sstValue
                }
            }
            null
        } catch (e: Exception) {
            logger.debug("SST parsing failed: ${e.message}")
            null
        }
    }

    /**
     * Regional SST estimates based on climatological averages.
     * Used as fallback when NOAA data is unavailable.
     */
    fun getRegionalSSTEstimate(lat: Double, lon: Double, date: String): Double {
        val month = try {
            date.substring(5, 7).toInt()
        } catch (e: Exception) {
            6 // Default to June
        }
        
        val seasonalOffset = when (month) {
            12, 1, 2 -> -2.0
            3, 4, 5 -> 0.0
            6, 7, 8 -> 2.0
            9, 10, 11 -> 0.0
            else -> 0.0
        }

        // Hawaii
        if (lat in 18.0..23.0 && lon in -161.0..-154.0) {
            return 25.0 + seasonalOffset * 0.5
        }
        
        // Channel Islands & Catalina
        if (lat in 32.5..34.2 && lon in -120.5..-117.5) {
            val baseTemp = 14.5
            val summerBonus = when (month) {
                6, 7, 8, 9 -> 4.0
                5, 10 -> 2.0
                else -> 0.0
            }
            logger.info("Channel Islands/Catalina SST estimate: ${baseTemp + summerBonus}°C")
            return baseTemp + summerBonus
        }
        
        // Southern California mainland coast
        if (lat in 32.0..34.5 && lon in -118.5..-117.0) {
            return 16.0 + seasonalOffset
        }
        
        // Central California
        if (lat in 34.5..38.0 && lon in -123.0..-121.0) {
            return 13.0 + seasonalOffset
        }
        
        // Northern California / Oregon
        if (lat in 38.0..46.0 && lon in -125.0..-123.0) {
            return 12.0 + seasonalOffset
        }
        
        // Florida Keys / South Florida
        if (lat in 24.0..27.0 && lon in -83.0..-80.0) {
            return 27.0 + seasonalOffset * 0.7
        }
        
        // Florida Atlantic coast
        if (lat in 27.0..31.0 && lon in -81.0..-79.0) {
            return 25.0 + seasonalOffset
        }
        
        // Florida Gulf coast
        if (lat in 25.0..30.0 && lon in -87.0..-81.0) {
            return 26.0 + seasonalOffset
        }
        
        // Caribbean
        if (lat in 15.0..25.0 && lon in -90.0..-60.0) {
            return 28.0 + seasonalOffset * 0.3
        }
        
        // Mediterranean
        if (lat in 30.0..45.0 && lon in -5.0..35.0) {
            return 22.0 + seasonalOffset
        }
        
        // Australia - Great Barrier Reef
        if (lat in -25.0..-10.0 && lon in 142.0..155.0) {
            val shSeasonalOffset = -seasonalOffset
            return 26.0 + shSeasonalOffset * 0.5
        }
        
        // Indonesia / Philippines
        if (lat in -10.0..20.0 && lon in 95.0..140.0) {
            return 29.0 + seasonalOffset * 0.2
        }
        
        // Default based on latitude
        return when {
            lat in -10.0..10.0 -> 28.0
            lat in 10.0..23.0 || lat in -23.0..-10.0 -> 26.0 + seasonalOffset * 0.5
            lat in 23.0..35.0 || lat in -35.0..-23.0 -> 22.0 + seasonalOffset
            lat in 35.0..50.0 || lat in -50.0..-35.0 -> 16.0 + seasonalOffset
            else -> 12.0 + seasonalOffset
        }
    }
}
