package com.shaka.service

import com.shaka.data.client.HttpClientFactory
import io.ktor.client.request.*
import io.ktor.client.statement.*
import kotlinx.coroutines.*
import kotlinx.serialization.Serializable
import org.slf4j.LoggerFactory
import java.time.Instant

/**
 * Service to check health of external dependencies.
 * Used by Flutter app to auto-degrade features when services are down.
 */
class HealthService {
    
    private val logger = LoggerFactory.getLogger(HealthService::class.java)
    
    // Health checks go through the SHARED client on purpose: during the Jul
    // 2026 outage this service's private client kept reporting "ok" while the
    // shared client's pool was wedged — health must exercise the same path
    // real fetches use. Per-check 5s deadline preserved via withTimeout.
    private val client = HttpClientFactory.shared

    private suspend fun <T> bounded(block: suspend () -> T): T =
        withTimeout(5_000) { block() }
    
    // Cache health status for 5 minutes to avoid hammering external services
    private var cachedHealth: ServiceHealth? = null
    private var cacheExpiry: Long = 0
    
    @Serializable
    data class ServiceStatus(
        val status: String, // "ok", "error", "degraded"
        val message: String? = null,
        val lastChecked: String
    )
    
    @Serializable
    data class ServiceHealth(
        val status: String, // "healthy", "degraded", "unhealthy"
        val services: Map<String, ServiceStatus>,
        val timestamp: String
    )
    
    suspend fun checkHealth(forceRefresh: Boolean = false): ServiceHealth {
        val now = System.currentTimeMillis()
        
        // Return cached health if still valid
        if (!forceRefresh && cachedHealth != null && now < cacheExpiry) {
            return cachedHealth!!
        }
        
        val timestamp = Instant.now().toString()
        
        // Check all services in parallel with individual timeouts
        val statuses = coroutineScope {
            mapOf(
                "openmeteo" to async { checkOpenMeteo() },
                "gibs" to async { checkGibs() },
                "noaa" to async { checkNoaa() },
                "copernicus" to async { checkCopernicus() }
            ).mapValues { it.value.await() }
        }
        
        // Determine overall status
        val errorCount = statuses.values.count { it.status == "error" }
        val overallStatus = when {
            errorCount == 0 -> "healthy"
            errorCount < statuses.size -> "degraded"
            else -> "unhealthy"
        }
        
        val health = ServiceHealth(
            status = overallStatus,
            services = statuses,
            timestamp = timestamp
        )
        
        // Cache for 5 minutes
        cachedHealth = health
        cacheExpiry = now + 5 * 60 * 1000
        
        return health
    }
    
    private suspend fun checkOpenMeteo(): ServiceStatus {
        return try {
            // Check BOTH hosts: the weather host (api.) and the marine host
            // (marine-api.) live on different networks. In Jul 2026 the marine
            // host was unreachable from Railway for days while this check —
            // which then only pinged the weather host — kept reporting "ok",
            // masking a 100% hourly_swell_wind failure.
            val weather = bounded {
                client.get("https://api.open-meteo.com/v1/forecast") {
                    parameter("latitude", 21.3)
                    parameter("longitude", -157.8)
                    parameter("current_weather", "true")
                }
            }
            val marine = bounded {
                client.get("https://marine-api.open-meteo.com/v1/marine") {
                    parameter("latitude", 21.3)
                    parameter("longitude", -157.8)
                    parameter("forecast_days", 1)
                    parameter("hourly", "wave_height")
                }
            }
            when {
                weather.status.value !in 200..299 ->
                    ServiceStatus("error", "weather host HTTP ${weather.status.value}", Instant.now().toString())
                marine.status.value !in 200..299 ->
                    ServiceStatus("error", "marine host HTTP ${marine.status.value}", Instant.now().toString())
                else -> ServiceStatus("ok", lastChecked = Instant.now().toString())
            }
        } catch (e: Exception) {
            logger.warn("OpenMeteo health check failed: ${e.message}")
            ServiceStatus("error", e.message, Instant.now().toString())
        }
    }
    
    private suspend fun checkGibs(): ServiceStatus {
        return try {
            // Probe a recent tile, not a frozen historical date: the hardcoded
            // 2024-01-01 tile could keep passing while current-day layers fail.
            val recentDate = java.time.LocalDate.now().minusDays(2).toString()
            val response = bounded { client.head("https://gibs.earthdata.nasa.gov/wmts/epsg4326/best/MODIS_Terra_CorrectedReflectance_TrueColor/default/$recentDate/250m/0/0/0.jpg") }
            if (response.status.value in 200..299) {
                ServiceStatus("ok", lastChecked = Instant.now().toString())
            } else {
                ServiceStatus("error", "HTTP ${response.status.value}", Instant.now().toString())
            }
        } catch (e: Exception) {
            logger.warn("GIBS health check failed: ${e.message}")
            ServiceStatus("error", e.message, Instant.now().toString())
        }
    }
    
    private suspend fun checkNoaa(): ServiceStatus {
        return try {
            // Check NOAA ERDDAP
            // Must match the host NOAAClient actually uses (pfeg host is unreachable from Railway)
            val response = bounded { client.get("https://coastwatch.noaa.gov/erddap/info/index.html") }
            if (response.status.value in 200..299) {
                ServiceStatus("ok", lastChecked = Instant.now().toString())
            } else {
                ServiceStatus("error", "HTTP ${response.status.value}", Instant.now().toString())
            }
        } catch (e: Exception) {
            logger.warn("NOAA health check failed: ${e.message}")
            ServiceStatus("error", e.message, Instant.now().toString())
        }
    }
    
    private suspend fun checkCopernicus(): ServiceStatus {
        return try {
            // A bare request returns 400 (missing WMTS params) even when the
            // service is healthy; probe GetCapabilities like a real client.
            val response = bounded { client.head("https://wmts.marine.copernicus.eu/teroWmts?SERVICE=WMTS&REQUEST=GetCapabilities") }
            if (response.status.value in 200..399) {
                ServiceStatus("ok", lastChecked = Instant.now().toString())
            } else {
                ServiceStatus("error", "HTTP ${response.status.value}", Instant.now().toString())
            }
        } catch (e: Exception) {
            logger.warn("Copernicus health check failed: ${e.message}")
            ServiceStatus("error", e.message, Instant.now().toString())
        }
    }
}
