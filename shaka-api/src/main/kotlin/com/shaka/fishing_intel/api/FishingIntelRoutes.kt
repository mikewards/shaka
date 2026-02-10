package com.shaka.fishing_intel.api

import com.shaka.data.cache.IntelCache
import com.shaka.data.client.SpotDatabase
import com.shaka.fishing_intel.ai.FishingIntelAiService
import com.shaka.fishing_intel.SpeciesOrder
import com.shaka.fishing_intel.SpeciesTier
import com.shaka.fishing_intel.db.FishingIntelDb
import com.shaka.fishing_intel.models.*
import com.shaka.fishing_intel.processing.Deduplicator
import com.shaka.fishing_intel.processing.SoCalGazetteer
import com.shaka.fishing_intel.processing.SpeciesNormalizer
import com.shaka.fishing_intel.processing.ThreadIntelScorer
import kotlinx.coroutines.runBlocking
import org.slf4j.LoggerFactory
import java.time.Instant
import java.time.Duration
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.ZonedDateTime

/**
 * API handlers for Fishing Intel endpoints.
 * Designed to get anglers STOKED!
 */
object FishingIntelRoutes {
    private val logger = LoggerFactory.getLogger(FishingIntelRoutes::class.java)
    
    private val sourceNames = mapOf(
        "976-tuna" to "976-TUNA",
        "976-tuna-longrange" to "976-TUNA Long Range",
        "bd-outdoors" to "BD Outdoors Forums"
    )
    
    /**
     * Get fishing intel for a spot - with TRENDS!
     * @param tzOffset UTC offset in hours (e.g. -8 for PST). When null, derived from spot longitude (SolunarClient pattern).
     */
    fun getSpotIntel(spotId: String, since: String, tzOffset: Int? = null): SpotIntelResponse? {
        val cacheKey = "$since:${tzOffset ?: "auto"}"
        IntelCache.get(spotId, cacheKey)?.let { return it }
        val spot = SpotDatabase.findSpotById(spotId) ?: return null

        // Get reports from last 7 days (no arbitrary cap); BD narrative drives most headlines
        val allReports = FishingIntelDb.getReportsNearby(
            spot.coordinates.lat,
            spot.coordinates.lon,
            radiusKm = 150,
            hoursBack = 168
        )

        if (allReports.isEmpty()) return null

        // Dedupe: for DOCK_TOTAL reports, keep only the LATEST per (sourceId, date).
        // For other types, keep all (each is a distinct event).
        val dedupedReports = dedupeByLatest(allReports)

        // Last 48h and baseline (5 days prior: today-2 through today-7) in user's local timezone
        val offset = tzOffset ?: (spot.coordinates.lon / 15).toInt()
        val userZone = ZoneOffset.ofHours(offset)
        val nowInUserZone = ZonedDateTime.now(userZone)
        val fortyEightHoursAgo = nowInUserZone.minusHours(48).toInstant()
        val baselineStart = nowInUserZone.minusHours(168).toInstant() // 7 days ago

        // Recent 48h = reports published in last 48h (publishedAt only)
        val recent48h = dedupedReports.filter { it.publishedAt?.isAfter(fortyEightHoursAgo) == true }
        // Baseline = 5 days prior to last 48h: [now-7d, now-48h)
        val baseline = dedupedReports.filter { r ->
            val t = r.publishedAt ?: return@filter false
            !t.isBefore(baselineStart) && t.isBefore(fortyEightHoursAgo)
        }

        val recentCounts = countSpecies(recent48h)
        val baselineCounts = countSpecies(baseline)

        val allSpecies = (recentCounts.keys + baselineCounts.keys).distinct()
        val trophyDisplayNames = SpeciesTier.TROPHY_SPECIES.map { formatSpeciesName(it) }.toSet()

        // Trend = last 48h vs (5-day baseline total × 2/5) = equivalent 48h rate from baseline
        val baselineMultiplier = 2.0 / 5.0
        val trendsWithMeta = allSpecies.mapNotNull { species ->
            if (species.contains("total_fish") || species.contains("released.")) return@mapNotNull null
            val recent = recentCounts[species] ?: SpeciesAgg()
            val base = baselineCounts[species] ?: SpeciesAgg()
            val recentTotal = recent.kept + recent.released
            val baseTotal = base.kept + base.released
            if (recentTotal == 0 && baseTotal == 0) return@mapNotNull null
            val baselineEquivalent48h = if (baseTotal == 0) 0.0 else baseTotal * baselineMultiplier
            val percentChange = when {
                baseTotal == 0 && recentTotal > 0 -> 999
                baseTotal == 0 -> 0
                baselineEquivalent48h == 0.0 -> 0
                else -> ((recentTotal - baselineEquivalent48h) * 100 / baselineEquivalent48h).toInt()
            }
            val trend = when {
                percentChange > 20 -> "UP"
                percentChange < -20 -> "DOWN"
                else -> "STABLE"
            }
            val trendLabel = when {
                baseTotal == 0 && recentTotal > 0 -> "New!"
                trend == "UP" -> "Above average"
                trend == "DOWN" -> "Below average"
                else -> "Average"
            }
            Pair(
                species,
                TrendingSpeciesResponse(
                    species = formatSpeciesName(species),
                    count24h = recentTotal,
                    countPrevious = baseTotal,
                    trend = trend,
                    percentChange = percentChange,
                    topLanding = recent.topLanding ?: base.topLanding,
                    trendLabel = trendLabel,
                    avgPerDayPrevious = if (baselineEquivalent48h > 0) baselineEquivalent48h else null
                )
            )
        }

        // Single list sorted by desirability (most to least), then by 48h count. No cap — show all species.
        val speciesWithTrends = trendsWithMeta
            .sortedWith(
                compareBy<Pair<String, TrendingSpeciesResponse>> { SpeciesOrder.sortKey(it.first) }
                    .thenByDescending { it.second.count24h }
            )
            .map { it.second }

        // Backward compat: hot/cold for old clients
        val hotSpecies = trendsWithMeta.map { it.second }.filter { it.trend == "UP" && it.count24h > 0 }
            .sortedWith(compareByDescending<TrendingSpeciesResponse> { it.species in trophyDisplayNames }.thenByDescending { it.count24h })
            .take(5)
        val coldSpecies = trendsWithMeta.map { it.second }.filter { it.trend == "DOWN" }.take(3)

        val narrativeInsights = buildNarrativeInsights(dedupedReports)

        val now = nowInUserZone.toInstant()
        val recentCatches = recent48h.take(10).flatMap { report ->
            val hoursAgo = Duration.between(report.publishedAt ?: now, now).toHours().toInt()
            report.claims
                .filter { it.claimType == ClaimType.CATCH && it.species != null }
                .filter { !it.species!!.contains("total_fish") && !it.species!!.contains("released.") }
                .map { claim ->
                    val canonical = SpeciesNormalizer.normalize(claim.species!!)
                    RecentCatchResponse(
                        species = formatSpeciesName(canonical),
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
            headline = null,
            hotSpecies = hotSpecies,
            coldSpecies = coldSpecies,
            speciesWithTrends = speciesWithTrends,
            recentCatches = recentCatches,
            sourcesUsed = sourcesUsed,
            dataFreshness = Instant.now().toString(),
            totalReports = dedupedReports.size,
            narrativeInsights = narrativeInsights
        )
        IntelCache.set(spotId, cacheKey, response)
        return response
    }

    /**
     * Get fishing intel for a region (filter by sources.regional_report). No geo.
     * Used by the Reports tab; regionId can be "socal" (API) or "so_cal" (DB).
     */
    fun getIntelForRegion(regionId: String, since: String, tzOffset: Int? = null): SpotIntelResponse? {
        val offset = tzOffset ?: -8
        val slotKey = insightSlotKey(offset)
        val cacheKey = "$since:${tzOffset ?: "auto"}:$slotKey"
        val normalizedRegionId = when (regionId.lowercase()) {
            "socal" -> "so_cal"
            else -> regionId.lowercase()
        }
        IntelCache.get(normalizedRegionId, cacheKey)?.let { return it }

        val allReports = FishingIntelDb.getReportsForRegion(normalizedRegionId, hoursBack = 168)
        if (allReports.isEmpty()) return null

        // Dedupe: for DOCK_TOTAL reports (976-tuna daily totals), keep only the LATEST
        // report per (sourceId, date) since each scrape supersedes the previous one.
        // For other types (BD narratives, long-range), keep all (each is a distinct event).
        val dedupedReports = dedupeByLatest(allReports)

        val userZone = ZoneOffset.ofHours(offset)
        val nowInUserZone = ZonedDateTime.now(userZone)
        val fortyEightHoursAgo = nowInUserZone.minusHours(48).toInstant()
        val baselineStart = nowInUserZone.minusHours(168).toInstant()

        val recent48h = dedupedReports.filter { it.publishedAt?.isAfter(fortyEightHoursAgo) == true }
        val baseline = dedupedReports.filter { r ->
            val t = r.publishedAt ?: return@filter false
            !t.isBefore(baselineStart) && t.isBefore(fortyEightHoursAgo)
        }

        val recentCounts = countSpecies(recent48h)
        val baselineCounts = countSpecies(baseline)

        val allSpecies = (recentCounts.keys + baselineCounts.keys).distinct()
        val trophyDisplayNames = SpeciesTier.TROPHY_SPECIES.map { formatSpeciesName(it) }.toSet()

        val baselineMultiplier = 2.0 / 5.0
        val trendsWithMeta = allSpecies.mapNotNull { species ->
            if (species.contains("total_fish") || species.contains("released.")) return@mapNotNull null
            val recent = recentCounts[species] ?: SpeciesAgg()
            val base = baselineCounts[species] ?: SpeciesAgg()
            val recentTotal = recent.kept + recent.released
            val baseTotal = base.kept + base.released
            if (recentTotal == 0 && baseTotal == 0) return@mapNotNull null
            val baselineEquivalent48h = if (baseTotal == 0) 0.0 else baseTotal * baselineMultiplier
            val percentChange = when {
                baseTotal == 0 && recentTotal > 0 -> 999
                baseTotal == 0 -> 0
                baselineEquivalent48h == 0.0 -> 0
                else -> ((recentTotal - baselineEquivalent48h) * 100 / baselineEquivalent48h).toInt()
            }
            val trend = when {
                percentChange > 20 -> "UP"
                percentChange < -20 -> "DOWN"
                else -> "STABLE"
            }
            val trendLabel = when {
                baseTotal == 0 && recentTotal > 0 -> "New!"
                trend == "UP" -> "Above average"
                trend == "DOWN" -> "Below average"
                else -> "Average"
            }
            Pair(
                species,
                TrendingSpeciesResponse(
                    species = formatSpeciesName(species),
                    count24h = recentTotal,
                    countPrevious = baseTotal,
                    trend = trend,
                    percentChange = percentChange,
                    topLanding = recent.topLanding ?: base.topLanding,
                    trendLabel = trendLabel,
                    avgPerDayPrevious = if (baselineEquivalent48h > 0) baselineEquivalent48h else null
                )
            )
        }

        val speciesWithTrends = trendsWithMeta
            .sortedWith(
                compareBy<Pair<String, TrendingSpeciesResponse>> { SpeciesOrder.sortKey(it.first) }
                    .thenByDescending { it.second.count24h }
            )
            .map { it.second }

        val hotSpecies = trendsWithMeta.map { it.second }.filter { it.trend == "UP" && it.count24h > 0 }
            .sortedWith(compareByDescending<TrendingSpeciesResponse> { it.species in trophyDisplayNames }.thenByDescending { it.count24h })
            .take(5)
        val coldSpecies = trendsWithMeta.map { it.second }.filter { it.trend == "DOWN" }.take(3)

        val narrativeInsights = buildNarrativeInsights(dedupedReports)

        val now = nowInUserZone.toInstant()
        val recentCatches = recent48h.take(10).flatMap { report ->
            val hoursAgo = Duration.between(report.publishedAt ?: now, now).toHours().toInt()
            report.claims
                .filter { it.claimType == ClaimType.CATCH && it.species != null }
                .filter { !it.species!!.contains("total_fish") && !it.species!!.contains("released.") }
                .map { claim ->
                    val canonical = SpeciesNormalizer.normalize(claim.species!!)
                    RecentCatchResponse(
                        species = formatSpeciesName(canonical),
                        count = (claim.countKept ?: 0) + (claim.countReleased ?: 0),
                        boatName = claim.boatName,
                        landingName = claim.landingName ?: "Unknown",
                        hoursAgo = hoursAgo,
                        sourceName = sourceNames[report.sourceId] ?: report.sourceId
                    )
                }
        }.take(5)

        val sourcesUsed = dedupedReports.map { it.sourceId }.distinct().mapNotNull { sourceNames[it] }

        val speciesSummary = speciesWithTrends.take(12).joinToString("\n") { s ->
            "${s.species}: ${s.count24h} (last 48h), ${s.countPrevious} (5-day baseline), ${s.trend} ${s.percentChange}%"
        }
        val tldrs = narrativeInsights.map { it.tldr }.filter { it.isNotBlank() }
        val regionLabel = if (normalizedRegionId == "so_cal") "SoCal" else normalizedRegionId
        // Insights change 3x/day by user timezone: morning 03–11:59, afternoon 12–19:59, night 20:00–02:59. Persist per slot so they don't change when app closes.
        var keyInsights = FishingIntelDb.getRegionInsights(normalizedRegionId, slotKey)
        if (keyInsights == null || keyInsights.isEmpty()) {
            keyInsights = runBlocking {
                FishingIntelAiService.generateRegionInsights(
                    speciesSummary = speciesSummary,
                    narrativeTldrs = tldrs,
                    totalReports = dedupedReports.size,
                    regionLabel = regionLabel
                ) ?: emptyList()
            }
            if (!keyInsights.isNullOrEmpty()) {
                try {
                    FishingIntelDb.setRegionInsights(normalizedRegionId, slotKey, keyInsights)
                } catch (e: Exception) {
                    logger.warn("Failed to persist region insights: ${e.message}")
                }
            }
        }
        val finalKeyInsights = keyInsights ?: emptyList()

        val response = SpotIntelResponse(
            spotId = normalizedRegionId,
            headline = null,
            hotSpecies = hotSpecies,
            coldSpecies = coldSpecies,
            speciesWithTrends = speciesWithTrends,
            recentCatches = recentCatches,
            sourcesUsed = sourcesUsed,
            dataFreshness = Instant.now().toString(),
            totalReports = dedupedReports.size,
            narrativeInsights = narrativeInsights,
            keyInsights = finalKeyInsights
        )
        IntelCache.set(normalizedRegionId, cacheKey, response)
        return response
    }

    /** Morning 03:00–11:59, afternoon 12:00–19:59, night 20:00–02:59. Returns e.g. "2025-02-08_afternoon". */
    private fun insightSlotKey(tzOffsetHours: Int): String {
        val zone = ZoneOffset.ofHours(tzOffsetHours)
        val now = ZonedDateTime.now(zone)
        val hour = now.hour
        val (slotName, date) = when {
            hour in 3..11 -> "morning" to now.toLocalDate()
            hour in 12..19 -> "afternoon" to now.toLocalDate()
            hour >= 20 -> "night" to now.toLocalDate()
            else -> "night" to now.toLocalDate().minusDays(1) // 00–02:59 = previous day's night
        }
        return "${date}_$slotName"
    }

    private fun buildNarrativeInsights(reports: List<ReportWithClaims>): List<NarrativeInsight> {
        val bdReports = reports.filter { it.sourceId == "bd-outdoors" }
        val eligible = bdReports.filter { report ->
            report.claims.any { it.claimType == ClaimType.CATCH && it.species != null && SpeciesNormalizer.normalize(it.species!!) in SpeciesTier.TROPHY_SPECIES }
        }
        val byThread = eligible.groupBy { it.threadUrl ?: it.url }
        val representatives = byThread.values.map { group ->
            group.firstOrNull { it.tldr?.isNotBlank() == true } ?: group.maxByOrNull { it.publishedAt?.toString() ?: "" } ?: group.first()
        }
        val scored = representatives.map { report ->
            report to ThreadIntelScorer.score(report, report.tldr)
        }.filter { (_, score) -> score >= 5.0 }.sortedByDescending { (_, score) -> score }.take(3)
        return scored.map { (report, _) ->
            val location = SoCalGazetteer.findInText(report.rawExcerpt ?: "").firstOrNull()?.name
                ?: SoCalGazetteer.findInText(report.title ?: "").firstOrNull()?.name ?: ""
            val trophyClaim = report.claims
                .filter { it.claimType == ClaimType.CATCH && it.species != null && SpeciesNormalizer.normalize(it.species!!) in SpeciesTier.TROPHY_SPECIES }
                .firstOrNull()
            val species = formatSpeciesName(SpeciesNormalizer.normalize(trophyClaim?.species ?: "fish"))
            val excerpt = (report.rawExcerpt ?: "").take(200)
            val tldr = report.tldr?.takeIf { it.isNotBlank() }
                ?: "$species at ${location.ifBlank { "SoCal" }}. ${excerpt.take(120).trim()}".replace(Regex("\\s+"), " ").trim().take(180)
            NarrativeInsight(
                species = species,
                location = location,
                excerpt = excerpt,
                sourceName = sourceNames[report.sourceId] ?: report.sourceId,
                threadUrl = report.threadUrl ?: report.url,
                publishedAt = report.publishedAt?.toString() ?: "",
                tldr = tldr,
                threadZone = report.threadZone
            )
        }
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
                val raw = claim.species!!
                if (!raw.contains("total_fish") && !raw.contains("released.")) {
                    val key = SpeciesNormalizer.normalize(raw)
                    speciesCounts[key] = speciesCounts.getOrDefault(key, 0) + 1
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

    /**
     * Dedupe reports so rolling daily totals don't stack.
     * DOCK_TOTAL reports (976-tuna daily totals): keep only the LATEST per (sourceId, date).
     *   Each scraper run produces a fresh total; older scrapes for the same date are superseded.
     * All other types (NARRATIVE, FISH_COUNT): keep all — each represents a distinct event.
     */
    private fun dedupeByLatest(reports: List<ReportWithClaims>): List<ReportWithClaims> {
        val (dockTotals, others) = reports.partition { it.reportType == ReportType.DOCK_TOTAL }

        // For dock totals, group by (sourceId, publishedAt date) and keep the one with highest reportId (= most recent insert)
        val latestDockTotals = dockTotals.groupBy { report ->
            val date = report.publishedAt?.atZone(ZoneOffset.UTC)?.toLocalDate() ?: LocalDate.now(ZoneOffset.UTC)
            "${report.sourceId}|$date"
        }.values.map { group ->
            group.maxByOrNull { it.reportId } ?: group.first()
        }

        return latestDockTotals + others
    }
    
    private fun countSpecies(reports: List<ReportWithClaims>): Map<String, SpeciesAgg> {
        val counts = mutableMapOf<String, SpeciesAgg>()
        for (report in reports) {
            for (claim in report.claims.filter { it.claimType == ClaimType.CATCH && it.species != null }) {
                val raw = claim.species!!
                val key = SpeciesNormalizer.normalize(raw) // merge "Halibut." into "halibut"
                val agg = counts.getOrPut(key) { SpeciesAgg() }
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
