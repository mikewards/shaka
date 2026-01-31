package com.shaka.data.cache

import com.shaka.model.TideData
import com.shaka.model.OceanData
import com.shaka.model.WeatherData
import com.shaka.model.WaterQuality
import org.slf4j.LoggerFactory
import java.time.Duration
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap

/**
 * Per-spot data cache for pre-fetched ocean data.
 * 
 * Each spot has its own cached data with dual timestamps:
 * - fetchedAt: When OUR job grabbed the data
 * - dataValidAt: When the PROVIDER captured/determined the data (if available)
 * 
 * This cache is populated by background prefetch jobs and provides instant
 * lookups for user requests (no external API calls needed).
 * 
 * Data retention: Latest-only (each job overwrites previous values)
 */
object SpotDataCache {
    
    private val logger = LoggerFactory.getLogger(SpotDataCache::class.java)
    
    /**
     * Generic wrapper for cached values with dual timestamps.
     * 
     * @param value The actual data value
     * @param fetchedAt When our job fetched this data
     * @param dataValidAt When the provider captured this data (e.g., satellite pass date)
     */
    data class CachedValue<T>(
        val value: T,
        val fetchedAt: Instant,
        val dataValidAt: Instant? = null
    ) {
        /**
         * Calculate minutes since we fetched this data.
         * Used for "Updated X minutes ago" display.
         */
        fun minutesSinceFetch(): Long = 
            Duration.between(fetchedAt, Instant.now()).toMinutes()
        
        /**
         * Get a human-readable string for data age.
         */
        fun ageString(): String {
            val minutes = minutesSinceFetch()
            return when {
                minutes < 1 -> "just now"
                minutes < 60 -> "${minutes}min ago"
                minutes < 1440 -> "${minutes / 60}h ago"
                else -> "${minutes / 1440}d ago"
            }
        }
        
        /**
         * Get the provider data date as a readable string (e.g., "Jan 27").
         */
        fun dataDateString(): String? {
            return dataValidAt?.let {
                val date = it.atZone(java.time.ZoneId.systemDefault()).toLocalDate()
                "${date.month.name.take(3).lowercase().replaceFirstChar { c -> c.uppercase() }} ${date.dayOfMonth}"
            }
        }
    }
    
    /**
     * Structured tide information for caching.
     */
    data class TideInfo(
        val state: String,              // "Rising", "Falling", "High", "Low"
        val nextHighTide: String,       // "3:42 PM (5.2ft)"
        val nextLowTide: String,        // "9:15 AM (0.8ft)"
        val currentHeight: Double,      // Current tide height in feet
        val stationId: String? = null   // NOAA station ID if available
    )
    
    /**
     * Structured swell/wave information for caching.
     */
    data class SwellInfo(
        val heightFt: Double,           // Wave height in feet
        val periodSec: Double,          // Wave period in seconds
        val direction: String,          // Cardinal direction (N, NE, E, etc.)
        val swellHeightFt: Double? = null  // Primary swell height if different
    )
    
    /**
     * Structured wind information for caching.
     */
    data class WindInfo(
        val speedKnots: Double,         // Wind speed in knots
        val direction: String,          // Cardinal direction
        val gustKnots: Double? = null   // Gust speed if available
    )
    
    /**
     * All cached data for a single spot.
     * Each field is nullable - data may not be available for all spots.
     */
    data class SpotData(
        val tide: CachedValue<TideInfo>? = null,
        val visibility: CachedValue<Double>? = null,      // Visibility in meters
        val sst: CachedValue<Double>? = null,             // Sea surface temp in Celsius
        val swell: CachedValue<SwellInfo>? = null,
        val wind: CachedValue<WindInfo>? = null,
        val chlorophyll: CachedValue<Double>? = null      // Chlorophyll-a in mg/m³
    ) {
        /**
         * Get the most recent fetch time across all data types.
         */
        fun mostRecentFetch(): Instant? {
            return listOfNotNull(
                tide?.fetchedAt,
                visibility?.fetchedAt,
                sst?.fetchedAt,
                swell?.fetchedAt,
                wind?.fetchedAt
            ).maxOrNull()
        }
        
        /**
         * Get the oldest fetch time (for staleness check).
         */
        fun oldestFetch(): Instant? {
            return listOfNotNull(
                tide?.fetchedAt,
                visibility?.fetchedAt,
                sst?.fetchedAt,
                swell?.fetchedAt,
                wind?.fetchedAt
            ).minOrNull()
        }
    }
    
    // Main cache: spotId -> SpotData
    private val cache = ConcurrentHashMap<String, SpotData>()
    
    // Statistics
    private var hits = 0L
    private var misses = 0L
    
    // ==================== Read Operations ====================
    
    /**
     * Get all cached data for a spot.
     */
    fun get(spotId: String): SpotData? {
        val data = cache[spotId]
        if (data != null) {
            hits++
        } else {
            misses++
        }
        return data
    }
    
    /**
     * Check if we have any data for a spot.
     */
    fun has(spotId: String): Boolean = cache.containsKey(spotId)
    
    /**
     * Get all cached spot IDs.
     */
    fun getAllSpotIds(): Set<String> = cache.keys.toSet()
    
    // ==================== Write Operations ====================
    
    /**
     * Update tide data for a spot.
     */
    fun updateTide(spotId: String, tide: CachedValue<TideInfo>) {
        cache.compute(spotId) { _, existing ->
            (existing ?: SpotData()).copy(tide = tide)
        }
        logger.debug("Updated tide for spot $spotId")
    }
    
    /**
     * Update visibility data for a spot.
     */
    fun updateVisibility(spotId: String, visibility: CachedValue<Double>) {
        cache.compute(spotId) { _, existing ->
            (existing ?: SpotData()).copy(visibility = visibility)
        }
        logger.debug("Updated visibility for spot $spotId: ${visibility.value}m")
    }
    
    /**
     * Update SST data for a spot.
     */
    fun updateSST(spotId: String, sst: CachedValue<Double>) {
        cache.compute(spotId) { _, existing ->
            (existing ?: SpotData()).copy(sst = sst)
        }
        logger.debug("Updated SST for spot $spotId: ${sst.value}°C")
    }
    
    /**
     * Update swell data for a spot.
     */
    fun updateSwell(spotId: String, swell: CachedValue<SwellInfo>) {
        cache.compute(spotId) { _, existing ->
            (existing ?: SpotData()).copy(swell = swell)
        }
        logger.debug("Updated swell for spot $spotId")
    }
    
    /**
     * Update wind data for a spot.
     */
    fun updateWind(spotId: String, wind: CachedValue<WindInfo>) {
        cache.compute(spotId) { _, existing ->
            (existing ?: SpotData()).copy(wind = wind)
        }
        logger.debug("Updated wind for spot $spotId")
    }
    
    /**
     * Update chlorophyll data for a spot.
     */
    fun updateChlorophyll(spotId: String, chlorophyll: CachedValue<Double>) {
        cache.compute(spotId) { _, existing ->
            (existing ?: SpotData()).copy(chlorophyll = chlorophyll)
        }
        logger.debug("Updated chlorophyll for spot $spotId: ${chlorophyll.value} mg/m³")
    }
    
    /**
     * Update weather (swell + wind) in one call.
     */
    fun updateWeather(spotId: String, swell: CachedValue<SwellInfo>, wind: CachedValue<WindInfo>) {
        cache.compute(spotId) { _, existing ->
            (existing ?: SpotData()).copy(swell = swell, wind = wind)
        }
        logger.debug("Updated weather for spot $spotId")
    }
    
    /**
     * Update satellite data (visibility + SST + chlorophyll) in one call.
     */
    fun updateSatelliteData(
        spotId: String, 
        visibility: CachedValue<Double>?,
        sst: CachedValue<Double>?,
        chlorophyll: CachedValue<Double>?
    ) {
        cache.compute(spotId) { _, existing ->
            val current = existing ?: SpotData()
            current.copy(
                visibility = visibility ?: current.visibility,
                sst = sst ?: current.sst,
                chlorophyll = chlorophyll ?: current.chlorophyll
            )
        }
        logger.debug("Updated satellite data for spot $spotId")
    }
    
    // ==================== Cache Management ====================
    
    /**
     * Get cache statistics.
     */
    fun getStats(): Map<String, Any> {
        val total = hits + misses
        val hitRate = if (total > 0) (hits.toDouble() / total * 100) else 0.0
        
        return mapOf(
            "totalSpots" to cache.size,
            "hits" to hits,
            "misses" to misses,
            "hitRate" to "%.1f%%".format(hitRate),
            "spotsWithTide" to cache.values.count { it.tide != null },
            "spotsWithSST" to cache.values.count { it.sst != null },
            "spotsWithVisibility" to cache.values.count { it.visibility != null },
            "spotsWithSwell" to cache.values.count { it.swell != null },
            "spotsWithWind" to cache.values.count { it.wind != null }
        )
    }
    
    /**
     * Get the total number of cached spots.
     */
    fun size(): Int = cache.size
    
    /**
     * Clear all cached data.
     */
    fun clear() {
        cache.clear()
        hits = 0
        misses = 0
        logger.info("SpotDataCache cleared")
    }
    
    /**
     * Remove data for a specific spot.
     */
    fun remove(spotId: String) {
        cache.remove(spotId)
    }
    
    // ==================== Utility Functions ====================
    
    /**
     * Convert degrees to cardinal direction.
     */
    fun degreesToCardinal(degrees: Double): String {
        val directions = listOf("N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", 
                                 "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW")
        val index = ((degrees + 11.25) / 22.5).toInt() % 16
        return directions[index]
    }
    
    /**
     * Convert meters per second to knots.
     */
    fun msToKnots(ms: Double): Double = ms * 1.94384
    
    /**
     * Convert km/h to knots.
     */
    fun kmhToKnots(kmh: Double): Double = kmh * 0.539957
    
    /**
     * Convert meters to feet.
     */
    fun metersToFeet(meters: Double): Double = meters * 3.28084
}
