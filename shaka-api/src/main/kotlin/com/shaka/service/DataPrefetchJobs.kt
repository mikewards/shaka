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
    private val protectedSeasClient: ProtectedSeasClient = ProtectedSeasClient(),
    private val globalFishingWatch: GlobalFishingWatchClient = GlobalFishingWatchClient(),
    private val solunarClient: SolunarClient = SolunarClient(),
    private val ndbcBuoyClient: NDBCBuoyClient = NDBCBuoyClient(),
    private val bathymetryClient: BathymetryClient = BathymetryClient()
) {
    private val logger = LoggerFactory.getLogger(DataPrefetchJobs::class.java)
    
    @Volatile private var buoyStationsCache: List<SpotDataCache.BuoyStation> = emptyList()
    
    companion object {
        const val BATCH_SIZE = 10
        const val BATCH_DELAY_MS = 500L
        const val SPOT_TIMEOUT_MS = 15000L  // 15s timeout (rate limiter adds delay)
        
        // Cache staleness thresholds
        const val TIDE_STALE_HOURS = 2      // Refetch if older than 2h
        const val WEATHER_STALE_HOURS = 4   // Refetch if older than 4h  
        const val SATELLITE_STALE_HOURS = 12 // Refetch if older than 12h
        const val MPA_STALE_HOURS = 168     // Weekly (168 hours) - MPA boundaries rarely change
        const val VESSEL_STALE_HOURS = 24   // Daily - GFW updates daily
        const val SOLUNAR_STALE_HOURS = 12  // Twice daily - solunar feeding windows shift through the day
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
                                        stationId = stationId,
                                        nextHighTideTime = tideData.nextHighTideTime?.let { Instant.ofEpochMilli(it) },
                                        nextLowTideTime = tideData.nextLowTideTime?.let { Instant.ofEpochMilli(it) }
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
    private data class WeatherSpot(val cacheId: String, val lat: Double, val lon: Double, val name: String)

    suspend fun prefetchWeather() = withContext(Dispatchers.IO) {
        val today = LocalDate.now().toString()
        
        // Combine curated + user spots into a unified list
        val curatedSpots = spotDb.getAllSpots().map { 
            WeatherSpot(it.id, it.coordinates.lat, it.coordinates.lon, it.name) 
        }
        val userSpots = try {
            com.shaka.data.db.UserSpotRepository.getAllUserSpots().map {
                WeatherSpot("user-${it.id}", it.coordinates.lat, it.coordinates.lon, it.name)
            }
        } catch (e: Exception) {
            logger.warn("Could not load user spots for weather prefetch: ${e.message}")
            emptyList()
        }
        val allSpots = curatedSpots + userSpots
        
        // Filter to spots that need updating (including those missing exposure/Phase 3 data)
        val spotsToUpdate = allSpots.filter { spot ->
            val cached = SpotDataCache.get(spot.cacheId)
            cached?.swell == null || cached.wind == null || 
                cached.exposure == null ||
                isStale(cached.swell.fetchedAt, WEATHER_STALE_HOURS)
        }
        
        logger.info("WEATHER prefetch: ${spotsToUpdate.size}/${allSpots.size} spots need updates (${curatedSpots.size} curated + ${userSpots.size} user)")
        
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
                            val cached = SpotDataCache.get(spot.cacheId)
                            var exposure = cached?.exposure
                            if (exposure == null || exposure.landDistances == null) {
                                try {
                                    val result = bathymetryClient.computeExposure(spot.lat, spot.lon)
                                    if (result != null) {
                                        exposure = SpotDataCache.ExposureInfo(
                                            result.bearing, result.width, result.depthM,
                                            result.directional.landDistanceKm, result.depthSource
                                        )
                                        SpotDataCache.updateExposure(spot.cacheId, exposure)
                                    }
                                } catch (e: Exception) {
                                    logger.debug("Exposure compute failed for ${spot.name}: ${e.message}")
                                }
                            }
                            // Depth retry disabled — NCEI ArcGIS is fragile.
                            // Use /admin/depth/refetch with conservative pacing instead.

                            val ocean = openMeteo.getMarineData(spot.lat, spot.lon, today)
                            val weather = openMeteo.getWeather(spot.lat, spot.lon, today)
                            
                            val now = Instant.now()
                            
                            // Option D: Open-Meteo primary, buoy only at < 1.5nm
                            val buoyMatch = SpotDataCache.findNearestBuoyReading(spot.lat, spot.lon)
                            val rawHeightFt: Double
                            val rawDirectionDeg: Double
                            val swellSource: String
                            val periodSec: Double
                            val directionCardinal: String
                            val usedBuoy: Boolean
                            
                            if (buoyMatch != null) {
                                rawHeightFt = SpotDataCache.metersToFeet(buoyMatch.reading.waveHeightM!!)
                                periodSec = buoyMatch.reading.dominantPeriodSec ?: ocean.wavePeriod
                                rawDirectionDeg = (buoyMatch.reading.meanDirection ?: ocean.waveDirection).toDouble()
                                directionCardinal = SpotDataCache.degreesToCardinal(rawDirectionDeg)
                                swellSource = "ndbc-${buoyMatch.station.stationId}"
                                usedBuoy = true
                            } else {
                                rawHeightFt = SpotDataCache.metersToFeet(ocean.waveHeight)
                                periodSec = ocean.wavePeriod
                                rawDirectionDeg = ocean.waveDirection.toDouble()
                                directionCardinal = SpotDataCache.degreesToCardinal(rawDirectionDeg)
                                swellSource = "open-meteo"
                                usedBuoy = false
                            }
                            
                            // Attenuation only for model data; buoy at < 1.5nm already reflects local conditions
                            val ld = exposure?.landDistances
                            val correctedHt = if (ld != null && !usedBuoy) {
                                SpotDataCache.attenuateSwell(rawHeightFt, rawDirectionDeg, ld)
                            } else null
                            
                            // Secondary swell from Open-Meteo (always model data)
                            val secHtRaw = ocean.secondarySwellHeight?.let { SpotDataCache.metersToFeet(it) }
                            val secPeriod = ocean.secondarySwellPeriod
                            val secDirDeg = ocean.secondarySwellDirection?.toDouble()
                            val secDirCardinal = secDirDeg?.let { SpotDataCache.degreesToCardinal(it) }
                            val secCorrHt = if (ld != null && secHtRaw != null && secDirDeg != null) {
                                SpotDataCache.attenuateSwell(secHtRaw, secDirDeg, ld)
                            } else null
                            
                            val swellInfo = SpotDataCache.SwellInfo(
                                heightFt = rawHeightFt,
                                periodSec = periodSec,
                                direction = directionCardinal,
                                swellHeightFt = rawHeightFt,
                                source = swellSource,
                                correctedHeightFt = correctedHt,
                                secondaryHeightFt = secHtRaw,
                                secondaryPeriodSec = secPeriod,
                                secondaryDirection = secDirCardinal,
                                secondaryCorrectedHeightFt = secCorrHt
                            )
                            
                            SpotDataCache.updateSwell(
                                spot.cacheId,
                                SpotDataCache.CachedValue(value = swellInfo, fetchedAt = now, dataValidAt = now)
                            )
                            SpotDataCache.updateSwellSource(spot.cacheId, swellInfo.source)
                            SpotDataCache.updateCorrectedSwell(spot.cacheId, correctedHt, secHtRaw, secPeriod, secDirCardinal, secCorrHt)
                            
                            SpotDataCache.updateWind(
                                spot.cacheId,
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
                            
                            SpotDataCache.saveToDatabase(spot.cacheId)
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
                
                // SST from NOAA satellite (date-2 internally for processing lag)
                try {
                    val sst = noaaClient.getSeaSurfaceTemperature(lat, lon, today)
                    SpotDataCache.updateSST(
                        spot.id,
                        if (sst != null) SpotDataCache.CachedValue(
                            value = sst,
                            fetchedAt = now,
                            dataValidAt = Instant.now().minusSeconds(86400)
                        ) else null
                    )
                    if (sst != null) gotData = true
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
                
                // GIBS satellite colors (all 5 satellites, today + yesterday)
                // Colors are for display only - use NOAA ERDDAP for actual chlorophyll values
                try {
                    val gibsColors = GIBSClient.getAllSatelliteColors(lat, lon)
                    SpotDataCache.updateGIBSChlorophyll(
                        spot.id,
                        SpotDataCache.CachedValue(
                            value = SpotDataCache.GIBSSatelliteData(
                                paceTodayColor = gibsColors.paceTodayColor,
                                paceYesterdayColor = gibsColors.paceYesterdayColor,
                                noaa20TodayColor = gibsColors.noaa20TodayColor,
                                noaa20YesterdayColor = gibsColors.noaa20YesterdayColor,
                                noaa21TodayColor = gibsColors.noaa21TodayColor,
                                noaa21YesterdayColor = gibsColors.noaa21YesterdayColor,
                                sentinel3aTodayColor = gibsColors.sentinel3aTodayColor,
                                sentinel3aYesterdayColor = gibsColors.sentinel3aYesterdayColor,
                                sentinel3bTodayColor = gibsColors.sentinel3bTodayColor,
                                sentinel3bYesterdayColor = gibsColors.sentinel3bYesterdayColor,
                                dataDate = gibsColors.dataDate,
                                paceObservationTime = gibsColors.paceObservationTime,
                                noaa20ObservationTime = gibsColors.noaa20ObservationTime,
                                noaa21ObservationTime = gibsColors.noaa21ObservationTime
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
                    // Step 1: Check EXACT location (is spot INSIDE an MPA?)
                    val exactResult = protectedSeasClient.getMPAStatusExact(
                        spot.coordinates.lat,
                        spot.coordinates.lon
                    )
                    
                    // Step 2: If not inside, check with buffer (is spot NEARBY an MPA?)
                    val bufferResult = if (exactResult == null) {
                        protectedSeasClient.getMPAStatus(spot.coordinates.lat, spot.coordinates.lon)
                    } else null
                    
                    val isInside = exactResult != null
                    val mpaInfo = exactResult ?: bufferResult
                    
                    // Convert to cache format (null mpaInfo is valid - means no specific MPA)
                    val cacheInfo = mpaInfo?.let {
                        SpotDataCache.MPACacheInfo(
                            siteName = it.siteName,
                            designation = it.designation,
                            spearfishingStatus = it.spearfishingStatus,
                            protectionLevel = it.protectionLevel,
                            speciesOfConcern = it.speciesOfConcern,
                            purpose = it.purpose,
                            detailsUrl = it.detailsUrl,
                            isInsideMPA = isInside
                        )
                    }
                    
                    SpotDataCache.updateMPA(
                        spot.id,
                        SpotDataCache.CachedValue(cacheInfo, Instant.now())
                    )
                    SpotDataCache.saveToDatabase(spot.id)
                    successCount++
                    
                    if (mpaInfo != null) {
                        logger.debug("MPA for ${spot.name}: ${mpaInfo.siteName} (inside=$isInside, spearfishing=${mpaInfo.spearfishingStatus})")
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
    
    // ==================== DAILY: Fishing Intel Prefetch ====================
    
    /**
     * Prefetch fishing intel data: vessel activity and solunar periods.
     * These are the raw data points fishermen use to make their own calls.
     * 
     * Global Fishing Watch provides vessel clustering data.
     * Solunar API provides moon phase and feeding periods.
     * 
     * Schedule: Daily (data changes day-to-day)
     */
    suspend fun prefetchFishingIntel() = withContext(Dispatchers.IO) {
        val allSpots = spotDb.getAllSpots()
        val today = LocalDate.now()
        
        // Filter to spots that need updating (daily refresh)
        val spotsToUpdate = allSpots.filter { spot ->
            val cached = SpotDataCache.get(spot.id)
            cached?.vessel == null || cached.solunar == null ||
                isStale(cached.vessel?.fetchedAt, VESSEL_STALE_HOURS) ||
                isStale(cached.solunar?.fetchedAt, SOLUNAR_STALE_HOURS)
        }
        
        logger.info("FISHING INTEL prefetch: ${spotsToUpdate.size}/${allSpots.size} spots need updates")
        
        if (spotsToUpdate.isEmpty()) {
            logger.info("FISHING INTEL prefetch: All spots have fresh data, skipping")
            return@withContext
        }
        
        val startTime = System.currentTimeMillis()
        var vesselSuccess = 0
        var solunarSuccess = 0
        var errorCount = 0
        
        // Process in batches to avoid overwhelming APIs
        spotsToUpdate.chunked(BATCH_SIZE).forEachIndexed { batchIndex, batch ->
            val results = batch.map { spot ->
                async {
                    val lat = spot.coordinates.lat
                    val lon = spot.coordinates.lon
                    val now = Instant.now()
                    var gotVessel = false
                    var gotSolunar = false
                    
                    // Fetch vessel activity from Global Fishing Watch
                    try {
                        val vesselData = globalFishingWatch.getVesselActivity(lat, lon)
                        if (vesselData != null) {
                            SpotDataCache.updateVessel(
                                spot.id,
                                SpotDataCache.CachedValue(
                                    value = SpotDataCache.VesselInfo(
                                        count = vesselData.count,
                                        radiusNm = vesselData.radiusNm
                                    ),
                                    fetchedAt = now
                                )
                            )
                            gotVessel = true
                        }
                    } catch (e: Exception) {
                        logger.debug("Vessel fetch failed for ${spot.name}: ${e.message}")
                    }
                    
                    // Fetch solunar data
                    try {
                        val solunarData = solunarClient.getSolunarData(lat, lon, today)
                        if (solunarData != null) {
                            SpotDataCache.updateSolunar(
                                spot.id,
                                SpotDataCache.CachedValue(
                                    value = SpotDataCache.SolunarInfo(
                                        moonPhase = solunarData.moonPhase,
                                        illumination = solunarData.illumination,
                                        majorStart1 = solunarData.majorPeriods.getOrNull(0)?.start,
                                        majorEnd1 = solunarData.majorPeriods.getOrNull(0)?.end,
                                        majorStart2 = solunarData.majorPeriods.getOrNull(1)?.start,
                                        majorEnd2 = solunarData.majorPeriods.getOrNull(1)?.end,
                                        minorStart1 = solunarData.minorPeriods.getOrNull(0)?.start,
                                        minorEnd1 = solunarData.minorPeriods.getOrNull(0)?.end,
                                        minorStart2 = solunarData.minorPeriods.getOrNull(1)?.start,
                                        minorEnd2 = solunarData.minorPeriods.getOrNull(1)?.end,
                                        dayRating = solunarData.dayRating
                                    ),
                                    fetchedAt = now
                                )
                            )
                            gotSolunar = true
                        }
                    } catch (e: Exception) {
                        logger.debug("Solunar fetch failed for ${spot.name}: ${e.message}")
                    }
                    
                    if (gotVessel || gotSolunar) {
                        SpotDataCache.saveToDatabase(spot.id)
                    }
                    
                    Pair(gotVessel, gotSolunar)
                }
            }.awaitAll()
            
            vesselSuccess += results.count { it.first }
            solunarSuccess += results.count { it.second }
            errorCount += results.count { !it.first && !it.second }
            
            if (batchIndex < spotsToUpdate.size / BATCH_SIZE) {
                delay(BATCH_DELAY_MS)
            }
        }
        
        val elapsed = System.currentTimeMillis() - startTime
        logger.info("FISHING INTEL prefetch complete: vessels=$vesselSuccess, solunar=$solunarSuccess, errors=$errorCount in ${elapsed}ms")
        logRateLimiterStats()
    }
    
    // ==================== EVERY 3 HOURS: User Spots Prefetch ====================
    
    /**
     * Prefetch data for all user-created spots.
     * Runs on same schedule as weather but in separate loop.
     */
    suspend fun prefetchUserSpots() = withContext(Dispatchers.IO) {
        val userSpots = try {
            com.shaka.data.db.UserSpotRepository.getAllUserSpots()
        } catch (e: Exception) {
            logger.error("USER SPOTS prefetch: Failed to load user spots from DB: ${e.message}", e)
            return@withContext
        }
        
        if (userSpots.isEmpty()) {
            logger.info("USER SPOTS prefetch: No user spots to prefetch")
            return@withContext
        }
        
        logger.info("USER SPOTS prefetch: ${userSpots.size} user spots to process")
        
        val startTime = System.currentTimeMillis()
        var successCount = 0
        var skippedCount = 0
        var errorCount = 0
        val today = LocalDate.now().toString()
        
        for (spot in userSpots) {
            val cacheId = "user-${spot.id}"
            
            // Check if satellite/SST data is stale (weather/swell is handled by prefetchWeather)
            val cached = SpotDataCache.get(cacheId)
            if (cached?.sst != null && cached.visibility != null &&
                !isStale(cached.sst.fetchedAt, SATELLITE_STALE_HOURS)) {
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
                                stationId = null,
                                nextHighTideTime = tideData.nextHighTideTime?.let { Instant.ofEpochMilli(it) },
                                nextLowTideTime = tideData.nextLowTideTime?.let { Instant.ofEpochMilli(it) }
                            ),
                            fetchedAt = now
                        )
                    )
                    gotData = true
                } catch (e: Exception) {
                    logger.debug("User spot tide fetch failed for ${spot.name}: ${e.message}")
                }
                
                // Weather/swell handled by prefetchWeather() which covers all spots
                
                // SST from NOAA satellite
                try {
                    val sst = noaaClient.getSeaSurfaceTemperature(lat, lon, today)
                    SpotDataCache.updateSST(
                        cacheId,
                        if (sst != null) SpotDataCache.CachedValue(
                            value = sst,
                            fetchedAt = now,
                            dataValidAt = Instant.now().minusSeconds(86400)
                        ) else null
                    )
                    if (sst != null) gotData = true
                } catch (e: Exception) {
                    logger.debug("User spot SST fetch failed for ${spot.name}: ${e.message}")
                }
                
                // Copernicus water quality (visibility + chlorophyll, no longer SST)
                try {
                    val wq = copernicus.getWaterQuality(lat, lon, today)
                    wq.visibility?.let { vis ->
                        SpotDataCache.updateVisibility(
                            cacheId,
                            SpotDataCache.CachedValue(value = vis, fetchedAt = now)
                        )
                    }
                    wq.chlorophyllA?.let { chl ->
                        SpotDataCache.updateChlorophyll(
                            cacheId,
                            SpotDataCache.CachedValue(value = chl, fetchedAt = now)
                        )
                    }
                    gotData = true
                } catch (e: Exception) {
                    logger.debug("User spot Copernicus fetch failed for ${spot.name}: ${e.message}")
                }
                
                // GIBS Satellite Colors (for display only)
                try {
                    val gibsColors = GIBSClient.getAllSatelliteColors(lat, lon)
                    SpotDataCache.updateGIBSChlorophyll(
                        cacheId,
                        SpotDataCache.CachedValue(
                            value = SpotDataCache.GIBSSatelliteData(
                                paceTodayColor = gibsColors.paceTodayColor,
                                paceYesterdayColor = gibsColors.paceYesterdayColor,
                                noaa20TodayColor = gibsColors.noaa20TodayColor,
                                noaa20YesterdayColor = gibsColors.noaa20YesterdayColor,
                                noaa21TodayColor = gibsColors.noaa21TodayColor,
                                noaa21YesterdayColor = gibsColors.noaa21YesterdayColor,
                                sentinel3aTodayColor = gibsColors.sentinel3aTodayColor,
                                sentinel3aYesterdayColor = gibsColors.sentinel3aYesterdayColor,
                                sentinel3bTodayColor = gibsColors.sentinel3bTodayColor,
                                sentinel3bYesterdayColor = gibsColors.sentinel3bYesterdayColor,
                                dataDate = gibsColors.dataDate,
                                paceObservationTime = gibsColors.paceObservationTime,
                                noaa20ObservationTime = gibsColors.noaa20ObservationTime,
                                noaa21ObservationTime = gibsColors.noaa21ObservationTime
                            ),
                            fetchedAt = now
                        )
                    )
                    gotData = true
                } catch (e: Exception) {
                    logger.debug("User spot GIBS fetch failed for ${spot.name}: ${e.message}")
                }
                
                // MPA - exact first, then buffer
                try {
                    // Step 1: Check EXACT location (is spot INSIDE an MPA?)
                    val exactResult = protectedSeasClient.getMPAStatusExact(lat, lon)
                    
                    // Step 2: If not inside, check with buffer (is spot NEARBY an MPA?)
                    val bufferResult = if (exactResult == null) {
                        protectedSeasClient.getMPAStatus(lat, lon)
                    } else null
                    
                    val isInside = exactResult != null
                    val mpaInfo = exactResult ?: bufferResult
                    
                    val cacheInfo = mpaInfo?.let {
                        SpotDataCache.MPACacheInfo(
                            siteName = it.siteName,
                            designation = it.designation,
                            spearfishingStatus = it.spearfishingStatus,
                            protectionLevel = it.protectionLevel,
                            speciesOfConcern = it.speciesOfConcern,
                            purpose = it.purpose,
                            detailsUrl = it.detailsUrl,
                            isInsideMPA = isInside
                        )
                    }
                    SpotDataCache.updateMPA(cacheId, SpotDataCache.CachedValue(cacheInfo, now))
                    gotData = true
                } catch (e: Exception) {
                    logger.debug("User spot MPA fetch failed for ${spot.name}: ${e.message}")
                }
                
                // Solunar (moon phase + feeding periods)
                try {
                    val solunarData = solunarClient.getSolunarData(lat, lon, LocalDate.now())
                    if (solunarData != null) {
                        SpotDataCache.updateSolunar(
                            cacheId,
                            SpotDataCache.CachedValue(
                                value = SpotDataCache.SolunarInfo(
                                    moonPhase = solunarData.moonPhase,
                                    illumination = solunarData.illumination,
                                    majorStart1 = solunarData.majorPeriods.getOrNull(0)?.start,
                                    majorEnd1 = solunarData.majorPeriods.getOrNull(0)?.end,
                                    majorStart2 = solunarData.majorPeriods.getOrNull(1)?.start,
                                    majorEnd2 = solunarData.majorPeriods.getOrNull(1)?.end,
                                    minorStart1 = solunarData.minorPeriods.getOrNull(0)?.start,
                                    minorEnd1 = solunarData.minorPeriods.getOrNull(0)?.end,
                                    minorStart2 = solunarData.minorPeriods.getOrNull(1)?.start,
                                    minorEnd2 = solunarData.minorPeriods.getOrNull(1)?.end,
                                    dayRating = solunarData.dayRating
                                ),
                                fetchedAt = now
                            )
                        )
                        gotData = true
                    }
                } catch (e: Exception) {
                    logger.debug("User spot solunar fetch failed for ${spot.name}: ${e.message}")
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
                logger.warn("User spot prefetch failed for ${spot.name}: ${e.message}")
                errorCount++
            }
        }
        
        val elapsed = System.currentTimeMillis() - startTime
        logger.info("USER SPOTS prefetch complete: $successCount updated, $skippedCount skipped (fresh), $errorCount errors out of ${userSpots.size} total in ${elapsed}ms")
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
        
        // Fishing intel health check (vessels and solunar are fetched live)
        prefetchFishingIntel()
        delay(1000)
        
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
    
    // ==================== BUOY DATA ====================
    
    /**
     * Fetch ALL NDBC wave buoy stations and save to database.
     * Idempotent — updates existing, adds new.
     * Called once on startup.
     */
    suspend fun seedBuoyStations() {
        logger.info("Seeding NDBC buoy stations...")
        val stations = ndbcBuoyClient.fetchWaveStations()
        if (stations.isEmpty()) {
            logger.warn("No NDBC stations fetched — skipping seed")
            return
        }
        SpotDataCache.saveBuoyStations(stations)
        buoyStationsCache = SpotDataCache.loadBuoyStations()
        logger.info("Seeded ${stations.size} stations, ${buoyStationsCache.size} active in cache")
    }
    
    /**
     * Fetch latest readings from all active buoy stations.
     * Runs hourly — buoys report every hour.
     * Never deactivates stations — transient failures are normal (NDBC is slow,
     * stations go offline for maintenance, wave data is intermittently missing).
     */
    suspend fun prefetchBuoyReadings() {
        if (buoyStationsCache.isEmpty()) {
            buoyStationsCache = SpotDataCache.loadBuoyStations()
        }
        if (buoyStationsCache.isEmpty()) {
            logger.info("No buoy stations configured — skipping buoy prefetch")
            return
        }
        
        logger.info("Fetching readings from ${buoyStationsCache.size} buoy stations...")
        var success = 0
        var skipped = 0
        var failed = 0
        
        for (batch in buoyStationsCache.chunked(BATCH_SIZE)) {
            coroutineScope {
                batch.map { station ->
                    async {
                        try {
                            val reading = withTimeoutOrNull(15_000) {
                                ndbcBuoyClient.fetchLatestReading(station.stationId)
                            }
                            if (reading != null && reading.waveHeightM != null) {
                                SpotDataCache.saveBuoyReading(reading)
                                success++
                            } else {
                                skipped++
                            }
                        } catch (e: Exception) {
                            failed++
                        }
                        Unit
                    }
                }.forEach { it.await() }
            }
            delay(BATCH_DELAY_MS)
        }
        
        logger.info("Buoy readings: $success successful, $skipped no wave data, $failed errors")
    }

}
