package com.shaka.service

import com.shaka.data.cache.SpotDataCache
import com.shaka.data.client.*
import com.shaka.model.*
import kotlinx.coroutines.*
import org.slf4j.LoggerFactory
import java.time.Instant
import java.time.LocalDate

/**
 * Background prefetch jobs for ocean data.
 * 
 * These jobs run on staggered schedules to pre-fetch data for all spots:
 * - Tide: Every 1 hour (tides change frequently)
 * - Weather (swell + wind): Every 3 hours (weather updates slowly)
 * - Satellite (SST + visibility): Every 6 hours (daily satellite data)
 * 
 * Rate limit management:
 * - NOAA CO-OPS (tide): No limit, ~7,200 calls/day
 * - Open-Meteo (weather): 10,000/day free tier, we use ~2,400/day
 * - NOAA ERDDAP (SST): No strict limit, ~1,200/day
 * - Copernicus (visibility): No limit, ~1,200/day
 * 
 * Processing strategy:
 * - Spots processed in batches of 10
 * - 500ms delay between batches for rate limiting
 * - Failed spots logged but don't stop the job
 */
class DataPrefetchJobs(
    private val spotDb: SpotDatabase,
    private val tidesClient: NOAATidesClient,
    private val openMeteo: OpenMeteoClient,
    private val copernicus: CopernicusClient,
    private val noaaClient: NOAAClient
) {
    private val logger = LoggerFactory.getLogger(DataPrefetchJobs::class.java)
    
    companion object {
        const val BATCH_SIZE = 10
        const val BATCH_DELAY_MS = 500L  // 500ms between batches
        const val SPOT_TIMEOUT_MS = 8000L  // 8s timeout per spot
    }
    
    // ==================== HOURLY: Tide Prefetch ====================
    
    /**
     * Prefetch tide data for all spots.
     * Runs every hour since tides change frequently.
     * 
     * Data source: NOAA CO-OPS (free, no rate limit)
     * Daily calls: ~7,200 (300 spots × 24 hours)
     */
    suspend fun prefetchTides() = withContext(Dispatchers.IO) {
        val spots = spotDb.getAllSpots()
        val today = LocalDate.now().toString()
        
        logger.info("Starting TIDE prefetch for ${spots.size} spots")
        val startTime = System.currentTimeMillis()
        var successCount = 0
        var errorCount = 0
        
        spots.chunked(BATCH_SIZE).forEachIndexed { batchIndex, batch ->
            val results = batch.map { spot ->
                async {
                    try {
                        withTimeout(SPOT_TIMEOUT_MS) {
                            val tideData = tidesClient.getTideData(
                                spot.coordinates.lat,
                                spot.coordinates.lon,
                                today
                            )
                            
                            // Find nearest station for reference
                            val stationId = tidesClient.findNearestStation(
                                spot.coordinates.lat,
                                spot.coordinates.lon
                            )
                            
                            SpotDataCache.updateTide(
                                spot.id,
                                SpotDataCache.CachedValue(
                                    value = SpotDataCache.TideInfo(
                                        state = tideData.tideState,
                                        nextHighTide = tideData.nextHighTide,
                                        nextLowTide = tideData.nextLowTide,
                                        currentHeight = tideData.currentHeight,
                                        stationId = stationId
                                    ),
                                    fetchedAt = Instant.now(),
                                    // Tide predictions are for current time, no separate data date
                                    dataValidAt = null
                                )
                            )
                            true
                        }
                    } catch (e: Exception) {
                        logger.debug("Tide fetch failed for ${spot.name}: ${e.message}")
                        false
                    }
                }
            }.awaitAll()
            
            successCount += results.count { it }
            errorCount += results.count { !it }
            
            // Rate limiting delay between batches
            if (batchIndex < spots.size / BATCH_SIZE) {
                delay(BATCH_DELAY_MS)
            }
        }
        
        val elapsed = System.currentTimeMillis() - startTime
        logger.info("TIDE prefetch complete: $successCount success, $errorCount errors in ${elapsed}ms")
    }
    
    // ==================== EVERY 3 HOURS: Weather Prefetch ====================
    
    /**
     * Prefetch weather data (swell + wind) for all spots.
     * Runs every 3 hours since weather changes slowly.
     * 
     * Data source: Open-Meteo (10,000/day free tier)
     * Daily calls: ~2,400 (300 spots × 8 times/day)
     * 
     * Combined call for marine + weather to reduce API usage.
     */
    suspend fun prefetchWeather() = withContext(Dispatchers.IO) {
        val spots = spotDb.getAllSpots()
        val today = LocalDate.now().toString()
        
        logger.info("Starting WEATHER prefetch for ${spots.size} spots")
        val startTime = System.currentTimeMillis()
        var successCount = 0
        var errorCount = 0
        
        spots.chunked(BATCH_SIZE).forEachIndexed { batchIndex, batch ->
            val results = batch.map { spot ->
                async {
                    try {
                        withTimeout(SPOT_TIMEOUT_MS) {
                            val lat = spot.coordinates.lat
                            val lon = spot.coordinates.lon
                            
                            // Fetch marine data (includes SST as backup)
                            val ocean = openMeteo.getMarineData(lat, lon, today)
                            
                            // Fetch weather data
                            val weather = openMeteo.getWeather(lat, lon, today)
                            
                            val now = Instant.now()
                            
                            // Update swell data
                            SpotDataCache.updateSwell(
                                spot.id,
                                SpotDataCache.CachedValue(
                                    value = SpotDataCache.SwellInfo(
                                        heightFt = SpotDataCache.metersToFeet(ocean.waveHeight),
                                        periodSec = ocean.wavePeriod,
                                        direction = SpotDataCache.degreesToCardinal(ocean.waveDirection.toDouble()),
                                        swellHeightFt = SpotDataCache.metersToFeet(ocean.swellHeight)
                                    ),
                                    fetchedAt = now,
                                    // Open-Meteo provides hourly forecasts, dataValidAt is "now"
                                    dataValidAt = now
                                )
                            )
                            
                            // Update wind data
                            SpotDataCache.updateWind(
                                spot.id,
                                SpotDataCache.CachedValue(
                                    value = SpotDataCache.WindInfo(
                                        speedKnots = SpotDataCache.kmhToKnots(weather.windSpeed),
                                        direction = SpotDataCache.degreesToCardinal(weather.windDirection.toDouble()),
                                        gustKnots = null  // Open-Meteo hourly doesn't include gusts in our query
                                    ),
                                    fetchedAt = now,
                                    dataValidAt = now
                                )
                            )
                            
                            true
                        }
                    } catch (e: Exception) {
                        logger.debug("Weather fetch failed for ${spot.name}: ${e.message}")
                        false
                    }
                }
            }.awaitAll()
            
            successCount += results.count { it }
            errorCount += results.count { !it }
            
            // Rate limiting delay
            if (batchIndex < spots.size / BATCH_SIZE) {
                delay(BATCH_DELAY_MS)
            }
        }
        
        val elapsed = System.currentTimeMillis() - startTime
        logger.info("WEATHER prefetch complete: $successCount success, $errorCount errors in ${elapsed}ms")
    }
    
    // ==================== EVERY 6 HOURS: Satellite Data Prefetch ====================
    
    /**
     * Prefetch satellite data (SST + visibility + chlorophyll) for all spots.
     * Runs every 6 hours since satellite data is typically daily.
     * 
     * Data sources:
     * - NOAA ERDDAP (SST): ~1,200 calls/day
     * - Copernicus WMTS (visibility): ~1,200 calls/day
     * 
     * Note: Satellite data has latency (1-2 days) so frequent updates aren't needed.
     */
    suspend fun prefetchSatelliteData() = withContext(Dispatchers.IO) {
        val spots = spotDb.getAllSpots()
        val today = LocalDate.now().toString()
        
        logger.info("Starting SATELLITE prefetch for ${spots.size} spots")
        val startTime = System.currentTimeMillis()
        var successCount = 0
        var errorCount = 0
        
        spots.chunked(BATCH_SIZE).forEachIndexed { batchIndex, batch ->
            val results = batch.map { spot ->
                async {
                    try {
                        withTimeout(SPOT_TIMEOUT_MS * 2) {  // Longer timeout for satellite data
                            val lat = spot.coordinates.lat
                            val lon = spot.coordinates.lon
                            val now = Instant.now()
                            
                            // Fetch SST from NOAA ERDDAP
                            try {
                                val sst = noaaClient.getSeaSurfaceTemperature(lat, lon, today)
                                SpotDataCache.updateSST(
                                    spot.id,
                                    SpotDataCache.CachedValue(
                                        value = sst,
                                        fetchedAt = now,
                                        // MUR SST is typically 1-2 days old
                                        dataValidAt = Instant.now().minusSeconds(86400)  // Approximate
                                    )
                                )
                            } catch (e: Exception) {
                                logger.debug("SST fetch failed for ${spot.name}: ${e.message}")
                            }
                            
                            // Fetch water quality from Copernicus
                            try {
                                val waterQuality = copernicus.getWaterQuality(lat, lon, today)
                                
                                waterQuality.visibility?.let { vis ->
                                    SpotDataCache.updateVisibility(
                                        spot.id,
                                        SpotDataCache.CachedValue(
                                            value = vis,
                                            fetchedAt = now,
                                            // Copernicus L3 NRT is typically 1 day old
                                            dataValidAt = Instant.now().minusSeconds(86400)
                                        )
                                    )
                                }
                                
                                waterQuality.chlorophyllA?.let { chl ->
                                    SpotDataCache.updateChlorophyll(
                                        spot.id,
                                        SpotDataCache.CachedValue(
                                            value = chl,
                                            fetchedAt = now,
                                            dataValidAt = Instant.now().minusSeconds(86400)
                                        )
                                    )
                                }
                            } catch (e: Exception) {
                                logger.debug("Water quality fetch failed for ${spot.name}: ${e.message}")
                            }
                            
                            true
                        }
                    } catch (e: Exception) {
                        logger.debug("Satellite fetch failed for ${spot.name}: ${e.message}")
                        false
                    }
                }
            }.awaitAll()
            
            successCount += results.count { it }
            errorCount += results.count { !it }
            
            // Rate limiting delay
            if (batchIndex < spots.size / BATCH_SIZE) {
                delay(BATCH_DELAY_MS)
            }
        }
        
        val elapsed = System.currentTimeMillis() - startTime
        logger.info("SATELLITE prefetch complete: $successCount success, $errorCount errors in ${elapsed}ms")
    }
    
    // ==================== Full Prefetch (Startup) ====================
    
    /**
     * Run all prefetch jobs in sequence.
     * Used on startup to populate the cache quickly.
     */
    suspend fun prefetchAll() {
        logger.info("Starting FULL prefetch for all data types")
        val startTime = System.currentTimeMillis()
        
        // Run in sequence to avoid overwhelming APIs
        prefetchTides()
        delay(5000)  // 5s gap
        
        prefetchWeather()
        delay(5000)  // 5s gap
        
        prefetchSatelliteData()
        
        val elapsed = System.currentTimeMillis() - startTime
        logger.info("FULL prefetch complete in ${elapsed}ms. Cache now has ${SpotDataCache.size()} spots")
        logger.info("Cache stats: ${SpotDataCache.getStats()}")
    }
    
    // ==================== Status ====================
    
    /**
     * Get current prefetch status and cache statistics.
     */
    fun getStatus(): Map<String, Any> {
        return mapOf(
            "cacheStats" to SpotDataCache.getStats(),
            "totalSpots" to spotDb.getAllSpots().size,
            "cachedSpots" to SpotDataCache.size()
        )
    }
}
