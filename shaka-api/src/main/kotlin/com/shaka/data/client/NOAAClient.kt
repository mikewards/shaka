package com.shaka.data.client

import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.engine.cio.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.serialization.json.Json
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
 * API: https://coastwatch.pfeg.noaa.gov/erddap/griddap/
 */
class NOAAClient {
    
    private val logger = LoggerFactory.getLogger(NOAAClient::class.java)
    
    private val client = HttpClient(CIO) {
        engine {
            requestTimeout = 10_000 // 10 seconds
        }
        install(ContentNegotiation) {
            json(Json {
                ignoreUnknownKeys = true
                isLenient = true
            })
        }
    }

    companion object {
        // NOAA CoastWatch ERDDAP - MUR SST (0.01° resolution, daily)
        // Updated URL: pfeg.noaa.gov now redirects to coastwatch.noaa.gov
        private const val MUR_SST_URL = "https://coastwatch.pfeg.noaa.gov/erddap/griddap/jplMURSST41.json"
        
        // NOAA GHRSST Level 4 (alternative, global coverage)
        private const val GHRSST_URL = "https://coastwatch.pfeg.noaa.gov/erddap/griddap/nceiPH53sstd1day.json"
        
        // NOAA CoastWatch VIIRS Chlorophyll-a (daily, ~4km resolution)
        // Near Real-Time data from NOAA-20 VIIRS satellite
        // Updated to use new coastwatch.noaa.gov endpoint (old pfeg redirects)
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
     * 
     * Chlorophyll-a interpretation:
     * - 0.1-0.3 mg/m³: Very clear (oligotrophic, like Hawaii)
     * - 0.3-1.0 mg/m³: Clear to moderate
     * - 1.0-5.0 mg/m³: Productive coastal waters
     * - >5.0 mg/m³: High productivity / potential bloom
     * 
     * @param lat Latitude
     * @param lon Longitude  
     * @param date Date in YYYY-MM-DD format
     * @return Chlorophyll-a in mg/m³, or null if unavailable
     */
    suspend fun getChlorophyll(lat: Double, lon: Double, date: String): Double? {
        return try {
            // Try S-NPP VIIRS first, then NOAA-20 VIIRS as backup
            getVIIRSChlorophyll(lat, lon, date) ?: getNOAA20Chlorophyll(lat, lon, date)
        } catch (e: Exception) {
            logger.warn("NOAA Chlorophyll fetch failed for ($lat, $lon): ${e.message}")
            null
        }
    }

    /**
     * Query VIIRS chlorophyll dataset from NOAA NESDIS.
     * Near Real-Time daily chlorophyll from S-NPP VIIRS, ~4km resolution.
     * Data source: https://coastwatch.noaa.gov/erddap/griddap/noaacwNPPVIIRSchlaDaily
     * 
     * NOTE: Satellite data has 3-4 day latency. Uses "(last)" to get most recent available.
     */
    private suspend fun getVIIRSChlorophyll(lat: Double, lon: Double, date: String): Double? {
        return try {
            // Query a small area around the point
            val latMin = lat - 0.1
            val latMax = lat + 0.1
            val lonMin = lon - 0.1
            val lonMax = lon + 0.1
            
            // Use "(last)" to get most recent available data (satellite has 3-4 day latency)
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
     * Near Real-Time daily chlorophyll from NOAA-20, ~4km resolution.
     * Uses "(last)" to get most recent available data.
     */
    private suspend fun getNOAA20Chlorophyll(lat: Double, lon: Double, date: String): Double? {
        return try {
            val latMin = lat - 0.1
            val latMax = lat + 0.1
            val lonMin = lon - 0.1
            val lonMax = lon + 0.1
            
            // Use "(last)" to get most recent available data
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
            // ERDDAP JSON format has data in "table" -> "rows" array
            val regex = """"rows"\s*:\s*\[\s*\[([^\]]+)\]""".toRegex()
            val match = regex.find(jsonResponse)
            
            if (match != null) {
                val rowData = match.groupValues[1]
                // Chlorophyll is typically the last value
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
     * Best for coastal waters, 0.01° (~1km) resolution.
     */
    private suspend fun getMURSST(lat: Double, lon: Double, date: String): Double? {
        return try {
            // MUR SST uses ISO datetime format
            val dateTime = "${date}T12:00:00Z"
            
            // Query a small area around the point
            val latMin = lat - 0.05
            val latMax = lat + 0.05
            val lonMin = lon - 0.05
            val lonMax = lon + 0.05
            
            val url = "$MUR_SST_URL?analysed_sst[($dateTime)][($latMin):($latMax)][($lonMin):($lonMax)]"
            
            val response: String = client.get(url).bodyAsText()
            
            // Parse the JSON response to extract SST value
            parseSSTFromERDDAP(response)
        } catch (e: Exception) {
            logger.debug("MUR SST unavailable: ${e.message}")
            null
        }
    }

    /**
     * Query GHRSST dataset - Global High Resolution SST.
     * Broader coverage, 0.05° resolution.
     */
    private suspend fun getGHRSST(lat: Double, lon: Double, date: String): Double? {
        return try {
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
     * ERDDAP returns data in a specific JSON structure with table/rows format.
     */
    private fun parseSSTFromERDDAP(jsonResponse: String): Double? {
        return try {
            // ERDDAP JSON format has data in "table" -> "rows" array
            // Each row contains [time, lat, lon, sst_value]
            val regex = """"rows"\s*:\s*\[\s*\[([^\]]+)\]""".toRegex()
            val match = regex.find(jsonResponse)
            
            if (match != null) {
                val rowData = match.groupValues[1]
                // SST is typically the last value, in Kelvin for MUR SST
                val values = rowData.split(",").map { it.trim() }
                val sstValue = values.lastOrNull()?.toDoubleOrNull()
                
                if (sstValue != null) {
                    // MUR SST is in Kelvin, convert to Celsius
                    if (sstValue > 200) {
                        return sstValue - 273.15
                    }
                    // Already in Celsius
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
     * 
     * These are based on actual oceanographic data patterns:
     * - Seasonal variations
     * - Regional ocean current patterns
     * - Upwelling zones
     */
    fun getRegionalSSTEstimate(lat: Double, lon: Double, date: String): Double {
        val month = try {
            date.substring(5, 7).toInt()
        } catch (e: Exception) {
            6 // Default to June
        }
        
        // Seasonal adjustment (-2 to +2°C based on month)
        val seasonalOffset = when (month) {
            12, 1, 2 -> -2.0  // Winter
            3, 4, 5 -> 0.0    // Spring
            6, 7, 8 -> 2.0    // Summer  
            9, 10, 11 -> 0.0  // Fall
            else -> 0.0
        }

        // Hawaii - warm tropical waters, relatively stable
        if (lat in 18.0..23.0 && lon in -161.0..-154.0) {
            return 25.0 + seasonalOffset * 0.5 // Less seasonal variation in tropics
        }
        
        // Channel Islands & Catalina (cold upwelling zone)
        // Catalina: 33.4°N, -118.4°W - water rarely exceeds 68°F (20°C)
        if (lat in 32.5..34.2 && lon in -120.5..-117.5) {
            // January average: ~14-15°C (57-59°F)
            // August average: ~18-20°C (64-68°F)
            val baseTemp = 14.5 // Winter baseline
            val summerBonus = when (month) {
                6, 7, 8, 9 -> 4.0  // Summer peak
                5, 10 -> 2.0       // Shoulder
                else -> 0.0        // Winter
            }
            logger.info("Channel Islands/Catalina SST estimate: ${baseTemp + summerBonus}°C")
            return baseTemp + summerBonus
        }
        
        // Southern California mainland coast (San Diego to LA)
        if (lat in 32.0..34.5 && lon in -118.5..-117.0) {
            return 16.0 + seasonalOffset // Slightly warmer than islands
        }
        
        // Central California (Monterey to SF)
        if (lat in 34.5..38.0 && lon in -123.0..-121.0) {
            return 13.0 + seasonalOffset // Strong upwelling, cold
        }
        
        // Northern California / Oregon
        if (lat in 38.0..46.0 && lon in -125.0..-123.0) {
            return 12.0 + seasonalOffset // Cold waters
        }
        
        // Florida Keys / South Florida
        if (lat in 24.0..27.0 && lon in -83.0..-80.0) {
            return 27.0 + seasonalOffset * 0.7 // Warm Gulf Stream influence
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
            return 28.0 + seasonalOffset * 0.3 // Stable warm tropics
        }
        
        // Mediterranean
        if (lat in 30.0..45.0 && lon in -5.0..35.0) {
            return 22.0 + seasonalOffset
        }
        
        // Australia - Great Barrier Reef
        if (lat in -25.0..-10.0 && lon in 142.0..155.0) {
            // Southern hemisphere - reverse seasons
            val shSeasonalOffset = -seasonalOffset
            return 26.0 + shSeasonalOffset * 0.5
        }
        
        // Indonesia / Philippines
        if (lat in -10.0..20.0 && lon in 95.0..140.0) {
            return 29.0 + seasonalOffset * 0.2 // Very warm, stable
        }
        
        // Default based on latitude (general ocean pattern)
        return when {
            lat in -10.0..10.0 -> 28.0  // Equatorial
            lat in 10.0..23.0 || lat in -23.0..-10.0 -> 26.0 + seasonalOffset * 0.5 // Tropical
            lat in 23.0..35.0 || lat in -35.0..-23.0 -> 22.0 + seasonalOffset // Subtropical
            lat in 35.0..50.0 || lat in -50.0..-35.0 -> 16.0 + seasonalOffset // Temperate
            else -> 12.0 + seasonalOffset // Cold
        }
    }
}
