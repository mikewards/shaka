package com.shaka.fishing_intel.jobs

import com.shaka.data.client.RateLimiters
import com.shaka.fishing_intel.db.FishingIntelDb
import com.shaka.fishing_intel.models.*
import com.shaka.fishing_intel.parsing.CountsParser
import com.shaka.fishing_intel.parsing.DateParser
import com.shaka.fishing_intel.processing.*
import kotlinx.coroutines.*
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.slf4j.LoggerFactory
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/**
 * Scheduled job that scrapes fishing report sources.
 * Runs every 2 hours from Application.kt.
 */
object FishingIntelPrefetchJob {
    private val logger = LoggerFactory.getLogger(FishingIntelPrefetchJob::class.java)
    
    const val USER_AGENT = "ShakaFishingBot/1.0 (https://shaka.app; support@shaka.app)"
    
    /**
     * Run a full scrape of all enabled sources.
     */
    suspend fun run() {
        logger.info("Starting fishing intel scrape...")
        
        val sources = FishingIntelDb.getEnabledSources()
        logger.info("Found ${sources.size} enabled sources")
        
        var totalReports = 0
        var totalClaims = 0
        
        for (source in sources) {
            try {
                val (reports, claims) = when (source.id) {
                    "socal-fish-reports" -> scrapeSoCalFishReports()
                    "san-diego-fish-reports" -> scrapeSanDiegoFishReports()
                    "976-tuna" -> scrape976Tuna()
                    else -> {
                        logger.warn("No scraper for source: ${source.id}")
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
    }
    
    /**
     * Fetch HTML with rate limiting and retries.
     */
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
                    .execute()
                
                if (response.statusCode() == 429) {
                    val backoff = (attempt + 1) * 5000L
                    logger.warn("Rate limited on $url, backing off ${backoff}ms")
                    delay(backoff)
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
    
    /**
     * Scrape SoCalFishReports boat counts.
     */
    private suspend fun scrapeSoCalFishReports(): Pair<Int, Int> {
        logger.info("Scraping SoCalFishReports...")
        var reports = 0
        var claims = 0
        
        val today = LocalDate.now()
        val dateFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
        
        // Scrape today and past 7 days
        for (daysBack in 0..7) {
            val date = today.minusDays(daysBack.toLong())
            val url = "https://www.socalfishreports.com/dock_totals/boats.php?date=${date.format(dateFormatter)}"
            
            val doc = fetchWithRetry(url, RateLimiters.socalFishReports) ?: continue
            
            // Save raw HTML
            FishingIntelDb.saveRawPage("socal-fish-reports", url, doc.html(), 200, null, null)
            
            // Parse the HTML
            val (r, c) = parseSoCalFishReportsPage(doc, url, date)
            reports += r
            claims += c
            
            delay(1000) // Be nice
        }
        
        return reports to claims
    }
    
    private fun parseSoCalFishReportsPage(doc: Document, url: String, date: LocalDate): Pair<Int, Int> {
        var reports = 0
        var claims = 0
        
        // Find all tables with boat data
        val tables = doc.select("table")
        
        for (table in tables) {
            val rows = table.select("tr")
            
            for (row in rows) {
                val cells = row.select("td")
                if (cells.size < 5) continue
                
                // Extract: Boat, Landing, City, Anglers, Trip Type, Dock Totals
                val boatName = cells.getOrNull(0)?.text()?.trim() ?: continue
                val landingName = cells.getOrNull(1)?.text()?.trim() ?: continue
                val city = cells.getOrNull(2)?.text()?.trim()
                val anglers = cells.getOrNull(3)?.text()?.toIntOrNull()
                val tripType = cells.getOrNull(4)?.text()?.trim()
                val dockTotals = cells.getOrNull(5)?.text()?.trim() ?: continue
                
                if (dockTotals.isBlank()) continue
                
                // Parse fish counts
                val fishCounts = CountsParser.parse(dockTotals)
                if (fishCounts.isEmpty()) continue
                
                // Build fingerprint for deduplication
                val fingerprint = Deduplicator.buildFingerprint(
                    landingName, boatName, tripType, date, anglers, fishCounts
                )
                
                // Skip if already exists
                if (FishingIntelDb.fingerprintExists(fingerprint)) continue
                
                // Create report
                val report = FishingReport(
                    sourceId = "socal-fish-reports",
                    url = url,
                    publishedAt = date.atStartOfDay().toInstant(ZoneOffset.UTC),
                    observedAt = date.atStartOfDay().toInstant(ZoneOffset.UTC),
                    reportType = ReportType.FISH_COUNT,
                    title = "$boatName - $tripType",
                    rawExcerpt = dockTotals.take(200),
                    fingerprint = fingerprint,
                    confidence = 1.0
                )
                
                val reportId = FishingIntelDb.saveReport(report)
                reports++
                
                // Create claims for each species
                for ((species, kept, released) in fishCounts) {
                    val claim = FishingClaim(
                        claimType = ClaimType.CATCH,
                        species = SpeciesNormalizer.normalize(species),
                        countKept = kept,
                        countReleased = released,
                        tripType = tripType,
                        anglerCount = anglers,
                        boatName = boatName,
                        landingName = landingName,
                        landingCity = city
                    )
                    FishingIntelDb.saveClaim(reportId, claim)
                    claims++
                }
                
                // Add geotag based on landing
                SoCalLandings.findByName(landingName)?.let { landing ->
                    FishingIntelDb.saveReportGeo(
                        reportId,
                        landing.lat,
                        landing.lon,
                        GeoType.LANDING_ANCHOR,
                        landing.radiusKm * 1000
                    )
                }
            }
        }
        
        return reports to claims
    }
    
    /**
     * Scrape SanDiegoFishReports (same pattern as SoCal).
     */
    private suspend fun scrapeSanDiegoFishReports(): Pair<Int, Int> {
        logger.info("Scraping SanDiegoFishReports...")
        var reports = 0
        var claims = 0
        
        val today = LocalDate.now()
        val dateFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
        
        for (daysBack in 0..7) {
            val date = today.minusDays(daysBack.toLong())
            val url = "https://www.sandiegofishreports.com/dock_totals/boats.php?date=${date.format(dateFormatter)}"
            
            val doc = fetchWithRetry(url, RateLimiters.sanDiegoFishReports) ?: continue
            
            FishingIntelDb.saveRawPage("san-diego-fish-reports", url, doc.html(), 200, null, null)
            
            val (r, c) = parseSoCalFishReportsPage(doc, url, date) // Same format
            reports += r
            claims += c
            
            delay(1000)
        }
        
        return reports to claims
    }
    
    /**
     * Scrape 976-TUNA counts and regional reports.
     */
    private suspend fun scrape976Tuna(): Pair<Int, Int> {
        logger.info("Scraping 976-TUNA...")
        var reports = 0
        var claims = 0
        
        // Scrape counts page
        val countsUrl = "https://www.976-tuna.com/counts"
        val countsDoc = fetchWithRetry(countsUrl, RateLimiters.tuna976)
        
        if (countsDoc != null) {
            FishingIntelDb.saveRawPage("976-tuna", countsUrl, countsDoc.html(), 200, null, null)
            val (r, c) = parse976TunaCounts(countsDoc, countsUrl)
            reports += r
            claims += c
        }
        
        delay(2000)
        
        // Scrape San Diego regional reports
        val sdUrl = "https://www.976-tuna.com/san-diego-fish-reports"
        val sdDoc = fetchWithRetry(sdUrl, RateLimiters.tuna976)
        
        if (sdDoc != null) {
            FishingIntelDb.saveRawPage("976-tuna", sdUrl, sdDoc.html(), 200, null, null)
            val (r, c) = parse976TunaRegional(sdDoc, sdUrl)
            reports += r
            claims += c
        }
        
        return reports to claims
    }
    
    private fun parse976TunaCounts(doc: Document, url: String): Pair<Int, Int> {
        var reports = 0
        var claims = 0
        
        // Look for daily totals section
        val totalsSection = doc.select("div:contains(Caught:)")
        
        for (section in totalsSection) {
            val text = section.text()
            if (!text.contains("Caught:")) continue
            
            // Extract date
            val dateMatch = Regex("""(\w+ \w+ \d+(?:st|nd|rd|th) \d{4})""").find(text)
            val date = dateMatch?.let { DateParser.parse976TunaCounts(it.value) } ?: LocalDate.now()
            
            // Extract fish counts from "Caught: X Species, Y Species Released"
            val countsMatch = Regex("""Caught:\s*(.+)""").find(text)
            val countsText = countsMatch?.groupValues?.get(1) ?: continue
            
            val fishCounts = CountsParser.parse(countsText)
            if (fishCounts.isEmpty()) continue
            
            val fingerprint = Deduplicator.buildFingerprint(
                "976-TUNA", "Daily Totals", "Daily", date, null, fishCounts
            )
            
            if (FishingIntelDb.fingerprintExists(fingerprint)) continue
            
            val report = FishingReport(
                sourceId = "976-tuna",
                url = url,
                publishedAt = date.atStartOfDay().toInstant(ZoneOffset.UTC),
                observedAt = Instant.now(),
                reportType = ReportType.DOCK_TOTAL,
                title = "976-TUNA Daily Totals",
                rawExcerpt = countsText.take(200),
                fingerprint = fingerprint,
                confidence = 1.0
            )
            
            val reportId = FishingIntelDb.saveReport(report)
            reports++
            
            for ((species, kept, released) in fishCounts) {
                val claim = FishingClaim(
                    claimType = ClaimType.CATCH,
                    species = SpeciesNormalizer.normalize(species),
                    countKept = kept,
                    countReleased = released,
                    landingName = "976-TUNA Aggregate"
                )
                FishingIntelDb.saveClaim(reportId, claim)
                claims++
            }
            
            // Geotag to San Diego region center
            FishingIntelDb.saveReportGeo(reportId, 32.7157, -117.1611, GeoType.REGION_FALLBACK, 50000)
        }
        
        return reports to claims
    }
    
    private fun parse976TunaRegional(doc: Document, url: String): Pair<Int, Int> {
        var reports = 0
        var claims = 0
        
        // Find post entries
        val posts = doc.select("div.post, article, div.entry")
        
        for (post in posts) {
            val title = post.select("h2, h3, .title").text()
            val content = post.text()
            val timeText = post.select("time, .date, .posted").text()
            
            if (content.isBlank()) continue
            
            // Parse date from "Thu Feb 5th 3:38 PM" format
            val parsedDateTime = DateParser.parse976TunaReports(timeText)
            val publishedInstant = parsedDateTime?.toInstant() 
                ?: LocalDate.now().atStartOfDay().toInstant(ZoneOffset.UTC)
            
            // Look for targeting mentions
            val targetingMatch = Regex("""(?:targeting|target|going for)\s+([^.]+)""", RegexOption.IGNORE_CASE).find(content)
            
            // Look for catch mentions
            val catchMatch = Regex("""(?:caught|landed|got|boated)\s+(\d+)\s+(\w+)""", RegexOption.IGNORE_CASE).find(content)
            
            if (targetingMatch == null && catchMatch == null) continue
            
            val fingerprint = java.security.MessageDigest.getInstance("SHA-256")
                .digest("$url|$title|${publishedInstant}".toByteArray())
                .joinToString("") { "%02x".format(it) }
            
            if (FishingIntelDb.fingerprintExists(fingerprint)) continue
            
            val report = FishingReport(
                sourceId = "976-tuna",
                url = url,
                publishedAt = publishedInstant,
                observedAt = Instant.now(),
                reportType = ReportType.NARRATIVE,
                title = title.take(100),
                rawExcerpt = content.take(300),
                fingerprint = fingerprint,
                confidence = 0.8
            )
            
            val reportId = FishingIntelDb.saveReport(report)
            reports++
            
            // Add targeting claim
            targetingMatch?.let { match ->
                val species = match.groupValues[1].split(Regex("""\s*(?:and|,|/)\s*"""))
                for (sp in species) {
                    val claim = FishingClaim(
                        claimType = ClaimType.TARGETING,
                        species = SpeciesNormalizer.normalize(sp.trim()),
                        notes = match.value
                    )
                    FishingIntelDb.saveClaim(reportId, claim)
                    claims++
                }
            }
            
            // Add catch claim
            catchMatch?.let { match ->
                val count = match.groupValues[1].toIntOrNull() ?: 0
                val species = match.groupValues[2]
                val claim = FishingClaim(
                    claimType = ClaimType.CATCH,
                    species = SpeciesNormalizer.normalize(species),
                    countKept = count,
                    notes = match.value
                )
                FishingIntelDb.saveClaim(reportId, claim)
                claims++
            }
            
            // Try to extract place mentions for geotagging
            val places = SoCalGazetteer.findInText(content)
            for (place in places) {
                FishingIntelDb.saveReportGeo(reportId, place.lat, place.lon, GeoType.PLACE_MENTION, place.radiusKm * 1000)
            }
            
            // Default geotag if no places found
            if (places.isEmpty()) {
                FishingIntelDb.saveReportGeo(reportId, 32.7157, -117.1611, GeoType.REGION_FALLBACK, 50000)
            }
        }
        
        return reports to claims
    }
}
