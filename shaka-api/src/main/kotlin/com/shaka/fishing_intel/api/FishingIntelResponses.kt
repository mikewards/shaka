package com.shaka.fishing_intel.api

import kotlinx.serialization.Serializable

/**
 * Response models for Fishing Intel API endpoints.
 * These match the Flutter client's expected JSON structure.
 */

@Serializable
data class SpotIntelResponse(
    val spotId: String,
    val highlights: List<IntelHighlightResponse>,
    val speciesSummary: List<SpeciesSummaryResponse>,
    val baitStatus: List<BaitStatusResponse>,
    val sourcesUsed: List<String>,
    val dataFreshness: String,
    val reportCount: Int,
    val timeWindowHours: Int
)

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
