package com.shaka.data.client

import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.slf4j.LoggerFactory
import java.util.concurrent.atomic.AtomicLong

/**
 * Token bucket rate limiter for API request throttling.
 * 
 * Prevents overwhelming external APIs by limiting request rate.
 * Uses token bucket algorithm which allows bursts up to bucket size.
 * 
 * Usage:
 * ```
 * val limiter = RateLimiter(requestsPerSecond = 1.0, burstSize = 2)
 * 
 * // This will block if rate limit exceeded
 * limiter.acquire()
 * httpClient.get(url)
 * ```
 */
class RateLimiter(
    private val name: String,
    private val requestsPerSecond: Double,
    private val burstSize: Int = 1
) {
    private val logger = LoggerFactory.getLogger("RateLimiter.$name")
    
    private val mutex = Mutex()
    private var tokens: Double = burstSize.toDouble()
    private var lastRefillTime: Long = System.currentTimeMillis()
    
    // Stats
    private val totalRequests = AtomicLong(0)
    private val throttledRequests = AtomicLong(0)
    
    /**
     * Acquire a token, blocking if necessary until one is available.
     * 
     * @param timeoutMs Maximum time to wait for a token (0 = wait forever)
     * @return true if token acquired, false if timed out
     */
    suspend fun acquire(timeoutMs: Long = 0): Boolean {
        totalRequests.incrementAndGet()
        
        val startTime = System.currentTimeMillis()
        
        while (true) {
            mutex.withLock {
                refillTokens()
                
                if (tokens >= 1.0) {
                    tokens -= 1.0
                    return true
                }
            }
            
            // Check timeout
            if (timeoutMs > 0 && System.currentTimeMillis() - startTime > timeoutMs) {
                logger.warn("Rate limit timeout after ${timeoutMs}ms")
                return false
            }
            
            // Calculate wait time until next token
            val waitMs = (1000.0 / requestsPerSecond).toLong().coerceAtLeast(10)
            throttledRequests.incrementAndGet()
            
            if (throttledRequests.get() % 10 == 0L) {
                logger.debug("Rate limited - waiting ${waitMs}ms (throttled ${throttledRequests.get()} times)")
            }
            
            delay(waitMs)
        }
    }
    
    /**
     * Try to acquire a token without blocking.
     * 
     * @return true if token acquired, false if rate limit would be exceeded
     */
    suspend fun tryAcquire(): Boolean {
        mutex.withLock {
            refillTokens()
            
            if (tokens >= 1.0) {
                tokens -= 1.0
                totalRequests.incrementAndGet()
                return true
            }
            
            return false
        }
    }
    
    /**
     * Get current token count (for monitoring).
     */
    suspend fun availableTokens(): Double {
        mutex.withLock {
            refillTokens()
            return tokens
        }
    }
    
    /**
     * Get rate limiter statistics.
     */
    fun getStats(): Map<String, Any> = mapOf(
        "name" to name,
        "requestsPerSecond" to requestsPerSecond,
        "burstSize" to burstSize,
        "totalRequests" to totalRequests.get(),
        "throttledRequests" to throttledRequests.get(),
        "throttleRate" to if (totalRequests.get() > 0) 
            "%.1f%%".format(throttledRequests.get().toDouble() / totalRequests.get() * 100) 
            else "0%"
    )
    
    /**
     * Reset statistics (for testing).
     */
    fun resetStats() {
        totalRequests.set(0)
        throttledRequests.set(0)
    }
    
    private fun refillTokens() {
        val now = System.currentTimeMillis()
        val elapsed = now - lastRefillTime
        
        // Add tokens based on elapsed time
        val newTokens = elapsed * requestsPerSecond / 1000.0
        tokens = (tokens + newTokens).coerceAtMost(burstSize.toDouble())
        lastRefillTime = now
    }
}

/**
 * Registry of rate limiters for different API domains.
 * 
 * Provides centralized rate limit management and monitoring.
 */
object RateLimiters {
    private val logger = LoggerFactory.getLogger(RateLimiters::class.java)
    
    // Conservative rate limits for external APIs
    // These are tuned to stay well under free tier limits
    
    /**
     * Copernicus WMTS - very conservative (they throttle aggressively)
     * 1 request/second with burst of 2
     */
    val copernicus = RateLimiter(
        name = "copernicus",
        requestsPerSecond = 1.0,
        burstSize = 2
    )
    
    /**
     * Open-Meteo - generous free tier
     * 5 requests/second with burst of 10
     */
    val openMeteo = RateLimiter(
        name = "open-meteo",
        requestsPerSecond = 5.0,
        burstSize = 10
    )
    
    /**
     * NOAA APIs - moderate limits
     * 3 requests/second with burst of 5
     */
    val noaa = RateLimiter(
        name = "noaa",
        requestsPerSecond = 3.0,
        burstSize = 5
    )
    
    /**
     * NOAA Tides - separate limiter (different endpoint)
     * 5 requests/second with burst of 10
     */
    val noaaTides = RateLimiter(
        name = "noaa-tides",
        requestsPerSecond = 5.0,
        burstSize = 10
    )
    
    /**
     * Global Fishing Watch - FREE tier
     * Conservative rate limit to respect their servers
     * 2 requests/second with burst of 5
     */
    val globalFishingWatch = RateLimiter(
        name = "global-fishing-watch",
        requestsPerSecond = 2.0,
        burstSize = 5
    )
    
    /**
     * Solunar API - FREE, generous limits
     * 5 requests/second with burst of 10
     */
    val solunar = RateLimiter(
        name = "solunar",
        requestsPerSecond = 5.0,
        burstSize = 10
    )
    
    /**
     * SoCalFishReports - be respectful to TECK.net sites
     * 1 request/second with burst of 2
     */
    val socalFishReports = RateLimiter(
        name = "socal-fish-reports",
        requestsPerSecond = 1.0,
        burstSize = 2
    )
    
    /**
     * SanDiegoFishReports - same network as SoCal
     * 1 request/second with burst of 2
     */
    val sanDiegoFishReports = RateLimiter(
        name = "san-diego-fish-reports",
        requestsPerSecond = 1.0,
        burstSize = 2
    )
    
    /**
     * Land/water classification service (is-on-water).
     * Light usage, but keep it fast and respectful.
     */
    val landWater = RateLimiter(
        name = "land-water",
        requestsPerSecond = 10.0,
        burstSize = 20
    )

    /**
     * NOAA NCEI DEM_all ImageServer (bathymetry mosaic).
     * Government API — no published rate limit, keep conservative.
     */
    val nceiDem = RateLimiter(
        name = "ncei-dem",
        requestsPerSecond = 2.0,
        burstSize = 5
    )

    /**
     * GEBCO WMS (GetFeatureInfo for depth values).
     * Public WMS, no published rate limit — be respectful.
     */
    val gebcoWms = RateLimiter(
        name = "gebco-wms",
        requestsPerSecond = 1.0,
        burstSize = 2
    )
    
    /**
     * Get stats for all rate limiters.
     */
    fun getAllStats(): Map<String, Map<String, Any>> = mapOf(
        "copernicus" to copernicus.getStats(),
        "openMeteo" to openMeteo.getStats(),
        "noaa" to noaa.getStats(),
        "noaaTides" to noaaTides.getStats(),
        "globalFishingWatch" to globalFishingWatch.getStats(),
        "solunar" to solunar.getStats(),
        "socalFishReports" to socalFishReports.getStats(),
        "sanDiegoFishReports" to sanDiegoFishReports.getStats(),

        "landWater" to landWater.getStats(),
        "nceiDem" to nceiDem.getStats(),
        "gebcoWms" to gebcoWms.getStats()
    )
    
    /**
     * Log current rate limiter status.
     */
    fun logStatus() {
        logger.info("Rate limiter status: ${getAllStats()}")
    }
}
