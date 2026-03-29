package com.shaka.fishing_intel.jobs

import com.shaka.data.client.RateLimiters
import com.shaka.fishing_intel.api.FishingIntelRoutes
import com.shaka.fishing_intel.db.FishingIntelDb
import com.shaka.fishing_intel.models.*
import com.shaka.fishing_intel.parsing.CountsParser
import com.shaka.fishing_intel.parsing.DateParser
import com.shaka.fishing_intel.processing.Deduplicator
import kotlinx.coroutines.*
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element
import org.slf4j.LoggerFactory
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset

object FishingIntelPrefetchJob {
    private val logger = LoggerFactory.getLogger(FishingIntelPrefetchJob::class.java)
    
    const val USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    private val PACIFIC = ZoneId.of("America/Los_Angeles")

    private val SFR_REGION_MAP = mapOf(
        "Washington Coast" to "wa_coast",
        "Oregon Coast" to "or_coast",
        "Northern California" to "norcal",
        "North Coast" to "north_coast",
        "Bay Area" to "bay_area",
        "Central Coast" to "central_coast",
        "Ventura Coast" to "ventura",
        "Los Angeles" to "la",
        "Orange" to "orange",
        "San Diego" to "san_diego",
        "Baja California Sur" to "baja"
    )

    suspend fun run(force: Boolean = false) {
        if (!force) {
            val lastFetch = FishingIntelDb.getSourceLastFetch("sportfishing-report")
            if (lastFetch != null) {
                val minutesSince = Duration.between(lastFetch, Instant.now()).toMinutes()
                if (minutesSince < 90) {
                    logger.info("Skipping fishing intel scrape — last run ${minutesSince}m ago")
                    prefetchGlobalInsights()
                    return
                }
            }
        }

        logger.info("Starting fishing intel scrape${if (force) " (forced)" else ""}...")

        val sources = FishingIntelDb.getEnabledSources()
        logger.info("Found ${sources.size} enabled sources")

        var totalReports = 0
        var totalClaims = 0

        for (source in sources) {
            try {
                val (reports, claims) = when (source.id) {
                    "sportfishing-report" -> scrapeSportFishingReport()
                    else -> {
                        logger.debug("Skipping source with no active scraper: ${source.id}")
                        0 to 0
                    }
                }
                totalReports += reports
                totalClaims += claims
                FishingIntelDb.updateSourceLastFetch(source.id)
            } catch (e: Exception) {
                logger.error("Failed to scrape ${source.id}: ${e.message}", e)
            }
        }

        logger.info("Fishing intel scrape complete: $totalReports reports, $totalClaims claims")

        prefetchGlobalInsights()
    }

    private suspend fun prefetchGlobalInsights() {
        try {
            FishingIntelRoutes.prefetchGlobalInsights()
        } catch (e: Exception) {
            logger.warn("Global insight pre-generation failed: ${e.message}")
        }
    }

    // =========================================================================
    // SportFishingReport.com Dock Totals Scraper
    // =========================================================================

    private suspend fun scrapeSportFishingReport(): Pair<Int, Int> {
        val url = "https://www.sportfishingreport.com/dock_totals/"
        val doc = fetchWithRetry(url, RateLimiters.sportFishingReport) ?: run {
            logger.error("Failed to fetch sportfishingreport.com dock totals")
            return 0 to 0
        }

        val dateStr = doc.selectFirst("h1")?.text()
            ?.substringAfter("-")?.trim()
        val reportDate = dateStr?.let { DateParser.parseSoCalFishReports(it) }
            ?: LocalDate.now(PACIFIC)
        val publishedAt = reportDate.atStartOfDay(PACIFIC).toInstant()
        val publishedAtLdt = LocalDateTime.ofInstant(publishedAt, ZoneOffset.UTC)

        logger.info("Scraping sportfishingreport.com dock totals for $reportDate")

        var totalReports = 0
        var totalClaims = 0

        val h2s = doc.select("h2.text-center")
        for (h2 in h2s) {
            val headerText = h2.text().trim()
            if (!headerText.endsWith("Dock Totals")) continue

            val regionName = headerText.removeSuffix("Dock Totals").trim()
            val regionId = SFR_REGION_MAP[regionName]
            if (regionId == null) {
                logger.warn("Unknown sportfishingreport region: '$regionName'")
                continue
            }

            // Collect landing row divs between this H2 and the next H2 (or end)
            val landingRows = mutableListOf<Element>()
            var sibling = h2.nextElementSibling()
            while (sibling != null && sibling.tagName() != "h2") {
                val landingLink = sibling.selectFirst("a[href*=/landings/]")
                if (landingLink != null) {
                    landingRows.add(sibling)
                }
                sibling = sibling.nextElementSibling()
            }

            for (landingDiv in landingRows) {
                try {
                    val (r, c) = parseLandingRow(landingDiv, regionId, reportDate, publishedAt, publishedAtLdt)
                    totalReports += r
                    totalClaims += c
                } catch (e: Exception) {
                    logger.warn("Failed to parse landing row in $regionName: ${e.message}")
                }
            }
        }

        logger.info("SportFishingReport scrape done: $totalReports reports, $totalClaims claims for $reportDate")
        return totalReports to totalClaims
    }

    private fun parseLandingRow(
        div: Element,
        regionId: String,
        reportDate: LocalDate,
        publishedAt: Instant,
        publishedAtLdt: LocalDateTime
    ): Pair<Int, Int> {
        val landingLink = div.selectFirst("a[href*=/landings/]") ?: return 0 to 0
        val landingName = landingLink.text().trim()

        // City is the text node after the first <br/> in the col-md-4 div
        val landingCol = landingLink.parent() ?: div.selectFirst(".col-md-4") ?: div
        val cityText = landingCol.html()
            .substringAfter("<br/>", "")
            .substringAfter("<br>", "")
            .substringBefore("<br", "")
            .replace(Regex("<[^>]*>"), "")
            .trim()
        val landingCity = cityText.takeIf { it.isNotBlank() }

        // Dock totals: the col-md-pull-5 div
        val countsDiv = div.selectFirst(".col-md-pull-5")
            ?: div.selectFirst("[class*=col-md-3][class*=col-md-pull-5]")
        val countsText = countsDiv?.text()?.trim() ?: ""

        if (countsText.isBlank()) return 0 to 0

        val fishCounts = CountsParser.parse(countsText)
        if (fishCounts.isEmpty()) return 0 to 0

        // Anglers count (optional)
        val anglersDiv = div.select(".col-md-push-3").getOrNull(1)
        val anglerCount = anglersDiv?.text()?.trim()
            ?.replace(Regex("[^0-9]"), "")
            ?.toIntOrNull()

        val fingerprint = Deduplicator.buildFingerprint(
            landingName, null, null, reportDate,
            anglerCount, fishCounts.sortedBy { it.species }
        )

        // Replace-on-scrape: delete previous report for this source+date, then insert fresh
        FishingIntelDb.deleteReportsForSourceAndDate("sportfishing-report", publishedAtLdt)

        val reportUrl = "https://www.sportfishingreport.com/dock_totals/"
        val report = FishingReport(
            sourceId = "sportfishing-report",
            url = reportUrl,
            publishedAt = publishedAt,
            observedAt = publishedAt,
            reportType = ReportType.DOCK_TOTAL,
            title = "$landingName - ${landingCity ?: regionId}",
            rawExcerpt = countsText,
            fingerprint = fingerprint,
            confidence = 1.0,
            region = regionId
        )

        val reportId = FishingIntelDb.saveReport(report)
        var claimCount = 0

        for (fc in fishCounts) {
            val claim = FishingClaim(
                claimType = ClaimType.CATCH,
                species = fc.species,
                countKept = fc.kept,
                countReleased = fc.released,
                landingName = landingName,
                landingCity = landingCity,
                anglerCount = anglerCount
            )
            FishingIntelDb.saveClaim(reportId, claim)
            claimCount++
        }

        return 1 to claimCount
    }

    // =========================================================================
    // HTTP Helpers
    // =========================================================================

    private suspend fun fetchWithRetry(
        url: String,
        rateLimiter: com.shaka.data.client.RateLimiter,
        maxRetries: Int = 3
    ): Document? {
        repeat(maxRetries) { attempt ->
            try {
                rateLimiter.acquire()

                val response = Jsoup.connect(url)
                    .userAgent(USER_AGENT)
                    .timeout(30_000)
                    .followRedirects(true)
                    .ignoreHttpErrors(true)
                    .execute()

                if (response.statusCode() == 429) {
                    val backoff = (attempt + 1) * 5000L
                    logger.warn("Rate limited on $url, backing off ${backoff}ms")
                    delay(backoff)
                    return@repeat
                }

                if (response.statusCode() != 200) {
                    logger.warn("Got status ${response.statusCode()} for $url")
                    return@repeat
                }

                return response.parse()
            } catch (e: Exception) {
                logger.warn("Fetch attempt ${attempt + 1} failed for $url: ${e.message}")
                if (attempt < maxRetries - 1) {
                    delay((attempt + 1) * 2000L)
                }
            }
        }
        return null
    }
}
