package com.shaka.fishing_intel.models

import java.time.Instant

/**
 * Trust tier for data sources.
 * A = Landing first-party (highest trust)
 * B = Aggregator sites (good trust)
 * C = Other sources (lower trust)
 */
enum class TrustTier { A, B, C }

/**
 * Type of fishing report.
 */
enum class ReportType {
    FISH_COUNT,       // Structured fish counts (X fish caught)
    DOCK_TOTAL,       // Landing-level daily totals
    NARRATIVE,        // Free-text story/report
    BAIT,             // Bait availability report
    AUDIO_LINK,       // Link to audio report
    TRIP_ANNOUNCEMENT // Captain announcing upcoming trip/targeting
}

/**
 * Type of claim extracted from a report.
 */
enum class ClaimType {
    CATCH,             // Fish caught (species + count)
    BAIT_AVAILABILITY, // Bait status at a location
    TARGETING,         // What species captain/boat is targeting
    LOCATION_MENTION   // Place name mentioned in narrative
}

/**
 * Type of geotag.
 */
enum class GeoType {
    LANDING_ANCHOR,   // Report originated from this landing
    PLACE_MENTION,    // Place name extracted from text
    REGION_FALLBACK   // Default regional fallback
}

/**
 * Source configuration.
 */
data class SourceConfig(
    val id: String,
    val name: String,
    val baseUrl: String,
    val trustTier: TrustTier,
    val rateLimitRps: Double,
    val regionalReport: String = "so_cal"
)

/**
 * A fishing report from a source.
 */
data class FishingReport(
    val sourceId: String,
    val url: String,
    val publishedAt: Instant?,
    val observedAt: Instant?,
    val reportType: ReportType,
    val title: String?,
    val rawExcerpt: String?,
    val fingerprint: String,
    val confidence: Double = 1.0,
    val threadZone: String? = null,
    val contentType: String? = null,
    val lastActivityAt: Instant? = null,
    val threadUrl: String? = null,
    val tldr: String? = null,
    val isCatchIntel: Boolean? = null,
    val region: String? = null
)

/**
 * A structured claim extracted from a report.
 */
data class FishingClaim(
    val claimType: ClaimType,
    val species: String? = null,
    val countKept: Int? = null,
    val countReleased: Int? = null,
    val baitType: String? = null,
    val baitStatus: String? = null,
    val tripType: String? = null,
    val anglerCount: Int? = null,
    val boatName: String? = null,
    val landingName: String? = null,
    val landingCity: String? = null,
    val notes: String? = null
)

/**
 * A report with its claims.
 */
data class ReportWithClaims(
    val reportId: Int,
    val sourceId: String,
    val url: String,
    val publishedAt: Instant?,
    val observedAt: Instant? = null,
    val reportType: ReportType,
    val title: String?,
    val rawExcerpt: String?,
    val confidence: Double,
    val threadUrl: String? = null,
    val threadZone: String? = null,
    val canonicalFingerprint: String? = null,
    val tldr: String? = null,
    val isCatchIntel: Boolean? = null,
    val lastActivityAt: Instant? = null,
    val claims: List<FishingClaim>
)

/**
 * Parsed fish count (species, kept, released).
 */
data class FishCount(
    val species: String,
    val kept: Int,
    val released: Int
)

/**
 * A SoCal landing with coordinates.
 */
data class Landing(
    val name: String,
    val normalizedName: String,
    val city: String,
    val lat: Double,
    val lon: Double,
    val radiusKm: Int
)

/**
 * A fishing ground/place for geotagging.
 */
data class FishingGround(
    val name: String,
    val lat: Double,
    val lon: Double,
    val radiusKm: Int,
    val aliases: List<String> = emptyList()
)
