package com.shaka

import com.shaka.api.routes.configureRouting
import com.shaka.data.cache.SpotDataCache
import com.shaka.data.client.*
import com.shaka.data.db.DatabaseFactory
import com.shaka.service.DataPrefetchJobs
import com.shaka.fishing_intel.db.FishingIntelDb
import com.shaka.fishing_intel.jobs.FishingIntelPrefetchJob
import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.server.plugins.cors.routing.*
import io.ktor.server.plugins.statuspages.*
import io.ktor.http.*
import io.ktor.server.response.*
import kotlinx.coroutines.*
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory

private val logger = LoggerFactory.getLogger("Application")

fun main() {
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
        NOAATidesClient(),
        OpenMeteoClient(),
        CopernicusClient(),
        NOAAClient(),
        ndbcBuoyClient = ndbcClient,
        bathymetryClient = bathymetryClient
    )
    
    // Create isolated scope for background jobs - failures won't affect other jobs or the app
    val backgroundScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    
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
    backgroundScope.launch {
        delay(60_000)  // Initial 1 minute delay (after startup prefetch starts)
        while (true) {
            delay(3_600_000)  // 1 hour = 3,600,000 ms
            try {
                logger.info("Running scheduled TIDE prefetch")
                prefetchJobs.prefetchTides()
            } catch (e: Exception) {
                logger.error("Scheduled tide prefetch failed: ${e.message}", e)
            }
        }
    }
    
    // EVERY 3 HOURS: Weather/swell refresh
    backgroundScope.launch {
        delay(120_000)  // Initial 2 minute delay
        while (true) {
            delay(10_800_000)  // 3 hours = 10,800,000 ms
            try {
                logger.info("Running scheduled WEATHER prefetch")
                prefetchJobs.prefetchWeather()
            } catch (e: Exception) {
                logger.error("Scheduled weather prefetch failed: ${e.message}", e)
            }
        }
    }
    
    // EVERY 6 HOURS: Satellite data refresh
    backgroundScope.launch {
        delay(180_000)  // Initial 3 minute delay
        while (true) {
            delay(21_600_000)  // 6 hours = 21,600,000 ms
            try {
                logger.info("Running scheduled SATELLITE prefetch")
                prefetchJobs.prefetchSatelliteData()
            } catch (e: Exception) {
                logger.error("Scheduled satellite prefetch failed: ${e.message}", e)
            }
        }
    }
    
    // EVERY 3 HOURS: User spots refresh (same as weather)
    backgroundScope.launch {
        delay(240_000)  // Initial 4 minute delay (after startup prefetch)
        while (true) {
            delay(10_800_000)  // 3 hours = 10,800,000 ms
            try {
                logger.info("Running scheduled USER SPOTS prefetch")
                prefetchJobs.prefetchUserSpots()
            } catch (e: Exception) {
                logger.error("Scheduled user spots prefetch failed: ${e.message}", e)
            }
        }
    }
    
    // EVERY 12 HOURS: Solunar + vessel data refresh (runs 2x/day)
    // Solunar feeding windows shift through the day, so twice-daily keeps data fresh.
    // Startup prefetchAll() handles the initial run; this handles recurring refreshes.
    backgroundScope.launch {
        delay(300_000)  // Initial 5 minute delay (startup prefetchAll already runs it)
        while (true) {
            delay(43_200_000)  // 12 hours = 43,200,000 ms
            try {
                logger.info("Running scheduled SOLUNAR + VESSEL prefetch")
                prefetchJobs.prefetchFishingIntel()
            } catch (e: Exception) {
                logger.error("Scheduled solunar prefetch failed: ${e.message}", e)
            }
        }
    }
    
    // HOURLY: Buoy readings refresh
    backgroundScope.launch {
        delay(360_000)  // Initial 6 minute delay
        while (true) {
            delay(3_600_000)  // 1 hour
            try {
                logger.info("Running scheduled BUOY READINGS prefetch")
                prefetchJobs.prefetchBuoyReadings()
            } catch (e: Exception) {
                logger.error("Scheduled buoy readings prefetch failed: ${e.message}", e)
            }
        }
    }
    
    // EVERY 6 HOURS: Tide chart materialization (today + tomorrow)
    backgroundScope.launch {
        delay(420_000)  // Initial 7 minute delay
        while (true) {
            try {
                logger.info("Running scheduled TIDE CHART materialization")
                prefetchJobs.materializeTideCharts()
            } catch (e: Exception) {
                logger.error("Scheduled tide chart materialization failed: ${e.message}", e)
            }
            delay(21_600_000)  // 6 hours
        }
    }

    // EVERY 10 MINUTES: Tide chart catch-up (missing spots)
    backgroundScope.launch {
        delay(480_000)  // Initial 8 minute delay
        while (true) {
            try {
                prefetchJobs.catchUpMissingTideCharts()
            } catch (e: Exception) {
                logger.error("Tide chart catch-up failed: ${e.message}", e)
            }
            delay(600_000)  // 10 minutes
        }
    }

    // NIGHTLY: Tide chart cleanup (old rows)
    backgroundScope.launch {
        delay(600_000)  // Initial 10 minute delay
        while (true) {
            try {
                prefetchJobs.cleanupOldTideDays()
            } catch (e: Exception) {
                logger.error("Tide chart cleanup failed: ${e.message}", e)
            }
            delay(86_400_000)  // 24 hours
        }
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
    backgroundScope.launch {
        delay(300_000)  // 5 minute initial delay before first scrape
        
        // Run initial scrape
        try {
            logger.info("Running initial FISHING INTEL scrape")
            FishingIntelPrefetchJob.run()
        } catch (e: Exception) {
            logger.error("Initial fishing intel scrape failed: ${e.message}", e)
        }
        
        // Schedule every 2 hours
        while (true) {
            delay(7_200_000)  // 2 hours = 7,200,000 ms
            try {
                logger.info("Running scheduled FISHING INTEL scrape")
                FishingIntelPrefetchJob.run()
            } catch (e: Exception) {
                logger.error("Scheduled fishing intel scrape failed: ${e.message}", e)
            }
        }
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
