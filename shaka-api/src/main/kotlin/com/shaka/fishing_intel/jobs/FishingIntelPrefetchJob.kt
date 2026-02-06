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
import org.jsoup.nodes.Element
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
    
    const val USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    
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
                    "22nd-street" -> scrape22ndStreet()
                    "fishermans-landing" -> scrapeFishermansLanding()
                    "seaforth" -> scrapeSeaforth()
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
    
    // =============================================================================
    // SoCalFishReports Scraper
    // =============================================================================
    
    /**
     * Scrape SoCalFishReports boat counts.
     * URL: https://www.socalfishreports.com/dock_totals/boats.php?date=YYYY-MM-DD
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
            
            // Parse the HTML - structure uses tables with boat rows
            val (r, c) = parseFishReportsPage(doc, url, date, "socal-fish-reports")
            reports += r
            claims += c
            
            logger.debug("SoCalFishReports $date: $r reports, $c claims")
            delay(1500) // Be nice
        }
        
        logger.info("SoCalFishReports total: $reports reports, $claims claims")
        return reports to claims
    }
    
    /**
     * Parse SoCalFishReports/SanDiegoFishReports page format.
     * Table structure: Boat | Trip Details | Dock Totals | Audio
     */
    private fun parseFishReportsPage(doc: Document, url: String, date: LocalDate, sourceId: String): Pair<Int, Int> {
        var reports = 0
        var claims = 0
        
        // Find all tables on the page
        val tables = doc.select("table")
        logger.debug("Found ${tables.size} tables")
        
        for (table in tables) {
            val rows = table.select("tr")
            
            for (row in rows) {
                try {
                    // Skip header rows
                    if (row.select("th").isNotEmpty()) continue
                    
                    val cells = row.select("td")
                    if (cells.size < 3) continue
                    
                    // Cell 0: Boat name (inside an anchor or bold)
                    val boatCell = cells[0]
                    val boatLink = boatCell.selectFirst("a")
                    val boatName = boatLink?.text()?.trim() 
                        ?: boatCell.selectFirst("b, strong")?.text()?.trim()
                        ?: boatCell.ownText().trim()
                    
                    if (boatName.isBlank()) continue
                    
                    // Landing name - look for second link or landing reference
                    val landingLink = boatCell.select("a").getOrNull(1)
                    val landingName = landingLink?.text()?.trim() ?: extractLandingFromCell(boatCell)
                    
                    // City - might be in the same cell after landing
                    val cityMatch = Regex("""([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*),\s*CA""").find(boatCell.text())
                    val city = cityMatch?.groupValues?.get(1)
                    
                    // Cell 1: Trip Details - "X Anglers\nTrip Type"
                    val tripCell = cells[1]
                    val tripText = tripCell.text()
                    val anglersMatch = Regex("""(\d+)\s*Anglers?""", RegexOption.IGNORE_CASE).find(tripText)
                    val anglers = anglersMatch?.groupValues?.get(1)?.toIntOrNull()
                    
                    val tripType = extractTripType(tripText)
                    
                    // Cell 2: Dock Totals - "12 Sand Bass, 1 Halibut, 90 Whitefish"
                    val totalsCell = cells[2]
                    val dockTotals = totalsCell.text().trim()
                    
                    if (dockTotals.isBlank() || dockTotals.equals("no report", ignoreCase = true)) continue
                    
                    // Parse fish counts
                    val fishCounts = CountsParser.parse(dockTotals)
                    if (fishCounts.isEmpty()) {
                        logger.debug("No fish counts parsed from: $dockTotals")
                        continue
                    }
                    
                    // Build fingerprint for deduplication
                    val fingerprint = Deduplicator.buildFingerprint(
                        landingName ?: "Unknown", boatName, tripType, date, anglers, fishCounts
                    )
                    
                    // Skip if already exists
                    if (FishingIntelDb.fingerprintExists(fingerprint)) continue
                    
                    // Create report
                    val report = FishingReport(
                        sourceId = sourceId,
                        url = url,
                        publishedAt = date.atStartOfDay().toInstant(ZoneOffset.UTC),
                        observedAt = date.atStartOfDay().toInstant(ZoneOffset.UTC),
                        reportType = ReportType.FISH_COUNT,
                        title = "$boatName - ${tripType ?: "Fishing Trip"}",
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
                    val landing = landingName?.let { SoCalLandings.findByName(it) }
                    if (landing != null) {
                        FishingIntelDb.saveReportGeo(
                            reportId,
                            landing.lat,
                            landing.lon,
                            GeoType.LANDING_ANCHOR,
                            landing.radiusKm * 1000
                        )
                    }
                } catch (e: Exception) {
                    logger.debug("Error parsing row: ${e.message}")
                }
            }
        }
        
        return reports to claims
    }
    
    private fun extractLandingFromCell(cell: Element): String? {
        // Look for landing link
        val links = cell.select("a")
        for (link in links) {
            val href = link.attr("href")
            if (href.contains("landing")) {
                return link.text().trim()
            }
        }
        // Look for text after boat name
        val text = cell.text()
        val landingMatch = Regex("""(?:Landing|Sportfishing)[:\s]+([^,]+)""", RegexOption.IGNORE_CASE).find(text)
        return landingMatch?.groupValues?.get(1)?.trim()
    }
    
    private fun extractTripType(text: String): String? {
        val tripPatterns = listOf(
            "1/2 Day AM", "1/2 Day PM", "1/2 Day", "Half Day",
            "3/4 Day", "Full Day", "Full-Day",
            "1.5 Day", "1.5-Day", "Overnight",
            "2 Day", "2-Day", "2.5 Day", "2.5-Day",
            "3 Day", "3-Day"
        )
        for (pattern in tripPatterns) {
            if (text.contains(pattern, ignoreCase = true)) {
                return pattern
            }
        }
        return null
    }
    
    // =============================================================================
    // SanDiegoFishReports Scraper
    // =============================================================================
    
    /**
     * Scrape SanDiegoFishReports (same format as SoCal).
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
            
            val (r, c) = parseFishReportsPage(doc, url, date, "san-diego-fish-reports")
            reports += r
            claims += c
            
            logger.debug("SanDiegoFishReports $date: $r reports, $c claims")
            delay(1500)
        }
        
        logger.info("SanDiegoFishReports total: $reports reports, $claims claims")
        return reports to claims
    }
    
    // =============================================================================
    // 976-TUNA Scraper
    // =============================================================================
    
    /**
     * Scrape 976-TUNA main page for daily totals and individual landing counts.
     */
    private suspend fun scrape976Tuna(): Pair<Int, Int> {
        logger.info("Scraping 976-TUNA...")
        var reports = 0
        var claims = 0
        
        // Scrape counts page which has current daily totals
        val mainUrl = "https://www.976-tuna.com/counts"
        val mainDoc = fetchWithRetry(mainUrl, RateLimiters.tuna976)
        
        if (mainDoc != null) {
            FishingIntelDb.saveRawPage("976-tuna", mainUrl, mainDoc.html(), 200, null, null)
            val (r, c) = parse976TunaMain(mainDoc, mainUrl)
            reports += r
            claims += c
        }
        
        logger.info("976-TUNA total: $reports reports, $claims claims")
        return reports to claims
    }
    
    /**
     * Parse 976-TUNA main page.
     * Structure includes:
     * - Daily totals section with "Caught : X rockfish, Y bass, ..."
     * - Individual landing sections with boat counts
     */
    private fun parse976TunaMain(doc: Document, url: String): Pair<Int, Int> {
        var reports = 0
        var claims = 0
        
        // Find the Fish Counts section - look for headers with date patterns
        // Pattern: **Thursday June 13th 2024 Totals**
        val dateHeaders = doc.getElementsMatchingOwnText("""(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\s+\w+\s+\d+(?:st|nd|rd|th)\s+\d{4}""".toRegex().toPattern())
        
        for (header in dateHeaders) {
            try {
                val headerText = header.text()
                if (!headerText.contains("Totals", ignoreCase = true)) continue
                
                // Parse date from header
                val date = DateParser.parse976TunaCounts(headerText) ?: LocalDate.now()
                
                // Find the "Caught :" line - look in siblings and next elements
                var currentElement: Element? = header.nextElementSibling()
                var caughtText: String? = null
                
                // Search for Caught text in nearby elements
                for (i in 0..10) {
                    if (currentElement == null) break
                    val text = currentElement.text()
                    if (text.contains("Caught", ignoreCase = true)) {
                        caughtText = text
                        break
                    }
                    currentElement = currentElement.nextElementSibling()
                }
                
                // Also search in parent's text
                if (caughtText == null) {
                    val parentText = header.parent()?.text() ?: ""
                    val caughtMatch = Regex("""Caught\s*:\s*(.+?)(?:\.|$)""", RegexOption.IGNORE_CASE).find(parentText)
                    caughtText = caughtMatch?.value
                }
                
                if (caughtText == null) continue
                
                // Extract just the fish counts portion
                val countsMatch = Regex("""Caught\s*:\s*(.+)""", RegexOption.IGNORE_CASE).find(caughtText)
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
                    title = "976-TUNA Daily Totals - $date",
                    rawExcerpt = countsText.take(300),
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
                        landingName = "976-TUNA Daily Aggregate"
                    )
                    FishingIntelDb.saveClaim(reportId, claim)
                    claims++
                }
                
                // Geotag to San Diego/SoCal region center
                FishingIntelDb.saveReportGeo(reportId, 32.7157, -117.1611, GeoType.REGION_FALLBACK, 100000)
                
            } catch (e: Exception) {
                logger.debug("Error parsing 976-TUNA date section: ${e.message}")
            }
        }
        
        // Also parse individual landing sections
        // Pattern: **[Landing Name](url)** followed by trip/angler/fish info
        val landingSections = doc.select("a[href*='/landing/']")
        val processedLandings = mutableSetOf<String>()
        
        for (landingLink in landingSections) {
            try {
                val landingName = landingLink.text().trim()
                if (landingName.isBlank() || processedLandings.contains(landingName)) continue
                
                // Find the parent section containing fish counts
                var parent = landingLink.parent()
                var sectionText = ""
                
                // Walk up to find the full section
                for (i in 0..5) {
                    if (parent == null) break
                    sectionText = parent.text()
                    if (sectionText.contains("anglers", ignoreCase = true) && 
                        sectionText.contains("caught", ignoreCase = true)) {
                        break
                    }
                    parent = parent.parent()
                }
                
                if (!sectionText.contains("caught", ignoreCase = true)) continue
                
                // Extract trip count and anglers
                val tripsMatch = Regex("""(\d+)\s*trips?""", RegexOption.IGNORE_CASE).find(sectionText)
                val anglersMatch = Regex("""(\d+)\s*anglers?""", RegexOption.IGNORE_CASE).find(sectionText)
                val anglers = anglersMatch?.groupValues?.get(1)?.toIntOrNull()
                
                // Extract caught fish
                val caughtMatch = Regex("""caught[:\s]+(.+?)(?:\.|$)""", RegexOption.IGNORE_CASE).find(sectionText)
                val countsText = caughtMatch?.groupValues?.get(1) ?: continue
                
                val fishCounts = CountsParser.parse(countsText)
                if (fishCounts.isEmpty()) continue
                
                processedLandings.add(landingName)
                
                val today = LocalDate.now()
                val fingerprint = Deduplicator.buildFingerprint(
                    landingName, "All Boats", "Daily", today, anglers, fishCounts
                )
                
                if (FishingIntelDb.fingerprintExists(fingerprint)) continue
                
                val report = FishingReport(
                    sourceId = "976-tuna",
                    url = url,
                    publishedAt = today.atStartOfDay().toInstant(ZoneOffset.UTC),
                    observedAt = Instant.now(),
                    reportType = ReportType.DOCK_TOTAL,
                    title = "$landingName Daily - $today",
                    rawExcerpt = countsText.take(200),
                    fingerprint = fingerprint,
                    confidence = 0.95
                )
                
                val reportId = FishingIntelDb.saveReport(report)
                reports++
                
                for ((species, kept, released) in fishCounts) {
                    val claim = FishingClaim(
                        claimType = ClaimType.CATCH,
                        species = SpeciesNormalizer.normalize(species),
                        countKept = kept,
                        countReleased = released,
                        anglerCount = anglers,
                        landingName = landingName
                    )
                    FishingIntelDb.saveClaim(reportId, claim)
                    claims++
                }
                
                // Try to geotag based on landing name
                val landing = SoCalLandings.findByName(landingName)
                if (landing != null) {
                    FishingIntelDb.saveReportGeo(reportId, landing.lat, landing.lon, GeoType.LANDING_ANCHOR, landing.radiusKm * 1000)
                } else {
                    FishingIntelDb.saveReportGeo(reportId, 32.7157, -117.1611, GeoType.REGION_FALLBACK, 50000)
                }
                
            } catch (e: Exception) {
                logger.debug("Error parsing 976-TUNA landing section: ${e.message}")
            }
        }
        
        return reports to claims
    }
    
    // =============================================================================
    // 22nd Street Landing Scraper
    // =============================================================================
    
    /**
     * Scrape 22nd Street Landing via 976-tuna.com landing page.
     */
    private suspend fun scrape22ndStreet(): Pair<Int, Int> {
        logger.info("Scraping 22nd Street Landing...")
        return scrape976LandingPage(
            landingId = 14,
            landingSlug = "san-pedro-22nd-street-sportfishing",
            sourceId = "22nd-street",
            defaultLat = 33.7185,
            defaultLon = -118.2778,
            landingName = "22nd Street Landing"
        )
    }
    
    // =============================================================================
    // Fishermans Landing Scraper
    // =============================================================================
    
    /**
     * Scrape Fishermans Landing via 976-tuna.com landing page.
     */
    private suspend fun scrapeFishermansLanding(): Pair<Int, Int> {
        logger.info("Scraping Fishermans Landing...")
        return scrape976LandingPage(
            landingId = 2,
            landingSlug = "fishermans",
            sourceId = "fishermans-landing",
            defaultLat = 32.7157,
            defaultLon = -117.2251,
            landingName = "Fishermans Landing"
        )
    }
    
    // =============================================================================
    // Seaforth Landing Scraper  
    // =============================================================================
    
    /**
     * Scrape Seaforth Landing via 976-tuna.com landing page.
     */
    private suspend fun scrapeSeaforth(): Pair<Int, Int> {
        logger.info("Scraping Seaforth Landing...")
        return scrape976LandingPage(
            landingId = 4,
            landingSlug = "seaforth",
            sourceId = "seaforth",
            defaultLat = 32.7226,
            defaultLon = -117.2291,
            landingName = "Seaforth Landing"
        )
    }
    
    // =============================================================================
    // Generic 976-TUNA Landing Page Scraper
    // =============================================================================
    
    /**
     * Generic scraper for 976-tuna.com landing pages.
     * URL pattern: https://976-tuna.com/landing/{id}/{slug}/counts
     * 
     * Structure:
     * ## Date Header (e.g., "Wed February 4th 2026")
     * ##### The [Boat Name](url) with X anglers on a Trip Type caught Y fish1, Z fish2, ...
     */
    private suspend fun scrape976LandingPage(
        landingId: Int,
        landingSlug: String,
        sourceId: String,
        defaultLat: Double,
        defaultLon: Double,
        landingName: String
    ): Pair<Int, Int> {
        var reports = 0
        var claims = 0
        
        // Get current month's counts
        val now = LocalDate.now()
        val url = "https://976-tuna.com/landing/$landingId/$landingSlug/counts?m=${now.monthValue}&y=${now.year}"
        
        val doc = fetchWithRetry(url, RateLimiters.tuna976) ?: run {
            logger.warn("Failed to fetch $url")
            return 0 to 0
        }
        
        FishingIntelDb.saveRawPage(sourceId, url, doc.html(), 200, null, null)
        
        // Find date headers (h2 elements with date patterns)
        val dateHeaders = doc.select("h2")
        var currentDate: LocalDate? = null
        
        for (header in dateHeaders) {
            val headerText = header.text().trim()
            
            // Try to parse date from header (e.g., "Wed February 4th 2026")
            val parsedDate = DateParser.parse976TunaReportsDate(headerText)
            if (parsedDate != null) {
                currentDate = parsedDate
                continue
            }
        }
        
        // Parse h5 elements which contain individual boat reports
        // Pattern: "The [Boat](url) with X anglers on a Trip Type caught ..."
        val reportElements = doc.select("h5")
        
        for (reportEl in reportElements) {
            try {
                val text = reportEl.text()
                if (!text.contains("caught", ignoreCase = true)) continue
                
                // Extract boat name from link
                val boatLink = reportEl.selectFirst("a")
                val boatName = boatLink?.text()?.trim() ?: "Unknown Boat"
                
                // Extract anglers
                val anglersMatch = Regex("""with\s+(\d+)\s+anglers?""", RegexOption.IGNORE_CASE).find(text)
                val anglers = anglersMatch?.groupValues?.get(1)?.toIntOrNull()
                
                // Extract trip type
                val tripTypeMatch = Regex("""on\s+(?:a|an)\s+([^c]+?)(?:\s+caught)""", RegexOption.IGNORE_CASE).find(text)
                val tripType = tripTypeMatch?.groupValues?.get(1)?.trim()
                
                // Extract caught fish
                val caughtMatch = Regex("""caught\s+(.+?)(?:\.|$)""", RegexOption.IGNORE_CASE).find(text)
                val countsText = caughtMatch?.groupValues?.get(1) ?: continue
                
                val fishCounts = CountsParser.parse(countsText)
                if (fishCounts.isEmpty()) continue
                
                // Try to find date from nearest h2
                var reportDate = currentDate ?: LocalDate.now()
                var prev = reportEl.previousElementSibling()
                for (i in 0..20) {
                    if (prev == null) break
                    if (prev.tagName() == "h2") {
                        val dateText = prev.text()
                        val parsed = DateParser.parse976TunaReportsDate(dateText)
                        if (parsed != null) {
                            reportDate = parsed
                        }
                        break
                    }
                    prev = prev.previousElementSibling()
                }
                
                // Build fingerprint
                val fingerprint = Deduplicator.buildFingerprint(
                    landingName, boatName, tripType, reportDate, anglers, fishCounts
                )
                
                if (FishingIntelDb.fingerprintExists(fingerprint)) continue
                
                val report = FishingReport(
                    sourceId = sourceId,
                    url = url,
                    publishedAt = reportDate.atStartOfDay().toInstant(ZoneOffset.UTC),
                    observedAt = Instant.now(),
                    reportType = ReportType.FISH_COUNT,
                    title = "$boatName - ${tripType ?: "Trip"}",
                    rawExcerpt = countsText.take(200),
                    fingerprint = fingerprint,
                    confidence = 0.95
                )
                
                val reportId = FishingIntelDb.saveReport(report)
                reports++
                
                for ((species, kept, released) in fishCounts) {
                    val claim = FishingClaim(
                        claimType = ClaimType.CATCH,
                        species = SpeciesNormalizer.normalize(species),
                        countKept = kept,
                        countReleased = released,
                        tripType = tripType,
                        anglerCount = anglers,
                        boatName = boatName,
                        landingName = landingName
                    )
                    FishingIntelDb.saveClaim(reportId, claim)
                    claims++
                }
                
                // Geotag to landing location
                FishingIntelDb.saveReportGeo(reportId, defaultLat, defaultLon, GeoType.LANDING_ANCHOR, 20000)
                
            } catch (e: Exception) {
                logger.debug("Error parsing report element: ${e.message}")
            }
        }
        
        logger.info("$sourceId total: $reports reports, $claims claims")
        return reports to claims
    }
}
