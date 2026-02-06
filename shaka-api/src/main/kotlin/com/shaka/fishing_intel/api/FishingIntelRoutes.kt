package com.shaka.fishing_intel.api

import com.shaka.data.client.SpotDatabase
import com.shaka.fishing_intel.db.FishingIntelDb
import com.shaka.fishing_intel.models.*
import org.slf4j.LoggerFactory
import java.time.Instant
import java.time.Duration

/**
 * API handlers for Fishing Intel endpoints.
 * Designed to get anglers STOKED!
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
    
    // Headlines for hot species
    private val fireMessages = listOf(
        "%s ARE FIRING!",
        "%s ARE ON FIRE!",
        "%s BITE IS HOT!",
        "THE %s BITE IS ON!"
    )
    
    /**
     * Get fishing intel for a spot - with TRENDS!
     */
    fun getSpotIntel(spotId: String, since: String): SpotIntelResponse? {
        val spot = SpotDatabase.findSpotById(spotId) ?: return null
        
        // Get reports from last 72h to calculate trends
        // Use 150km radius to include offshore long-range reports for all SoCal spots
        val allReports = FishingIntelDb.getReportsNearby(
            spot.coordinates.lat,
            spot.coordinates.lon,
            radiusKm = 150,
            hoursBack = 72
        )
        
        if (allReports.isEmpty()) return null
        
        val now = Instant.now()
        val twentyFourHoursAgo = now.minus(Duration.ofHours(24))
        
        // Split into recent (24h) and previous (24-72h)
        val recent24h = allReports.filter { report ->
            report.publishedAt?.isAfter(twentyFourHoursAgo) == true
        }
        val previous = allReports.filter { report ->
            report.publishedAt?.isBefore(twentyFourHoursAgo) == true
        }
        
        // Count species in each period
        val recentCounts = countSpecies(recent24h)
        val previousCounts = countSpecies(previous)
        
        // Calculate trends
        val allSpecies = (recentCounts.keys + previousCounts.keys).distinct()
        val trends = allSpecies.mapNotNull { species ->
            // Skip weird parsed artifacts
            if (species.contains("total_fish") || species.contains("released.")) return@mapNotNull null
            
            val recent = recentCounts[species] ?: SpeciesAgg()
            val prev = previousCounts[species] ?: SpeciesAgg()
            
            val recentTotal = recent.kept + recent.released
            val prevTotal = prev.kept + prev.released
            
            // Need some activity to be relevant
            if (recentTotal == 0 && prevTotal == 0) return@mapNotNull null
            
            val percentChange = when {
                prevTotal == 0 && recentTotal > 0 -> 999  // New activity!
                prevTotal == 0 -> 0
                else -> ((recentTotal - prevTotal) * 100) / prevTotal
            }
            
            val trend = when {
                percentChange > 20 -> "UP"
                percentChange < -20 -> "DOWN"
                else -> "STABLE"
            }
            
            TrendingSpeciesResponse(
                species = formatSpeciesName(species),
                count24h = recentTotal,
                countPrevious = prevTotal,
                trend = trend,
                percentChange = percentChange,
                topLanding = recent.topLanding ?: prev.topLanding
            )
        }.sortedByDescending { it.count24h }
        
        // Separate hot (UP) and cold (DOWN)
        val hotSpecies = trends.filter { it.trend == "UP" && it.count24h > 0 }.take(5)
        val coldSpecies = trends.filter { it.trend == "DOWN" }.take(3)
        
        // Build headline from the hottest species
        val headline = hotSpecies.firstOrNull()?.let { top ->
            val heatLevel = when {
                top.percentChange > 200 -> 3  // ON FIRE
                top.percentChange > 100 -> 2  // HOT
                else -> 1  // WARM
            }
            val message = fireMessages.random().format(top.species.uppercase())
            HeadlineResponse(
                species = top.species,
                message = message,
                heatLevel = heatLevel,
                count24h = top.count24h,
                topLanding = top.topLanding
            )
        }
        
        // Build recent catches list
        val recentCatches = recent24h.take(10).flatMap { report ->
            val hoursAgo = Duration.between(report.publishedAt ?: now, now).toHours().toInt()
            report.claims
                .filter { it.claimType == ClaimType.CATCH && it.species != null }
                .filter { !it.species!!.contains("total_fish") && !it.species!!.contains("released.") }
                .map { claim ->
                    RecentCatchResponse(
                        species = formatSpeciesName(claim.species!!),
                        count = (claim.countKept ?: 0) + (claim.countReleased ?: 0),
                        boatName = claim.boatName,
                        landingName = claim.landingName ?: "Unknown",
                        hoursAgo = hoursAgo,
                        sourceName = sourceNames[report.sourceId] ?: report.sourceId
                    )
                }
        }.take(5)
        
        val sourcesUsed = allReports.map { it.sourceId }.distinct().mapNotNull { sourceNames[it] }
        
        return SpotIntelResponse(
            spotId = spotId,
            headline = headline,
            hotSpecies = hotSpecies,
            coldSpecies = coldSpecies,
            recentCatches = recentCatches,
            sourcesUsed = sourcesUsed,
            dataFreshness = Instant.now().toString(),
            totalReports = allReports.size
        )
    }
    
    /**
     * Get raw evidence cards for a spot.
     */
    fun getSpotEvidence(spotId: String, species: String?): EvidenceResponse {
        val spot = SpotDatabase.findSpotById(spotId) 
            ?: return EvidenceResponse(spotId = spotId, species = species, evidence = emptyList(), count = 0)
        
        val reports = FishingIntelDb.getReportsNearby(
            spot.coordinates.lat,
            spot.coordinates.lon,
            radiusKm = 50,
            hoursBack = 168
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
        val reports = FishingIntelDb.getReportsNearby(33.0, -117.5, radiusKm = 200, hoursBack = hours)
        
        val speciesCounts = mutableMapOf<String, Int>()
        for (report in reports) {
            for (claim in report.claims.filter { it.species != null }) {
                val species = claim.species!!
                if (!species.contains("total_fish") && !species.contains("released.")) {
                    speciesCounts[species] = speciesCounts.getOrDefault(species, 0) + 1
                }
            }
        }
        
        val trending = speciesCounts.entries
            .sortedByDescending { it.value }
            .take(10)
            .map { TrendingSpecies(species = formatSpeciesName(it.key), mentions = it.value) }
        
        return TrendingResponse(
            region = "socal",
            timeWindowHours = hours,
            trending = trending,
            totalReports = reports.size
        )
    }
    
    /**
     * Get health status.
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
    
    // --- Helpers ---
    
    private fun countSpecies(reports: List<ReportWithClaims>): Map<String, SpeciesAgg> {
        val counts = mutableMapOf<String, SpeciesAgg>()
        for (report in reports) {
            for (claim in report.claims.filter { it.claimType == ClaimType.CATCH && it.species != null }) {
                val species = claim.species!!
                val agg = counts.getOrPut(species) { SpeciesAgg() }
                agg.kept += claim.countKept ?: 0
                agg.released += claim.countReleased ?: 0
                if (claim.landingName != null) {
                    agg.landingCounts[claim.landingName] = 
                        agg.landingCounts.getOrDefault(claim.landingName, 0) + 1
                }
            }
        }
        // Calculate top landing for each
        for (agg in counts.values) {
            agg.topLanding = agg.landingCounts.maxByOrNull { it.value }?.key
        }
        return counts
    }
    
    private fun formatSpeciesName(species: String): String {
        return species
            .replace("_", " ")
            .split(" ")
            .joinToString(" ") { word ->
                word.replaceFirstChar { it.uppercase() }
            }
    }
    
    private class SpeciesAgg {
        var kept: Int = 0
        var released: Int = 0
        val landingCounts = mutableMapOf<String, Int>()
        var topLanding: String? = null
    }
}
