package com.shaka

import com.shaka.api.routes.configureRouting
import com.shaka.data.cache.SpotDataCache
import com.shaka.data.client.*
import com.shaka.data.db.DatabaseFactory
import com.shaka.service.DataPrefetchJobs
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
    val prefetchJobs = DataPrefetchJobs(
        SpotDatabase,
        NOAATidesClient(),
        OpenMeteoClient(),
        CopernicusClient(),
        NOAAClient()
    )
    
    // Create isolated scope for background jobs - failures won't affect other jobs or the app
    val backgroundScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    
    // Run full prefetch on startup (after a brief delay to let the app initialize)
    backgroundScope.launch {
        delay(5_000)  // Wait 5 seconds for app to fully start
        
        val cacheSize = SpotDataCache.size()
        if (cacheSize > 0) {
            logger.info("Cache already has $cacheSize spots from database - prefetch will update stale data only")
        } else {
            logger.info("Cache empty - starting full data prefetch...")
        }
        
        try {
            prefetchJobs.prefetchAll()
        } catch (e: Exception) {
            logger.error("Initial prefetch failed: ${e.message}", e)
        }
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
    
    logger.info("Background prefetch jobs configured: hourly (tide), 3h (weather), 6h (satellite)")
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
