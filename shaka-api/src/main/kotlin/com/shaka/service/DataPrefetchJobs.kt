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
        
        // Satellite prefetch is more conservative - Copernicus doesn't like concurrency
        const val SATELLITE_BATCH_SIZE = 2
        const val SATELLITE_BATCH_DELAY_MS = 2000L  // 2s between batches
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
                            // Persist to database
                            SpotDataCache.saveToDatabase(spot.id)
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
                            
                            // Persist to database
                            SpotDataCache.saveToDatabase(spot.id)
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
        // Date for SST/caching - the WMTS client auto-detects available satellite dates
        val today = LocalDate.now().toString()
        
        logger.info("Starting SATELLITE prefetch for ${spots.size} spots (conservative: batch=${SATELLITE_BATCH_SIZE}, delay=${SATELLITE_BATCH_DELAY_MS}ms)")
        val startTime = System.currentTimeMillis()
        var successCount = 0
        var errorCount = 0
        var consecutiveFailures = 0
        
        // Health check - test Copernicus is responding (use a known ocean location)
        // Bahamas (26.5, -77.5) - the WMTS client will auto-fallback to available dates
        try {
            logger.info("Testing Copernicus connectivity...")
            val testResult = copernicus.getWaterQuality(26.5, -77.5, today)
            // Pass if we got ANY response (even null vis means Copernicus responded)
            logger.info("Copernicus health check passed (vis=${testResult.visibility}, chl=${testResult.chlorophyllA})")
        } catch (e: Exception) {
            logger.warn("Copernicus health check failed: ${e.message} - skipping satellite prefetch")
            return@withContext
        }
        
        // Process ONE spot at a time - slow and steady
        for ((index, spot) in spots.withIndex()) {
            // Circuit breaker - stop if too many consecutive failures
            if (consecutiveFailures >= 5) {
                logger.warn("Circuit breaker triggered after $consecutiveFailures consecutive failures - stopping satellite prefetch")
                break
            }
            
            try {
                val lat = spot.coordinates.lat
                val lon = spot.coordinates.lon
                val now = Instant.now()
                var gotData = false
                
                // Fetch SST from NOAA ERDDAP
                try {
                    val sst = noaaClient.getSeaSurfaceTemperature(lat, lon, today)
                    SpotDataCache.updateSST(
                        spot.id,
                        SpotDataCache.CachedValue(
                            value = sst,
                            fetchedAt = now,
                            dataValidAt = Instant.now().minusSeconds(86400)
                        )
                    )
                    gotData = true
                } catch (e: Exception) {
                    logger.debug("SST fetch failed for ${spot.name}: ${e.message}")
                }
                
                // Fetch water quality from Copernicus - one request at a time
                try {
                    val waterQuality = copernicus.getWaterQuality(lat, lon, today)
                    
                    waterQuality.visibility?.let { vis ->
                        SpotDataCache.updateVisibility(
                            spot.id,
                            SpotDataCache.CachedValue(
                                value = vis,
                                fetchedAt = now,
                                dataValidAt = Instant.now().minusSeconds(86400)
                            )
                        )
                        gotData = true
                        logger.info("Cached visibility for ${spot.name}: ${vis}m")
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
                        gotData = true
                    }
                } catch (e: Exception) {
                    logger.debug("Water quality fetch failed for ${spot.name}: ${e.message}")
                }
                
                if (gotData) {
                    // Persist to database
                    SpotDataCache.saveToDatabase(spot.id)
                    successCount++
                    consecutiveFailures = 0  // Reset on success
                } else {
                    errorCount++
                    consecutiveFailures++
                }
                
            } catch (e: Exception) {
                logger.debug("Satellite fetch failed for ${spot.name}: ${e.message}")
                errorCount++
                consecutiveFailures++
            }
            
            // Log progress every 50 spots
            if (index > 0 && index % 50 == 0) {
                logger.info("Satellite prefetch progress: $index/${spots.size} spots ($successCount success, $errorCount errors)")
            }
            
            // Wait between each request - be gentle
            delay(1000)  // 1 second between each spot
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
