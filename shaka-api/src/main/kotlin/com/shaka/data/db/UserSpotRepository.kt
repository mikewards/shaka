package com.shaka.data.db

import com.shaka.model.Coordinates
import org.jetbrains.exposed.sql.*
import org.jetbrains.exposed.sql.SqlExpressionBuilder.eq
import org.slf4j.LoggerFactory
import java.time.LocalDateTime
import java.util.UUID

/**
 * Repository for user-saved spots.
 * Each device can save custom fishing locations (up to 100 per device).
 */
class UserSpotRepository {

    private val logger = LoggerFactory.getLogger(UserSpotRepository::class.java)

    /**
     * Data class representing a user spot from the database.
     */
    data class UserSpotRecord(
        val id: UUID,
        val deviceId: String,
        val name: String,
        val coordinates: Coordinates,
        val region: String,
        val country: String,
        val createdAt: LocalDateTime
    )

    /**
     * Create a new user spot.
     * 
     * @return The created spot record, or null if limit exceeded
     */
    suspend fun create(
        deviceId: String,
        name: String,
        latitude: Double,
        longitude: Double,
        region: String,
        country: String
    ): UserSpotRecord? {
        return try {
            if (!DatabaseFactory.isConnected()) {
                logger.warn("Database not connected, cannot create user spot")
                return null
            }

            DatabaseFactory.dbQuery {
                // Check limit (100 per device)
                val count = UserSpotsTable.selectAll()
                    .where { UserSpotsTable.deviceId eq deviceId }
                    .count()
                
                if (count >= 100) {
                    logger.warn("Device $deviceId has reached 100 spot limit")
                    return@dbQuery null
                }

                val now = LocalDateTime.now()
                val id = UserSpotsTable.insertAndGetId {
                    it[UserSpotsTable.deviceId] = deviceId
                    it[UserSpotsTable.name] = name
                    it[UserSpotsTable.latitude] = latitude
                    it[UserSpotsTable.longitude] = longitude
                    it[UserSpotsTable.region] = region
                    it[UserSpotsTable.country] = country
                    it[UserSpotsTable.accessType] = "shore"  // Legacy field, kept for DB compatibility
                    it[UserSpotsTable.createdAt] = now
                }.value

                UserSpotRecord(
                    id = id,
                    deviceId = deviceId,
                    name = name,
                    coordinates = Coordinates(latitude, longitude),
                    region = region,
                    country = country,
                    createdAt = now
                )
            }
        } catch (e: Exception) {
            logger.error("Failed to create user spot: ${e.message}")
            null
        }
    }

    /**
     * Get all user spots for a device.
     */
    suspend fun findByDeviceId(deviceId: String): List<UserSpotRecord> {
        return try {
            if (!DatabaseFactory.isConnected()) {
                return emptyList()
            }

            DatabaseFactory.dbQuery {
                UserSpotsTable.selectAll()
                    .where { UserSpotsTable.deviceId eq deviceId }
                    .orderBy(UserSpotsTable.createdAt, SortOrder.DESC)
                    .map { rowToRecord(it) }
            }
        } catch (e: Exception) {
            logger.warn("Failed to find user spots for device: ${e.message}")
            emptyList()
        }
    }

    /**
     * Find a user spot by ID only (no device ownership check).
     * Used for coordinate lookups where access control isn't needed (e.g. forecasts).
     */
    suspend fun findById(spotId: String): UserSpotRecord? {
        return try {
            if (!DatabaseFactory.isConnected()) return null

            val uuid = try {
                UUID.fromString(spotId)
            } catch (e: Exception) {
                return null
            }

            DatabaseFactory.dbQuery {
                UserSpotsTable.selectAll()
                    .where { UserSpotsTable.id eq uuid }
                    .map { rowToRecord(it) }
                    .firstOrNull()
            }
        } catch (e: Exception) {
            logger.warn("Failed to find user spot by ID: ${e.message}")
            null
        }
    }

    /**
     * Find a user spot by ID and device ID.
     * Device ID check ensures users can only access their own spots.
     */
    suspend fun findByIdAndDevice(spotId: String, deviceId: String): UserSpotRecord? {
        return try {
            if (!DatabaseFactory.isConnected()) {
                return null
            }

            val uuid = try {
                UUID.fromString(spotId)
            } catch (e: Exception) {
                logger.debug("Invalid UUID: $spotId")
                return null
            }

            DatabaseFactory.dbQuery {
                UserSpotsTable.selectAll()
                    .where { 
                        (UserSpotsTable.id eq uuid) and 
                        (UserSpotsTable.deviceId eq deviceId) 
                    }
                    .map { rowToRecord(it) }
                    .firstOrNull()
            }
        } catch (e: Exception) {
            logger.warn("Failed to find user spot by ID: ${e.message}")
            null
        }
    }

    /**
     * Delete a user spot by ID and device ID.
     * Device ID check ensures users can only delete their own spots.
     * 
     * @return true if deleted, false if not found or error
     */
    suspend fun delete(spotId: String, deviceId: String): Boolean {
        return try {
            if (!DatabaseFactory.isConnected()) {
                return false
            }

            val uuid = try {
                UUID.fromString(spotId)
            } catch (e: Exception) {
                logger.debug("Invalid UUID: $spotId")
                return false
            }

            DatabaseFactory.dbQuery {
                val deleted = UserSpotsTable.deleteWhere { 
                    (UserSpotsTable.id eq uuid) and 
                    (UserSpotsTable.deviceId eq deviceId) 
                }
                deleted > 0
            }
        } catch (e: Exception) {
            logger.warn("Failed to delete user spot: ${e.message}")
            false
        }
    }

    /**
     * Search user spots by name for a device.
     */
    suspend fun searchByName(deviceId: String, query: String, limit: Int = 20): List<UserSpotRecord> {
        return try {
            if (!DatabaseFactory.isConnected()) {
                return emptyList()
            }

            DatabaseFactory.dbQuery {
                UserSpotsTable.selectAll()
                    .where { 
                        (UserSpotsTable.deviceId eq deviceId) and 
                        (UserSpotsTable.name.lowerCase() like "%${query.lowercase()}%")
                    }
                    .limit(limit)
                    .orderBy(UserSpotsTable.name, SortOrder.ASC)
                    .map { rowToRecord(it) }
            }
        } catch (e: Exception) {
            logger.warn("Failed to search user spots: ${e.message}")
            emptyList()
        }
    }

    /**
     * Count user spots for a device.
     */
    suspend fun countByDevice(deviceId: String): Long {
        return try {
            if (!DatabaseFactory.isConnected()) {
                return 0
            }

            DatabaseFactory.dbQuery {
                UserSpotsTable.selectAll()
                    .where { UserSpotsTable.deviceId eq deviceId }
                    .count()
            }
        } catch (e: Exception) {
            logger.warn("Failed to count user spots: ${e.message}")
            0
        }
    }

    /**
     * Generate a cache ID for user spots (prefixed with "user-" to avoid collisions).
     */
    fun getCacheId(spotId: String): String = "user-$spotId"

    private fun rowToRecord(row: ResultRow): UserSpotRecord {
        return UserSpotRecord(
            id = row[UserSpotsTable.id].value,
            deviceId = row[UserSpotsTable.deviceId],
            name = row[UserSpotsTable.name],
            coordinates = Coordinates(
                row[UserSpotsTable.latitude],
                row[UserSpotsTable.longitude]
            ),
            region = row[UserSpotsTable.region],
            country = row[UserSpotsTable.country],
            createdAt = row[UserSpotsTable.createdAt]
        )
    }

    companion object {
        private val companionLogger = LoggerFactory.getLogger(UserSpotRepository::class.java)
        
        /**
         * Get ALL user spots across all devices (for prefetch jobs).
         * This is a static method for use by DataPrefetchJobs.
         */
        suspend fun getAllUserSpots(): List<UserSpotRecord> {
            return try {
                if (!DatabaseFactory.isConnected()) {
                    return emptyList()
                }

                DatabaseFactory.dbQuery {
                    UserSpotsTable.selectAll()
                        .map { row ->
                            UserSpotRecord(
                                id = row[UserSpotsTable.id].value,
                                deviceId = row[UserSpotsTable.deviceId],
                                name = row[UserSpotsTable.name],
                                coordinates = Coordinates(
                                    row[UserSpotsTable.latitude],
                                    row[UserSpotsTable.longitude]
                                ),
                                region = row[UserSpotsTable.region],
                                country = row[UserSpotsTable.country],
                                createdAt = row[UserSpotsTable.createdAt]
                            )
                        }
                }
            } catch (e: Exception) {
                companionLogger.warn("Failed to get all user spots: ${e.message}")
                emptyList()
            }
        }
        
        /**
         * Infer region and country from coordinates.
         * Used when creating user spots to assign them to a region.
         */
        fun inferRegionAndCountry(lat: Double, lon: Double): Pair<String, String> {
            return when {
                // Hawaii
                lat in 18.0..23.0 && lon in -161.0..-154.0 -> "Hawaii" to "USA"
                // Bahamas - must precede the Florida boxes (which extend to lon -79)
                // so Bimini (lon ~-79.3) resolves to Bahamas. Western edge -79.6
                // approximates the US/Bahamas boundary in the Straits of Florida,
                // keeping nearshore Florida Atlantic spots (coast at lon -80.0
                // to -80.2) mapped to Florida.
                lat in 20.0..28.0 && lon in -79.6..-72.0 -> "Bahamas" to "Bahamas"
                // Florida Keys
                lat in 24.0..26.0 && lon in -82.0..-79.0 -> "Florida" to "USA"
                // Florida (general)
                lat in 24.0..31.0 && lon in -88.0..-79.0 -> "Florida" to "USA"
                // California
                lat in 32.0..42.0 && lon in -125.0..-114.0 -> "California" to "USA"
                // Mexican Caribbean (Cancun/Cozumel/Riviera Maya) - must precede the
                // generic Caribbean box, which otherwise swallows it
                lat in 19.0..22.0 && lon in -88.0..-85.5 -> "Mexico" to "Mexico"
                // Caribbean general
                lat in 10.0..25.0 && lon in -90.0..-59.0 -> "Caribbean" to "Caribbean"
                // Mediterranean
                lat in 30.0..46.0 && lon in -6.0..36.0 -> "Mediterranean" to "Europe"
                // French Polynesia
                lat in -23.0..-7.0 && lon in -155.0..-134.0 -> "French Polynesia" to "France"
                // Australia
                lat in -44.0..-10.0 && lon in 110.0..155.0 -> "Australia" to "Australia"
                // Indonesia
                lat in -11.0..6.0 && lon in 95.0..141.0 -> "Indonesia" to "Indonesia"
                // Mexico (Pacific side)
                lat in 14.0..32.0 && lon in -118.0..-86.0 -> "Mexico" to "Mexico"
                // Default
                else -> "Unknown" to "Unknown"
            }
        }
    }
}
