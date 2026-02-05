package com.shaka.data.db

import com.shaka.data.client.SpotDatabase
import com.shaka.model.Coordinates
import org.jetbrains.exposed.sql.*
import org.jetbrains.exposed.sql.SqlExpressionBuilder.eq
import org.slf4j.LoggerFactory
import java.time.LocalDateTime
import java.util.UUID
import kotlin.math.*

/**
 * Repository for spot data operations using PostgreSQL.
 * Falls back to in-memory SpotDatabase when database is unavailable.
 */
class SpotRepository {

    private val logger = LoggerFactory.getLogger(SpotRepository::class.java)

    /**
     * Data class representing a spot from the database.
     */
    data class SpotRecord(
        val id: UUID,
        val name: String,
        val description: String?,
        val coordinates: Coordinates,
        val region: String,
        val country: String,
        val depthMinM: Double?,
        val depthMaxM: Double?,
        val difficulty: String?,
        val parking: Boolean,
        val parkingInfo: String?,
        val permitsRequired: Boolean,
        val permitInfo: String?,
        val directions: String?,
        val hazards: List<String>,
        val targetSpecies: List<String>,
        val bestMonths: List<Int>,
        val imageUrl: String?
    )

    /**
     * Find spots within a radius of a given point.
     * Uses Haversine formula for distance calculation.
     */
    suspend fun findNearbySpots(lat: Double, lon: Double, radiusKm: Double): List<SpotRecord> {
        return try {
            if (!DatabaseFactory.isConnected()) {
                return fallbackToInMemory(lat, lon, radiusKm)
            }

            DatabaseFactory.dbQuery {
                SpotsTable.selectAll()
                    .map { row -> rowToSpotRecord(row) }
                    .filter { spot ->
                        haversineDistance(lat, lon, spot.coordinates.lat, spot.coordinates.lon) <= radiusKm
                    }
                    .sortedBy { spot ->
                        haversineDistance(lat, lon, spot.coordinates.lat, spot.coordinates.lon)
                    }
            }
        } catch (e: Exception) {
            logger.warn("Database query failed, falling back to in-memory: ${e.message}")
            fallbackToInMemory(lat, lon, radiusKm)
        }
    }

    /**
     * Find a spot by its ID.
     */
    suspend fun findById(id: String): SpotRecord? {
        return try {
            if (!DatabaseFactory.isConnected()) {
                return fallbackFindById(id)
            }

            val uuid = try {
                UUID.fromString(id)
            } catch (e: Exception) {
                // ID might be a string ID from in-memory database
                return fallbackFindById(id)
            }

            DatabaseFactory.dbQuery {
                SpotsTable.selectAll()
                    .where { SpotsTable.id eq uuid }
                    .map { rowToSpotRecord(it) }
                    .firstOrNull()
            }
        } catch (e: Exception) {
            logger.warn("Database query failed, falling back to in-memory: ${e.message}")
            fallbackFindById(id)
        }
    }

    /**
     * Get all spots (with optional limit).
     */
    suspend fun getAllSpots(limit: Int? = null): List<SpotRecord> {
        return try {
            if (!DatabaseFactory.isConnected()) {
                return fallbackGetAll(limit)
            }

            DatabaseFactory.dbQuery {
                val query = SpotsTable.selectAll()
                if (limit != null) {
                    query.limit(limit)
                }
                query.map { rowToSpotRecord(it) }
            }
        } catch (e: Exception) {
            logger.warn("Database query failed, falling back to in-memory: ${e.message}")
            fallbackGetAll(limit)
        }
    }

    /**
     * Find spots by region.
     */
    suspend fun findByRegion(region: String): List<SpotRecord> {
        return try {
            if (!DatabaseFactory.isConnected()) {
                return fallbackByRegion(region)
            }

            DatabaseFactory.dbQuery {
                SpotsTable.selectAll()
                    .where { SpotsTable.region.lowerCase() like "%${region.lowercase()}%" }
                    .map { rowToSpotRecord(it) }
            }
        } catch (e: Exception) {
            logger.warn("Database query failed, falling back to in-memory: ${e.message}")
            fallbackByRegion(region)
        }
    }

    /**
     * Insert a new spot.
     */
    suspend fun insert(spot: SpotRecord): UUID {
        return DatabaseFactory.dbQuery {
            SpotsTable.insertAndGetId {
                it[name] = spot.name
                it[description] = spot.description
                it[latitude] = spot.coordinates.lat
                it[longitude] = spot.coordinates.lon
                it[region] = spot.region
                it[country] = spot.country
                it[accessType] = "shore"  // Legacy field, kept for DB compatibility
                it[depthMinM] = spot.depthMinM
                it[depthMaxM] = spot.depthMaxM
                it[difficulty] = spot.difficulty
                it[parking] = spot.parking
                it[parkingInfo] = spot.parkingInfo
                it[permitsRequired] = spot.permitsRequired
                it[permitInfo] = spot.permitInfo
                it[directions] = spot.directions
                it[hazards] = spot.hazards.joinToString(",")
                it[targetSpecies] = spot.targetSpecies.joinToString(",")
                it[bestMonths] = spot.bestMonths.joinToString(",")
                it[imageUrl] = spot.imageUrl
                it[createdAt] = LocalDateTime.now()
                it[updatedAt] = LocalDateTime.now()
            }.value
        }
    }

    /**
     * Bulk insert spots for migration.
     */
    suspend fun bulkInsert(spots: List<SpotRecord>) {
        DatabaseFactory.dbQuery {
            SpotsTable.batchInsert(spots) { spot ->
                this[SpotsTable.name] = spot.name
                this[SpotsTable.description] = spot.description
                this[SpotsTable.latitude] = spot.coordinates.lat
                this[SpotsTable.longitude] = spot.coordinates.lon
                this[SpotsTable.region] = spot.region
                this[SpotsTable.country] = spot.country
                this[SpotsTable.accessType] = "shore"  // Legacy field, kept for DB compatibility
                this[SpotsTable.depthMinM] = spot.depthMinM
                this[SpotsTable.depthMaxM] = spot.depthMaxM
                this[SpotsTable.difficulty] = spot.difficulty
                this[SpotsTable.parking] = spot.parking
                this[SpotsTable.parkingInfo] = spot.parkingInfo
                this[SpotsTable.permitsRequired] = spot.permitsRequired
                this[SpotsTable.permitInfo] = spot.permitInfo
                this[SpotsTable.directions] = spot.directions
                this[SpotsTable.hazards] = spot.hazards.joinToString(",")
                this[SpotsTable.targetSpecies] = spot.targetSpecies.joinToString(",")
                this[SpotsTable.bestMonths] = spot.bestMonths.joinToString(",")
                this[SpotsTable.imageUrl] = spot.imageUrl
                this[SpotsTable.createdAt] = LocalDateTime.now()
                this[SpotsTable.updatedAt] = LocalDateTime.now()
            }
        }
    }

    /**
     * Count total spots in database.
     */
    suspend fun count(): Long {
        return try {
            if (!DatabaseFactory.isConnected()) {
                return SpotDatabase.getAllSpots().size.toLong()
            }
            DatabaseFactory.dbQuery {
                SpotsTable.selectAll().count()
            }
        } catch (e: Exception) {
            SpotDatabase.getAllSpots().size.toLong()
        }
    }

    // ==========================================
    // Private helper methods
    // ==========================================

    private fun rowToSpotRecord(row: ResultRow): SpotRecord {
        return SpotRecord(
            id = row[SpotsTable.id].value,
            name = row[SpotsTable.name],
            description = row[SpotsTable.description],
            coordinates = Coordinates(row[SpotsTable.latitude], row[SpotsTable.longitude]),
            region = row[SpotsTable.region],
            country = row[SpotsTable.country],
            depthMinM = row[SpotsTable.depthMinM],
            depthMaxM = row[SpotsTable.depthMaxM],
            difficulty = row[SpotsTable.difficulty],
            parking = row[SpotsTable.parking],
            parkingInfo = row[SpotsTable.parkingInfo],
            permitsRequired = row[SpotsTable.permitsRequired],
            permitInfo = row[SpotsTable.permitInfo],
            directions = row[SpotsTable.directions],
            hazards = row[SpotsTable.hazards]?.split(",")?.filter { it.isNotBlank() } ?: emptyList(),
            targetSpecies = row[SpotsTable.targetSpecies]?.split(",")?.filter { it.isNotBlank() } ?: emptyList(),
            bestMonths = row[SpotsTable.bestMonths]?.split(",")?.mapNotNull { it.trim().toIntOrNull() } ?: emptyList(),
            imageUrl = row[SpotsTable.imageUrl]
        )
    }

    private fun haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val R = 6371.0 // Earth radius in km
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = sin(dLat / 2).pow(2) + cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) * sin(dLon / 2).pow(2)
        val c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    // ==========================================
    // Fallback methods using in-memory database
    // ==========================================

    private fun fallbackToInMemory(lat: Double, lon: Double, radiusKm: Double): List<SpotRecord> {
        return SpotDatabase.findNearbySpots(lat, lon, radiusKm).map { inMemoryToRecord(it) }
    }

    private fun fallbackFindById(id: String): SpotRecord? {
        return SpotDatabase.findSpotById(id)?.let { inMemoryToRecord(it) }
    }

    private fun fallbackGetAll(limit: Int?): List<SpotRecord> {
        val spots = SpotDatabase.getAllSpots()
        return (if (limit != null) spots.take(limit) else spots).map { inMemoryToRecord(it) }
    }

    private fun fallbackByRegion(region: String): List<SpotRecord> {
        return SpotDatabase.getAllSpots()
            .filter { it.id.contains(region.lowercase()) || it.name.lowercase().contains(region.lowercase()) }
            .map { inMemoryToRecord(it) }
    }

    private fun inMemoryToRecord(spot: SpotDatabase.SpotRecord): SpotRecord {
        // Extract region and country from ID (e.g., "oahu-sharks-cove" -> region: "hawaii", country: "usa")
        val (region, country) = inferRegionCountry(spot.id)

        return SpotRecord(
            id = UUID.nameUUIDFromBytes(spot.id.toByteArray()),
            name = spot.name,
            description = spot.description,
            coordinates = spot.coordinates,
            region = region,
            country = country,
            depthMinM = spot.depth.toDouble() - 2,
            depthMaxM = spot.depth.toDouble() + 5,
            difficulty = inferDifficulty(spot.depth),
            parking = spot.parking.isNotBlank() && spot.parking.lowercase() != "none",
            parkingInfo = spot.parking,
            permitsRequired = false,
            permitInfo = null,
            directions = spot.directions,
            hazards = emptyList(),
            targetSpecies = spot.commonFish,
            bestMonths = emptyList(),
            imageUrl = spot.imageUrl
        )
    }

    private fun inferRegionCountry(id: String): Pair<String, String> {
        return when {
            id.startsWith("oahu-") || id.startsWith("maui-") || id.startsWith("bigisland-") ||
            id.startsWith("kauai-") || id.startsWith("molokai-") || id.startsWith("lanai-") -> "Hawaii" to "USA"
            id.startsWith("keys-") || id.startsWith("fl-") -> "Florida" to "USA"
            id.startsWith("cali-") -> "California" to "USA"
            id.startsWith("nc-") -> "North Carolina" to "USA"
            id.startsWith("bahamas-") || id.startsWith("andros-") || id.startsWith("exuma-") ||
            id.startsWith("eleuthera-") || id.startsWith("cat-") || id.startsWith("long-") ||
            id.startsWith("rum-") || id.startsWith("salvador-") || id.startsWith("berry-") ||
            id.startsWith("bimini-") || id.startsWith("abaco-") || id.startsWith("nassau-") ||
            id.startsWith("grand-bahama-") || id.startsWith("conception-") || id.startsWith("crooked-") ||
            id.startsWith("acklins-") -> "Bahamas" to "Bahamas"
            id.startsWith("fakarava-") || id.startsWith("rangiroa-") || id.startsWith("moorea-") ||
            id.startsWith("bora-bora-") || id.startsWith("tikehau-") || id.startsWith("manihi-") ||
            id.startsWith("tahiti-") -> "French Polynesia" to "France"
            id.startsWith("sardinia-") || id.startsWith("sicily-") || id.startsWith("italy-") -> "Italy" to "Italy"
            id.startsWith("corsica-") || id.startsWith("france-") -> "France" to "France"
            id.startsWith("spain-") -> "Spain" to "Spain"
            id.startsWith("greece-") -> "Greece" to "Greece"
            id.startsWith("croatia-") -> "Croatia" to "Croatia"
            id.startsWith("turkey-") -> "Turkey" to "Turkey"
            id.startsWith("mexico-") -> "Mexico" to "Mexico"
            id.startsWith("raja-ampat-") || id.startsWith("indo-") -> "Indonesia" to "Indonesia"
            id.startsWith("aus-") -> "Australia" to "Australia"
            id.startsWith("phil-") -> "Philippines" to "Philippines"
            id.startsWith("fiji-") -> "Fiji" to "Fiji"
            id.startsWith("maldives-") -> "Maldives" to "Maldives"
            id.startsWith("egypt-") -> "Red Sea" to "Egypt"
            id.startsWith("sa-") -> "South Africa" to "South Africa"
            id.startsWith("nz-") -> "New Zealand" to "New Zealand"
            id.startsWith("belize-") -> "Belize" to "Belize"
            id.startsWith("pr-") -> "Puerto Rico" to "USA"
            id.startsWith("brazil-") -> "Brazil" to "Brazil"
            id.startsWith("japan-") -> "Japan" to "Japan"
            id.startsWith("moz-") -> "Mozambique" to "Mozambique"
            id.startsWith("tanzania-") -> "Tanzania" to "Tanzania"
            id.startsWith("kenya-") -> "Kenya" to "Kenya"
            id.startsWith("seychelles-") -> "Seychelles" to "Seychelles"
            id.startsWith("mauritius-") -> "Mauritius" to "Mauritius"
            id.startsWith("reunion-") -> "Reunion" to "France"
            id.startsWith("usvi-") -> "US Virgin Islands" to "USA"
            id.startsWith("bvi-") -> "British Virgin Islands" to "UK"
            id.startsWith("cayman-") -> "Cayman Islands" to "UK"
            id.startsWith("jamaica-") -> "Jamaica" to "Jamaica"
            id.startsWith("curacao-") -> "Curacao" to "Netherlands"
            id.startsWith("bonaire-") -> "Bonaire" to "Netherlands"
            id.startsWith("aruba-") -> "Aruba" to "Netherlands"
            id.startsWith("dominican-") -> "Dominican Republic" to "Dominican Republic"
            id.startsWith("st-lucia-") -> "St. Lucia" to "St. Lucia"
            id.startsWith("grenada-") -> "Grenada" to "Grenada"
            id.startsWith("barbados-") -> "Barbados" to "Barbados"
            id.startsWith("trinidad-") -> "Trinidad and Tobago" to "Trinidad and Tobago"
            else -> "Unknown" to "Unknown"
        }
    }

    private fun inferDifficulty(depth: Int): String {
        return when {
            depth > 30 -> "advanced"
            depth > 15 -> "intermediate"
            else -> "beginner"
        }
    }
}
