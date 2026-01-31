package com.shaka.data.cache

import com.shaka.data.db.DatabaseFactory
import com.shaka.model.TideData
import com.shaka.model.OceanData
import com.shaka.model.WeatherData
import com.shaka.model.WaterQuality
import org.jetbrains.exposed.sql.transactions.transaction
import org.slf4j.LoggerFactory
import java.sql.Timestamp
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
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
     * GIBS satellite chlorophyll data from all 5 satellites for today and yesterday.
     * Used for comparison with Copernicus data.
     */
    data class GIBSSatelliteData(
        val paceToday: Double?,
        val paceYesterday: Double?,
        val noaa20Today: Double?,
        val noaa20Yesterday: Double?,
        val noaa21Today: Double?,
        val noaa21Yesterday: Double?,
        val sentinel3aToday: Double?,
        val sentinel3aYesterday: Double?,
        val sentinel3bToday: Double?,
        val sentinel3bYesterday: Double?,
        val dataDate: LocalDate   // "Today" when this was fetched
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
        val chlorophyll: CachedValue<Double>? = null,     // Chlorophyll-a in mg/m³ (Copernicus)
        val gibsChlorophyll: CachedValue<GIBSSatelliteData>? = null  // GIBS satellite data
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
     * Update GIBS satellite chlorophyll data for a spot.
     */
    fun updateGIBSChlorophyll(spotId: String, gibsData: CachedValue<GIBSSatelliteData>) {
        cache.compute(spotId) { _, existing ->
            (existing ?: SpotData()).copy(gibsChlorophyll = gibsData)
        }
        val data = gibsData.value
        val hasData = listOfNotNull(
            data.paceToday, data.paceYesterday,
            data.noaa20Today, data.noaa20Yesterday,
            data.noaa21Today, data.noaa21Yesterday,
            data.sentinel3aToday, data.sentinel3aYesterday,
            data.sentinel3bToday, data.sentinel3bYesterday
        ).size
        logger.debug("Updated GIBS chlorophyll for spot $spotId: $hasData/10 satellites have data")
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
    
    /**
     * Clear all chlorophyll values from cache and database.
     * Used to remove fake climatology fallback data.
     */
    fun clearAllChlorophyll(): Int {
        var cleared = 0
        cache.forEach { (spotId, data) ->
            if (data.chlorophyll != null) {
                cache[spotId] = data.copy(chlorophyll = null)
                cleared++
            }
        }
        
        // Also clear from database
        try {
            val conn = java.sql.DriverManager.getConnection(
                System.getenv("DATABASE_URL") ?: "",
                System.getenv("PGUSER") ?: "",
                System.getenv("PGPASSWORD") ?: ""
            )
            conn.prepareStatement("UPDATE spot_cache SET chlorophyll_mg_m3 = NULL").executeUpdate()
            conn.close()
            logger.info("Cleared chlorophyll from database")
        } catch (e: Exception) {
            logger.warn("Could not clear chlorophyll from database: ${e.message}")
        }
        
        logger.info("Cleared chlorophyll from $cleared cached spots")
        return cleared
    }
    
    /**
     * Get chlorophyll statistics.
     */
    fun getChlorophyllStats(): Map<String, Any> {
        val total = cache.size
        val withChlorophyll = cache.values.count { it.chlorophyll != null }
        val withoutChlorophyll = total - withChlorophyll
        
        return mapOf(
            "totalSpots" to total,
            "withChlorophyll" to withChlorophyll,
            "withoutChlorophyll" to withoutChlorophyll,
            "percentageWithData" to if (total > 0) "%.1f%%".format(withChlorophyll.toDouble() / total * 100) else "0%"
        )
    }
    
    /**
     * Get chlorophyll stats as JSON string (avoids serialization issues).
     */
    fun getChlorophyllStatsJson(): String {
        val stats = getChlorophyllStats()
        return """{"totalSpots":${stats["totalSpots"]},"withChlorophyll":${stats["withChlorophyll"]},"withoutChlorophyll":${stats["withoutChlorophyll"]},"percentageWithData":"${stats["percentageWithData"]}"}"""
    }
    
    /**
     * Known fake climatology values that were used as fallbacks.
     */
    private val FAKE_CLIMATOLOGY_VALUES = setOf(0.10, 0.15, 0.20, 0.25, 0.30, 0.60, 0.80, 1.20, 1.50, 2.00, 2.50)
    
    /**
     * Identify spots with fake climatology chlorophyll values.
     * Returns list of (spotId, value) pairs where value matches a known fake.
     */
    fun identifyFakeChlorophyll(spotDb: com.shaka.data.client.SpotDatabase): List<Pair<String, Double>> {
        val fakeSpots = mutableListOf<Pair<String, Double>>()
        
        cache.forEach { (spotId, data) ->
            val chlValue = data.chlorophyll?.value
            if (chlValue != null) {
                // Check if value matches a known climatology fallback
                // Use small epsilon for floating point comparison
                val isFake = FAKE_CLIMATOLOGY_VALUES.any { fake -> 
                    kotlin.math.abs(chlValue - fake) < 0.001 
                }
                if (isFake) {
                    fakeSpots.add(spotId to chlValue)
                }
            }
        }
        
        return fakeSpots
    }
    
    /**
     * Clear only fake climatology chlorophyll values.
     * Preserves real Copernicus data.
     */
    fun clearFakeChlorophyll(spotDb: com.shaka.data.client.SpotDatabase): Int {
        val fakeSpots = identifyFakeChlorophyll(spotDb)
        var cleared = 0
        
        for ((spotId, _) in fakeSpots) {
            cache[spotId]?.let { data ->
                cache[spotId] = data.copy(chlorophyll = null)
                cleared++
            }
        }
        
        // Also clear from database
        if (fakeSpots.isNotEmpty()) {
            try {
                val conn = java.sql.DriverManager.getConnection(
                    System.getenv("DATABASE_URL") ?: "",
                    System.getenv("PGUSER") ?: "",
                    System.getenv("PGPASSWORD") ?: ""
                )
                val spotIds = fakeSpots.map { "'${it.first}'" }.joinToString(",")
                conn.prepareStatement("UPDATE spot_cache SET chlorophyll_mg_m3 = NULL WHERE spot_id IN ($spotIds)").executeUpdate()
                conn.close()
                logger.info("Cleared fake chlorophyll from database for ${fakeSpots.size} spots")
            } catch (e: Exception) {
                logger.warn("Could not clear fake chlorophyll from database: ${e.message}")
            }
        }
        
        logger.info("Cleared fake chlorophyll from $cleared cached spots")
        return cleared
    }
    
    /**
     * Get all spot IDs where chlorophyll is null.
     */
    fun getSpotsWithoutChlorophyll(): List<String> {
        return cache.filter { (_, data) -> data.chlorophyll == null }.keys.toList()
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
    
    // ==================== Database Persistence ====================
    
    /**
     * Create the spot_cache table if it doesn't exist.
     * Called on application startup to ensure schema is ready.
     */
    fun createTableIfNotExists() {
        if (!DatabaseFactory.isConnected()) {
            logger.info("Database not connected, skipping table creation")
            return
        }
        
        try {
            transaction {
                val conn = this.connection.connection as java.sql.Connection
                
                val sql = """
                    CREATE TABLE IF NOT EXISTS spot_cache (
                        spot_id VARCHAR(100) PRIMARY KEY,
                        tide_state VARCHAR(20),
                        tide_height_ft DOUBLE PRECISION,
                        tide_next_time TIMESTAMP,
                        tide_fetched_at TIMESTAMP,
                        swell_height_ft DOUBLE PRECISION,
                        swell_period_sec DOUBLE PRECISION,
                        swell_direction VARCHAR(10),
                        wind_speed_kts DOUBLE PRECISION,
                        wind_direction VARCHAR(10),
                        weather_fetched_at TIMESTAMP,
                        visibility_m DOUBLE PRECISION,
                        sst_celsius DOUBLE PRECISION,
                        chlorophyll_mg_m3 DOUBLE PRECISION,
                        satellite_date DATE,
                        satellite_fetched_at TIMESTAMP,
                        updated_at TIMESTAMP DEFAULT NOW()
                    );
                    CREATE INDEX IF NOT EXISTS spot_cache_updated_idx ON spot_cache (updated_at);
                """.trimIndent()
                
                conn.createStatement().use { stmt ->
                    stmt.execute(sql)
                }
                
                // Add GIBS satellite columns (if they don't exist)
                val gibsColumns = """
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_pace_today DOUBLE PRECISION;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_pace_yesterday DOUBLE PRECISION;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_noaa20_today DOUBLE PRECISION;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_noaa20_yesterday DOUBLE PRECISION;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_noaa21_today DOUBLE PRECISION;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_noaa21_yesterday DOUBLE PRECISION;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_sentinel3a_today DOUBLE PRECISION;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_sentinel3a_yesterday DOUBLE PRECISION;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_sentinel3b_today DOUBLE PRECISION;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_sentinel3b_yesterday DOUBLE PRECISION;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_data_date DATE;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_fetched_at TIMESTAMP;
                """.trimIndent()
                
                conn.createStatement().use { stmt ->
                    gibsColumns.split(";").filter { it.isNotBlank() }.forEach { sql ->
                        stmt.execute(sql.trim())
                    }
                }
                
                logger.info("GIBS columns added to spot_cache table")
            }
            logger.info("spot_cache table ready")
        } catch (e: Exception) {
            logger.error("Failed to create spot_cache table: ${e.message}")
        }
    }
    
    /**
     * Save a spot's cached data to the database.
     * Uses UPSERT (INSERT ON CONFLICT UPDATE) for efficiency.
     */
    fun saveToDatabase(spotId: String) {
        if (!DatabaseFactory.isConnected()) {
            logger.debug("Database not connected, skipping persist for $spotId")
            return
        }
        
        val data = cache[spotId] ?: return
        
        try {
            transaction {
                val conn = this.connection.connection as java.sql.Connection
                
                val sql = """
                    INSERT INTO spot_cache (
                        spot_id,
                        tide_state, tide_height_ft, tide_next_time, tide_fetched_at,
                        swell_height_ft, swell_period_sec, swell_direction,
                        wind_speed_kts, wind_direction, weather_fetched_at,
                        visibility_m, sst_celsius, chlorophyll_mg_m3, satellite_date, satellite_fetched_at,
                        gibs_pace_today, gibs_pace_yesterday, gibs_noaa20_today, gibs_noaa20_yesterday,
                        gibs_noaa21_today, gibs_noaa21_yesterday, gibs_sentinel3a_today, gibs_sentinel3a_yesterday,
                        gibs_sentinel3b_today, gibs_sentinel3b_yesterday, gibs_data_date, gibs_fetched_at,
                        updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
                    ON CONFLICT (spot_id) DO UPDATE SET
                        tide_state = COALESCE(EXCLUDED.tide_state, spot_cache.tide_state),
                        tide_height_ft = COALESCE(EXCLUDED.tide_height_ft, spot_cache.tide_height_ft),
                        tide_next_time = COALESCE(EXCLUDED.tide_next_time, spot_cache.tide_next_time),
                        tide_fetched_at = COALESCE(EXCLUDED.tide_fetched_at, spot_cache.tide_fetched_at),
                        swell_height_ft = COALESCE(EXCLUDED.swell_height_ft, spot_cache.swell_height_ft),
                        swell_period_sec = COALESCE(EXCLUDED.swell_period_sec, spot_cache.swell_period_sec),
                        swell_direction = COALESCE(EXCLUDED.swell_direction, spot_cache.swell_direction),
                        wind_speed_kts = COALESCE(EXCLUDED.wind_speed_kts, spot_cache.wind_speed_kts),
                        wind_direction = COALESCE(EXCLUDED.wind_direction, spot_cache.wind_direction),
                        weather_fetched_at = COALESCE(EXCLUDED.weather_fetched_at, spot_cache.weather_fetched_at),
                        visibility_m = COALESCE(EXCLUDED.visibility_m, spot_cache.visibility_m),
                        sst_celsius = COALESCE(EXCLUDED.sst_celsius, spot_cache.sst_celsius),
                        chlorophyll_mg_m3 = COALESCE(EXCLUDED.chlorophyll_mg_m3, spot_cache.chlorophyll_mg_m3),
                        satellite_date = COALESCE(EXCLUDED.satellite_date, spot_cache.satellite_date),
                        satellite_fetched_at = COALESCE(EXCLUDED.satellite_fetched_at, spot_cache.satellite_fetched_at),
                        gibs_pace_today = COALESCE(EXCLUDED.gibs_pace_today, spot_cache.gibs_pace_today),
                        gibs_pace_yesterday = COALESCE(EXCLUDED.gibs_pace_yesterday, spot_cache.gibs_pace_yesterday),
                        gibs_noaa20_today = COALESCE(EXCLUDED.gibs_noaa20_today, spot_cache.gibs_noaa20_today),
                        gibs_noaa20_yesterday = COALESCE(EXCLUDED.gibs_noaa20_yesterday, spot_cache.gibs_noaa20_yesterday),
                        gibs_noaa21_today = COALESCE(EXCLUDED.gibs_noaa21_today, spot_cache.gibs_noaa21_today),
                        gibs_noaa21_yesterday = COALESCE(EXCLUDED.gibs_noaa21_yesterday, spot_cache.gibs_noaa21_yesterday),
                        gibs_sentinel3a_today = COALESCE(EXCLUDED.gibs_sentinel3a_today, spot_cache.gibs_sentinel3a_today),
                        gibs_sentinel3a_yesterday = COALESCE(EXCLUDED.gibs_sentinel3a_yesterday, spot_cache.gibs_sentinel3a_yesterday),
                        gibs_sentinel3b_today = COALESCE(EXCLUDED.gibs_sentinel3b_today, spot_cache.gibs_sentinel3b_today),
                        gibs_sentinel3b_yesterday = COALESCE(EXCLUDED.gibs_sentinel3b_yesterday, spot_cache.gibs_sentinel3b_yesterday),
                        gibs_data_date = COALESCE(EXCLUDED.gibs_data_date, spot_cache.gibs_data_date),
                        gibs_fetched_at = COALESCE(EXCLUDED.gibs_fetched_at, spot_cache.gibs_fetched_at),
                        updated_at = NOW()
                """.trimIndent()
                
                conn.prepareStatement(sql).use { stmt ->
                    stmt.setString(1, spotId)
                    
                    // Tide data
                    stmt.setString(2, data.tide?.value?.state)
                    stmt.setObject(3, data.tide?.value?.currentHeight)
                    stmt.setTimestamp(4, null) // tide_next_time - simplified
                    stmt.setTimestamp(5, data.tide?.fetchedAt?.let { Timestamp.from(it) })
                    
                    // Weather data
                    stmt.setObject(6, data.swell?.value?.heightFt)
                    stmt.setObject(7, data.swell?.value?.periodSec)
                    stmt.setString(8, data.swell?.value?.direction)
                    stmt.setObject(9, data.wind?.value?.speedKnots)
                    stmt.setString(10, data.wind?.value?.direction)
                    stmt.setTimestamp(11, data.swell?.fetchedAt?.let { Timestamp.from(it) })
                    
                    // Satellite data (Copernicus)
                    stmt.setObject(12, data.visibility?.value)
                    stmt.setObject(13, data.sst?.value)
                    stmt.setObject(14, data.chlorophyll?.value)
                    stmt.setObject(15, data.visibility?.dataValidAt?.let { 
                        java.sql.Date.valueOf(it.atZone(java.time.ZoneId.systemDefault()).toLocalDate())
                    })
                    stmt.setTimestamp(16, data.visibility?.fetchedAt?.let { Timestamp.from(it) })
                    
                    // GIBS satellite data
                    val gibs = data.gibsChlorophyll?.value
                    stmt.setObject(17, gibs?.paceToday)
                    stmt.setObject(18, gibs?.paceYesterday)
                    stmt.setObject(19, gibs?.noaa20Today)
                    stmt.setObject(20, gibs?.noaa20Yesterday)
                    stmt.setObject(21, gibs?.noaa21Today)
                    stmt.setObject(22, gibs?.noaa21Yesterday)
                    stmt.setObject(23, gibs?.sentinel3aToday)
                    stmt.setObject(24, gibs?.sentinel3aYesterday)
                    stmt.setObject(25, gibs?.sentinel3bToday)
                    stmt.setObject(26, gibs?.sentinel3bYesterday)
                    stmt.setObject(27, gibs?.dataDate?.let { java.sql.Date.valueOf(it) })
                    stmt.setTimestamp(28, data.gibsChlorophyll?.fetchedAt?.let { Timestamp.from(it) })
                    
                    stmt.executeUpdate()
                }
            }
            logger.debug("Persisted cache for spot $spotId to database")
        } catch (e: Exception) {
            logger.warn("Failed to persist cache for $spotId: ${e.message}")
        }
    }
    
    /**
     * Load all cached data from database into memory.
     * Called on server startup to restore cache state.
     */
    fun loadFromDatabase(): Int {
        if (!DatabaseFactory.isConnected()) {
            logger.info("Database not connected, starting with empty cache")
            return 0
        }
        
        var loadedCount = 0
        
        try {
            transaction {
                val conn = this.connection.connection as java.sql.Connection
                
                val sql = "SELECT * FROM spot_cache"
                
                conn.prepareStatement(sql).use { stmt ->
                    val rs = stmt.executeQuery()
                    
                    while (rs.next()) {
                        val spotId = rs.getString("spot_id")
                        
                        // Build SpotData from database row
                        var spotData = SpotData()
                        
                        // Tide data
                        val tideState = rs.getString("tide_state")
                        val tideHeight = rs.getDouble("tide_height_ft")
                        val tideFetchedAt = rs.getTimestamp("tide_fetched_at")
                        if (tideState != null && tideFetchedAt != null) {
                            spotData = spotData.copy(
                                tide = CachedValue(
                                    value = TideInfo(
                                        state = tideState,
                                        nextHighTide = "Loading...",
                                        nextLowTide = "Loading...",
                                        currentHeight = if (rs.wasNull()) 0.0 else tideHeight
                                    ),
                                    fetchedAt = tideFetchedAt.toInstant()
                                )
                            )
                        }
                        
                        // Weather data
                        val swellHeight = rs.getDouble("swell_height_ft")
                        val swellPeriod = rs.getDouble("swell_period_sec")
                        val swellDir = rs.getString("swell_direction")
                        val weatherFetchedAt = rs.getTimestamp("weather_fetched_at")
                        if (!rs.wasNull() && weatherFetchedAt != null) {
                            spotData = spotData.copy(
                                swell = CachedValue(
                                    value = SwellInfo(
                                        heightFt = swellHeight,
                                        periodSec = swellPeriod,
                                        direction = swellDir ?: "N"
                                    ),
                                    fetchedAt = weatherFetchedAt.toInstant()
                                )
                            )
                        }
                        
                        val windSpeed = rs.getDouble("wind_speed_kts")
                        val windDir = rs.getString("wind_direction")
                        if (!rs.wasNull() && weatherFetchedAt != null) {
                            spotData = spotData.copy(
                                wind = CachedValue(
                                    value = WindInfo(
                                        speedKnots = windSpeed,
                                        direction = windDir ?: "N"
                                    ),
                                    fetchedAt = weatherFetchedAt.toInstant()
                                )
                            )
                        }
                        
                        // Satellite data
                        val visibility = rs.getDouble("visibility_m")
                        val satelliteFetchedAt = rs.getTimestamp("satellite_fetched_at")
                        val satelliteDate = rs.getDate("satellite_date")
                        if (!rs.wasNull() && satelliteFetchedAt != null) {
                            spotData = spotData.copy(
                                visibility = CachedValue(
                                    value = visibility,
                                    fetchedAt = satelliteFetchedAt.toInstant(),
                                    dataValidAt = satelliteDate?.toLocalDate()?.atStartOfDay(java.time.ZoneId.systemDefault())?.toInstant()
                                )
                            )
                        }
                        
                        val sst = rs.getDouble("sst_celsius")
                        if (!rs.wasNull() && satelliteFetchedAt != null) {
                            spotData = spotData.copy(
                                sst = CachedValue(
                                    value = sst,
                                    fetchedAt = satelliteFetchedAt.toInstant()
                                )
                            )
                        }
                        
                        val chlorophyll = rs.getDouble("chlorophyll_mg_m3")
                        if (!rs.wasNull() && satelliteFetchedAt != null) {
                            spotData = spotData.copy(
                                chlorophyll = CachedValue(
                                    value = chlorophyll,
                                    fetchedAt = satelliteFetchedAt.toInstant()
                                )
                            )
                        }
                        
                        // GIBS satellite data
                        val gibsFetchedAt = rs.getTimestamp("gibs_fetched_at")
                        val gibsDataDate = rs.getDate("gibs_data_date")
                        if (gibsFetchedAt != null && gibsDataDate != null) {
                            // Read all GIBS columns - use try/catch in case columns don't exist yet
                            try {
                                val paceToday = rs.getDouble("gibs_pace_today").takeUnless { rs.wasNull() }
                                val paceYesterday = rs.getDouble("gibs_pace_yesterday").takeUnless { rs.wasNull() }
                                val noaa20Today = rs.getDouble("gibs_noaa20_today").takeUnless { rs.wasNull() }
                                val noaa20Yesterday = rs.getDouble("gibs_noaa20_yesterday").takeUnless { rs.wasNull() }
                                val noaa21Today = rs.getDouble("gibs_noaa21_today").takeUnless { rs.wasNull() }
                                val noaa21Yesterday = rs.getDouble("gibs_noaa21_yesterday").takeUnless { rs.wasNull() }
                                val sentinel3aToday = rs.getDouble("gibs_sentinel3a_today").takeUnless { rs.wasNull() }
                                val sentinel3aYesterday = rs.getDouble("gibs_sentinel3a_yesterday").takeUnless { rs.wasNull() }
                                val sentinel3bToday = rs.getDouble("gibs_sentinel3b_today").takeUnless { rs.wasNull() }
                                val sentinel3bYesterday = rs.getDouble("gibs_sentinel3b_yesterday").takeUnless { rs.wasNull() }
                                
                                spotData = spotData.copy(
                                    gibsChlorophyll = CachedValue(
                                        value = GIBSSatelliteData(
                                            paceToday = paceToday,
                                            paceYesterday = paceYesterday,
                                            noaa20Today = noaa20Today,
                                            noaa20Yesterday = noaa20Yesterday,
                                            noaa21Today = noaa21Today,
                                            noaa21Yesterday = noaa21Yesterday,
                                            sentinel3aToday = sentinel3aToday,
                                            sentinel3aYesterday = sentinel3aYesterday,
                                            sentinel3bToday = sentinel3bToday,
                                            sentinel3bYesterday = sentinel3bYesterday,
                                            dataDate = gibsDataDate.toLocalDate()
                                        ),
                                        fetchedAt = gibsFetchedAt.toInstant()
                                    )
                                )
                            } catch (e: Exception) {
                                // GIBS columns may not exist yet
                                logger.debug("Could not load GIBS data for $spotId: ${e.message}")
                            }
                        }
                        
                        // Store in memory cache
                        cache[spotId] = spotData
                        loadedCount++
                    }
                }
            }
            
            logger.info("Loaded $loadedCount spots from database into cache")
        } catch (e: Exception) {
            logger.warn("Failed to load cache from database: ${e.message}")
        }
        
        return loadedCount
    }
    
    /**
     * Check if data for a spot is stale (older than given hours).
     */
    fun isStale(spotId: String, maxAgeHours: Int): Boolean {
        val data = cache[spotId] ?: return true
        val oldest = data.oldestFetch() ?: return true
        return Duration.between(oldest, Instant.now()).toHours() >= maxAgeHours
    }
}
