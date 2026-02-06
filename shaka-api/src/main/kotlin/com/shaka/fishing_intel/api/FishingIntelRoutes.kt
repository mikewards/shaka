package com.shaka.fishing_intel.api

import com.shaka.data.client.SpotDatabase
import com.shaka.fishing_intel.db.FishingIntelDb
import com.shaka.fishing_intel.models.*
import org.slf4j.LoggerFactory

/**
 * API handlers for Fishing Intel endpoints.
 * Called from SpotRoutes.kt.
 */
object FishingIntelRoutes {
    private val logger = LoggerFactory.getLogger(FishingIntelRoutes::class.java)
    
    /**
     * Get fishing intel for a spot.
     */
    fun getSpotIntel(spotId: String, since: String): Map<String, Any?>? {
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
        
        // Build highlights (top 5 most recent)
        val highlights = reports.take(5).map { report ->
            mapOf(
                "title" to report.title,
                "excerpt" to report.rawExcerpt,
                "sourceUrl" to report.url,
                "publishedAt" to report.publishedAt?.toString(),
                "reportType" to report.reportType.name,
                "claims" to report.claims.map { claim ->
                    mapOf(
                        "type" to claim.claimType.name,
                        "species" to claim.species,
                        "countKept" to claim.countKept,
                        "countReleased" to claim.countReleased,
                        "boatName" to claim.boatName,
                        "landingName" to claim.landingName
                    )
                }
            )
        }
        
        // Build species summary
        val speciesCounts = mutableMapOf<String, SpeciesCount>()
        for (report in reports) {
            for (claim in report.claims.filter { it.claimType == ClaimType.CATCH && it.species != null }) {
                val species = claim.species!!
                val current = speciesCounts.getOrPut(species) { SpeciesCount(species, 0, 0, mutableSetOf(), null) }
                speciesCounts[species] = current.copy(
                    totalKept = current.totalKept + (claim.countKept ?: 0),
                    totalReleased = current.totalReleased + (claim.countReleased ?: 0),
                    sources = current.sources.apply { claim.landingName?.let { add(it) } },
                    lastSeenAt = report.publishedAt ?: current.lastSeenAt
                )
            }
        }
        
        val speciesSummary = speciesCounts.values.sortedByDescending { it.totalKept + it.totalReleased }.take(10)
        
        // Build bait status (from BAIT reports)
        val baitReports = reports.filter { it.reportType == ReportType.BAIT }
        val baitStatus = baitReports.flatMap { report ->
            report.claims.filter { it.claimType == ClaimType.BAIT_AVAILABILITY }.map { claim ->
                mapOf(
                    "baitType" to claim.baitType,
                    "status" to claim.baitStatus,
                    "location" to claim.landingName,
                    "reportedAt" to report.publishedAt?.toString()
                )
            }
        }
        
        return mapOf(
            "spotId" to spotId,
            "highlights" to highlights,
            "species" to speciesSummary.map { 
                mapOf(
                    "species" to it.species,
                    "totalKept" to it.totalKept,
                    "totalReleased" to it.totalReleased,
                    "sources" to it.sources.toList(),
                    "lastSeenAt" to it.lastSeenAt?.toString()
                )
            },
            "bait" to baitStatus,
            "reportCount" to reports.size,
            "timeWindowHours" to hours
        )
    }
    
    /**
     * Get raw evidence cards for a spot.
     */
    fun getSpotEvidence(spotId: String, species: String?): Map<String, Any?> {
        val spot = SpotDatabase.findSpotById(spotId) 
            ?: return mapOf("evidence" to emptyList<Any>(), "error" to "Spot not found")
        
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
        
        return mapOf(
            "spotId" to spotId,
            "species" to species,
            "evidence" to filtered.map { report ->
                mapOf(
                    "reportId" to report.reportId,
                    "title" to report.title,
                    "excerpt" to report.rawExcerpt,
                    "sourceUrl" to report.url,
                    "sourceId" to report.sourceId,
                    "publishedAt" to report.publishedAt?.toString(),
                    "reportType" to report.reportType.name,
                    "claims" to report.claims.map { claim ->
                        mapOf(
                            "type" to claim.claimType.name,
                            "species" to claim.species,
                            "countKept" to claim.countKept,
                            "countReleased" to claim.countReleased,
                            "boatName" to claim.boatName,
                            "landingName" to claim.landingName,
                            "notes" to claim.notes
                        )
                    }
                )
            },
            "count" to filtered.size
        )
    }
    
    /**
     * Get trending species for SoCal region.
     */
    fun getTrending(hours: Int): Map<String, Any> {
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
            .map { mapOf("species" to it.key, "mentions" to it.value) }
        
        return mapOf(
            "region" to "socal",
            "timeWindowHours" to hours,
            "trending" to trending,
            "totalReports" to reports.size
        )
    }
    
    /**
     * Get health status of fishing intel system.
     */
    fun getHealth(): Map<String, Any> {
        val sources = FishingIntelDb.getSourceStats()
        return mapOf(
            "status" to "ok",
            "sources" to sources,
            "message" to "Fishing intel system operational"
        )
    }
    
    /**
     * Toggle a source on/off.
     */
    fun toggleSource(sourceId: String, enabled: Boolean): Map<String, Any> {
        FishingIntelDb.toggleSource(sourceId, enabled)
        return mapOf(
            "sourceId" to sourceId,
            "enabled" to enabled,
            "message" to "Source ${if (enabled) "enabled" else "disabled"}"
        )
    }
    
    private fun parseTimeWindow(since: String): Int {
        return when {
            since.endsWith("h") -> since.dropLast(1).toIntOrNull() ?: 72
            since.endsWith("d") -> (since.dropLast(1).toIntOrNull() ?: 3) * 24
            else -> 72
        }
    }
    
    private data class SpeciesCount(
        val species: String,
        val totalKept: Int,
        val totalReleased: Int,
        val sources: MutableSet<String>,
        val lastSeenAt: java.time.Instant?
    )
}
