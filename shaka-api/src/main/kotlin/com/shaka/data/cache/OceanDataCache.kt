package com.shaka.data.cache

import com.shaka.model.TideData
import com.shaka.model.WaterQuality
import com.shaka.model.WeatherData
import com.shaka.model.OceanData
import org.slf4j.LoggerFactory
import java.util.concurrent.ConcurrentHashMap
import kotlin.time.Duration
import kotlin.time.Duration.Companion.hours
import kotlin.time.Duration.Companion.minutes

/**
 * In-memory cache for ocean data with TTL-based expiration.
 * 
 * Caching strategy based on data change frequency:
 * - Chlorophyll/Visibility: 12 hours (satellite data, changes slowly)
 * - SST: 6 hours (moderate change rate)
 * - Tides: 6 hours (predictable, computed)
 * - Wind/Swell: 1 hour (changes faster, weather-dependent)
 * 
 * Cache keys are formatted as: "dataType:lat:lon:date" with coordinates
 * rounded to 2 decimal places for reasonable spatial grouping.
 */
object OceanDataCache {
    
    private val logger = LoggerFactory.getLogger(OceanDataCache::class.java)
    
    // TTLs based on data change frequency
    val TTL_WATER_QUALITY = 12.hours    // Chlorophyll, turbidity, visibility
    val TTL_SST = 6.hours               // Sea surface temperature
    val TTL_TIDES = 6.hours             // Tide predictions
    val TTL_WEATHER = 1.hours           // Wind, precipitation
    val TTL_OCEAN = 1.hours             // Swell, waves
    
    // Cache storage
    private val waterQualityCache = ConcurrentHashMap<String, CacheEntry<WaterQuality>>()
    private val tideCache = ConcurrentHashMap<String, CacheEntry<TideData>>()
    private val weatherCache = ConcurrentHashMap<String, CacheEntry<WeatherData>>()
    private val oceanCache = ConcurrentHashMap<String, CacheEntry<OceanData>>()
    
    // Statistics
    private var hits = 0L
    private var misses = 0L
    
    data class CacheEntry<T>(
        val data: T,
        val expiry: Long,
        val createdAt: Long = System.currentTimeMillis()
    ) {
        fun isExpired(): Boolean = System.currentTimeMillis() > expiry
        
        fun age(): Duration = (System.currentTimeMillis() - createdAt).minutes
    }
    
    /**
     * Generate cache key with rounded coordinates for spatial grouping.
     * Rounds to 2 decimal places (~1km precision).
     */
    private fun makeKey(lat: Double, lon: Double, date: String): String {
        val roundedLat = "%.2f".format(lat)
        val roundedLon = "%.2f".format(lon)
        return "$roundedLat:$roundedLon:$date"
    }
    
    // ==================== Water Quality ====================
    
    fun getWaterQuality(lat: Double, lon: Double, date: String): WaterQuality? {
        val key = makeKey(lat, lon, date)
        val entry = waterQualityCache[key]
        
        return if (entry != null && !entry.isExpired()) {
            hits++
            logger.debug("Cache HIT for water quality at ($lat, $lon)")
            entry.data
        } else {
            misses++
            if (entry != null) {
                waterQualityCache.remove(key)
            }
            null
        }
    }
    
    fun putWaterQuality(lat: Double, lon: Double, date: String, data: WaterQuality, ttl: Duration = TTL_WATER_QUALITY) {
        val key = makeKey(lat, lon, date)
        val expiry = System.currentTimeMillis() + ttl.inWholeMilliseconds
        waterQualityCache[key] = CacheEntry(data, expiry)
        logger.debug("Cached water quality for ($lat, $lon), expires in ${ttl.inWholeMinutes} minutes")
    }
    
    // ==================== Tides ====================
    
    fun getTide(lat: Double, lon: Double, date: String): TideData? {
        val key = makeKey(lat, lon, date)
        val entry = tideCache[key]
        
        return if (entry != null && !entry.isExpired()) {
            hits++
            logger.debug("Cache HIT for tides at ($lat, $lon)")
            entry.data
        } else {
            misses++
            if (entry != null) {
                tideCache.remove(key)
            }
            null
        }
    }
    
    fun putTide(lat: Double, lon: Double, date: String, data: TideData, ttl: Duration = TTL_TIDES) {
        val key = makeKey(lat, lon, date)
        val expiry = System.currentTimeMillis() + ttl.inWholeMilliseconds
        tideCache[key] = CacheEntry(data, expiry)
        logger.debug("Cached tides for ($lat, $lon), expires in ${ttl.inWholeMinutes} minutes")
    }
    
    // ==================== Weather ====================
    
    fun getWeather(lat: Double, lon: Double, date: String): WeatherData? {
        val key = makeKey(lat, lon, date)
        val entry = weatherCache[key]
        
        return if (entry != null && !entry.isExpired()) {
            hits++
            entry.data
        } else {
            misses++
            if (entry != null) {
                weatherCache.remove(key)
            }
            null
        }
    }
    
    fun putWeather(lat: Double, lon: Double, date: String, data: WeatherData, ttl: Duration = TTL_WEATHER) {
        val key = makeKey(lat, lon, date)
        val expiry = System.currentTimeMillis() + ttl.inWholeMilliseconds
        weatherCache[key] = CacheEntry(data, expiry)
    }
    
    // ==================== Ocean (Swell/Waves) ====================
    
    fun getOcean(lat: Double, lon: Double, date: String): OceanData? {
        val key = makeKey(lat, lon, date)
        val entry = oceanCache[key]
        
        return if (entry != null && !entry.isExpired()) {
            hits++
            entry.data
        } else {
            misses++
            if (entry != null) {
                oceanCache.remove(key)
            }
            null
        }
    }
    
    fun putOcean(lat: Double, lon: Double, date: String, data: OceanData, ttl: Duration = TTL_OCEAN) {
        val key = makeKey(lat, lon, date)
        val expiry = System.currentTimeMillis() + ttl.inWholeMilliseconds
        oceanCache[key] = CacheEntry(data, expiry)
    }
    
    // ==================== Cache Management ====================
    
    /**
     * Get cache statistics.
     */
    fun getStats(): Map<String, Any> {
        val total = hits + misses
        val hitRate = if (total > 0) (hits.toDouble() / total * 100) else 0.0
        
        return mapOf(
            "hits" to hits,
            "misses" to misses,
            "hitRate" to "%.1f%%".format(hitRate),
            "waterQualityEntries" to waterQualityCache.size,
            "tideEntries" to tideCache.size,
            "weatherEntries" to weatherCache.size,
            "oceanEntries" to oceanCache.size
        )
    }
    
    /**
     * Clear all caches.
     */
    fun clearAll() {
        waterQualityCache.clear()
        tideCache.clear()
        weatherCache.clear()
        oceanCache.clear()
        hits = 0
        misses = 0
        logger.info("All caches cleared")
    }
    
    /**
     * Remove expired entries from all caches.
     * Should be called periodically (e.g., every hour).
     */
    fun evictExpired() {
        var evicted = 0
        
        waterQualityCache.entries.removeIf { it.value.isExpired().also { expired -> if (expired) evicted++ } }
        tideCache.entries.removeIf { it.value.isExpired().also { expired -> if (expired) evicted++ } }
        weatherCache.entries.removeIf { it.value.isExpired().also { expired -> if (expired) evicted++ } }
        oceanCache.entries.removeIf { it.value.isExpired().also { expired -> if (expired) evicted++ } }
        
        if (evicted > 0) {
            logger.info("Evicted $evicted expired cache entries")
        }
    }
}
