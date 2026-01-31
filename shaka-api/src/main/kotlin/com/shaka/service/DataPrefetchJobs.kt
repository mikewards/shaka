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
 * ENTERPRISE PATTERNS:
 * - Cache-aware: Only fetches data for spots that need updates
 * - Rate-limited: Uses RateLimiters for all external APIs
 * - Circuit-breaker: Integrates with CopernicusWMTSClient circuit breaker
 * - Graceful degradation: Continues on individual failures
 * 
 * Schedule:
 * - Tide: Every 1 hour (tides change frequently)
 * - Weather (swell + wind): Every 3 hours (weather updates slowly)
 * - Satellite (SST + visibility): Every 6 hours (daily satellite data)
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
        const val BATCH_DELAY_MS = 500L
        const val SPOT_TIMEOUT_MS = 15000L  // 15s timeout (rate limiter adds delay)
        
        // Cache staleness thresholds
        const val TIDE_STALE_HOURS = 2      // Refetch if older than 2h
        const val WEATHER_STALE_HOURS = 4   // Refetch if older than 4h  
        const val SATELLITE_STALE_HOURS = 12 // Refetch if older than 12h
    }
    
    // ==================== HOURLY: Tide Prefetch ====================
    
    /**
     * Prefetch tide data for spots with stale or missing data.
     * Cache-aware: skips spots with fresh data.
     */
    suspend fun prefetchTides() = withContext(Dispatchers.IO) {
        val allSpots = spotDb.getAllSpots()
        val today = LocalDate.now().toString()
        
        // Filter to spots that need updating
        val spotsToUpdate = allSpots.filter { spot ->
            val cached = SpotDataCache.get(spot.id)
            cached?.tide == null || isStale(cached.tide.fetchedAt, TIDE_STALE_HOURS)
        }
        
        logger.info("TIDE prefetch: ${spotsToUpdate.size}/${allSpots.size} spots need updates")
        
        if (spotsToUpdate.isEmpty()) {
            logger.info("TIDE prefetch: All spots have fresh data, skipping")
            return@withContext
        }
        
        val startTime = System.currentTimeMillis()
        var successCount = 0
        var errorCount = 0
        
        spotsToUpdate.chunked(BATCH_SIZE).forEachIndexed { batchIndex, batch ->
            val results = batch.map { spot ->
                async {
                    try {
                        withTimeout(SPOT_TIMEOUT_MS) {
                            val tideData = tidesClient.getTideData(
                                spot.coordinates.lat,
                                spot.coordinates.lon,
                                today
                            )
                            
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
                                    dataValidAt = null
                                )
                            )
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
            
            if (batchIndex < spotsToUpdate.size / BATCH_SIZE) {
                delay(BATCH_DELAY_MS)
            }
        }
        
        val elapsed = System.currentTimeMillis() - startTime
        logger.info("TIDE prefetch complete: $successCount success, $errorCount errors in ${elapsed}ms")
        logRateLimiterStats()
    }
    
    // ==================== EVERY 3 HOURS: Weather Prefetch ====================
    
    /**
     * Prefetch weather data for spots with stale or missing data.
     * Cache-aware: skips spots with fresh data.
     */
    suspend fun prefetchWeather() = withContext(Dispatchers.IO) {
        val allSpots = spotDb.getAllSpots()
        val today = LocalDate.now().toString()
        
        // Filter to spots that need updating
        val spotsToUpdate = allSpots.filter { spot ->
            val cached = SpotDataCache.get(spot.id)
            cached?.swell == null || cached.wind == null || 
                isStale(cached.swell.fetchedAt, WEATHER_STALE_HOURS)
        }
        
        logger.info("WEATHER prefetch: ${spotsToUpdate.size}/${allSpots.size} spots need updates")
        
        if (spotsToUpdate.isEmpty()) {
            logger.info("WEATHER prefetch: All spots have fresh data, skipping")
            return@withContext
        }
        
        val startTime = System.currentTimeMillis()
        var successCount = 0
        var errorCount = 0
        
        spotsToUpdate.chunked(BATCH_SIZE).forEachIndexed { batchIndex, batch ->
            val results = batch.map { spot ->
                async {
                    try {
                        withTimeout(SPOT_TIMEOUT_MS) {
                            val lat = spot.coordinates.lat
                            val lon = spot.coordinates.lon
                            
                            val ocean = openMeteo.getMarineData(lat, lon, today)
                            val weather = openMeteo.getWeather(lat, lon, today)
                            
                            val now = Instant.now()
                            
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
                                    dataValidAt = now
                                )
                            )
                            
                            SpotDataCache.updateWind(
                                spot.id,
                                SpotDataCache.CachedValue(
                                    value = SpotDataCache.WindInfo(
                                        speedKnots = SpotDataCache.kmhToKnots(weather.windSpeed),
                                        direction = SpotDataCache.degreesToCardinal(weather.windDirection.toDouble()),
                                        gustKnots = null
                                    ),
                                    fetchedAt = now,
                                    dataValidAt = now
                                )
                            )
                            
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
            
            if (batchIndex < spotsToUpdate.size / BATCH_SIZE) {
                delay(BATCH_DELAY_MS)
            }
        }
        
        val elapsed = System.currentTimeMillis() - startTime
        logger.info("WEATHER prefetch complete: $successCount success, $errorCount errors in ${elapsed}ms")
        logRateLimiterStats()
    }
    
    // ==================== EVERY 6 HOURS: Satellite Data Prefetch ====================
    
    /**
     * Prefetch satellite data for spots with stale or missing data.
     * 
     * Cache-aware: Only fetches for spots missing visibility/SST data
     * or where existing data is older than SATELLITE_STALE_HOURS.
     * 
     * Sequential processing respects CopernicusWMTSClient circuit breaker.
     */
    suspend fun prefetchSatelliteData() = withContext(Dispatchers.IO) {
        val allSpots = spotDb.getAllSpots()
        val today = LocalDate.now().toString()
        
        // Filter to spots that need updating
        val spotsToUpdate = allSpots.filter { spot ->
            val cached = SpotDataCache.get(spot.id)
            cached?.visibility == null || cached.sst == null ||
                isStale(cached.visibility?.fetchedAt, SATELLITE_STALE_HOURS)
        }
        
        logger.info("SATELLITE prefetch: ${spotsToUpdate.size}/${allSpots.size} spots need updates")
        
        if (spotsToUpdate.isEmpty()) {
            logger.info("SATELLITE prefetch: All spots have fresh data, skipping")
            return@withContext
        }
        
        val startTime = System.currentTimeMillis()
        var successCount = 0
        var errorCount = 0
        var skippedCount = 0
        
        // Health check with circuit breaker awareness
        logger.info("Testing Copernicus connectivity...")
        try {
            val testResult = copernicus.getWaterQuality(26.5, -77.5, today)
            logger.info("Copernicus health check passed (vis=${testResult.visibility}, chl=${testResult.chlorophyllA})")
        } catch (e: CircuitBreakerOpenException) {
            logger.warn("Copernicus circuit breaker is OPEN - skipping satellite prefetch entirely")
            return@withContext
        } catch (e: Exception) {
            logger.warn("Copernicus health check failed: ${e.message} - skipping satellite prefetch")
            return@withContext
        }
        
        // Process sequentially - Copernicus doesn't handle concurrency well
        for ((index, spot) in spotsToUpdate.withIndex()) {
            try {
                val lat = spot.coordinates.lat
                val lon = spot.coordinates.lon
                val now = Instant.now()
                var gotData = false
                
                // SST from NOAA
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
                
                // Water quality from Copernicus
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
                } catch (e: CircuitBreakerOpenException) {
                    logger.info("Circuit breaker opened - stopping satellite prefetch early")
                    skippedCount = spotsToUpdate.size - index - 1
                    break
                } catch (e: Exception) {
                    logger.debug("Water quality fetch failed for ${spot.name}: ${e.message}")
                }
                
                if (gotData) {
                    SpotDataCache.saveToDatabase(spot.id)
                    successCount++
                } else {
                    errorCount++
                }
                
            } catch (e: Exception) {
                logger.debug("Satellite fetch failed for ${spot.name}: ${e.message}")
                errorCount++
            }
            
            // Progress logging
            if (index > 0 && index % 50 == 0) {
                logger.info("Satellite prefetch progress: $index/${spotsToUpdate.size} ($successCount success, $errorCount errors)")
            }
            
            // No explicit delay - rate limiter handles it
        }
        
        val elapsed = System.currentTimeMillis() - startTime
        logger.info("SATELLITE prefetch complete: $successCount success, $errorCount errors, $skippedCount skipped in ${elapsed}ms")
        logRateLimiterStats()
    }
    
    // ==================== Full Prefetch (Startup) ====================
    
    /**
     * Run all prefetch jobs in sequence.
     * Used on startup to populate the cache quickly.
     */
    suspend fun prefetchAll() {
        logger.info("Starting FULL prefetch for all data types")
        logger.info("Rate limiter config: ${RateLimiters.getAllStats()}")
        
        val startTime = System.currentTimeMillis()
        
        // Run in sequence to avoid overwhelming APIs
        prefetchTides()
        delay(3000)
        
        prefetchWeather()
        delay(3000)
        
        prefetchSatelliteData()
        
        val elapsed = System.currentTimeMillis() - startTime
        logger.info("FULL prefetch complete in ${elapsed}ms. Cache now has ${SpotDataCache.size()} spots")
        logger.info("Cache stats: ${SpotDataCache.getStats()}")
        logRateLimiterStats()
    }
    
    // ==================== Utilities ====================
    
    /**
     * Check if a timestamp is stale (older than given hours).
     */
    private fun isStale(fetchedAt: Instant?, staleHours: Int): Boolean {
        if (fetchedAt == null) return true
        val ageMs = Instant.now().toEpochMilli() - fetchedAt.toEpochMilli()
        val ageHours = ageMs / (1000 * 60 * 60)
        return ageHours >= staleHours
    }
    
    /**
     * Log rate limiter statistics.
     */
    private fun logRateLimiterStats() {
        logger.info("Rate limiter stats: ${RateLimiters.getAllStats()}")
    }
    
    /**
     * Get current prefetch status and cache statistics.
     */
    fun getStatus(): Map<String, Any> {
        return mapOf(
            "cacheStats" to SpotDataCache.getStats(),
            "totalSpots" to spotDb.getAllSpots().size,
            "cachedSpots" to SpotDataCache.size(),
            "rateLimiters" to RateLimiters.getAllStats()
        )
    }
}
