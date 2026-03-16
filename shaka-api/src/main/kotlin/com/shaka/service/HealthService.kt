package com.shaka.service

import io.ktor.client.*
import io.ktor.client.engine.cio.*
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
    
    private val client = HttpClient(CIO) {
        engine {
            requestTimeout = 5_000 // 5 second timeout for health checks
        }
    }
    
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
            // Simple ping to Open-Meteo API
            val response = client.get("https://api.open-meteo.com/v1/forecast") {
                parameter("latitude", 21.3)
                parameter("longitude", -157.8)
                parameter("current_weather", "true")
            }
            if (response.status.value in 200..299) {
                ServiceStatus("ok", lastChecked = Instant.now().toString())
            } else {
                ServiceStatus("error", "HTTP ${response.status.value}", Instant.now().toString())
            }
        } catch (e: Exception) {
            logger.warn("OpenMeteo health check failed: ${e.message}")
            ServiceStatus("error", e.message, Instant.now().toString())
        }
    }
    
    private suspend fun checkGibs(): ServiceStatus {
        return try {
            val response = client.head("https://gibs.earthdata.nasa.gov/wmts/epsg4326/best/MODIS_Terra_CorrectedReflectance_TrueColor/default/2024-01-01/250m/0/0/0.jpg")
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
            val response = client.get("https://coastwatch.pfeg.noaa.gov/erddap/info/index.html")
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
            val response = client.head("https://wmts.marine.copernicus.eu/teroWmts")
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
