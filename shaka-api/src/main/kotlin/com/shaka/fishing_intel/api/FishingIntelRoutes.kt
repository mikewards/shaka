package com.shaka.fishing_intel.api

import com.shaka.data.client.SpotDatabase
import com.shaka.fishing_intel.db.FishingIntelDb
import com.shaka.fishing_intel.models.*
import org.slf4j.LoggerFactory
import java.time.Instant
import java.time.format.DateTimeFormatter

/**
 * API handlers for Fishing Intel endpoints.
 * Called from SpotRoutes.kt.
 */
object FishingIntelRoutes {
    private val logger = LoggerFactory.getLogger(FishingIntelRoutes::class.java)
    
    // Source name lookup
    private val sourceNames = mapOf(
        "socal-fish-reports" to "SoCal Fish Reports",
        "san-diego-fish-reports" to "San Diego Fish Reports",
        "976-tuna" to "976-TUNA",
        "22nd-street" to "22nd Street Landing",
        "fishermans-landing" to "Fisherman's Landing",
        "seaforth" to "Seaforth Landing"
    )
    
    /**
     * Get fishing intel for a spot.
     */
    fun getSpotIntel(spotId: String, since: String): SpotIntelResponse? {
        // Get spot coordinates
        val spot = SpotDatabase.findSpotById(spotId) ?: return null
        
        // Parse time window
        val hours = parseTimeWindow(since)
        
        // Get reports near this spot
        val reports = FishingIntelDb.getReportsNearby(
            spot.coordinates.lat,
            spot.coordinates.lon,
            radiusKm = 50,
            hoursBack = hours
        )
        
        if (reports.isEmpty()) return null
        
        // Track sources used
        val sourcesUsed = reports.map { it.sourceId }.distinct().mapNotNull { sourceNames[it] }
        
        // Build highlights from claims (flatten claims into individual highlight cards)
        val highlights = mutableListOf<IntelHighlightResponse>()
        for (report in reports.take(10)) {
            val catchClaims = report.claims.filter { it.claimType == ClaimType.CATCH && it.species != null }
            if (catchClaims.isNotEmpty()) {
                // Group by species within this report
                for (claim in catchClaims) {
                    highlights.add(
                        IntelHighlightResponse(
                            type = "CATCH",
                            species = claim.species ?: "",
                            countKept = claim.countKept,
                            countReleased = claim.countReleased,
                            boatName = claim.boatName,
                            landingName = claim.landingName ?: "Unknown",
                            distanceMi = 0.0, // TODO: Calculate actual distance
                            publishedAt = report.publishedAt?.toString() ?: "",
                            excerpt = report.rawExcerpt ?: "",
                            sourceUrl = report.url,
                            sourceName = sourceNames[report.sourceId] ?: report.sourceId,
                            corroboratedBy = emptyList()
                        )
                    )
                }
            }
        }
        
        // Build species summary
        val speciesCounts = mutableMapOf<String, SpeciesAggregator>()
        for (report in reports) {
            for (claim in report.claims.filter { it.claimType == ClaimType.CATCH && it.species != null }) {
                val species = claim.species!!
                val current = speciesCounts.getOrPut(species) { SpeciesAggregator() }
                current.totalKept += claim.countKept ?: 0
                current.totalReleased += claim.countReleased ?: 0
                current.reportCount++
            }
        }
        
        val speciesSummary = speciesCounts.entries
            .sortedByDescending { it.value.totalKept + it.value.totalReleased }
            .take(10)
            .map { (species, agg) ->
                SpeciesSummaryResponse(
                    species = species,
                    totalKept = agg.totalKept,
                    totalReleased = agg.totalReleased,
                    reportCount = agg.reportCount
                )
            }
        
        // Build bait status (from BAIT reports)
        val baitStatus = reports
            .filter { it.reportType == ReportType.BAIT }
            .flatMap { report ->
                report.claims
                    .filter { it.claimType == ClaimType.BAIT_AVAILABILITY }
                    .map { claim ->
                        BaitStatusResponse(
                            location = claim.landingName ?: "Unknown",
                            baitType = claim.baitType ?: "Live Bait",
                            status = claim.baitStatus ?: "Available",
                            updatedAt = report.publishedAt?.toString() ?: ""
                        )
                    }
            }
        
        return SpotIntelResponse(
            spotId = spotId,
            highlights = highlights.take(5),
            speciesSummary = speciesSummary,
            baitStatus = baitStatus,
            sourcesUsed = sourcesUsed,
            dataFreshness = Instant.now().toString(),
            reportCount = reports.size,
            timeWindowHours = hours
        )
    }
    
    /**
     * Get raw evidence cards for a spot.
     */
    fun getSpotEvidence(spotId: String, species: String?): EvidenceResponse {
        val spot = SpotDatabase.findSpotById(spotId) 
            ?: return EvidenceResponse(
                spotId = spotId,
                species = species,
                evidence = emptyList(),
                count = 0
            )
        
        val reports = FishingIntelDb.getReportsNearby(
            spot.coordinates.lat,
            spot.coordinates.lon,
            radiusKm = 50,
            hoursBack = 168 // 7 days for evidence
        )
        
        val filtered = if (species != null) {
            reports.filter { report ->
                report.claims.any { it.species?.equals(species, ignoreCase = true) == true }
            }
        } else {
            reports
        }
        
        return EvidenceResponse(
            spotId = spotId,
            species = species,
            evidence = filtered.map { report ->
                EvidenceItem(
                    reportId = report.reportId,
                    title = report.title,
                    excerpt = report.rawExcerpt,
                    sourceUrl = report.url,
                    sourceId = report.sourceId,
                    publishedAt = report.publishedAt?.toString(),
                    reportType = report.reportType.name,
                    claims = report.claims.map { claim ->
                        EvidenceClaimResponse(
                            type = claim.claimType.name,
                            species = claim.species,
                            countKept = claim.countKept,
                            countReleased = claim.countReleased,
                            boatName = claim.boatName,
                            landingName = claim.landingName,
                            notes = claim.notes
                        )
                    }
                )
            },
            count = filtered.size
        )
    }
    
    /**
     * Get trending species for SoCal region.
     */
    fun getTrending(hours: Int): TrendingResponse {
        // Get all reports from past N hours across SoCal
        val reports = FishingIntelDb.getReportsNearby(
            33.0, -117.5, // SoCal center
            radiusKm = 200,
            hoursBack = hours
        )
        
        // Count species mentions
        val speciesCounts = mutableMapOf<String, Int>()
        for (report in reports) {
            for (claim in report.claims.filter { it.species != null }) {
                val species = claim.species!!
                speciesCounts[species] = speciesCounts.getOrDefault(species, 0) + 1
            }
        }
        
        val trending = speciesCounts.entries
            .sortedByDescending { it.value }
            .take(10)
            .map { TrendingSpecies(species = it.key, mentions = it.value) }
        
        return TrendingResponse(
            region = "socal",
            timeWindowHours = hours,
            trending = trending,
            totalReports = reports.size
        )
    }
    
    /**
     * Get health status of fishing intel system.
     */
    fun getHealth(): IntelHealthResponse {
        val sourceStats = FishingIntelDb.getSourceStats()
        return IntelHealthResponse(
            status = "ok",
            sources = sourceStats.map { stat ->
                SourceStats(
                    sourceId = stat["sourceId"] as? String ?: "",
                    name = stat["name"] as? String ?: "",
                    enabled = stat["enabled"] as? Boolean ?: false,
                    lastSuccessfulFetch = stat["lastSuccessfulFetch"] as? String,
                    reportCount = stat["reportCount"] as? Int ?: 0,
                    claimCount = stat["claimCount"] as? Int ?: 0
                )
            },
            message = "Fishing intel system operational"
        )
    }
    
    /**
     * Toggle a source on/off.
     */
    fun toggleSource(sourceId: String, enabled: Boolean): ToggleSourceResponse {
        FishingIntelDb.toggleSource(sourceId, enabled)
        return ToggleSourceResponse(
            sourceId = sourceId,
            enabled = enabled,
            message = "Source ${if (enabled) "enabled" else "disabled"}"
        )
    }
    
    private fun parseTimeWindow(since: String): Int {
        return when {
            since.endsWith("h") -> since.dropLast(1).toIntOrNull() ?: 72
            since.endsWith("d") -> (since.dropLast(1).toIntOrNull() ?: 3) * 24
            else -> 72
        }
    }
    
    private class SpeciesAggregator {
        var totalKept: Int = 0
        var totalReleased: Int = 0
        var reportCount: Int = 0
    }
}
