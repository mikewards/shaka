package com.shaka.fishing_intel.db

import org.jetbrains.exposed.dao.id.IntIdTable
import org.jetbrains.exposed.sql.Table
import org.jetbrains.exposed.sql.javatime.CurrentDateTime
import org.jetbrains.exposed.sql.javatime.datetime

/**
 * Exposed table definitions for Fishing Intel feature.
 */

object FishingIntelSourcesTable : Table("fishing_intel_sources") {
    val sourceId = varchar("source_id", 50)
    val name = varchar("name", 100)
    val baseUrl = varchar("base_url", 255)
    val trustTier = char("trust_tier")
    val rateLimitRps = decimal("rate_limit_rps", 3, 1)
    val enabled = bool("enabled").default(true)
    val regionalReport = varchar("regional_report", 50).default("so_cal")
    val lastSuccessfulFetch = datetime("last_successful_fetch").nullable()
    val createdAt = datetime("created_at").defaultExpression(CurrentDateTime)
    
    override val primaryKey = PrimaryKey(sourceId)
}

object FishingIntelRawPagesTable : IntIdTable("fishing_intel_raw_pages", "raw_page_id") {
    val sourceId = varchar("source_id", 50).references(FishingIntelSourcesTable.sourceId)
    val url = varchar("url", 512)
    val fetchedAt = datetime("fetched_at").defaultExpression(CurrentDateTime)
    val httpStatus = integer("http_status").nullable()
    val etag = varchar("etag", 255).nullable()
    val lastModified = varchar("last_modified", 255).nullable()
    val htmlBlob = text("html_blob").nullable()
    val sha256 = varchar("sha256", 64).nullable()
}

object FishingIntelReportsTable : IntIdTable("fishing_intel_reports", "report_id") {
    val sourceId = varchar("source_id", 50).references(FishingIntelSourcesTable.sourceId)
    val url = varchar("url", 512)
    val publishedAt = datetime("published_at").nullable()
    val observedAt = datetime("observed_at").nullable()
    val reportType = varchar("report_type", 30)
    val title = varchar("title", 255).nullable()
    val rawExcerpt = text("raw_excerpt").nullable()
    val tldr = text("tldr").nullable()
    val isCatchIntel = bool("is_catch_intel").nullable()
    val canonicalFingerprint = varchar("canonical_fingerprint", 64).nullable()
    val confidence = decimal("confidence", 3, 2).default(java.math.BigDecimal.ONE)
    val threadZone = varchar("thread_zone", 50).nullable()
    val contentType = varchar("content_type", 30).nullable()
    val lastActivityAt = datetime("last_activity_at").nullable()
    val threadUrl = varchar("thread_url", 512).nullable()
    val createdAt = datetime("created_at").defaultExpression(CurrentDateTime)
}

object FishingIntelClaimsTable : IntIdTable("fishing_intel_claims", "claim_id") {
    val reportId = integer("report_id").references(FishingIntelReportsTable.id)
    val claimType = varchar("claim_type", 30)
    val species = varchar("species", 50).nullable()
    val countKept = integer("count_kept").nullable()
    val countReleased = integer("count_released").nullable()
    val baitType = varchar("bait_type", 50).nullable()
    val baitStatus = varchar("bait_status", 50).nullable()
    val tripType = varchar("trip_type", 50).nullable()
    val anglerCount = integer("angler_count").nullable()
    val boatName = varchar("boat_name", 100).nullable()
    val landingName = varchar("landing_name", 100).nullable()
    val landingCity = varchar("landing_city", 100).nullable()
    val notes = text("notes").nullable()
    val createdAt = datetime("created_at").defaultExpression(CurrentDateTime)
}

object FishingIntelLandingsTable : IntIdTable("fishing_intel_landings", "landing_id") {
    val name = varchar("name", 100).uniqueIndex()
    val normalizedName = varchar("normalized_name", 100)
    val city = varchar("city", 100).nullable()
    val latitude = double("latitude")
    val longitude = double("longitude")
    val defaultRadiusKm = integer("default_radius_km").default(25)
}

object FishingIntelReportGeosTable : IntIdTable("fishing_intel_report_geos", "report_geo_id") {
    val reportId = integer("report_id").references(FishingIntelReportsTable.id)
    val latitude = double("latitude")
    val longitude = double("longitude")
    val geoType = varchar("geo_type", 30)
    val radiusM = integer("radius_m").default(25000)
}
