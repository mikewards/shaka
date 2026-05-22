package com.shaka

import com.shaka.api.routes.configureRouting
import com.shaka.data.cache.SpotDataCache
import com.shaka.data.client.*
import com.shaka.data.db.DatabaseFactory
import com.shaka.service.DataPrefetchJobs
import com.shaka.service.WeatherTileService
import com.shaka.fishing_intel.db.FishingIntelDb
import com.shaka.fishing_intel.jobs.FishingIntelPrefetchJob
import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.server.plugins.cors.routing.*
import io.ktor.server.plugins.compression.*
import io.ktor.server.plugins.statuspages.*
import io.ktor.http.*
import io.ktor.server.response.*
import io.ktor.util.*
import kotlinx.coroutines.*
import kotlinx.serialization.json.Json
import io.sentry.Sentry
import org.slf4j.LoggerFactory

val PrefetchJobsKey = AttributeKey<DataPrefetchJobs>("PrefetchJobs")

private val logger = LoggerFactory.getLogger("Application")

fun main() {
    val sentryDsn = System.getenv("SENTRY_DSN")
    if (!sentryDsn.isNullOrBlank()) {
        Sentry.init { options ->
            options.dsn = sentryDsn
            options.environment = System.getenv("RAILWAY_ENVIRONMENT") ?: "production"
            options.sampleRate = 1.0
            options.tracesSampleRate = 0.0
        }
        println("Sentry initialized (env=${System.getenv("RAILWAY_ENVIRONMENT") ?: "production"})")
    }

    val port = System.getenv("PORT")?.toIntOrNull() ?: 8080
    println("Starting Shaka API on port $port")
    
    embeddedServer(Netty, port = port, host = "0.0.0.0", module = Application::module)
        .start(wait = true)
}

fun Application.module() {
    println("Initializing Shaka API module...")
    
    // Try database connection (non-blocking - app works without it)
    tryInitDatabase()
    
    // Ensure spot_cache table exists
    SpotDataCache.createTableIfNotExists()
    
    // Load cached data from database (survives restarts!)
    val cachedSpots = SpotDataCache.loadFromDatabase()
    if (cachedSpots > 0) {
        logger.info("Restored $cachedSpots spots from database cache")
    }
    
    install(CORS) {
        anyHost()
        allowMethod(HttpMethod.Get)
        allowMethod(HttpMethod.Post)
        allowMethod(HttpMethod.Options)
        allowHeader(HttpHeaders.ContentType)
        allowHeader(HttpHeaders.Authorization)
    }

    install(Compression) {
        gzip {
            priority = 1.0
            matchContentType(ContentType.Application.Json, ContentType.Text.Any)
        }
        deflate {
            priority = 0.9
            matchContentType(ContentType.Application.Json, ContentType.Text.Any)
        }
    }

    install(ContentNegotiation) {
        json(Json {
            prettyPrint = true
            isLenient = true
            ignoreUnknownKeys = true
        })
    }

    install(StatusPages) {
        exception<Throwable> { call, cause ->
            logger.error("Request failed: ${cause.message}", cause)
            call.respond(
                HttpStatusCode.InternalServerError,
                mapOf("error" to (cause.message ?: "Unknown error"))
            )
        }
    }

    configureRouting()
    
    // Start background data prefetch jobs
    configureScheduledJobs()
    
    logger.info("Shaka API initialized successfully")
}

/**
 * Configure background prefetch jobs for ocean data.
 * 
 * Schedule:
 * - Startup: Full prefetch of all data types (staggered)
 * - Hourly: Tide data (changes frequently)
 * - Every 3 hours: Weather/swell data
 * - Every 6 hours: Satellite data (SST, visibility)
 * 
 * Uses SupervisorJob to prevent failures from cancelling other jobs.
 */
private fun Application.configureScheduledJobs() {
    val ndbcClient = NDBCBuoyClient()
    val landWaterClient = LandWaterClient()
    val bathymetryClient = BathymetryClient(landWaterClient)
    val prefetchJobs = DataPrefetchJobs(
        SpotDatabase,
        TideClient.create(),
        OpenMeteoClient(),
        CopernicusClient(),
        NOAAClient(),
        ndbcBuoyClient = ndbcClient,
        bathymetryClient = bathymetryClient
    )
    attributes.put(PrefetchJobsKey, prefetchJobs)
    
    // Create isolated scope for background jobs - failures won't affect other jobs or the app
    val backgroundScope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    /**
     * Run a job on a fixed cadence with a per-iteration watchdog.
     *
     * Hardening from the Jun 2026 outage: a hung dependency froze job
     * coroutines mid-iteration for 8 days (no timeout), and anything
     * escaping the old catch(Exception) would have killed the loop.
     * Each iteration is bounded by maxRunMs and survives Throwable.
     */
    fun scheduleJob(
        name: String,
        initialDelayMs: Long,
        intervalMs: Long,
        maxRunMs: Long = intervalMs * 4,
        runImmediately: Boolean = false,
        job: suspend () -> Unit
    ) {
        backgroundScope.launch {
            delay(initialDelayMs)
            if (!runImmediately) delay(intervalMs)
            while (true) {
                try {
                    logger.info("Running scheduled job: $name")
                    withTimeout(maxRunMs) { job() }
                } catch (e: TimeoutCancellationException) {
                    logger.error("Scheduled job $name exceeded ${maxRunMs}ms watchdog; iteration aborted")
                } catch (e: Throwable) {
                    logger.error("Scheduled job $name failed: ${e.message}", e)
                }
                delay(intervalMs)
            }
        }
    }
    
    // Run full prefetch on startup (after a brief delay to let the app initialize)
    backgroundScope.launch {
        delay(5_000)  // Wait 5 seconds for app to fully start
        
        // CRITICAL: Load cached data from database first!
        // This restores chlorophyll/SST/visibility data from previous runs
        try {
            SpotDataCache.createTableIfNotExists()
            val loadedCount = SpotDataCache.loadFromDatabase()
            logger.info("Loaded $loadedCount spots from database cache")
        } catch (e: Exception) {
            logger.warn("Failed to load cache from database: ${e.message}")
        }
        
        val cacheSize = SpotDataCache.size()
        if (cacheSize > 0) {
            logger.info("Cache has $cacheSize spots - prefetch will update stale data only")
        } else {
            logger.info("Cache empty - starting full data prefetch...")
        }
        
        // Seed NDBC buoy stations (idempotent — updates existing, adds new)
        try {
            prefetchJobs.seedBuoyStations()
        } catch (e: Exception) {
            logger.warn("Buoy station seeding failed: ${e.message}")
        }
        
        logger.info("Startup complete — scheduled jobs will refresh stale data on cadence")
    }
    
    // HOURLY: Tide refresh
    scheduleJob("tide_prefetch", initialDelayMs = 60_000, intervalMs = 3_600_000) {
        prefetchJobs.prefetchTides()
    }

    // EVERY 3 HOURS: Weather/swell refresh
    scheduleJob("weather_prefetch", initialDelayMs = 120_000, intervalMs = 10_800_000) {
        prefetchJobs.prefetchWeather()
    }

    // EVERY 6 HOURS: Satellite data refresh (rate-limited, can run very long)
    scheduleJob("satellite_prefetch", initialDelayMs = 180_000, intervalMs = 21_600_000, maxRunMs = 86_400_000) {
        prefetchJobs.prefetchSatelliteData()
    }

    // EVERY 3 HOURS: User spots refresh (same as weather)
    scheduleJob("user_spots_prefetch", initialDelayMs = 240_000, intervalMs = 10_800_000, maxRunMs = 86_400_000) {
        prefetchJobs.prefetchUserSpots()
    }

    // EVERY 12 HOURS: Solunar + vessel data refresh (runs 2x/day)
    scheduleJob("solunar_vessel_prefetch", initialDelayMs = 300_000, intervalMs = 43_200_000) {
        prefetchJobs.prefetchFishingIntel()
    }

    // HOURLY: Buoy readings refresh
    scheduleJob("buoy_readings", initialDelayMs = 360_000, intervalMs = 3_600_000) {
        prefetchJobs.prefetchBuoyReadings()
    }

    // EVERY 6 HOURS: Tide chart materialization (today + tomorrow)
    scheduleJob("tide_chart_materialize", initialDelayMs = 420_000, intervalMs = 21_600_000, runImmediately = true) {
        prefetchJobs.materializeTideCharts()
    }

    // EVERY 10 MINUTES: Tide chart catch-up (missing spots)
    scheduleJob("tide_chart_catchup", initialDelayMs = 480_000, intervalMs = 600_000, maxRunMs = 21_600_000, runImmediately = true) {
        prefetchJobs.catchUpMissingTideCharts()
    }

    // WEEKLY: MPA boundary refresh. Previously only reachable via the dead
    // prefetchAll() path, so MPA data silently aged for months.
    scheduleJob("mpa_prefetch", initialDelayMs = 900_000, intervalMs = 604_800_000, maxRunMs = 86_400_000, runImmediately = true) {
        prefetchJobs.prefetchMPA()
    }

    // NIGHTLY: Tide chart cleanup (old rows)
    scheduleJob("tide_chart_cleanup", initialDelayMs = 600_000, intervalMs = 86_400_000, runImmediately = true) {
        prefetchJobs.cleanupOldTideDays()
    }

    // ==================== WEATHER TILES (Ocean Forecast) ====================
    // Runs the Copernicus CMEMS pipeline every 6 hours to generate PNG tiles
    scheduleJob("weather_tile_pipeline", initialDelayMs = 30_000, intervalMs = 21_600_000, runImmediately = true) {
        WeatherTileService.runPipeline()
    }

    // ==================== FISHING INTEL (ISOLATED) ====================
    // Scrapes SoCal fishing reports every 2 hours
    // Fully isolated - can be disabled without affecting other features
    
    // Initialize fishing intel database tables IMMEDIATELY at startup
    try {
        FishingIntelDb.createTablesIfNotExists()
        FishingIntelDb.seedLandings()
        FishingIntelDb.seedSources()
        FishingIntelDb.backfillBdOutdoorsGeos()
        FishingIntelDb.backfillAllMissingGeos()
        logger.info("Fishing intel tables initialized")
    } catch (e: Exception) {
        logger.error("Failed to initialize fishing intel tables: ${e.message}")
    }
    
    // Schedule scraping job (delayed start, then every 2 hours)
    scheduleJob("fishing_intel_scrape", initialDelayMs = 300_000, intervalMs = 7_200_000, runImmediately = true) {
        FishingIntelPrefetchJob.run()
    }
    
    logger.info("Fishing intel job configured: every 2 hours")
    
    // Clean up when application stops
    environment.monitor.subscribe(ApplicationStopped) {
        logger.info("Shutting down Shaka API...")
        
        // Cancel background jobs
        backgroundScope.cancel()
        logger.info("Background prefetch jobs stopped")
        
        // Close shared HTTP client (releases connection pool)
        HttpClientFactory.close()
        logger.info("HTTP client closed")
        
        // Log final rate limiter stats
        logger.info("Final rate limiter stats: ${RateLimiters.getAllStats()}")
    }
    
    logger.info("Background prefetch jobs configured: hourly (tide), 3h (weather + user spots), 6h (satellite)")
}

private fun Application.tryInitDatabase() {
    val dbUrl = System.getenv("DATABASE_URL")
    
    if (dbUrl.isNullOrBlank()) {
        println("DATABASE_URL not set - using in-memory database")
        return
    }
    
    try {
        val dbUser = System.getenv("DATABASE_USER") ?: ""
        val dbPassword = System.getenv("DATABASE_PASSWORD") ?: ""
        
        println("Attempting database connection...")
        println("DB User: $dbUser")
        println("DB URL prefix: ${dbUrl.take(30)}...")
        
        DatabaseFactory.init(dbUrl, dbUser, dbPassword)
        println("Database connection established!")
    } catch (e: Throwable) {
        // Catch Throwable to handle Errors too, not just Exceptions
        println("Database connection failed: ${e.message}")
        e.printStackTrace()
        println("Continuing with in-memory database...")
    }
}

// Triggered redeploy 2026-02-01_fix_user_spots_no_updated_at
