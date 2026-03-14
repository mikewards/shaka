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
        val stationId: String? = null,  // NOAA station ID if available
        val nextHighTideTime: Instant? = null,  // Actual timestamp for next high tide
        val nextLowTideTime: Instant? = null    // Actual timestamp for next low tide
    )
    
    /**
     * Structured swell/wave information for caching.
     */
    data class SwellInfo(
        val heightFt: Double,           // Raw wave height in feet (from buoy or Open-Meteo)
        val periodSec: Double,          // Wave period in seconds
        val direction: String,          // Cardinal direction (N, NE, E, etc.)
        val swellHeightFt: Double? = null,  // Primary swell height if different
        val source: String = "open-meteo",  // Data source: "open-meteo" or "ndbc-{station_id}"
        val correctedHeightFt: Double? = null,  // Height after exposure attenuation
        val secondaryHeightFt: Double? = null,  // Secondary swell raw height
        val secondaryPeriodSec: Double? = null,  // Secondary swell period
        val secondaryDirection: String? = null,  // Secondary swell cardinal direction
        val secondaryCorrectedHeightFt: Double? = null  // Secondary swell attenuated height
    )

    data class ExposureInfo(
        val bearing: Int,       // Direction of open water (0-360 degrees)
        val width: Int,         // Angular spread of open water arc
        val depthM: Double?,    // Bathymetry depth at spot (positive = underwater depth in meters)
        val landDistances: DoubleArray? = null, // 16 values: km to land per compass direction, -1 = open
        val depthSource: String? = null  // "ncei" or "gebco" — retry if not ncei
    ) {
        companion object {
            const val NUM_DIRECTIONS = 16
            const val OPEN = -1.0
            val DIRECTION_LABELS = arrayOf(
                "n", "nne", "ne", "ene", "e", "ese", "se", "sse",
                "s", "ssw", "sw", "wsw", "w", "wnw", "nw", "nnw"
            )
            val DB_COLUMNS = DIRECTION_LABELS.map { "land_km_$it" }
        }
    }
    
    /**
     * Structured wind information for caching.
     */
    data class WindInfo(
        val speedKnots: Double,         // Wind speed in knots
        val direction: String,          // Cardinal direction
        val gustKnots: Double? = null   // Gust speed if available
    )
    
    /**
     * GIBS satellite imagery colors from all 5 satellites for today and yesterday.
     * 
     * IMPORTANT: These colors are for DISPLAY ONLY - they do NOT represent actual
     * chlorophyll concentrations. Coastal imagery is often contaminated by sediment,
     * kelp, and bottom reflectance. Use NOAA ERDDAP for actual chlorophyll values.
     * 
     * Colors are RGB hex strings "#RRGGBB" from the satellite imagery.
     * Observation times are from NASA CMR granule metadata (only available for NASA satellites).
     */
    data class GIBSSatelliteData(
        // Colors only - no chlorophyll values (those were misleading in coastal areas)
        val paceTodayColor: String?,
        val paceYesterdayColor: String?,
        val noaa20TodayColor: String?,
        val noaa20YesterdayColor: String?,
        val noaa21TodayColor: String?,
        val noaa21YesterdayColor: String?,
        val sentinel3aTodayColor: String?,
        val sentinel3aYesterdayColor: String?,
        val sentinel3bTodayColor: String?,
        val sentinel3bYesterdayColor: String?,
        val dataDate: LocalDate,   // "Today" when this was fetched
        // Observation timestamps from CMR (NASA satellites only)
        val paceObservationTime: Instant? = null,
        val noaa20ObservationTime: Instant? = null,
        val noaa21ObservationTime: Instant? = null
        // Sentinel-3 times not available in NASA CMR (would need ESA API)
    )
    
    /**
     * Cached MPA (Marine Protected Area) info from ProtectedSeas.
     */
    data class MPACacheInfo(
        val siteName: String?,
        val designation: String?,
        val spearfishingStatus: Int,        // 0=Allowed, 1=Prohibited, 2=Restricted, 3=Unknown
        val protectionLevel: Int,           // 1-5 Level of Fishing Protection
        val speciesOfConcern: String?,
        val purpose: String?,
        val detailsUrl: String?,
        val isInsideMPA: Boolean = false    // True if spot is inside MPA boundary (not just nearby)
    )
    
    /**
     * Cached vessel activity from Global Fishing Watch.
     */
    data class VesselInfo(
        val count: Int,                     // Number of fishing vessels nearby
        val radiusNm: Int                   // Search radius in nautical miles
    )
    
    /**
     * Cached solunar (moon/feeding) data.
     */
    data class SolunarInfo(
        val moonPhase: String,              // "waning_gibbous", "full_moon", etc.
        val illumination: Int,              // 0-100 percent
        val majorStart1: String?,           // Major period 1 start time (HH:mm)
        val majorEnd1: String?,             // Major period 1 end time
        val majorStart2: String?,           // Major period 2 start time
        val majorEnd2: String?,             // Major period 2 end time
        val minorStart1: String?,           // Minor period 1 start time
        val minorEnd1: String?,             // Minor period 1 end time
        val minorStart2: String?,           // Minor period 2 start time
        val minorEnd2: String?,             // Minor period 2 end time
        val dayRating: Int? = null          // 0-100 overall day rating
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
        val gibsChlorophyll: CachedValue<GIBSSatelliteData>? = null,  // GIBS satellite data
        val mpa: CachedValue<MPACacheInfo?>? = null,      // MPA data (null value = no specific MPA)
        val vessel: CachedValue<VesselInfo>? = null,      // Vessel activity from Global Fishing Watch
        val solunar: CachedValue<SolunarInfo>? = null,    // Moon phase and feeding periods
        val exposure: ExposureInfo? = null                 // Spot coastal exposure (static, computed once)
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
    
    // Spot coordinate registry for in-memory nearest-SST lookups
    private val spotCoordinates = ConcurrentHashMap<String, Pair<Double, Double>>()
    
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
     * Update SST data for a spot. Pass null to explicitly clear stale data.
     */
    fun updateSST(spotId: String, sst: CachedValue<Double>?) {
        cache.compute(spotId) { _, existing ->
            (existing ?: SpotData()).copy(sst = sst)
        }
        if (sst != null) {
            logger.debug("Updated SST for spot $spotId: ${sst.value}°C")
        } else {
            logger.debug("Cleared SST for spot $spotId (satellite data unavailable)")
            clearSSTFromDatabase(spotId)
        }
    }

    /**
     * Explicitly NULL out sst_celsius in the DB for a spot.
     * Only called when NOAA satellite confirms no data available,
     * because the UPSERT COALESCE prevents saveToDatabase from clearing it.
     */
    private fun clearSSTFromDatabase(spotId: String) {
        if (!DatabaseFactory.isConnected()) return
        try {
            transaction {
                val conn = this.connection.connection as java.sql.Connection
                conn.prepareStatement("UPDATE spot_cache SET sst_celsius = NULL WHERE spot_id = ?").use { stmt ->
                    stmt.setString(1, spotId)
                    stmt.executeUpdate()
                }
            }
        } catch (e: Exception) {
            logger.debug("Could not clear SST from database for $spotId: ${e.message}")
        }
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
        val hasColorData = listOfNotNull(
            data.paceTodayColor, data.paceYesterdayColor,
            data.noaa20TodayColor, data.noaa20YesterdayColor,
            data.noaa21TodayColor, data.noaa21YesterdayColor,
            data.sentinel3aTodayColor, data.sentinel3aYesterdayColor,
            data.sentinel3bTodayColor, data.sentinel3bYesterdayColor
        ).size
        logger.debug("Updated GIBS satellite colors for spot $spotId: $hasColorData/10 satellites have data")
    }
    
    /**
     * Update MPA (Marine Protected Area) data for a spot.
     */
    fun updateMPA(spotId: String, mpaData: CachedValue<MPACacheInfo?>) {
        cache.compute(spotId) { _, existing ->
            (existing ?: SpotData()).copy(mpa = mpaData)
        }
        val siteName = mpaData.value?.siteName ?: "No specific MPA"
        logger.debug("Updated MPA for spot $spotId: $siteName")
    }
    
    /**
     * Update vessel activity data for a spot.
     */
    fun updateVessel(spotId: String, vessel: CachedValue<VesselInfo>) {
        cache.compute(spotId) { _, existing ->
            (existing ?: SpotData()).copy(vessel = vessel)
        }
        logger.debug("Updated vessel for spot $spotId: ${vessel.value.count} vessels within ${vessel.value.radiusNm}nm")
    }
    
    /**
     * Update solunar (moon/feeding) data for a spot.
     */
    fun updateSolunar(spotId: String, solunar: CachedValue<SolunarInfo>) {
        cache.compute(spotId) { _, existing ->
            (existing ?: SpotData()).copy(solunar = solunar)
        }
        logger.debug("Updated solunar for spot $spotId: ${solunar.value.moonPhase} (${solunar.value.illumination}%)")
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
     * Clear all GIBS chlorophyll values from cache and database.
     * Used to force a full refetch with new color data.
     */
    fun clearAllGIBS(): Int {
        var cleared = 0
        cache.forEach { (spotId, data) ->
            if (data.gibsChlorophyll != null) {
                cache[spotId] = data.copy(gibsChlorophyll = null)
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
            conn.prepareStatement("""
                UPDATE spot_cache SET 
                    gibs_pace_today = NULL, gibs_pace_today_color = NULL,
                    gibs_pace_yesterday = NULL, gibs_pace_yesterday_color = NULL,
                    gibs_noaa20_today = NULL, gibs_noaa20_today_color = NULL,
                    gibs_noaa20_yesterday = NULL, gibs_noaa20_yesterday_color = NULL,
                    gibs_noaa21_today = NULL, gibs_noaa21_today_color = NULL,
                    gibs_noaa21_yesterday = NULL, gibs_noaa21_yesterday_color = NULL,
                    gibs_sentinel3a_today = NULL, gibs_sentinel3a_today_color = NULL,
                    gibs_sentinel3a_yesterday = NULL, gibs_sentinel3a_yesterday_color = NULL,
                    gibs_sentinel3b_today = NULL, gibs_sentinel3b_today_color = NULL,
                    gibs_sentinel3b_yesterday = NULL, gibs_sentinel3b_yesterday_color = NULL,
                    gibs_data_date = NULL,
                    gibs_fetched_at = NULL,
                    gibs_pace_obs_time = NULL,
                    gibs_noaa20_obs_time = NULL,
                    gibs_noaa21_obs_time = NULL
            """.trimIndent()).executeUpdate()
            conn.close()
            logger.info("Cleared GIBS data from database")
        } catch (e: Exception) {
            logger.warn("Could not clear GIBS from database: ${e.message}")
        }
        
        logger.info("Cleared GIBS data from $cleared cached spots")
        return cleared
    }
    
    /**
     * Clear all tide data from cache and database.
     * Used to force a full refetch after code changes.
     */
    fun clearAllTides(): Int {
        var cleared = 0
        cache.forEach { (spotId, data) ->
            if (data.tide != null) {
                cache[spotId] = data.copy(tide = null)
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
            conn.prepareStatement("""
                UPDATE spot_cache SET 
                    tide_state = NULL,
                    tide_height_ft = NULL,
                    tide_next_time = NULL,
                    tide_next_high = NULL,
                    tide_next_low = NULL,
                    tide_next_high_time = NULL,
                    tide_next_low_time = NULL,
                    tide_fetched_at = NULL
            """.trimIndent()).executeUpdate()
            conn.close()
            logger.info("Cleared tide data from database")
        } catch (e: Exception) {
            logger.warn("Could not clear tides from database: ${e.message}")
        }
        
        logger.info("Cleared tide data from $cleared cached spots")
        return cleared
    }
    
    /**
     * Get all spots without tide data.
     */
    fun getSpotsWithoutTide(): List<String> {
        return cache.filter { it.value.tide == null }.keys.toList()
    }
    
    /**
     * Clear all weather/swell data from cache and database.
     * Used to force a full refetch after code changes.
     */
    fun clearAllWeather(): Int {
        var cleared = 0
        cache.forEach { (spotId, data) ->
            if (data.swell != null || data.wind != null) {
                cache[spotId] = data.copy(swell = null, wind = null)
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
            conn.prepareStatement("""
                UPDATE spot_cache SET 
                    swell_height_ft = NULL,
                    swell_period_sec = NULL,
                    swell_direction = NULL,
                    wind_speed_kts = NULL,
                    wind_direction = NULL,
                    weather_fetched_at = NULL
            """.trimIndent()).executeUpdate()
            conn.close()
            logger.info("Cleared weather/swell data from database")
        } catch (e: Exception) {
            logger.warn("Could not clear weather from database: ${e.message}")
        }
        
        logger.info("Cleared weather/swell data from $cleared cached spots")
        return cleared
    }
    
    /**
     * Get all spots without weather/swell data.
     */
    fun getSpotsWithoutWeather(): List<String> {
        return cache.filter { it.value.swell == null }.keys.toList()
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
    
    // ============================================
    // BUOY DATA METHODS
    // ============================================
    
    data class BuoyStation(
        val stationId: String,
        val lat: Double,
        val lon: Double,
        val name: String?,
        val network: String = "ndbc",
        val active: Boolean = true
    )
    
    data class BuoyReading(
        val stationId: String,
        val observedAt: java.time.Instant,
        val waveHeightM: Double?,
        val dominantPeriodSec: Double?,
        val meanDirection: Int?,
        val waterTempC: Double? = null
    )
    
    fun saveBuoyStations(stations: List<BuoyStation>) {
        if (!DatabaseFactory.isConnected()) return
        try {
            transaction {
                val conn = this.connection.connection as java.sql.Connection
                val sql = """
                    INSERT INTO buoy_stations (station_id, lat, lon, name, network, active)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT (station_id) DO UPDATE SET
                        lat = EXCLUDED.lat, lon = EXCLUDED.lon,
                        name = EXCLUDED.name, active = EXCLUDED.active
                """.trimIndent()
                conn.prepareStatement(sql).use { stmt ->
                    for (s in stations) {
                        stmt.setString(1, s.stationId)
                        stmt.setDouble(2, s.lat)
                        stmt.setDouble(3, s.lon)
                        stmt.setString(4, s.name)
                        stmt.setString(5, s.network)
                        stmt.setBoolean(6, s.active)
                        stmt.addBatch()
                    }
                    stmt.executeBatch()
                }
            }
            logger.info("Saved ${stations.size} buoy stations to database")
        } catch (e: Exception) {
            logger.error("Failed to save buoy stations: ${e.message}")
        }
    }
    
    fun loadBuoyStations(): List<BuoyStation> {
        if (!DatabaseFactory.isConnected()) return emptyList()
        try {
            return transaction {
                val conn = this.connection.connection as java.sql.Connection
                val results = mutableListOf<BuoyStation>()
                conn.prepareStatement("SELECT station_id, lat, lon, name, network, active FROM buoy_stations WHERE active = true").use { stmt ->
                    stmt.executeQuery().use { rs ->
                        while (rs.next()) {
                            results += BuoyStation(
                                stationId = rs.getString("station_id"),
                                lat = rs.getDouble("lat"),
                                lon = rs.getDouble("lon"),
                                name = rs.getString("name"),
                                network = rs.getString("network") ?: "ndbc",
                                active = rs.getBoolean("active")
                            )
                        }
                    }
                }
                results
            }
        } catch (e: Exception) {
            logger.error("Failed to load buoy stations: ${e.message}")
            return emptyList()
        }
    }
    
    fun saveBuoyReading(reading: BuoyReading) {
        if (!DatabaseFactory.isConnected()) return
        try {
            transaction {
                val conn = this.connection.connection as java.sql.Connection
                conn.prepareStatement("""
                    INSERT INTO buoy_readings (station_id, observed_at, wave_height_m, dominant_period_sec, mean_direction, water_temp_c)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT (station_id, observed_at) DO UPDATE SET
                        wave_height_m = EXCLUDED.wave_height_m,
                        dominant_period_sec = EXCLUDED.dominant_period_sec,
                        mean_direction = EXCLUDED.mean_direction,
                        water_temp_c = EXCLUDED.water_temp_c,
                        fetched_at = NOW()
                """.trimIndent()).use { stmt ->
                    stmt.setString(1, reading.stationId)
                    stmt.setTimestamp(2, java.sql.Timestamp.from(reading.observedAt))
                    stmt.setObject(3, reading.waveHeightM)
                    stmt.setObject(4, reading.dominantPeriodSec)
                    stmt.setObject(5, reading.meanDirection)
                    stmt.setObject(6, reading.waterTempC)
                    stmt.executeUpdate()
                }
            }
        } catch (e: Exception) {
            logger.warn("Failed to save buoy reading for ${reading.stationId}: ${e.message}")
        }
    }
    
    fun getLatestBuoyReading(stationId: String): BuoyReading? {
        if (!DatabaseFactory.isConnected()) return null
        try {
            return transaction {
                val conn = this.connection.connection as java.sql.Connection
                conn.prepareStatement("""
                    SELECT station_id, observed_at, wave_height_m, dominant_period_sec, mean_direction, water_temp_c
                    FROM buoy_readings WHERE station_id = ? ORDER BY observed_at DESC LIMIT 1
                """.trimIndent()).use { stmt ->
                    stmt.setString(1, stationId)
                    stmt.executeQuery().use { rs ->
                        if (rs.next()) BuoyReading(
                            stationId = rs.getString("station_id"),
                            observedAt = rs.getTimestamp("observed_at").toInstant(),
                            waveHeightM = rs.getDouble("wave_height_m").takeIf { !rs.wasNull() },
                            dominantPeriodSec = rs.getDouble("dominant_period_sec").takeIf { !rs.wasNull() },
                            meanDirection = rs.getInt("mean_direction").takeIf { !rs.wasNull() },
                            waterTempC = rs.getDouble("water_temp_c").takeIf { !rs.wasNull() }
                        ) else null
                    }
                }
            }
        } catch (e: Exception) {
            logger.warn("Failed to get buoy reading for $stationId: ${e.message}")
            return null
        }
    }
    
    fun updateSwellSource(spotId: String, source: String) {
        if (!DatabaseFactory.isConnected()) return
        try {
            transaction {
                val conn = this.connection.connection as java.sql.Connection
                conn.prepareStatement("UPDATE spot_cache SET swell_source = ? WHERE spot_id = ?").use { stmt ->
                    stmt.setString(1, source)
                    stmt.setString(2, spotId)
                    stmt.executeUpdate()
                }
            }
        } catch (e: Exception) {
            logger.warn("Failed to update swell source for $spotId: ${e.message}")
        }
    }
    
    fun ensureRowExists(spotId: String) {
        if (!DatabaseFactory.isConnected()) return
        try {
            transaction {
                val conn = this.connection.connection as java.sql.Connection
                conn.prepareStatement("INSERT INTO spot_cache (spot_id) VALUES (?) ON CONFLICT DO NOTHING")
                    .use { stmt ->
                        stmt.setString(1, spotId)
                        stmt.executeUpdate()
                    }
            }
        } catch (e: Exception) {
            logger.debug("ensureRowExists failed for $spotId: ${e.message}")
        }
    }

    fun updateExposure(spotId: String, exposure: ExposureInfo) {
        if (!DatabaseFactory.isConnected()) return
        cache.compute(spotId) { _, existing ->
            (existing ?: SpotData()).copy(exposure = exposure)
        }
        try {
            transaction {
                val conn = this.connection.connection as java.sql.Connection
                conn.prepareStatement("""
                    UPDATE spot_cache SET exposure_bearing = ?, exposure_width = ?, bathymetry_depth_m = ? WHERE spot_id = ?
                """.trimIndent()).use { stmt ->
                    stmt.setInt(1, exposure.bearing)
                    stmt.setInt(2, exposure.width)
                    stmt.setObject(3, exposure.depthM)
                    stmt.setString(4, spotId)
                    stmt.executeUpdate()
                }

                val ld = exposure.landDistances
                if (ld != null && ld.size == 16) {
                    val cols = ExposureInfo.DB_COLUMNS
                    val setClauses = cols.joinToString(", ") { "$it = ?" }
                    conn.prepareStatement("""
                        INSERT INTO spot_exposure (spot_id, ${cols.joinToString()}, depth_m, depth_source, bearing, width)
                        VALUES (?, ${cols.joinToString { "?" }}, ?, ?, ?, ?)
                        ON CONFLICT (spot_id) DO UPDATE SET $setClauses, depth_m = ?, depth_source = ?, bearing = ?, width = ?
                    """.trimIndent()).use { stmt ->
                        var idx = 1
                        stmt.setString(idx++, spotId)
                        for (i in 0 until 16) stmt.setDouble(idx++, ld[i])
                        stmt.setObject(idx++, exposure.depthM)
                        stmt.setString(idx++, exposure.depthSource)
                        stmt.setInt(idx++, exposure.bearing)
                        stmt.setInt(idx++, exposure.width)
                        for (i in 0 until 16) stmt.setDouble(idx++, ld[i])
                        stmt.setObject(idx++, exposure.depthM)
                        stmt.setString(idx++, exposure.depthSource)
                        stmt.setInt(idx++, exposure.bearing)
                        stmt.setInt(idx++, exposure.width)
                        stmt.executeUpdate()
                    }
                }
            }
        } catch (e: Exception) {
            logger.warn("Failed to update exposure for $spotId: ${e.message}")
        }
    }

    fun updateCorrectedSwell(spotId: String, correctedHeightFt: Double?, secondaryHeightFt: Double?, secondaryPeriodSec: Double?, secondaryDirection: String?, secondaryCorrectedHeightFt: Double?) {
        if (!DatabaseFactory.isConnected()) return
        try {
            transaction {
                val conn = this.connection.connection as java.sql.Connection
                conn.prepareStatement("""
                    UPDATE spot_cache SET 
                        swell_corrected_height_ft = ?,
                        secondary_swell_height_ft = ?,
                        secondary_swell_period_sec = ?,
                        secondary_swell_direction = ?,
                        secondary_swell_corrected_height_ft = ?
                    WHERE spot_id = ?
                """.trimIndent()).use { stmt ->
                    stmt.setObject(1, correctedHeightFt)
                    stmt.setObject(2, secondaryHeightFt)
                    stmt.setObject(3, secondaryPeriodSec)
                    stmt.setString(4, secondaryDirection)
                    stmt.setObject(5, secondaryCorrectedHeightFt)
                    stmt.setString(6, spotId)
                    stmt.executeUpdate()
                }
            }
        } catch (e: Exception) {
            logger.warn("Failed to update corrected swell for $spotId: ${e.message}")
        }
    }

    fun deactivateBuoyStations(stationIds: List<String>) {
        if (!DatabaseFactory.isConnected() || stationIds.isEmpty()) return
        try {
            transaction {
                val conn = this.connection.connection as java.sql.Connection
                val placeholders = stationIds.joinToString(",") { "?" }
                conn.prepareStatement("UPDATE buoy_stations SET active = false WHERE station_id IN ($placeholders)").use { stmt ->
                    stationIds.forEachIndexed { i, id -> stmt.setString(i + 1, id) }
                    stmt.executeUpdate()
                }
            }
        } catch (e: Exception) {
            logger.warn("Failed to deactivate buoy stations: ${e.message}")
        }
    }
    
    fun haversineNm(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val R = 3440.065 // Earth radius in nautical miles
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                Math.sin(dLon / 2) * Math.sin(dLon / 2)
        return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    }
    
    @Volatile private var buoyStationsMemCache: List<BuoyStation> = emptyList()
    
    fun ensureBuoyStationsLoaded() {
        if (buoyStationsMemCache.isEmpty()) {
            buoyStationsMemCache = loadBuoyStations()
        }
    }
    
    fun refreshBuoyStationsCache() {
        buoyStationsMemCache = loadBuoyStations()
    }
    
    data class BuoyMatch(
        val station: BuoyStation,
        val reading: BuoyReading,
        val distanceNm: Double
    )

    /**
     * Find the nearest active buoy to a lat/lon within maxNm nautical miles,
     * with a fresh wave reading (< 2 hours old). Returns null if none qualifies.
     *
     * Option D: buoy only overrides when the spot is essentially ON the buoy
     * (< 1.5nm). Open-Meteo is the primary source for everything else.
     * Iterates in distance order so a tide gauge doesn't block a wave buoy.
     */
    fun findNearestBuoyReading(lat: Double, lon: Double, maxNm: Double = 1.5): BuoyMatch? {
        ensureBuoyStationsLoaded()
        
        val candidates = buoyStationsMemCache
            .map { station -> station to haversineNm(lat, lon, station.lat, station.lon) }
            .filter { it.second <= maxNm }
            .sortedBy { it.second }
        
        val now = java.time.Instant.now()
        for ((station, dist) in candidates) {
            val reading = getLatestBuoyReading(station.stationId) ?: continue
            val ageHours = java.time.Duration.between(reading.observedAt, now).toHours()
            if (ageHours > 2) continue
            if (reading.waveHeightM == null) continue
            return BuoyMatch(station, reading, dist)
        }
        
        return null
    }
    
    /**
     * Register coordinates for a spot so findNearestSST can locate it.
     * Called during prefetch when we already have lat/lon.
     */
    fun registerSpotCoordinates(spotId: String, lat: Double, lon: Double) {
        spotCoordinates[spotId] = Pair(lat, lon)
    }

    /**
     * Find SST from the nearest cached spot within maxKm kilometers.
     * Pure in-memory scan -- no DB or network calls. Safe for the read path.
     */
    fun findNearestSST(lat: Double, lon: Double, maxKm: Double = 25.0): Double? {
        val maxNm = maxKm / 1.852
        var bestDist = Double.MAX_VALUE
        var bestSST: Double? = null

        for ((spotId, coords) in spotCoordinates) {
            val cached = cache[spotId] ?: continue
            val sst = cached.sst?.value ?: continue
            val dist = haversineNm(lat, lon, coords.first, coords.second)
            if (dist <= maxNm && dist < bestDist) {
                bestDist = dist
                bestSST = sst
            }
        }

        if (bestSST != null) {
            logger.debug("Found nearby SST ${String.format("%.1f", bestSST)}°C at ${String.format("%.1f", bestDist)}nm")
        }
        return bestSST
    }

    /**
     * Find water temperature from the nearest NDBC buoy within maxNm nautical miles.
     * Involves DB reads per candidate station -- use ONLY in background prefetch, not on read path.
     */
    fun findNearestBuoyWaterTemp(lat: Double, lon: Double, maxNm: Double = 25.0): Double? {
        ensureBuoyStationsLoaded()

        val candidates = buoyStationsMemCache
            .map { station -> station to haversineNm(lat, lon, station.lat, station.lon) }
            .filter { it.second <= maxNm }
            .sortedBy { it.second }

        val now = java.time.Instant.now()
        for ((station, dist) in candidates) {
            val reading = getLatestBuoyReading(station.stationId) ?: continue
            val ageHours = java.time.Duration.between(reading.observedAt, now).toHours()
            if (ageHours > 6) continue
            val temp = reading.waterTempC ?: continue
            if (temp in -2.0..45.0) {
                logger.debug("Found buoy water temp ${String.format("%.1f", temp)}°C from ${station.stationId} at ${String.format("%.1f", dist)}nm")
                return temp
            }
        }

        return null
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
    
    /**
     * Get all spot IDs where GIBS chlorophyll is null OR missing observation times.
     * This ensures spots get refetched to pick up CMR observation timestamps.
     */
    fun getSpotsWithoutGIBS(): List<String> {
        return cache.filter { (_, data) -> 
            data.gibsChlorophyll == null || 
            (data.gibsChlorophyll != null && 
             data.gibsChlorophyll.value.paceObservationTime == null &&
             data.gibsChlorophyll.value.noaa20ObservationTime == null &&
             data.gibsChlorophyll.value.noaa21ObservationTime == null)
        }.keys.toList()
    }
    
    /**
     * Get all spot IDs where MPA data is null (never fetched).
     */
    fun getSpotsWithoutMPA(): List<String> {
        return cache.filter { (_, data) -> data.mpa == null }.keys.toList()
    }
    
    /**
     * Get all spot IDs where MPA data is stale (older than specified hours).
     */
    fun getSpotsWithStaleMPA(staleHours: Long = 168): List<String> {  // 168 hours = 1 week
        val cutoff = Instant.now().minus(staleHours, java.time.temporal.ChronoUnit.HOURS)
        return cache.filter { (_, data) -> 
            data.mpa == null || data.mpa.fetchedAt.isBefore(cutoff)
        }.keys.toList()
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

    /**
     * Directional swell attenuation using per-direction land distances.
     *
     * Interpolates between the two nearest compass directions to find
     * the effective land distance for the swell's arrival direction,
     * then maps distance to an attenuation factor.
     *
     * Only called for Open-Meteo (model) data. When a buoy is within 1.5nm,
     * the buoy reading is used directly without attenuation since it already
     * reflects local conditions.
     *
     * Applies two corrections:
     *  1. Land-blocking attenuation based on directional exposure profile
     *  2. Offshore-to-surf scaling (0.728) — open ocean swell height ≠ breaking
     *     surf height; waves lose energy through shoaling, refraction, and
     *     bottom friction as they approach shore.
     *
     * Parameters calibrated against 4,700+ Surfline spots (2026-03).
     */
    private const val OFFSHORE_TO_SURF_FACTOR = 0.728

    fun attenuateSwell(
        swellHeightFt: Double,
        swellDirectionDeg: Double,
        landDistances: DoubleArray
    ): Double {
        if (landDistances.size != 16) return swellHeightFt * OFFSHORE_TO_SURF_FACTOR
        if (landDistances.all { it < 0 }) return swellHeightFt * OFFSHORE_TO_SURF_FACTOR

        val stepDeg = 360.0 / 16
        val normalizedDir = ((swellDirectionDeg % 360) + 360) % 360
        val exactIndex = normalizedDir / stepDeg
        val lowerIdx = exactIndex.toInt() % 16
        val upperIdx = (lowerIdx + 1) % 16
        val fraction = exactIndex - exactIndex.toInt()

        val lowerFactor = landDistToFactor(landDistances[lowerIdx])
        val upperFactor = landDistToFactor(landDistances[upperIdx])
        val factor = lowerFactor * (1.0 - fraction) + upperFactor * fraction

        return swellHeightFt * factor * OFFSHORE_TO_SURF_FACTOR
    }

    /**
     * Maps land distance (km) to a swell transmission factor [0..1].
     *
     * Calibrated via differential evolution against 4,700+ Surfline spots,
     * validated on a held-out set of 60 spots + deep-dive on O'ahu, Maui,
     * and Santa Cruz (2026-03).
     *
     * -1 (open)  → 1.000  no land detected within 5km
     *  5 km      → 0.950  land far away, mild sheltering
     *  2 km      → 0.706  moderate sheltering
     *  1 km      → 0.492  heavy sheltering (diffraction + wrapping)
     */
    private fun landDistToFactor(distKm: Double): Double {
        if (distKm < 0) return 1.0
        return when {
            distKm <= 1.0 -> 0.492
            distKm <= 2.0 -> 0.492 + 0.214 * ((distKm - 1.0) / 1.0)
            distKm <= 5.0 -> 0.706 + 0.244 * ((distKm - 2.0) / 3.0)
            else -> 0.954
        }
    }
    
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
                
                // Add tide next high/low columns (if they don't exist)
                val tideColumns = """
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS tide_next_high VARCHAR(50);
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS tide_next_low VARCHAR(50);
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS tide_next_high_time TIMESTAMP;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS tide_next_low_time TIMESTAMP;
                """.trimIndent()
                
                conn.createStatement().use { stmt ->
                    tideColumns.split(";").filter { it.isNotBlank() }.forEach { sql ->
                        stmt.execute(sql.trim())
                    }
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
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_pace_obs_time TIMESTAMP;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_noaa20_obs_time TIMESTAMP;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_noaa21_obs_time TIMESTAMP;
                """.trimIndent()
                
                conn.createStatement().use { stmt ->
                    gibsColumns.split(";").filter { it.isNotBlank() }.forEach { sql ->
                        stmt.execute(sql.trim())
                    }
                }
                
                // Add GIBS satellite RGB color columns (hex string "#RRGGBB")
                val gibsColorColumns = """
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_pace_today_color VARCHAR(7);
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_pace_yesterday_color VARCHAR(7);
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_noaa20_today_color VARCHAR(7);
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_noaa20_yesterday_color VARCHAR(7);
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_noaa21_today_color VARCHAR(7);
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_noaa21_yesterday_color VARCHAR(7);
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_sentinel3a_today_color VARCHAR(7);
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_sentinel3a_yesterday_color VARCHAR(7);
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_sentinel3b_today_color VARCHAR(7);
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS gibs_sentinel3b_yesterday_color VARCHAR(7);
                """.trimIndent()
                
                conn.createStatement().use { stmt ->
                    gibsColorColumns.split(";").filter { it.isNotBlank() }.forEach { sql ->
                        stmt.execute(sql.trim())
                    }
                }
                logger.info("GIBS satellite color columns added to spot_cache table")
                
                // Add MPA (Marine Protected Area) columns (if they don't exist)
                val mpaColumns = """
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS mpa_site_name VARCHAR(500);
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS mpa_designation VARCHAR(200);
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS mpa_spearfishing_status INTEGER;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS mpa_protection_level INTEGER;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS mpa_species_of_concern TEXT;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS mpa_purpose TEXT;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS mpa_details_url VARCHAR(500);
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS mpa_fetched_at TIMESTAMP;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS mpa_is_inside BOOLEAN DEFAULT FALSE;
                """.trimIndent()
                
                conn.createStatement().use { stmt ->
                    mpaColumns.split(";").filter { it.isNotBlank() }.forEach { sql ->
                        stmt.execute(sql.trim())
                    }
                }
                
                // Add vessel activity columns (Global Fishing Watch)
                val vesselColumns = """
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS vessel_count INTEGER;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS vessel_radius_nm INTEGER;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS vessel_fetched_at TIMESTAMP;
                """.trimIndent()
                
                conn.createStatement().use { stmt ->
                    vesselColumns.split(";").filter { it.isNotBlank() }.forEach { sql ->
                        stmt.execute(sql.trim())
                    }
                }
                
                // Add solunar (moon/feeding) columns
                val solunarColumns = """
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS solunar_moon_phase VARCHAR(30);
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS solunar_illumination INTEGER;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS solunar_major_start1 VARCHAR(10);
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS solunar_major_end1 VARCHAR(10);
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS solunar_major_start2 VARCHAR(10);
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS solunar_major_end2 VARCHAR(10);
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS solunar_minor_start1 VARCHAR(10);
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS solunar_minor_end1 VARCHAR(10);
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS solunar_minor_start2 VARCHAR(10);
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS solunar_minor_end2 VARCHAR(10);
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS solunar_day_rating INTEGER;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS solunar_fetched_at TIMESTAMP;
                """.trimIndent()
                
                conn.createStatement().use { stmt ->
                    solunarColumns.split(";").filter { it.isNotBlank() }.forEach { sql ->
                        stmt.execute(sql.trim())
                    }
                }
                
                logger.info("Vessel and solunar columns added to spot_cache table")
                
                // Add swell source attribution column
                val swellSourceColumn = """
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS swell_source VARCHAR(50) DEFAULT 'open-meteo';
                """.trimIndent()
                conn.createStatement().use { stmt ->
                    swellSourceColumn.split(";").filter { it.isNotBlank() }.forEach { sql ->
                        stmt.execute(sql.trim())
                    }
                }
                
                // Create buoy stations registry table
                val buoyStationsTable = """
                    CREATE TABLE IF NOT EXISTS buoy_stations (
                        station_id VARCHAR(10) PRIMARY KEY,
                        lat DOUBLE PRECISION NOT NULL,
                        lon DOUBLE PRECISION NOT NULL,
                        name VARCHAR(200),
                        network VARCHAR(20) DEFAULT 'ndbc',
                        active BOOLEAN DEFAULT true
                    );
                """.trimIndent()
                conn.createStatement().use { stmt ->
                    stmt.execute(buoyStationsTable)
                }
                
                // Create buoy readings cache table
                val buoyReadingsTable = """
                    CREATE TABLE IF NOT EXISTS buoy_readings (
                        station_id VARCHAR(10) NOT NULL,
                        observed_at TIMESTAMP NOT NULL,
                        wave_height_m DOUBLE PRECISION,
                        dominant_period_sec DOUBLE PRECISION,
                        mean_direction INTEGER,
                        water_temp_c DOUBLE PRECISION,
                        fetched_at TIMESTAMP DEFAULT NOW(),
                        PRIMARY KEY (station_id, observed_at)
                    );
                    CREATE INDEX IF NOT EXISTS buoy_readings_station_idx ON buoy_readings (station_id, observed_at DESC);
                    ALTER TABLE buoy_readings ADD COLUMN IF NOT EXISTS water_temp_c DOUBLE PRECISION;
                """.trimIndent()
                conn.createStatement().use { stmt ->
                    buoyReadingsTable.split(";").filter { it.isNotBlank() }.forEach { sql ->
                        stmt.execute(sql.trim())
                    }
                }
                logger.info("Buoy tables and swell_source column ready")
                
                // Re-activate ALL buoy stations on every deploy. Previous code
                // permanently deactivated stations on transient failures (timeouts,
                // temporary missing data). This undoes that damage.
                conn.createStatement().use { stmt ->
                    stmt.execute("UPDATE buoy_stations SET active = true")
                }
                logger.info("All buoy stations re-activated")
                
                // Phase 3: Exposure, depth, corrected swell, secondary swell columns
                val phase3Columns = """
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS exposure_bearing INT;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS exposure_width INT;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS bathymetry_depth_m DOUBLE PRECISION;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS swell_corrected_height_ft DOUBLE PRECISION;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS secondary_swell_height_ft DOUBLE PRECISION;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS secondary_swell_period_sec DOUBLE PRECISION;
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS secondary_swell_direction VARCHAR(10);
                    ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS secondary_swell_corrected_height_ft DOUBLE PRECISION;
                """.trimIndent()
                conn.createStatement().use { stmt ->
                    phase3Columns.split(";").filter { it.isNotBlank() }.forEach { sql ->
                        stmt.execute(sql.trim())
                    }
                }
                logger.info("Phase 3 columns (exposure, depth, corrected/secondary swell) ready")

                // One-time migration: recompute exposure with 5km sample distance.
                // Old 1km data stored negative depth values (raw elevation).
                // New code stores positive depth. Detect old data by checking for
                // negative depth values; if found, clear all exposure for recomputation.
                val oldDataCount = conn.prepareStatement(
                    "SELECT COUNT(*) FROM spot_cache WHERE bathymetry_depth_m < 0 AND bathymetry_depth_m IS NOT NULL"
                ).use { stmt ->
                    stmt.executeQuery().use { rs -> if (rs.next()) rs.getInt(1) else 0 }
                }
                if (oldDataCount > 0) {
                    val updated = conn.createStatement().executeUpdate("""
                        UPDATE spot_cache 
                        SET exposure_bearing = NULL, 
                            exposure_width = NULL, 
                            bathymetry_depth_m = NULL,
                            swell_corrected_height_ft = NULL,
                            secondary_swell_corrected_height_ft = NULL
                    """.trimIndent())
                    logger.info("Cleared $updated spots with old 1km exposure data — will recompute with 5km sampling")
                } else {
                    logger.info("Exposure data already uses 5km sampling, no migration needed")
                }
                
                // Schema migration tracking — uses a dedicated table instead of per-row
                // versioning to prevent re-running migrations when new spots are inserted.
                conn.createStatement().use { stmt ->
                    stmt.execute("""
                        CREATE TABLE IF NOT EXISTS schema_migrations (
                            id INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
                            version INT NOT NULL DEFAULT 0
                        )
                    """.trimIndent())
                }
                conn.createStatement().use { stmt ->
                    stmt.execute("INSERT INTO schema_migrations (id, version) VALUES (1, 2) ON CONFLICT DO NOTHING")
                }
                val schemaVersion = conn.prepareStatement(
                    "SELECT version FROM schema_migrations WHERE id = 1"
                ).use { stmt ->
                    stmt.executeQuery().use { rs -> if (rs.next()) rs.getInt(1) else 0 }
                }
                // Keep swell_data_version column (existing rows have it) but stop relying on it
                conn.createStatement().use { stmt ->
                    stmt.execute("ALTER TABLE spot_cache ADD COLUMN IF NOT EXISTS swell_data_version INT DEFAULT 0")
                }

                if (schemaVersion < 1) {
                    val migrated = conn.createStatement().executeUpdate(
                        "UPDATE spot_cache SET weather_fetched_at = NULL, swell_data_version = 1"
                    )
                    conn.createStatement().executeUpdate("UPDATE schema_migrations SET version = 1")
                    logger.info("Option D migration: cleared weather_fetched_at for $migrated spots")
                } else {
                    logger.info("Schema already at version >= 1, skipping Option D migration")
                }

                // Create spot_exposure table for 16-direction land distances
                val cols = ExposureInfo.DB_COLUMNS.joinToString(",\n") { "    $it DOUBLE PRECISION DEFAULT -1" }
                conn.createStatement().use { stmt ->
                    stmt.execute("""
                        CREATE TABLE IF NOT EXISTS spot_exposure (
                            spot_id VARCHAR(100) PRIMARY KEY,
                        $cols,
                            depth_m DOUBLE PRECISION,
                            depth_source VARCHAR(20),
                            bearing INT,
                            width INT,
                            computed_at TIMESTAMP DEFAULT NOW()
                        )
                    """.trimIndent())
                }
                logger.info("spot_exposure table ready")

                if (schemaVersion < 2) {
                    val cleared = conn.createStatement().executeUpdate("""
                        UPDATE spot_cache SET
                            exposure_bearing = NULL,
                            exposure_width = NULL,
                            bathymetry_depth_m = NULL,
                            swell_corrected_height_ft = NULL,
                            secondary_swell_corrected_height_ft = NULL,
                            swell_data_version = 2
                    """.trimIndent())
                    conn.createStatement().executeUpdate("DELETE FROM spot_exposure")
                    conn.createStatement().executeUpdate("UPDATE schema_migrations SET version = 2")
                    logger.info("V2 migration: cleared exposure for $cleared spots")
                } else {
                    logger.info("Schema already at version >= 2, skipping multi-ring migration")
                }

                if (schemaVersion < 3) {
                    val cleared = conn.createStatement().executeUpdate("""
                        UPDATE spot_cache SET
                            bathymetry_depth_m = NULL,
                            swell_data_version = 3
                    """.trimIndent())
                    conn.createStatement().executeUpdate(
                        "UPDATE spot_exposure SET depth_m = NULL"
                    )
                    conn.createStatement().executeUpdate("UPDATE schema_migrations SET version = 3")
                    logger.info("V3 migration: cleared depth for $cleared spots (NCEI DEM_all recomputation)")
                } else {
                    logger.info("Schema already at version >= 3, skipping depth clear migration")
                }

                if (schemaVersion < 4) {
                    conn.createStatement().executeUpdate(
                        "ALTER TABLE spot_exposure ADD COLUMN IF NOT EXISTS depth_source VARCHAR(20)"
                    )
                    conn.createStatement().executeUpdate("UPDATE schema_migrations SET version = 4")
                    logger.info("V4 migration: added depth_source column to spot_exposure")
                } else {
                    logger.info("Schema already at version >= 4, skipping depth source migration")
                }
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
                        gibs_pace_obs_time, gibs_noaa20_obs_time, gibs_noaa21_obs_time,
                        gibs_pace_today_color, gibs_pace_yesterday_color, gibs_noaa20_today_color, gibs_noaa20_yesterday_color,
                        gibs_noaa21_today_color, gibs_noaa21_yesterday_color, gibs_sentinel3a_today_color, gibs_sentinel3a_yesterday_color,
                        gibs_sentinel3b_today_color, gibs_sentinel3b_yesterday_color,
                        tide_next_high, tide_next_low,
                        mpa_site_name, mpa_designation, mpa_spearfishing_status, mpa_protection_level,
                        mpa_species_of_concern, mpa_purpose, mpa_details_url, mpa_fetched_at, mpa_is_inside,
                        vessel_count, vessel_radius_nm, vessel_fetched_at,
                        solunar_moon_phase, solunar_illumination, solunar_major_start1, solunar_major_end1,
                        solunar_major_start2, solunar_major_end2, solunar_minor_start1, solunar_minor_end1,
                        solunar_minor_start2, solunar_minor_end2, solunar_day_rating, solunar_fetched_at,
                        tide_next_high_time, tide_next_low_time,
                        updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
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
                        gibs_pace_obs_time = COALESCE(EXCLUDED.gibs_pace_obs_time, spot_cache.gibs_pace_obs_time),
                        gibs_noaa20_obs_time = COALESCE(EXCLUDED.gibs_noaa20_obs_time, spot_cache.gibs_noaa20_obs_time),
                        gibs_noaa21_obs_time = COALESCE(EXCLUDED.gibs_noaa21_obs_time, spot_cache.gibs_noaa21_obs_time),
                        gibs_pace_today_color = COALESCE(EXCLUDED.gibs_pace_today_color, spot_cache.gibs_pace_today_color),
                        gibs_pace_yesterday_color = COALESCE(EXCLUDED.gibs_pace_yesterday_color, spot_cache.gibs_pace_yesterday_color),
                        gibs_noaa20_today_color = COALESCE(EXCLUDED.gibs_noaa20_today_color, spot_cache.gibs_noaa20_today_color),
                        gibs_noaa20_yesterday_color = COALESCE(EXCLUDED.gibs_noaa20_yesterday_color, spot_cache.gibs_noaa20_yesterday_color),
                        gibs_noaa21_today_color = COALESCE(EXCLUDED.gibs_noaa21_today_color, spot_cache.gibs_noaa21_today_color),
                        gibs_noaa21_yesterday_color = COALESCE(EXCLUDED.gibs_noaa21_yesterday_color, spot_cache.gibs_noaa21_yesterday_color),
                        gibs_sentinel3a_today_color = COALESCE(EXCLUDED.gibs_sentinel3a_today_color, spot_cache.gibs_sentinel3a_today_color),
                        gibs_sentinel3a_yesterday_color = COALESCE(EXCLUDED.gibs_sentinel3a_yesterday_color, spot_cache.gibs_sentinel3a_yesterday_color),
                        gibs_sentinel3b_today_color = COALESCE(EXCLUDED.gibs_sentinel3b_today_color, spot_cache.gibs_sentinel3b_today_color),
                        gibs_sentinel3b_yesterday_color = COALESCE(EXCLUDED.gibs_sentinel3b_yesterday_color, spot_cache.gibs_sentinel3b_yesterday_color),
                        tide_next_high = COALESCE(EXCLUDED.tide_next_high, spot_cache.tide_next_high),
                        tide_next_low = COALESCE(EXCLUDED.tide_next_low, spot_cache.tide_next_low),
                        mpa_site_name = EXCLUDED.mpa_site_name,
                        mpa_designation = EXCLUDED.mpa_designation,
                        mpa_spearfishing_status = EXCLUDED.mpa_spearfishing_status,
                        mpa_protection_level = EXCLUDED.mpa_protection_level,
                        mpa_species_of_concern = EXCLUDED.mpa_species_of_concern,
                        mpa_purpose = EXCLUDED.mpa_purpose,
                        mpa_details_url = EXCLUDED.mpa_details_url,
                        mpa_fetched_at = EXCLUDED.mpa_fetched_at,
                        mpa_is_inside = EXCLUDED.mpa_is_inside,
                        vessel_count = COALESCE(EXCLUDED.vessel_count, spot_cache.vessel_count),
                        vessel_radius_nm = COALESCE(EXCLUDED.vessel_radius_nm, spot_cache.vessel_radius_nm),
                        vessel_fetched_at = COALESCE(EXCLUDED.vessel_fetched_at, spot_cache.vessel_fetched_at),
                        solunar_moon_phase = COALESCE(EXCLUDED.solunar_moon_phase, spot_cache.solunar_moon_phase),
                        solunar_illumination = COALESCE(EXCLUDED.solunar_illumination, spot_cache.solunar_illumination),
                        solunar_major_start1 = COALESCE(EXCLUDED.solunar_major_start1, spot_cache.solunar_major_start1),
                        solunar_major_end1 = COALESCE(EXCLUDED.solunar_major_end1, spot_cache.solunar_major_end1),
                        solunar_major_start2 = COALESCE(EXCLUDED.solunar_major_start2, spot_cache.solunar_major_start2),
                        solunar_major_end2 = COALESCE(EXCLUDED.solunar_major_end2, spot_cache.solunar_major_end2),
                        solunar_minor_start1 = COALESCE(EXCLUDED.solunar_minor_start1, spot_cache.solunar_minor_start1),
                        solunar_minor_end1 = COALESCE(EXCLUDED.solunar_minor_end1, spot_cache.solunar_minor_end1),
                        solunar_minor_start2 = COALESCE(EXCLUDED.solunar_minor_start2, spot_cache.solunar_minor_start2),
                        solunar_minor_end2 = COALESCE(EXCLUDED.solunar_minor_end2, spot_cache.solunar_minor_end2),
                        solunar_day_rating = COALESCE(EXCLUDED.solunar_day_rating, spot_cache.solunar_day_rating),
                        solunar_fetched_at = COALESCE(EXCLUDED.solunar_fetched_at, spot_cache.solunar_fetched_at),
                        tide_next_high_time = COALESCE(EXCLUDED.tide_next_high_time, spot_cache.tide_next_high_time),
                        tide_next_low_time = COALESCE(EXCLUDED.tide_next_low_time, spot_cache.tide_next_low_time),
                        updated_at = NOW()
                """.trimIndent()
                
                conn.prepareStatement(sql).use { stmt ->
                    stmt.setString(1, spotId)
                    
                    // Tide data
                    stmt.setString(2, data.tide?.value?.state)
                    stmt.setObject(3, data.tide?.value?.currentHeight)
                    // Get the soonest upcoming tide time (whichever is next: high or low)
                    val nextTideTime = listOfNotNull(
                        data.tide?.value?.nextHighTideTime,
                        data.tide?.value?.nextLowTideTime
                    ).minOrNull()
                    stmt.setTimestamp(4, nextTideTime?.let { Timestamp.from(it) })
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
                    
                    // GIBS satellite data - Double values removed (were misleading in coastal areas)
                    // We now only store colors for display, and use NOAA ERDDAP for actual chlorophyll
                    val gibs = data.gibsChlorophyll?.value
                    stmt.setObject(17, null)  // gibs_pace_today - deprecated
                    stmt.setObject(18, null)  // gibs_pace_yesterday - deprecated
                    stmt.setObject(19, null)  // gibs_noaa20_today - deprecated
                    stmt.setObject(20, null)  // gibs_noaa20_yesterday - deprecated
                    stmt.setObject(21, null)  // gibs_noaa21_today - deprecated
                    stmt.setObject(22, null)  // gibs_noaa21_yesterday - deprecated
                    stmt.setObject(23, null)  // gibs_sentinel3a_today - deprecated
                    stmt.setObject(24, null)  // gibs_sentinel3a_yesterday - deprecated
                    stmt.setObject(25, null)  // gibs_sentinel3b_today - deprecated
                    stmt.setObject(26, null)  // gibs_sentinel3b_yesterday - deprecated
                    stmt.setObject(27, gibs?.dataDate?.let { java.sql.Date.valueOf(it) })
                    stmt.setTimestamp(28, data.gibsChlorophyll?.fetchedAt?.let { Timestamp.from(it) })
                    
                    // GIBS observation timestamps from CMR
                    stmt.setTimestamp(29, gibs?.paceObservationTime?.let { Timestamp.from(it) })
                    stmt.setTimestamp(30, gibs?.noaa20ObservationTime?.let { Timestamp.from(it) })
                    stmt.setTimestamp(31, gibs?.noaa21ObservationTime?.let { Timestamp.from(it) })
                    
                    // GIBS RGB color hex strings (for display only)
                    stmt.setString(32, gibs?.paceTodayColor)
                    stmt.setString(33, gibs?.paceYesterdayColor)
                    stmt.setString(34, gibs?.noaa20TodayColor)
                    stmt.setString(35, gibs?.noaa20YesterdayColor)
                    stmt.setString(36, gibs?.noaa21TodayColor)
                    stmt.setString(37, gibs?.noaa21YesterdayColor)
                    stmt.setString(38, gibs?.sentinel3aTodayColor)
                    stmt.setString(39, gibs?.sentinel3aYesterdayColor)
                    stmt.setString(40, gibs?.sentinel3bTodayColor)
                    stmt.setString(41, gibs?.sentinel3bYesterdayColor)
                    
                    // Tide next high/low strings
                    stmt.setString(42, data.tide?.value?.nextHighTide)
                    stmt.setString(43, data.tide?.value?.nextLowTide)
                    
                    // MPA data
                    val mpa = data.mpa?.value
                    stmt.setString(44, mpa?.siteName)
                    stmt.setString(45, mpa?.designation)
                    stmt.setObject(46, mpa?.spearfishingStatus)
                    stmt.setObject(47, mpa?.protectionLevel)
                    stmt.setString(48, mpa?.speciesOfConcern)
                    stmt.setString(49, mpa?.purpose)
                    stmt.setString(50, mpa?.detailsUrl)
                    stmt.setTimestamp(51, data.mpa?.fetchedAt?.let { Timestamp.from(it) })
                    stmt.setObject(52, mpa?.isInsideMPA)
                    
                    // Vessel data (Global Fishing Watch)
                    val vessel = data.vessel?.value
                    stmt.setObject(53, vessel?.count)
                    stmt.setObject(54, vessel?.radiusNm)
                    stmt.setTimestamp(55, data.vessel?.fetchedAt?.let { Timestamp.from(it) })
                    
                    // Solunar data
                    val solunar = data.solunar?.value
                    stmt.setString(56, solunar?.moonPhase)
                    stmt.setObject(57, solunar?.illumination)
                    stmt.setString(58, solunar?.majorStart1)
                    stmt.setString(59, solunar?.majorEnd1)
                    stmt.setString(60, solunar?.majorStart2)
                    stmt.setString(61, solunar?.majorEnd2)
                    stmt.setString(62, solunar?.minorStart1)
                    stmt.setString(63, solunar?.minorEnd1)
                    stmt.setString(64, solunar?.minorStart2)
                    stmt.setString(65, solunar?.minorEnd2)
                    stmt.setObject(66, solunar?.dayRating)
                    stmt.setTimestamp(67, data.solunar?.fetchedAt?.let { Timestamp.from(it) })
                    
                    // Tide next high/low timestamps (separate columns for round-trip persistence)
                    stmt.setTimestamp(68, data.tide?.value?.nextHighTideTime?.let { Timestamp.from(it) })
                    stmt.setTimestamp(69, data.tide?.value?.nextLowTideTime?.let { Timestamp.from(it) })
                    
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
                        val tideHeightWasNull = rs.wasNull()
                        val tideNextHigh = rs.getString("tide_next_high")
                        val tideNextLow = rs.getString("tide_next_low")
                        val tideNextHighTime = rs.getTimestamp("tide_next_high_time")
                        val tideNextLowTime = rs.getTimestamp("tide_next_low_time")
                        val tideFetchedAt = rs.getTimestamp("tide_fetched_at")
                        if (tideState != null && tideFetchedAt != null) {
                            spotData = spotData.copy(
                                tide = CachedValue(
                                    value = TideInfo(
                                        state = tideState,
                                        nextHighTide = tideNextHigh ?: "Check local source",
                                        nextLowTide = tideNextLow ?: "Check local source",
                                        currentHeight = if (tideHeightWasNull) 0.0 else tideHeight,
                                        nextHighTideTime = tideNextHighTime?.toInstant(),
                                        nextLowTideTime = tideNextLowTime?.toInstant()
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
                            val swellSource = try { rs.getString("swell_source") } catch (_: Exception) { null }
                            val correctedHt = try { rs.getDouble("swell_corrected_height_ft").takeIf { !rs.wasNull() } } catch (_: Exception) { null }
                            val secHt = try { rs.getDouble("secondary_swell_height_ft").takeIf { !rs.wasNull() } } catch (_: Exception) { null }
                            val secPeriod = try { rs.getDouble("secondary_swell_period_sec").takeIf { !rs.wasNull() } } catch (_: Exception) { null }
                            val secDir = try { rs.getString("secondary_swell_direction") } catch (_: Exception) { null }
                            val secCorrHt = try { rs.getDouble("secondary_swell_corrected_height_ft").takeIf { !rs.wasNull() } } catch (_: Exception) { null }
                            spotData = spotData.copy(
                                swell = CachedValue(
                                    value = SwellInfo(
                                        heightFt = swellHeight,
                                        periodSec = swellPeriod,
                                        direction = swellDir ?: "N",
                                        source = swellSource ?: "open-meteo",
                                        correctedHeightFt = correctedHt,
                                        secondaryHeightFt = secHt,
                                        secondaryPeriodSec = secPeriod,
                                        secondaryDirection = secDir,
                                        secondaryCorrectedHeightFt = secCorrHt
                                    ),
                                    fetchedAt = weatherFetchedAt.toInstant()
                                )
                            )
                        }
                        
                        // Exposure data (static, computed once)
                        val expBearing = try { rs.getInt("exposure_bearing").takeIf { !rs.wasNull() } } catch (_: Exception) { null }
                        val expWidth = try { rs.getInt("exposure_width").takeIf { !rs.wasNull() } } catch (_: Exception) { null }
                        val bathDepth = try { rs.getDouble("bathymetry_depth_m").takeIf { !rs.wasNull() } } catch (_: Exception) { null }
                        if (expBearing != null && expWidth != null) {
                            spotData = spotData.copy(
                                exposure = ExposureInfo(bearing = expBearing, width = expWidth, depthM = bathDepth)
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
                        if (!rs.wasNull()) {
                            spotData = spotData.copy(
                                sst = CachedValue(
                                    value = sst,
                                    fetchedAt = satelliteFetchedAt?.toInstant()
                                        ?: weatherFetchedAt?.toInstant()
                                        ?: Instant.now()
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
                        
                        // GIBS satellite data - now colors only (chlorophyll values deprecated)
                        val gibsFetchedAt = rs.getTimestamp("gibs_fetched_at")
                        val gibsDataDate = rs.getDate("gibs_data_date")
                        if (gibsFetchedAt != null && gibsDataDate != null) {
                            try {
                                // Read observation timestamps (may not exist in older schemas)
                                val paceObsTime = try { rs.getTimestamp("gibs_pace_obs_time")?.toInstant() } catch (e: Exception) { null }
                                val noaa20ObsTime = try { rs.getTimestamp("gibs_noaa20_obs_time")?.toInstant() } catch (e: Exception) { null }
                                val noaa21ObsTime = try { rs.getTimestamp("gibs_noaa21_obs_time")?.toInstant() } catch (e: Exception) { null }
                                
                                // Read RGB color hex strings (for display only)
                                val paceTodayColor = try { rs.getString("gibs_pace_today_color") } catch (e: Exception) { null }
                                val paceYesterdayColor = try { rs.getString("gibs_pace_yesterday_color") } catch (e: Exception) { null }
                                val noaa20TodayColor = try { rs.getString("gibs_noaa20_today_color") } catch (e: Exception) { null }
                                val noaa20YesterdayColor = try { rs.getString("gibs_noaa20_yesterday_color") } catch (e: Exception) { null }
                                val noaa21TodayColor = try { rs.getString("gibs_noaa21_today_color") } catch (e: Exception) { null }
                                val noaa21YesterdayColor = try { rs.getString("gibs_noaa21_yesterday_color") } catch (e: Exception) { null }
                                val sentinel3aTodayColor = try { rs.getString("gibs_sentinel3a_today_color") } catch (e: Exception) { null }
                                val sentinel3aYesterdayColor = try { rs.getString("gibs_sentinel3a_yesterday_color") } catch (e: Exception) { null }
                                val sentinel3bTodayColor = try { rs.getString("gibs_sentinel3b_today_color") } catch (e: Exception) { null }
                                val sentinel3bYesterdayColor = try { rs.getString("gibs_sentinel3b_yesterday_color") } catch (e: Exception) { null }
                                
                                spotData = spotData.copy(
                                    gibsChlorophyll = CachedValue(
                                        value = GIBSSatelliteData(
                                            paceTodayColor = paceTodayColor,
                                            paceYesterdayColor = paceYesterdayColor,
                                            noaa20TodayColor = noaa20TodayColor,
                                            noaa20YesterdayColor = noaa20YesterdayColor,
                                            noaa21TodayColor = noaa21TodayColor,
                                            noaa21YesterdayColor = noaa21YesterdayColor,
                                            sentinel3aTodayColor = sentinel3aTodayColor,
                                            sentinel3aYesterdayColor = sentinel3aYesterdayColor,
                                            sentinel3bTodayColor = sentinel3bTodayColor,
                                            sentinel3bYesterdayColor = sentinel3bYesterdayColor,
                                            dataDate = gibsDataDate.toLocalDate(),
                                            paceObservationTime = paceObsTime,
                                            noaa20ObservationTime = noaa20ObsTime,
                                            noaa21ObservationTime = noaa21ObsTime
                                        ),
                                        fetchedAt = gibsFetchedAt.toInstant()
                                    )
                                )
                            } catch (e: Exception) {
                                // GIBS columns may not exist yet
                                logger.debug("Could not load GIBS data for $spotId: ${e.message}")
                            }
                        }
                        
                        // MPA data
                        try {
                            val mpaFetchedAt = rs.getTimestamp("mpa_fetched_at")
                            if (mpaFetchedAt != null) {
                                val mpaSiteName = rs.getString("mpa_site_name")
                                val mpaDesignation = rs.getString("mpa_designation")
                                val mpaSpearfishingStatus = rs.getInt("mpa_spearfishing_status")
                                val mpaSpearfishingStatusWasNull = rs.wasNull()
                                val mpaProtectionLevel = rs.getInt("mpa_protection_level")
                                val mpaProtectionLevelWasNull = rs.wasNull()
                                val mpaSpeciesOfConcern = rs.getString("mpa_species_of_concern")
                                val mpaPurpose = rs.getString("mpa_purpose")
                                val mpaDetailsUrl = rs.getString("mpa_details_url")
                                val mpaIsInside = try { rs.getBoolean("mpa_is_inside").takeUnless { rs.wasNull() } ?: false } catch (e: Exception) { false }
                                
                                // If spearfishing status was null, it means no specific MPA (just jurisdiction)
                                val mpaInfo = if (!mpaSpearfishingStatusWasNull) {
                                    MPACacheInfo(
                                        siteName = mpaSiteName,
                                        designation = mpaDesignation,
                                        spearfishingStatus = mpaSpearfishingStatus,
                                        protectionLevel = if (mpaProtectionLevelWasNull) 0 else mpaProtectionLevel,
                                        speciesOfConcern = mpaSpeciesOfConcern,
                                        purpose = mpaPurpose,
                                        detailsUrl = mpaDetailsUrl,
                                        isInsideMPA = mpaIsInside
                                    )
                                } else null
                                
                                spotData = spotData.copy(
                                    mpa = CachedValue(
                                        value = mpaInfo,
                                        fetchedAt = mpaFetchedAt.toInstant()
                                    )
                                )
                            }
                        } catch (e: Exception) {
                            // MPA columns may not exist yet
                            logger.debug("Could not load MPA data for $spotId: ${e.message}")
                        }
                        
                        // Vessel data (Global Fishing Watch)
                        try {
                            val vesselFetchedAt = rs.getTimestamp("vessel_fetched_at")
                            if (vesselFetchedAt != null) {
                                val vesselCount = rs.getInt("vessel_count")
                                val vesselCountWasNull = rs.wasNull()
                                val vesselRadiusNm = rs.getInt("vessel_radius_nm")
                                
                                if (!vesselCountWasNull) {
                                    spotData = spotData.copy(
                                        vessel = CachedValue(
                                            value = VesselInfo(
                                                count = vesselCount,
                                                radiusNm = vesselRadiusNm
                                            ),
                                            fetchedAt = vesselFetchedAt.toInstant()
                                        )
                                    )
                                }
                            }
                        } catch (e: Exception) {
                            // Vessel columns may not exist yet
                            logger.debug("Could not load vessel data for $spotId: ${e.message}")
                        }
                        
                        // Solunar data (moon/feeding periods)
                        try {
                            val solunarFetchedAt = rs.getTimestamp("solunar_fetched_at")
                            if (solunarFetchedAt != null) {
                                val moonPhase = rs.getString("solunar_moon_phase")
                                val illumination = rs.getInt("solunar_illumination")
                                val illuminationWasNull = rs.wasNull()
                                
                                if (moonPhase != null && !illuminationWasNull) {
                                    spotData = spotData.copy(
                                        solunar = CachedValue(
                                            value = SolunarInfo(
                                                moonPhase = moonPhase,
                                                illumination = illumination,
                                                majorStart1 = rs.getString("solunar_major_start1"),
                                                majorEnd1 = rs.getString("solunar_major_end1"),
                                                majorStart2 = rs.getString("solunar_major_start2"),
                                                majorEnd2 = rs.getString("solunar_major_end2"),
                                                minorStart1 = rs.getString("solunar_minor_start1"),
                                                minorEnd1 = rs.getString("solunar_minor_end1"),
                                                minorStart2 = rs.getString("solunar_minor_start2"),
                                                minorEnd2 = rs.getString("solunar_minor_end2"),
                                                dayRating = rs.getInt("solunar_day_rating").takeUnless { rs.wasNull() }
                                            ),
                                            fetchedAt = solunarFetchedAt.toInstant()
                                        )
                                    )
                                }
                            }
                        } catch (e: Exception) {
                            // Solunar columns may not exist yet
                            logger.debug("Could not load solunar data for $spotId: ${e.message}")
                        }
                        
                        // Store in memory cache
                        cache[spotId] = spotData
                        loadedCount++
                    }
                }
            }
            
            logger.info("Loaded $loadedCount spots from database into cache")

            // Load directional land distances from spot_exposure table
            try {
                transaction {
                    val expConn = this.connection.connection as java.sql.Connection
                    val cols = ExposureInfo.DB_COLUMNS.joinToString()
                    expConn.prepareStatement("SELECT spot_id, $cols, depth_m, depth_source, bearing, width FROM spot_exposure").use { stmt ->
                        val rs = stmt.executeQuery()
                        var enriched = 0
                        while (rs.next()) {
                            val sid = rs.getString("spot_id")
                            val ld = DoubleArray(16) { i ->
                                rs.getDouble(ExposureInfo.DB_COLUMNS[i]).let { if (rs.wasNull()) ExposureInfo.OPEN else it }
                            }
                            val depth = rs.getDouble("depth_m").takeIf { !rs.wasNull() }
                            val dSource = rs.getString("depth_source")
                            val bearing = rs.getInt("bearing").takeIf { !rs.wasNull() } ?: 0
                            val width = rs.getInt("width").takeIf { !rs.wasNull() } ?: 360
                            cache.compute(sid) { _, existing ->
                                val current = existing ?: SpotData()
                                current.copy(exposure = ExposureInfo(bearing, width, depth, ld, dSource))
                            }
                            enriched++
                        }
                        logger.info("Loaded directional exposure for $enriched spots from spot_exposure table")
                    }
                }
            } catch (e: Exception) {
                logger.debug("spot_exposure table not loaded (may not exist yet): ${e.message}")
            }
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
