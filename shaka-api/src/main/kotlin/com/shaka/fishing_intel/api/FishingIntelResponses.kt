package com.shaka.fishing_intel.api

import kotlinx.serialization.Serializable

/**
 * Response models for Fishing Intel API endpoints.
 * Designed to get anglers STOKED about what's happening!
 */

@Serializable
data class SpotIntelResponse(
    val spotId: String,
    val headline: HeadlineResponse?,
    @Deprecated("Use speciesWithTrends") val hotSpecies: List<TrendingSpeciesResponse> = emptyList(),
    @Deprecated("Use speciesWithTrends") val coldSpecies: List<TrendingSpeciesResponse> = emptyList(),
    /** Single list sorted by desirability (most to least). Last 48h vs 5-day baseline (×2/5) equivalent. */
    val speciesWithTrends: List<TrendingSpeciesResponse> = emptyList(),
    val recentCatches: List<RecentCatchResponse>,
    val sourcesUsed: List<String>,
    val dataFreshness: String,
    val totalReports: Int,
    val narrativeInsights: List<NarrativeInsight> = emptyList(),
    /** AI-generated key insights (Groq). Hemingway style, uplifting, 2 lines max each. */
    val keyInsights: List<String> = emptyList()
)

@Serializable
data class HeadlineResponse(
    val species: String,
    val message: String,  // e.g., "YELLOWTAIL ARE FIRING!"
    val heatLevel: Int,   // 1-3 (warm, hot, on fire)
    val count24h: Int,
    val topLanding: String?
)

@Serializable
data class TrendingSpeciesResponse(
    val species: String,
    val count24h: Int,              // catches in last 48h (field name kept for API compat)
    val countPrevious: Int,         // total in baseline 5 days (today-2 to today-7)
    val trend: String,              // "UP", "DOWN", "STABLE"
    val percentChange: Int,         // vs (5-day total × 2/5) equivalent 48h
    val topLanding: String?,
    val trendLabel: String? = null,  // "Above average", "Below average", "Average", "New!"
    val avgPerDayPrevious: Double? = null
)

@Serializable
data class RecentCatchResponse(
    val species: String,
    val count: Int,
    val boatName: String?,
    val landingName: String,
    val hoursAgo: Int,
    val sourceName: String
)

@Serializable
data class NarrativeInsight(
    val species: String,
    val location: String,
    val excerpt: String,
    val sourceName: String,
    val threadUrl: String,
    val publishedAt: String,
    val tldr: String = "",
    val threadZone: String? = null
)

// Legacy response types (keep for backwards compat)
@Serializable
data class IntelHighlightResponse(
    val type: String,
    val species: String,
    val countKept: Int? = null,
    val countReleased: Int? = null,
    val boatName: String? = null,
    val landingName: String,
    val distanceMi: Double,
    val publishedAt: String,
    val excerpt: String,
    val sourceUrl: String,
    val sourceName: String,
    val corroboratedBy: List<String> = emptyList()
)

@Serializable
data class SpeciesSummaryResponse(
    val species: String,
    val totalKept: Int,
    val totalReleased: Int,
    val reportCount: Int
)

@Serializable
data class BaitStatusResponse(
    val location: String,
    val baitType: String,
    val status: String,
    val updatedAt: String
)

@Serializable
data class TrendingResponse(
    val region: String,
    val timeWindowHours: Int,
    val trending: List<TrendingSpecies>,
    val totalReports: Int
)

@Serializable
data class TrendingSpecies(
    val species: String,
    val mentions: Int
)

@Serializable
data class IntelHealthResponse(
    val status: String,
    val sources: List<SourceStats>,
    val message: String
)

@Serializable
data class SourceStats(
    val sourceId: String,
    val name: String,
    val enabled: Boolean,
    val lastSuccessfulFetch: String?,
    val reportCount: Int,
    val claimCount: Int
)

@Serializable
data class EvidenceResponse(
    val spotId: String,
    val species: String?,
    val evidence: List<EvidenceItem>,
    val count: Int
)

@Serializable
data class EvidenceItem(
    val reportId: Int,
    val title: String?,
    val excerpt: String?,
    val sourceUrl: String,
    val sourceId: String,
    val publishedAt: String?,
    val reportType: String,
    val claims: List<EvidenceClaimResponse>
)

@Serializable
data class EvidenceClaimResponse(
    val type: String,
    val species: String?,
    val countKept: Int?,
    val countReleased: Int?,
    val boatName: String?,
    val landingName: String?,
    val notes: String?
)

@Serializable
data class ToggleSourceResponse(
    val sourceId: String,
    val enabled: Boolean,
    val message: String
)

/**
 * Request model for ingesting scraped forum posts from local scraper.
 * Optional fields (threadZone, postUrl, postRole, etc.) are region-agnostic; same shape for any BD forum.
 */
@Serializable
data class IngestPostRequest(
    val threadUrl: String,
    val title: String,
    val author: String,
    val date: String,  // ISO-8601 format: "2026-02-06T12:00:00Z"
    val content: String,
    val speciesMentioned: List<String> = emptyList(),
    val speciesCaught: List<String> = emptyList(),
    val locationMentioned: String? = null,
    val forumName: String,
    // Optional normalized fields (all geos)
    val threadZone: String? = null,
    val postUrl: String? = null,
    val postRole: String? = null,
    val contentType: String? = null,
    val replyCount: Int? = null,
    val lastActivityAt: String? = null
)

/**
 * Response model for ingest endpoint.
 */
@Serializable
data class IngestResponse(
    val status: String,
    val saved: Int,
    val skipped: Int,
    val errors: List<String> = emptyList()
)
