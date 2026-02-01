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
    private val noaaClient: NOAAClient,
    private val protectedSeasClient: ProtectedSeasClient = ProtectedSeasClient()
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
        const val MPA_STALE_HOURS = 168     // Weekly (168 hours) - MPA boundaries rarely change
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
                
                // GIBS satellite chlorophyll (all 5 satellites, today + yesterday)
                // Also fetches observation timestamps from NASA CMR
                try {
                    val gibsData = GIBSClient.getAllChlorophyll(lat, lon)
                    SpotDataCache.updateGIBSChlorophyll(
                        spot.id,
                        SpotDataCache.CachedValue(
                            value = SpotDataCache.GIBSSatelliteData(
                                paceToday = gibsData.paceToday,
                                paceYesterday = gibsData.paceYesterday,
                                noaa20Today = gibsData.noaa20Today,
                                noaa20Yesterday = gibsData.noaa20Yesterday,
                                noaa21Today = gibsData.noaa21Today,
                                noaa21Yesterday = gibsData.noaa21Yesterday,
                                sentinel3aToday = gibsData.sentinel3aToday,
                                sentinel3aYesterday = gibsData.sentinel3aYesterday,
                                sentinel3bToday = gibsData.sentinel3bToday,
                                sentinel3bYesterday = gibsData.sentinel3bYesterday,
                                dataDate = gibsData.dataDate,
                                paceObservationTime = gibsData.paceObservationTime,
                                noaa20ObservationTime = gibsData.noaa20ObservationTime,
                                noaa21ObservationTime = gibsData.noaa21ObservationTime
                            ),
                            fetchedAt = now
                        )
                    )
                    gotData = true
                } catch (e: Exception) {
                    logger.debug("GIBS fetch failed for ${spot.name}: ${e.message}")
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
    
    // ==================== WEEKLY: MPA Prefetch ====================
    
    /**
     * Prefetch MPA (Marine Protected Area) data for spots with stale or missing data.
     * MPA boundaries rarely change, so weekly updates are sufficient.
     */
    suspend fun prefetchMPA() = withContext(Dispatchers.IO) {
        val allSpots = spotDb.getAllSpots()
        
        // Filter to spots that need updating (no data or data older than 1 week)
        val spotsToUpdate = SpotDataCache.getSpotsWithStaleMPA(MPA_STALE_HOURS.toLong())
            .mapNotNull { spotId -> allSpots.find { it.id == spotId } }
            .ifEmpty {
                // If no stale spots in cache, check if any cached spots are missing MPA
                SpotDataCache.getSpotsWithoutMPA()
                    .mapNotNull { spotId -> allSpots.find { it.id == spotId } }
            }
            .ifEmpty {
                // If all cached spots have MPA, check for any spots not yet in cache
                allSpots.filter { spot -> SpotDataCache.get(spot.id)?.mpa == null }
            }
        
        logger.info("MPA prefetch: ${spotsToUpdate.size}/${allSpots.size} spots need updates")
        
        if (spotsToUpdate.isEmpty()) {
            logger.info("MPA prefetch: All spots have fresh data, skipping")
            return@withContext
        }
        
        val startTime = System.currentTimeMillis()
        var successCount = 0
        var errorCount = 0
        
        // Process sequentially with small delays (conservative rate limiting for Esri API)
        spotsToUpdate.forEachIndexed { index, spot ->
            try {
                withTimeout(SPOT_TIMEOUT_MS) {
                    val mpaInfo = protectedSeasClient.getMPAStatus(
                        spot.coordinates.lat,
                        spot.coordinates.lon
                    )
                    
                    // Convert to cache format (null mpaInfo is valid - means no specific MPA)
                    val cacheInfo = mpaInfo?.let {
                        SpotDataCache.MPACacheInfo(
                            siteName = it.siteName,
                            designation = it.designation,
                            spearfishingStatus = it.spearfishingStatus,
                            protectionLevel = it.protectionLevel,
                            speciesOfConcern = it.speciesOfConcern,
                            purpose = it.purpose,
                            detailsUrl = it.detailsUrl
                        )
                    }
                    
                    SpotDataCache.updateMPA(
                        spot.id,
                        SpotDataCache.CachedValue(cacheInfo, Instant.now())
                    )
                    SpotDataCache.saveToDatabase(spot.id)
                    successCount++
                    
                    if (mpaInfo != null) {
                        logger.debug("MPA for ${spot.name}: ${mpaInfo.siteName} (spearfishing=${mpaInfo.spearfishingStatus})")
                    } else {
                        logger.debug("MPA for ${spot.name}: No specific MPA found")
                    }
                }
            } catch (e: Exception) {
                logger.debug("MPA fetch failed for ${spot.name}: ${e.message}")
                errorCount++
            }
            
            // Progress logging
            if (index > 0 && index % 50 == 0) {
                logger.info("MPA prefetch progress: $index/${spotsToUpdate.size} ($successCount success, $errorCount errors)")
            }
            
            // Small delay between requests (Esri API has no published rate limit, but be conservative)
            delay(200)
        }
        
        val elapsed = System.currentTimeMillis() - startTime
        logger.info("MPA prefetch complete: $successCount success, $errorCount errors in ${elapsed}ms")
    }
    
    // ==================== EVERY 3 HOURS: User Spots Prefetch ====================
    
    /**
     * Prefetch data for all user-created spots.
     * Runs on same schedule as weather but in separate loop.
     */
    suspend fun prefetchUserSpots() = withContext(Dispatchers.IO) {
        val userSpots = com.shaka.data.db.UserSpotRepository.getAllUserSpots()
        
        if (userSpots.isEmpty()) {
            logger.info("USER SPOTS prefetch: No user spots to prefetch")
            return@withContext
        }
        
        logger.info("USER SPOTS prefetch: ${userSpots.size} user spots to check")
        
        val startTime = System.currentTimeMillis()
        var successCount = 0
        var skippedCount = 0
        var errorCount = 0
        val today = LocalDate.now().toString()
        
        for (spot in userSpots) {
            val cacheId = "user-${spot.id}"
            
            // Check if data is stale (same threshold as weather: 4 hours)
            val cached = SpotDataCache.get(cacheId)
            if (cached?.swell != null && !isStale(cached.swell.fetchedAt, WEATHER_STALE_HOURS)) {
                skippedCount++
                continue
            }
            
            try {
                val lat = spot.coordinates.lat
                val lon = spot.coordinates.lon
                val now = Instant.now()
                var gotData = false
                
                // Tide
                try {
                    val tideData = tidesClient.getTideData(lat, lon, today)
                    SpotDataCache.updateTide(
                        cacheId,
                        SpotDataCache.CachedValue(
                            value = SpotDataCache.TideInfo(
                                state = tideData.tideState,
                                nextHighTide = tideData.nextHighTide,
                                nextLowTide = tideData.nextLowTide,
                                currentHeight = tideData.currentHeight,
                                stationId = null
                            ),
                            fetchedAt = now
                        )
                    )
                    gotData = true
                } catch (e: Exception) {
                    logger.debug("User spot tide fetch failed for ${spot.name}: ${e.message}")
                }
                
                // Weather
                try {
                    val ocean = openMeteo.getMarineData(lat, lon, today)
                    val weather = openMeteo.getWeather(lat, lon, today)
                    
                    SpotDataCache.updateSwell(
                        cacheId,
                        SpotDataCache.CachedValue(
                            value = SpotDataCache.SwellInfo(
                                heightFt = SpotDataCache.metersToFeet(ocean.waveHeight),
                                periodSec = ocean.wavePeriod,
                                direction = SpotDataCache.degreesToCardinal(ocean.waveDirection.toDouble()),
                                swellHeightFt = SpotDataCache.metersToFeet(ocean.swellHeight)
                            ),
                            fetchedAt = now
                        )
                    )
                    
                    SpotDataCache.updateWind(
                        cacheId,
                        SpotDataCache.CachedValue(
                            value = SpotDataCache.WindInfo(
                                speedKnots = SpotDataCache.kmhToKnots(weather.windSpeed),
                                direction = SpotDataCache.degreesToCardinal(weather.windDirection.toDouble()),
                                gustKnots = null
                            ),
                            fetchedAt = now
                        )
                    )
                    gotData = true
                } catch (e: Exception) {
                    logger.debug("User spot weather fetch failed for ${spot.name}: ${e.message}")
                }
                
                // GIBS Chlorophyll
                try {
                    val gibsData = GIBSClient.getAllChlorophyll(lat, lon)
                    SpotDataCache.updateGIBSChlorophyll(
                        cacheId,
                        SpotDataCache.CachedValue(
                            value = SpotDataCache.GIBSSatelliteData(
                                paceToday = gibsData.paceToday,
                                paceYesterday = gibsData.paceYesterday,
                                noaa20Today = gibsData.noaa20Today,
                                noaa20Yesterday = gibsData.noaa20Yesterday,
                                noaa21Today = gibsData.noaa21Today,
                                noaa21Yesterday = gibsData.noaa21Yesterday,
                                sentinel3aToday = gibsData.sentinel3aToday,
                                sentinel3aYesterday = gibsData.sentinel3aYesterday,
                                sentinel3bToday = gibsData.sentinel3bToday,
                                sentinel3bYesterday = gibsData.sentinel3bYesterday,
                                dataDate = gibsData.dataDate,
                                paceObservationTime = gibsData.paceObservationTime,
                                noaa20ObservationTime = gibsData.noaa20ObservationTime,
                                noaa21ObservationTime = gibsData.noaa21ObservationTime
                            ),
                            fetchedAt = now
                        )
                    )
                    gotData = true
                } catch (e: Exception) {
                    logger.debug("User spot GIBS fetch failed for ${spot.name}: ${e.message}")
                }
                
                // MPA
                try {
                    val mpaInfo = protectedSeasClient.getMPAStatus(lat, lon)
                    val cacheInfo = mpaInfo?.let {
                        SpotDataCache.MPACacheInfo(
                            siteName = it.siteName,
                            designation = it.designation,
                            spearfishingStatus = it.spearfishingStatus,
                            protectionLevel = it.protectionLevel,
                            speciesOfConcern = it.speciesOfConcern,
                            purpose = it.purpose,
                            detailsUrl = it.detailsUrl
                        )
                    }
                    SpotDataCache.updateMPA(cacheId, SpotDataCache.CachedValue(cacheInfo, now))
                    gotData = true
                } catch (e: Exception) {
                    logger.debug("User spot MPA fetch failed for ${spot.name}: ${e.message}")
                }
                
                if (gotData) {
                    SpotDataCache.saveToDatabase(cacheId)
                    successCount++
                } else {
                    errorCount++
                }
                
                // Rate limit
                delay(500)
                
            } catch (e: Exception) {
                logger.debug("User spot prefetch failed for ${spot.name}: ${e.message}")
                errorCount++
            }
        }
        
        val elapsed = System.currentTimeMillis() - startTime
        logger.info("USER SPOTS prefetch complete: $successCount updated, $skippedCount skipped (fresh), $errorCount errors in ${elapsed}ms")
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
        delay(3000)
        
        prefetchMPA()
        delay(3000)
        
        // Also prefetch user spots
        prefetchUserSpots()
        
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
