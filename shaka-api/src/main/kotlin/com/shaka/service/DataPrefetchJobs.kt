package com.shaka.service

import com.shaka.data.cache.SpotDataCache
import com.shaka.data.client.*
import com.shaka.model.*
import com.shaka.monitoring.ItemFailure
import com.shaka.monitoring.MonitoringService
import com.shaka.util.SpotTime
import kotlinx.coroutines.*
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset

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
    private val tidesClient: TideClient,
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
        const val HOURLY_HORIZON_DAYS = 7   // days of hourly swell/wind to persist per spot

        // Cache staleness thresholds
        const val TIDE_STALE_HOURS = 2      // Refetch if older than 2h
        const val WEATHER_STALE_HOURS = 4   // Refetch if older than 4h  
        const val SATELLITE_STALE_HOURS = 12 // Refetch if older than 12h
        const val MPA_STALE_HOURS = 168     // Weekly (168 hours) - MPA boundaries rarely change
        const val VESSEL_STALE_HOURS = 24   // Daily - GFW updates daily
        const val SOLUNAR_STALE_HOURS = 12  // Twice daily - solunar feeding windows shift through the day

        // Tide horizon top-up tuning. Tide curves are deterministic, so once a
        // year is materialized we only regenerate as the horizon nears expiry.
        const val HORIZON_TARGET_DAYS = 365        // regenerate a full year at a time
        const val HORIZON_REFRESH_DAYS = 45        // refresh when < 45 days of horizon remain
        const val TOPUP_TIME_BUDGET_MS = 90 * 60 * 1000L  // bound each scheduled run to ~90 min of FES work
    }

    // Guards against overlapping horizon top-up runs (each FES year prediction
    // holds a ~5GB working set; concurrent runs would OOM the single instance).
    private val tideTopUpRunning = java.util.concurrent.atomic.AtomicBoolean(false)
    
    private fun spotLocalDate(lon: Double): LocalDate = SpotTime.spotLocalDate(null, lon)

    /**
     * Today's date in the spot's real local timezone, preferring the IANA tz
     * recorded in spot_tide_series. Falls back to the longitude approximation
     * for spots not yet backfilled. Delegates to the shared SpotTime helper so
     * all timezone resolution stays in one place.
     */
    private fun spotLocalDate(spotId: String, lon: Double): LocalDate =
        SpotTime.spotLocalDate(SpotDataCache.getTideSeries(spotId)?.timezoneId, lon)

    // ==================== EVERY 6 HOURS: Tide Chart Materialization ====================

    suspend fun materializeTideCharts() = withContext(Dispatchers.IO) {
        val allSpots = spotDb.getAllSpots()

        logger.info("TIDE CHART materialization: processing ${allSpots.size} catalog spots (serial, per-spot local dates)")

        val startTime = System.currentTimeMillis()
        var persisted = 0
        var skipped = 0
        var errors = 0
        val failures = mutableListOf<ItemFailure>()

        for (spot in allSpots) {
            val localToday = spotLocalDate(spot.coordinates.lon)
            val todayStr = localToday.toString()
            val tomorrowStr = localToday.plusDays(1).toString()

            for (day in listOf(todayStr, tomorrowStr)) {
                val existing = SpotDataCache.getTideDay(spot.id, day, tidesClient.provider)
                if (existing != null) { skipped++; continue }

                try {
                    withTimeout(SPOT_TIMEOUT_MS) {
                        val chartData = tidesClient.getTideChartData(
                            spot.coordinates.lat, spot.coordinates.lon, day
                        ) ?: return@withTimeout

                        val json = kotlinx.serialization.json.Json { ignoreUnknownKeys = true }
                        val localDate = chartData.localDate.ifEmpty { day }
                        SpotDataCache.upsertTideDay(SpotDataCache.TideDayRow(
                            spotId = spot.id,
                            localDate = localDate,
                            provider = chartData.provider,
                            stationId = chartData.stationId,
                            stationName = chartData.stationName,
                            stationDistanceMi = chartData.stationDistanceMi,
                            timezoneId = chartData.timezoneId,
                            datum = chartData.datum,
                            pointsJson = json.encodeToString(ListSerializer(TidePoint.serializer()), chartData.points),
                            extremesJson = json.encodeToString(ListSerializer(TideExtreme.serializer()), chartData.extremes),
                            fetchedAt = Instant.now()
                        ))
                        persisted++
                    }
                } catch (e: Exception) {
                    logger.debug("Tide chart failed for ${spot.name}/$day: ${e.message}")
                    MonitoringService.captureItemFailure("tide_chart_materialize", "${spot.id}/$day", "${spot.name}/$day", e)
                    failures.add(ItemFailure("${spot.id}/$day", "${spot.name}/$day", e.message ?: "unknown", MonitoringService.classifyError(e)))
                    errors++
                }
                delay(5000)
            }
        }

        // Also process user spots (same today+tomorrow logic)
        val userSpots = try {
            com.shaka.data.db.UserSpotRepository.getAllUserSpots()
        } catch (e: Exception) {
            logger.warn("TIDE CHART materialization: failed to load user spots: ${e.message}")
            emptyList()
        }

        for (spot in userSpots) {
            val cacheId = "user-${spot.id}"
            val localToday = spotLocalDate(spot.coordinates.lon)
            val todayStr = localToday.toString()
            val tomorrowStr = localToday.plusDays(1).toString()

            for (day in listOf(todayStr, tomorrowStr)) {
                val existing = SpotDataCache.getTideDay(cacheId, day, tidesClient.provider)
                if (existing != null) { skipped++; continue }

                try {
                    withTimeout(SPOT_TIMEOUT_MS) {
                        val chartData = tidesClient.getTideChartData(
                            spot.coordinates.lat, spot.coordinates.lon, day
                        ) ?: return@withTimeout

                        val json = kotlinx.serialization.json.Json { ignoreUnknownKeys = true }
                        val localDate = chartData.localDate.ifEmpty { day }
                        SpotDataCache.upsertTideDay(SpotDataCache.TideDayRow(
                            spotId = cacheId,
                            localDate = localDate,
                            provider = chartData.provider,
                            stationId = chartData.stationId,
                            stationName = chartData.stationName,
                            stationDistanceMi = chartData.stationDistanceMi,
                            timezoneId = chartData.timezoneId,
                            datum = chartData.datum,
                            pointsJson = json.encodeToString(ListSerializer(TidePoint.serializer()), chartData.points),
                            extremesJson = json.encodeToString(ListSerializer(TideExtreme.serializer()), chartData.extremes),
                            fetchedAt = Instant.now()
                        ))
                        persisted++
                    }
                } catch (e: Exception) {
                    logger.debug("Tide chart failed for user spot ${spot.name}/$day: ${e.message}")
                    MonitoringService.captureItemFailure("tide_chart_materialize", "$cacheId/$day", "${spot.name}/$day", e)
                    failures.add(ItemFailure("$cacheId/$day", "${spot.name}/$day", e.message ?: "unknown", MonitoringService.classifyError(e)))
                    errors++
                }
                delay(5000)
            }
        }

        val elapsed = System.currentTimeMillis() - startTime
        val totalAttempted = persisted + errors
        MonitoringService.reportRun("tide_chart_materialize", totalAttempted, persisted, failures, elapsed)
    }

    // ==================== EVERY 10 MIN: Tide Chart Catch-Up ====================

    suspend fun catchUpMissingTideCharts() = withContext(Dispatchers.IO) {
        val missing = SpotDataCache.spotsMissingTideDay()
        if (missing.isEmpty()) return@withContext

        logger.info("TIDE CHART catch-up: ${missing.size} spots missing recent chart data")

        var persisted = 0
        var errors = 0
        val failures = mutableListOf<ItemFailure>()

        for ((spotId, coords) in missing) {
            try {
                withTimeout(SPOT_TIMEOUT_MS) {
                    val lon = coords.second
                    val spotToday = spotLocalDate(lon).toString()
                    val chartData = tidesClient.getTideChartData(coords.first, lon, spotToday)
                        ?: return@withTimeout

                    val json = kotlinx.serialization.json.Json { ignoreUnknownKeys = true }
                    val localDate = chartData.localDate.ifEmpty { spotToday }
                    SpotDataCache.upsertTideDay(SpotDataCache.TideDayRow(
                        spotId = spotId,
                        localDate = localDate,
                        provider = chartData.provider,
                        stationId = chartData.stationId,
                        stationName = chartData.stationName,
                        stationDistanceMi = chartData.stationDistanceMi,
                        timezoneId = chartData.timezoneId,
                        datum = chartData.datum,
                        pointsJson = json.encodeToString(ListSerializer(TidePoint.serializer()), chartData.points),
                        extremesJson = json.encodeToString(ListSerializer(TideExtreme.serializer()), chartData.extremes),
                        fetchedAt = Instant.now()
                    ))
                    persisted++
                }
            } catch (e: Exception) {
                logger.debug("Tide chart catch-up failed for $spotId: ${e.message}")
                MonitoringService.captureItemFailure("tide_chart_catchup", spotId, spotId, e)
                failures.add(ItemFailure(spotId, spotId, e.message ?: "unknown", MonitoringService.classifyError(e)))
                errors++
            }
            delay(5000)
        }

        MonitoringService.reportRun("tide_chart_catchup", missing.size, persisted, failures, 0)
    }

    fun cleanupOldTideDays() {
        SpotDataCache.cleanupOldTideDays()
    }

    // ==================== UPFRONT: Full-Year Tide Backfill ====================

    /**
     * Materialize a full year (default 365 days) of tide data for every catalog
     * and user spot, one spot at a time. Tide curves are deterministic, so this
     * runs ONCE and the daily/hourly jobs then read from spot_tide_days instead
     * of hammering the FES2022 service every day (the cause of the OOM crashes).
     *
     * Strictly serial (concurrency=1): the FES model has a ~5GB working set, so
     * overlapping year predictions would OOM-kill the Python service.
     */
    private data class TideTarget(val spotId: String, val lat: Double, val lon: Double, val name: String)

    /** Catalog + user spots as tide-materialization targets. */
    private suspend fun tideTargets(): List<TideTarget> {
        val catalog = spotDb.getAllSpots().map {
            TideTarget(it.id, it.coordinates.lat, it.coordinates.lon, it.name)
        }
        val userSpots = try {
            com.shaka.data.db.UserSpotRepository.getAllUserSpots().map {
                TideTarget("user-${it.id}", it.coordinates.lat, it.coordinates.lon, it.name)
            }
        } catch (e: Exception) {
            logger.warn("TIDE targets: failed to load user spots: ${e.message}")
            emptyList()
        }
        return catalog + userSpots
    }

    suspend fun backfillTideYears(days: Int = 365) = withContext(Dispatchers.IO) {
        val fes = tidesClient as? FES2022TideClient
        if (fes == null) {
            logger.warn("TIDE YEAR backfill requires the FES2022 client; skipping")
            return@withContext
        }

        val all = tideTargets()

        logger.info("TIDE YEAR backfill: ${all.size} spots x $days days (serial, concurrency=1)")
        val startTime = System.currentTimeMillis()
        var done = 0
        var failed = 0
        val failures = mutableListOf<ItemFailure>()

        for (target in all) {
            try {
                val ok = backfillTideYear(fes, target.spotId, target.lat, target.lon, days)
                if (ok) done++ else { failed++ }
            } catch (e: Exception) {
                logger.warn("TIDE YEAR backfill failed for ${target.name}: ${e.message}")
                MonitoringService.captureItemFailure("tide_year_backfill", target.spotId, target.name, e)
                failures.add(ItemFailure(target.spotId, target.name, e.message ?: "unknown", MonitoringService.classifyError(e)))
                failed++
            }
            // Brief pause between spots so the single FES instance can reclaim memory.
            delay(2000)
        }

        val elapsed = System.currentTimeMillis() - startTime
        MonitoringService.reportRun("tide_year_backfill", all.size, done, failures, elapsed)
        logger.info("TIDE YEAR backfill complete: $done ok, $failed failed in ${elapsed / 1000}s")
    }

    /**
     * Generate and persist a full-year horizon for a single spot. Upserts each
     * day into spot_tide_days and records the horizon in spot_tide_series.
     */
    suspend fun backfillTideYear(
        fes: FES2022TideClient,
        spotId: String,
        lat: Double,
        lon: Double,
        days: Int = 365
    ): Boolean {
        val result = fes.getTideYear(lat, lon, null, days) ?: return false
        val json = kotlinx.serialization.json.Json { ignoreUnknownKeys = true }

        for (day in result.tideDays) {
            SpotDataCache.upsertTideDay(SpotDataCache.TideDayRow(
                spotId = spotId,
                localDate = day.localDate,
                provider = "fes2022",
                stationId = "",
                stationName = "FES2022",
                stationDistanceMi = 0.0,
                timezoneId = result.timezoneId,
                datum = result.datum,
                pointsJson = json.encodeToString(ListSerializer(TidePoint.serializer()), day.points),
                extremesJson = json.encodeToString(ListSerializer(TideExtreme.serializer()), day.extremes),
                fetchedAt = Instant.now()
            ))
        }

        val from = result.tideDays.firstOrNull()?.localDate
        val through = result.tideDays.lastOrNull()?.localDate
        SpotDataCache.upsertTideSeries(SpotDataCache.TideSeriesRow(
            spotId = spotId,
            provider = "fes2022",
            lat = lat,
            lon = lon,
            timezoneId = result.timezoneId,
            datum = result.datum,
            stationId = null,
            stationName = "FES2022",
            stationDistanceMi = null,
            modelVersion = "FES2022",
            stepMinutes = result.stepMinutes,
            generatedFrom = from,
            generatedThrough = through,
            generatedAt = Instant.now(),
            status = "ready"
        ))

        logger.info("Tide year materialized for $spotId: ${result.tideDays.size} days ($from..$through)")
        return true
    }

    /**
     * On-demand: materialize a full year for only the REMAINING spots whose
     * precomputed horizon is missing or already expired (generated_through <
     * today). Unbounded (no time budget) and strictly serial, intended to be
     * fired manually via POST /admin/tide/topup-remaining to finish the
     * outstanding spots in one pass. Logs every spot result and full stack
     * traces on failure so errors are captured.
     */
    suspend fun backfillRemainingTideYears() = withContext(Dispatchers.IO) {
        if (!tideTopUpRunning.compareAndSet(false, true)) {
            logger.warn("TIDE remaining-backfill: a top-up is already running (tideTopUpRunning=true); not starting another")
            return@withContext
        }
        try {
            val fes = tidesClient as? FES2022TideClient
            if (fes == null) {
                logger.warn("TIDE remaining-backfill requires the FES2022 client; skipping")
                return@withContext
            }

            val today = LocalDate.now()
            val remaining = tideTargets().filter { t ->
                val through = SpotDataCache.getTideSeries(t.spotId)?.generatedThrough
                    ?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
                through == null || through.isBefore(today)
            }

            if (remaining.isEmpty()) {
                logger.info("TIDE remaining-backfill: nothing to do, all spots have a current-or-future horizon")
                return@withContext
            }

            logger.info("TIDE remaining-backfill: ${remaining.size} spots remaining (unbounded, serial)")
            val startTime = System.currentTimeMillis()
            var done = 0
            var failed = 0
            val failures = mutableListOf<ItemFailure>()

            for ((index, t) in remaining.withIndex()) {
                try {
                    val ok = backfillTideYear(fes, t.spotId, t.lat, t.lon, HORIZON_TARGET_DAYS)
                    if (ok) {
                        done++
                    } else {
                        failed++
                        logger.warn("TIDE remaining-backfill: ${t.spotId} (${t.name}) produced no tide_days (getTideYear returned null)")
                        failures.add(ItemFailure(t.spotId, t.name, "getTideYear returned null", "no_data"))
                    }
                } catch (e: Exception) {
                    failed++
                    logger.warn("TIDE remaining-backfill: ${t.spotId} (${t.name}) failed: ${e.message}", e)
                    MonitoringService.captureItemFailure("tide_remaining_backfill", t.spotId, t.name, e)
                    failures.add(ItemFailure(t.spotId, t.name, e.message ?: "unknown", MonitoringService.classifyError(e)))
                }
                if ((index + 1) % 20 == 0) {
                    logger.info("TIDE remaining-backfill progress: ${index + 1}/${remaining.size} ($done ok, $failed failed)")
                }
                delay(2000)
            }

            val elapsed = System.currentTimeMillis() - startTime
            MonitoringService.reportRun("tide_remaining_backfill", remaining.size, done, failures, elapsed)
            logger.info("TIDE remaining-backfill COMPLETE: $done ok, $failed failed of ${remaining.size} in ${elapsed / 1000}s")
        } finally {
            tideTopUpRunning.set(false)
        }
    }

    /**
     * Horizon top-up: (re)generate a full year for any spot whose precomputed
     * tide horizon is missing or within HORIZON_REFRESH_DAYS of expiry. Replaces
     * the old 6-hourly materialize + 10-minute catch-up jobs.
     *
     * Bounded by TOPUP_TIME_BUDGET_MS per run and strictly serial, so the first
     * deploy (no horizons yet) fills the whole catalog over several runs without
     * any single run starving the FES instance or tripping the job watchdog.
     * Once filled, runs are near-no-ops until the horizon nears expiry.
     */
    suspend fun topUpTideHorizons() = withContext(Dispatchers.IO) {
        if (!tideTopUpRunning.compareAndSet(false, true)) {
            logger.info("TIDE horizon top-up already running; skipping this trigger")
            return@withContext
        }
        try {
            val fes = tidesClient as? FES2022TideClient
            if (fes == null) {
                logger.warn("TIDE horizon top-up requires the FES2022 client; skipping")
                return@withContext
            }

            val threshold = LocalDate.now().plusDays(HORIZON_REFRESH_DAYS.toLong())
            val needy = tideTargets().filter { t ->
                val through = SpotDataCache.getTideSeries(t.spotId)?.generatedThrough
                    ?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
                through == null || through.isBefore(threshold)
            }

            if (needy.isEmpty()) {
                logger.info("TIDE horizon top-up: all spots have >= $HORIZON_REFRESH_DAYS days of horizon")
                return@withContext
            }

            logger.info("TIDE horizon top-up: ${needy.size} spots need a fresh year (budget ${TOPUP_TIME_BUDGET_MS / 60000}min, serial)")
            val startTime = System.currentTimeMillis()
            var done = 0
            var failed = 0
            val failures = mutableListOf<ItemFailure>()

            for (t in needy) {
                if (System.currentTimeMillis() - startTime > TOPUP_TIME_BUDGET_MS) {
                    logger.info("TIDE horizon top-up: time budget reached after $done spots; ${needy.size - done} deferred to next run")
                    break
                }
                try {
                    if (backfillTideYear(fes, t.spotId, t.lat, t.lon, HORIZON_TARGET_DAYS)) done++ else failed++
                } catch (e: Exception) {
                    logger.warn("TIDE horizon top-up failed for ${t.name}: ${e.message}")
                    MonitoringService.captureItemFailure("tide_horizon_topup", t.spotId, t.name, e)
                    failures.add(ItemFailure(t.spotId, t.name, e.message ?: "unknown", MonitoringService.classifyError(e)))
                    failed++
                }
                delay(2000)
            }

            val elapsed = System.currentTimeMillis() - startTime
            MonitoringService.reportRun("tide_horizon_topup", done + failed, done, failures, elapsed)
            logger.info("TIDE horizon top-up: $done generated, $failed failed in ${elapsed / 1000}s")
        } finally {
            tideTopUpRunning.set(false)
        }
    }

    /** Shared spot descriptor for the hourly swell/wind prefetch. */
    private data class WeatherSpot(val cacheId: String, val lat: Double, val lon: Double, val name: String)

    // ==================== DAILY: Hourly Swell + Wind Series ====================

    private val hourlyJson = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    /**
     * Fetch and persist the full hourly swell + wind curves (7-day horizon) for
     * every catalog + user spot, partitioned by the spot's IANA timezone.
     *
     * Replaces the per-3h single-snapshot weather prefetch. The displayed
     * current-hour value is derived in-memory from these tables by the hourly
     * tick (deriveHourlySnapshots), so reads never hit the DB or an API.
     *
     * Corrected (exposure-attenuated) swell is precomputed per hour using that
     * hour's predicted wind, keeping the swell table self-contained.
     */
    suspend fun prefetchHourlySwellWind() = withContext(Dispatchers.IO) {
        val curatedSpots = spotDb.getAllSpots().map {
            WeatherSpot(it.id, it.coordinates.lat, it.coordinates.lon, it.name)
        }
        val userSpots = try {
            com.shaka.data.db.UserSpotRepository.getAllUserSpots().map {
                WeatherSpot("user-${it.id}", it.coordinates.lat, it.coordinates.lon, it.name)
            }
        } catch (e: Exception) {
            logger.warn("Could not load user spots for hourly prefetch: ${e.message}")
            emptyList()
        }
        val allSpots = curatedSpots + userSpots

        logger.info("HOURLY swell/wind prefetch: ${allSpots.size} spots (${curatedSpots.size} curated + ${userSpots.size} user), ${HOURLY_HORIZON_DAYS}-day horizon")

        val startTime = System.currentTimeMillis()
        var successCount = 0
        val failures = mutableListOf<ItemFailure>()

        allSpots.chunked(BATCH_SIZE).forEachIndexed { batchIndex, batch ->
            val results = batch.map { spot ->
                async {
                    try {
                        withTimeout(SPOT_TIMEOUT_MS * 2) {
                            persistHourlyForSpot(spot)
                        }
                        true
                    } catch (e: Exception) {
                        logger.debug("Hourly prefetch failed for ${spot.name}: ${e.message}")
                        MonitoringService.captureItemFailure("hourly_swell_wind", spot.cacheId, spot.name, e)
                        synchronized(failures) {
                            failures.add(ItemFailure(spot.cacheId, spot.name, e.message ?: "unknown", MonitoringService.classifyError(e)))
                        }
                        false
                    }
                }
            }.awaitAll()

            successCount += results.count { it }
            if (batchIndex < allSpots.size / BATCH_SIZE) {
                delay(BATCH_DELAY_MS)
            }
        }

        val elapsed = System.currentTimeMillis() - startTime
        MonitoringService.reportRun("hourly_swell_wind", allSpots.size, successCount, failures, elapsed)
        logRateLimiterStats()
    }

    /**
     * Hourly tick: re-derive the current-hour swell + wind snapshot for every
     * spot from its in-memory series. Cheap (no DB/API), keeps displayed "now"
     * values moving through the day between daily fetches.
     */
    suspend fun deriveHourlySnapshots() = withContext(Dispatchers.Default) {
        val n = SpotDataCache.deriveAllCurrentHourSnapshots()
        if (n > 0) logger.info("Hourly snapshot tick: re-derived $n spots")
    }

    /** Nightly cleanup of stale hourly swell/wind day rows. */
    suspend fun cleanupOldHourly() = withContext(Dispatchers.IO) {
        SpotDataCache.cleanupOldHourly()
    }

    /**
     * Fetch the hourly marine + wind series for one spot, compute per-hour
     * corrected swell, and upsert one row per local_date into both tables.
     */
    private suspend fun persistHourlyForSpot(spot: WeatherSpot) {
        SpotDataCache.registerSpotCoordinates(spot.cacheId, spot.lat, spot.lon)
        // Ensure exposure for attenuation (compute once if missing).
        var exposure = SpotDataCache.get(spot.cacheId)?.exposure
        if (exposure?.landDistances == null) {
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
        val ld = exposure?.landDistances

        val marine = openMeteo.getMarineHourly(spot.lat, spot.lon, HOURLY_HORIZON_DAYS)
            ?: error("Open-Meteo marine hourly unavailable")
        val weather = openMeteo.getWeatherHourly(spot.lat, spot.lon, HOURLY_HORIZON_DAYS)
            ?: error("Open-Meteo weather hourly unavailable")

        val zone = SpotTime.resolveZone(marine.timezone, spot.lon)
        val now = Instant.now()

        // Index wind by epoch so per-hour swell attenuation can use the
        // concurrent predicted wind.
        val windByEpoch = weather.points.associateBy { it.epochMs }

        val swellPoints = marine.points.filter { it.epochMs > 0 }.map { mp ->
            val swellM = mp.swellHeightM ?: 0.0
            val rawHeightFt = SpotDataCache.metersToFeet(swellM)
            val periodSec = (mp.swellPeriodSec?.takeIf { it > 0 }) ?: (mp.wavePeriodSec ?: 0.0)
            val dirDeg = mp.swellDirectionDeg ?: 0
            val wind = windByEpoch[mp.epochMs]

            val correctedHt = if (ld != null) {
                SpotDataCache.attenuateSwell(
                    rawHeightFt, dirDeg.toDouble(), ld,
                    swellPeriodSec = periodSec,
                    totalWaveHeightM = mp.waveHeightM ?: 0.0,
                    swellHeightM = swellM,
                    windSpeedKmh = wind?.windSpeedKmh ?: 0.0,
                    windDirectionDeg = (wind?.windDirectionDeg ?: 0).toDouble()
                )
            } else null

            val secHtFt = mp.secondarySwellHeightM?.let { SpotDataCache.metersToFeet(it) }
            val secDirDeg = mp.secondarySwellDirectionDeg
            val secCorrHt = if (ld != null && secHtFt != null && secDirDeg != null) {
                SpotDataCache.attenuateSwell(secHtFt, secDirDeg.toDouble(), ld)
            } else null

            SwellHourlyPoint(
                epochMs = mp.epochMs,
                heightFt = rawHeightFt,
                periodSec = periodSec,
                directionDeg = dirDeg,
                correctedHeightFt = correctedHt,
                secondaryHeightFt = secHtFt,
                secondaryPeriodSec = mp.secondarySwellPeriodSec,
                secondaryDirectionDeg = secDirDeg,
                secondaryCorrectedHeightFt = secCorrHt
            )
        }

        val windPoints = weather.points.filter { it.epochMs > 0 }.map { wp ->
            WindHourlyPoint(
                epochMs = wp.epochMs,
                speedKts = SpotDataCache.kmhToKnots(wp.windSpeedKmh ?: 0.0),
                directionDeg = wp.windDirectionDeg ?: 0,
                gustKts = wp.windGustKmh?.let { SpotDataCache.kmhToKnots(it) }
            )
        }

        persistDays(spot.cacheId, marine.timezone, zone, now, swellPoints, windPoints)

        // Refresh in-memory series + current snapshot so reads reflect new data
        // immediately (without waiting for the next startup load).
        SpotDataCache.updateSwellSeries(spot.cacheId, swellPoints, marine.timezone, now)
        SpotDataCache.updateWindSeries(spot.cacheId, windPoints, marine.timezone, now)
        SpotDataCache.deriveCurrentHourSnapshot(spot.cacheId)
    }

    /** Group hourly points by local date in the spot zone and upsert each day. */
    private fun persistDays(
        cacheId: String,
        timezoneId: String,
        zone: ZoneId,
        fetchedAt: Instant,
        swellPoints: List<SwellHourlyPoint>,
        windPoints: List<WindHourlyPoint>
    ) {
        swellPoints.groupBy { SpotTime.localDateOf(it.epochMs, zone).toString() }
            .forEach { (date, pts) ->
                SpotDataCache.upsertSwellDay(SpotDataCache.SwellHourlyRow(
                    spotId = cacheId,
                    localDate = date,
                    timezoneId = timezoneId,
                    source = "open-meteo",
                    pointsJson = hourlyJson.encodeToString(ListSerializer(SwellHourlyPoint.serializer()), pts),
                    fetchedAt = fetchedAt
                ))
            }
        windPoints.groupBy { SpotTime.localDateOf(it.epochMs, zone).toString() }
            .forEach { (date, pts) ->
                SpotDataCache.upsertWindDay(SpotDataCache.WindHourlyRow(
                    spotId = cacheId,
                    localDate = date,
                    timezoneId = timezoneId,
                    pointsJson = hourlyJson.encodeToString(ListSerializer(WindHourlyPoint.serializer()), pts),
                    fetchedAt = fetchedAt
                ))
            }
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
        val failures = mutableListOf<ItemFailure>()

        // Per-source tallies (Q9): the aggregate "any source returned" success
        // hid total failures of a single source (e.g. SST 0/789 while GIBS was
        // healthy). Each source reports its own run below.
        var sstAttempts = 0; var sstSuccess = 0
        val sstFailures = mutableListOf<ItemFailure>()
        var copAttempts = 0; var copSuccess = 0
        val copFailures = mutableListOf<ItemFailure>()
        var gibsAttempts = 0; var gibsSuccess = 0
        val gibsFailures = mutableListOf<ItemFailure>()

        // Informational connectivity check only. This used to ABORT the whole
        // 6-hourly run on any single failure -- one transient error to one
        // coordinate could starve visibility/chlorophyll/SST for every spot
        // for weeks (observed May-Jun 2026). Per-spot calls already degrade
        // gracefully via the circuit breaker, so never skip the run here.
        try {
            val testResult = copernicus.getWaterQuality(26.5, -77.5, today)
            logger.info("Copernicus connectivity check (vis=${testResult.visibility}, chl=${testResult.chlorophyllA})")
        } catch (e: Exception) {
            logger.warn("Copernicus connectivity check failed (continuing anyway): ${e.message}")
        }
        
        // Register coordinates for all spots (enables in-memory nearest-SST lookups)
        for (spot in allSpots) {
            SpotDataCache.registerSpotCoordinates(spot.id, spot.coordinates.lat, spot.coordinates.lon)
        }

        // Process sequentially - Copernicus doesn't handle concurrency well
        for ((index, spot) in spotsToUpdate.withIndex()) {
            try {
                val lat = spot.coordinates.lat
                val lon = spot.coordinates.lon
                val now = Instant.now()
                var gotData = false
                
                // SST from NOAA satellite with progressive bbox expansion
                sstAttempts++
                try {
                    val sst = noaaClient.getSeaSurfaceTemperatureProgressive(lat, lon, today)
                    SpotDataCache.updateSST(
                        spot.id,
                        if (sst != null) SpotDataCache.CachedValue(
                            value = sst,
                            fetchedAt = now,
                            dataValidAt = Instant.now().minusSeconds(86400)
                        ) else null
                    )
                    if (sst != null) {
                        gotData = true
                        sstSuccess++
                    } else {
                        sstFailures.add(ItemFailure(spot.id, spot.name, "NOAA returned no SST value", "no_data"))
                    }
                } catch (e: Exception) {
                    logger.debug("SST fetch failed for ${spot.name}: ${e.message}")
                    sstFailures.add(ItemFailure(spot.id, spot.name, e.message ?: "unknown", MonitoringService.classifyError(e)))
                }
                
                // Water quality from Copernicus
                copAttempts++
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
                    if (waterQuality.visibility != null || waterQuality.chlorophyllA != null) {
                        copSuccess++
                    } else {
                        copFailures.add(ItemFailure(spot.id, spot.name, "Copernicus returned no visibility/chlorophyll", "no_data"))
                    }
                } catch (e: CircuitBreakerOpenException) {
                    logger.info("Circuit breaker opened - stopping satellite prefetch early")
                    copFailures.add(ItemFailure(spot.id, spot.name, "circuit breaker open", "circuit_breaker_open"))
                    skippedCount = spotsToUpdate.size - index - 1
                    break
                } catch (e: Exception) {
                    logger.debug("Water quality fetch failed for ${spot.name}: ${e.message}")
                    copFailures.add(ItemFailure(spot.id, spot.name, e.message ?: "unknown", MonitoringService.classifyError(e)))
                }
                
                // GIBS satellite colors (all 5 satellites, today + yesterday)
                // Colors are for display only - use NOAA ERDDAP for actual chlorophyll values
                gibsAttempts++
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
                    gibsSuccess++
                } catch (e: Exception) {
                    logger.debug("GIBS fetch failed for ${spot.name}: ${e.message}")
                    gibsFailures.add(ItemFailure(spot.id, spot.name, e.message ?: "unknown", MonitoringService.classifyError(e)))
                }
                
                if (gotData) {
                    SpotDataCache.saveToDatabase(spot.id)
                    successCount++
                } else {
                    errorCount++
                }
                
            } catch (e: Exception) {
                logger.debug("Satellite fetch failed for ${spot.name}: ${e.message}")
                MonitoringService.captureItemFailure("satellite_prefetch", spot.id, spot.name, e)
                failures.add(ItemFailure(spot.id, spot.name, e.message ?: "unknown", MonitoringService.classifyError(e)))
                errorCount++
            }
            
            // Progress logging
            if (index > 0 && index % 50 == 0) {
                logger.info("Satellite prefetch progress: $index/${spotsToUpdate.size} ($successCount success, $errorCount errors)")
            }
            
            // No explicit delay - rate limiter handles it
        }
        
        val elapsed = System.currentTimeMillis() - startTime
        MonitoringService.reportRun("satellite_prefetch", spotsToUpdate.size, successCount, failures, elapsed)
        // Per-source reports (Q9): totals are actual attempts (a circuit-breaker
        // break stops the loop early, so unattempted spots are not counted).
        MonitoringService.reportRun("satellite_sst", sstAttempts, sstSuccess, sstFailures, elapsed)
        MonitoringService.reportRun("satellite_copernicus", copAttempts, copSuccess, copFailures, elapsed)
        MonitoringService.reportRun("satellite_gibs", gibsAttempts, gibsSuccess, gibsFailures, elapsed)

        // SST backfill pass: fill spots still missing SST from buoys and neighbors
        val allSpotIds = allSpots.map { it.id }
        val missingSSTSpots = allSpotIds.filter { SpotDataCache.get(it)?.sst == null }
        if (missingSSTSpots.isNotEmpty()) {
            var buoyFills = 0
            var neighborFills = 0
            val now = Instant.now()
            for (spotId in missingSSTSpots) {
                val coords = allSpots.find { it.id == spotId }?.coordinates ?: continue
                val lat = coords.lat
                val lon = coords.lon

                // Try nearest buoy water temp
                val buoyTemp = SpotDataCache.findNearestBuoyWaterTemp(lat, lon)
                if (buoyTemp != null) {
                    SpotDataCache.updateSST(spotId, SpotDataCache.CachedValue(
                        value = buoyTemp, fetchedAt = now, dataValidAt = now
                    ))
                    SpotDataCache.saveToDatabase(spotId)
                    buoyFills++
                    continue
                }

                // Try nearest cached spot SST
                val nearbySST = SpotDataCache.findNearestSST(lat, lon)
                if (nearbySST != null) {
                    SpotDataCache.updateSST(spotId, SpotDataCache.CachedValue(
                        value = nearbySST, fetchedAt = now, dataValidAt = now
                    ))
                    SpotDataCache.saveToDatabase(spotId)
                    neighborFills++
                }
            }
            val stillMissing = allSpotIds.count { SpotDataCache.get(it)?.sst == null }
            logger.info("SST backfill: ${buoyFills} from buoys, ${neighborFills} from neighbors. Coverage: ${allSpotIds.size - stillMissing}/${allSpotIds.size} spots have SST")
        } else {
            logger.info("SST coverage: ${allSpotIds.size}/${allSpotIds.size} spots have SST (no backfill needed)")
        }

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
        val failures = mutableListOf<ItemFailure>()
        
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
                MonitoringService.captureItemFailure("mpa_prefetch", spot.id, spot.name, e)
                failures.add(ItemFailure(spot.id, spot.name, e.message ?: "unknown", MonitoringService.classifyError(e)))
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
        MonitoringService.reportRun("mpa_prefetch", spotsToUpdate.size, successCount, failures, elapsed)
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
        val failures = mutableListOf<ItemFailure>()
        
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
                    
                    if (!gotVessel && !gotSolunar) {
                        MonitoringService.captureItemFailure("fishing_intel_prefetch", spot.id, spot.name, Exception("Both vessel and solunar fetch failed"))
                        synchronized(failures) {
                            failures.add(ItemFailure(spot.id, spot.name, "Both vessel and solunar fetch failed", "complete_failure"))
                        }
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
        val effectiveSuccess = spotsToUpdate.size - errorCount
        MonitoringService.reportRun("fishing_intel_prefetch", spotsToUpdate.size, effectiveSuccess, failures, elapsed)
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
        val failures = mutableListOf<ItemFailure>()
        
        // Register coordinates for user spots (enables in-memory nearest-SST lookups)
        for (spot in userSpots) {
            SpotDataCache.registerSpotCoordinates("user-${spot.id}", spot.coordinates.lat, spot.coordinates.lon)
        }

        for (spot in userSpots) {
            val cacheId = "user-${spot.id}"
            
            // Check if satellite/SST data is stale (swell/wind is handled by prefetchHourlySwellWind)
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
                val spotToday = spotLocalDate(lon).toString()
                
                // Tide is no longer fetched here. The full-year chart is
                // materialized on spot creation (prefetchSingleSpot) + the monthly
                // horizon top-up, and the live now-state is derived on read from
                // that persisted chart (SpotService.deriveTideData) -- no FES call.

                // Swell/wind handled by prefetchHourlySwellWind() which covers all spots
                
                // SST from NOAA satellite with progressive bbox expansion
                try {
                    val sst = noaaClient.getSeaSurfaceTemperatureProgressive(lat, lon, spotToday)
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
                    val wq = copernicus.getWaterQuality(lat, lon, spotToday)
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
                MonitoringService.captureItemFailure("user_spots_prefetch", cacheId, spot.name, e)
                failures.add(ItemFailure(cacheId, spot.name, e.message ?: "unknown", MonitoringService.classifyError(e)))
                errorCount++
            }
        }
        
        // SST backfill pass for user spots still missing SST
        val userSpotIds = userSpots.map { "user-${it.id}" }
        val missingSST = userSpotIds.filter { SpotDataCache.get(it)?.sst == null }
        if (missingSST.isNotEmpty()) {
            var buoyFills = 0
            var neighborFills = 0
            val now = Instant.now()
            for (cacheId in missingSST) {
                val spot = userSpots.find { "user-${it.id}" == cacheId } ?: continue
                val lat = spot.coordinates.lat
                val lon = spot.coordinates.lon

                val buoyTemp = SpotDataCache.findNearestBuoyWaterTemp(lat, lon)
                if (buoyTemp != null) {
                    SpotDataCache.updateSST(cacheId, SpotDataCache.CachedValue(value = buoyTemp, fetchedAt = now, dataValidAt = now))
                    SpotDataCache.saveToDatabase(cacheId)
                    buoyFills++
                    continue
                }

                val nearbySST = SpotDataCache.findNearestSST(lat, lon)
                if (nearbySST != null) {
                    SpotDataCache.updateSST(cacheId, SpotDataCache.CachedValue(value = nearbySST, fetchedAt = now, dataValidAt = now))
                    SpotDataCache.saveToDatabase(cacheId)
                    neighborFills++
                }
            }
            val stillMissing = userSpotIds.count { SpotDataCache.get(it)?.sst == null }
            logger.info("User spots SST backfill: ${buoyFills} from buoys, ${neighborFills} from neighbors. Coverage: ${userSpotIds.size - stillMissing}/${userSpotIds.size}")
        }

        val elapsed = System.currentTimeMillis() - startTime
        val processed = userSpots.size - skippedCount
        MonitoringService.reportRun("user_spots_prefetch", processed, successCount, failures, elapsed)
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
        val failures = mutableListOf<ItemFailure>()
        
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
                            MonitoringService.captureItemFailure("buoy_readings", station.stationId, station.stationId, e)
                            synchronized(failures) {
                                failures.add(ItemFailure(station.stationId, station.stationId, e.message ?: "unknown", MonitoringService.classifyError(e)))
                            }
                            failed++
                        }
                        Unit
                    }
                }.forEach { it.await() }
            }
            delay(BATCH_DELAY_MS)
        }
        
        val total = success + failed
        MonitoringService.reportRun("buoy_readings", total, success, failures, 0)
    }

}
