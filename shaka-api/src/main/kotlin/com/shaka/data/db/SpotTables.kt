package com.shaka.data.db

import org.jetbrains.exposed.dao.id.UUIDTable
import org.jetbrains.exposed.sql.Column
import org.jetbrains.exposed.sql.javatime.datetime
import java.time.LocalDateTime
import java.util.UUID

/**
 * Exposed table definition for spots.
 * Maps to the PostgreSQL spots table with PostGIS geography column.
 */
object SpotsTable : UUIDTable("spots") {
    val name: Column<String> = varchar("name", 255)
    val description: Column<String?> = text("description").nullable()
    val latitude: Column<Double> = double("latitude")
    val longitude: Column<Double> = double("longitude")
    val region: Column<String> = varchar("region", 100)
    val country: Column<String> = varchar("country", 100)
    val accessType: Column<String> = varchar("access_type", 50)
    val depthMinM: Column<Double?> = double("depth_min_m").nullable()
    val depthMaxM: Column<Double?> = double("depth_max_m").nullable()
    val difficulty: Column<String?> = varchar("difficulty", 20).nullable()
    val parking: Column<Boolean> = bool("parking").default(false)
    val parkingInfo: Column<String?> = text("parking_info").nullable()
    val permitsRequired: Column<Boolean> = bool("permits_required").default(false)
    val permitInfo: Column<String?> = text("permit_info").nullable()
    val directions: Column<String?> = text("directions").nullable()
    val hazards: Column<String?> = text("hazards").nullable() // Stored as comma-separated
    val targetSpecies: Column<String?> = text("target_species").nullable() // Stored as comma-separated
    val bestMonths: Column<String?> = varchar("best_months", 50).nullable() // Stored as comma-separated
    val imageUrl: Column<String?> = text("image_url").nullable()
    val createdAt: Column<LocalDateTime> = datetime("created_at").default(LocalDateTime.now())
    val updatedAt: Column<LocalDateTime> = datetime("updated_at").default(LocalDateTime.now())
}

/**
 * Community reports table for dive condition reports.
 */
object ReportsTable : UUIDTable("reports") {
    val spotId: Column<UUID?> = uuid("spot_id").references(SpotsTable.id).nullable()
    val reportSource: Column<String> = varchar("source", 100)
    val sourceUrl: Column<String?> = text("source_url").nullable()
    val reportDate: Column<LocalDateTime> = datetime("report_date")
    val visibilityM: Column<Double?> = double("visibility_m").nullable()
    val waterTempC: Column<Double?> = double("water_temp_c").nullable()
    val fishSighted: Column<String?> = text("fish_sighted").nullable() // Comma-separated
    val conditionsNotes: Column<String?> = text("conditions_notes").nullable()
    val createdAt: Column<LocalDateTime> = datetime("created_at").default(LocalDateTime.now())
}

/**
 * User-created custom spots.
 * These spots function identically to regular spots but are private to the device that created them.
 * Each device can save up to 100 custom spots.
 */
object UserSpotsTable : UUIDTable("user_spots") {
    val deviceId: Column<String> = varchar("device_id", 64)
    val name: Column<String> = varchar("name", 255)
    val latitude: Column<Double> = double("latitude")
    val longitude: Column<Double> = double("longitude")
    val region: Column<String> = varchar("region", 100).default("Custom")
    val country: Column<String> = varchar("country", 100).default("Custom")
    val accessType: Column<String> = varchar("access_type", 50).default("shore")
    val createdAt: Column<LocalDateTime> = datetime("created_at").default(LocalDateTime.now())
    val updatedAt: Column<LocalDateTime> = datetime("updated_at").default(LocalDateTime.now())
}
