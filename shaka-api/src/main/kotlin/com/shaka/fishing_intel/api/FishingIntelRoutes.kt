package com.shaka.fishing_intel.api

import com.shaka.data.cache.IntelCache
import com.shaka.data.client.SpotDatabase
import com.shaka.fishing_intel.SpeciesTier
import com.shaka.fishing_intel.db.FishingIntelDb
import com.shaka.fishing_intel.models.*
import com.shaka.fishing_intel.processing.Deduplicator
import com.shaka.fishing_intel.processing.SoCalGazetteer
import org.slf4j.LoggerFactory
import java.time.Instant
import java.time.Duration
import java.time.LocalDate
import java.time.ZoneOffset

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
        "seaforth" to "Seaforth Landing",
        "bd-outdoors" to "BD Outdoors Forums"
    )
    
    /**
     * Get fishing intel for a spot - with TRENDS!
     */
    fun getSpotIntel(spotId: String, since: String): SpotIntelResponse? {
        IntelCache.get(spotId, since)?.let { return it }
        val spot = SpotDatabase.findSpotById(spotId) ?: return null

        // Get reports from last 7 days (no arbitrary cap); BD narrative drives most headlines
        val allReports = FishingIntelDb.getReportsNearby(
            spot.coordinates.lat,
            spot.coordinates.lon,
            radiusKm = 150,
            hoursBack = 168
        )

        if (allReports.isEmpty()) return null

        // Dedupe by fingerprint so each logical report counts once
        val dedupedReports = allReports.groupBy { reportFingerprint(it) }.values.map { group ->
            group.minByOrNull { it.publishedAt ?: Instant.MAX } ?: group.first()
        }

        val now = Instant.now()
        val twentyFourHoursAgo = now.minus(Duration.ofHours(24))
        val recent24h = dedupedReports.filter { it.publishedAt?.isAfter(twentyFourHoursAgo) == true }
        val previous = dedupedReports.filter { it.publishedAt?.isBefore(twentyFourHoursAgo) == true }

        val recentCounts = countSpecies(recent24h)
        val previousCounts = countSpecies(previous)

        val allSpecies = (recentCounts.keys + previousCounts.keys).distinct()
        val trends = allSpecies.mapNotNull { species ->
            if (species.contains("total_fish") || species.contains("released.")) return@mapNotNull null
            val recent = recentCounts[species] ?: SpeciesAgg()
            val prev = previousCounts[species] ?: SpeciesAgg()
            val recentTotal = recent.kept + recent.released
            val prevTotal = prev.kept + prev.released
            if (recentTotal == 0 && prevTotal == 0) return@mapNotNull null
            val percentChange = when {
                prevTotal == 0 && recentTotal > 0 -> 999
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

        val trophyDisplayNames = SpeciesTier.TROPHY_SPECIES.map { formatSpeciesName(it) }.toSet()
        val hotSpecies = trends
            .filter { it.trend == "UP" && it.count24h > 0 }
            .sortedWith(compareByDescending<TrendingSpeciesResponse> { it.species in trophyDisplayNames }.thenByDescending { it.count24h })
            .take(5)
        val coldSpecies = trends.filter { it.trend == "DOWN" }.take(3)

        val narrativeInsights = buildNarrativeInsights(dedupedReports)

        // BD narrative = where most headlines come from; dock counts = pure stats unless wild anomaly
        val headline = when {
            narrativeInsights.isNotEmpty() -> HeadlineResponse(
                species = narrativeInsights.first().species,
                message = "${narrativeInsights.first().species} at ${narrativeInsights.first().location}",
                heatLevel = 1,
                count24h = 0,
                topLanding = null
            )
            else -> {
                val trophyUp = trends
                    .filter { it.trend == "UP" && it.count24h > 0 && it.species in trophyDisplayNames }
                    .sortedByDescending { it.count24h }
                    .firstOrNull()
                // Only use dock-based headline for a clear anomaly (huge count or massive % change)
                if (trophyUp != null && (trophyUp.count24h >= 10 || trophyUp.percentChange > 200)) {
                    HeadlineResponse(
                        species = trophyUp.species,
                        message = "${trophyUp.species} activity at ${trophyUp.topLanding ?: "local waters"}",
                        heatLevel = if (trophyUp.percentChange > 100) 2 else 1,
                        count24h = trophyUp.count24h,
                        topLanding = trophyUp.topLanding
                    )
                } else null
            }
        }

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

        val sourcesUsed = dedupedReports.map { it.sourceId }.distinct().mapNotNull { sourceNames[it] }

        val response = SpotIntelResponse(
            spotId = spotId,
            headline = headline,
            hotSpecies = hotSpecies,
            coldSpecies = coldSpecies,
            recentCatches = recentCatches,
            sourcesUsed = sourcesUsed,
            dataFreshness = Instant.now().toString(),
            totalReports = dedupedReports.size,
            narrativeInsights = narrativeInsights
        )
        IntelCache.set(spotId, since, response)
        return response
    }

    private fun reportFingerprint(report: ReportWithClaims): String {
        val fishCounts = report.claims
            .filter { it.claimType == ClaimType.CATCH && it.species != null }
            .map { FishCount(it.species!!, it.countKept ?: 0, it.countReleased ?: 0) }
        val firstWithMeta = report.claims.firstOrNull { it.landingName != null || it.boatName != null || it.tripType != null }
        val landingName = firstWithMeta?.landingName
        val boatName = firstWithMeta?.boatName ?: report.claims.firstOrNull()?.boatName
        val tripType = firstWithMeta?.tripType ?: report.claims.firstOrNull()?.tripType
        val anglerCount = report.claims.firstOrNull()?.anglerCount
        val date = report.publishedAt?.atZone(ZoneOffset.UTC)?.toLocalDate() ?: LocalDate.now(ZoneOffset.UTC)
        return Deduplicator.getReportFingerprint(
            report.canonicalFingerprint,
            landingName,
            boatName,
            tripType,
            date,
            anglerCount,
            fishCounts
        )
    }

    private fun buildNarrativeInsights(reports: List<ReportWithClaims>): List<NarrativeInsight> {
        val bdReports = reports.filter { it.sourceId == "bd-outdoors" }
        val eligible = bdReports.mapNotNull { report ->
            val location = report.threadZone?.takeIf { it.isNotBlank() }
                ?: SoCalGazetteer.findInText(report.rawExcerpt ?: "").firstOrNull()?.name
                ?: SoCalGazetteer.findInText(report.title ?: "").firstOrNull()?.name
            if (location.isNullOrBlank()) return@mapNotNull null
            val trophyClaim = report.claims
                .filter { it.claimType == ClaimType.CATCH && it.species != null && it.species in SpeciesTier.TROPHY_SPECIES }
                .firstOrNull()
            if (trophyClaim == null) return@mapNotNull null
            val species = formatSpeciesName(trophyClaim.species!!)
            val excerpt = (report.rawExcerpt ?: "").take(200)
            // Prefer stored TL;DR (from AI or backfill); else build fallback with longer excerpt for context
            val tldr = report.tldr?.takeIf { it.isNotBlank() }
                ?: "$species at $location. ${excerpt.take(120).trim()}".replace(Regex("\\s+"), " ").trim().take(180)
            NarrativeInsight(
                species = species,
                location = location,
                excerpt = excerpt,
                sourceName = sourceNames[report.sourceId] ?: report.sourceId,
                threadUrl = report.threadUrl ?: report.url,
                publishedAt = report.publishedAt?.toString() ?: "",
                tldr = tldr
            )
        }
        val dedupedByThread = eligible.groupBy { it.threadUrl }.values.map { group ->
            group.maxByOrNull { it.publishedAt } ?: group.first()
        }
        return dedupedByThread.sortedByDescending { it.publishedAt }.take(3)
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
