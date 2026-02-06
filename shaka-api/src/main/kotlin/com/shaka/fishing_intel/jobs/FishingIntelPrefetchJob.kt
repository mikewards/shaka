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
        
        // Scrape counts page which has current daily totals (local boats)
        val mainUrl = "https://www.976-tuna.com/counts"
        val mainDoc = fetchWithRetry(mainUrl, RateLimiters.tuna976)
        
        if (mainDoc != null) {
            FishingIntelDb.saveRawPage("976-tuna", mainUrl, mainDoc.html(), 200, null, null)
            val (r, c) = parse976TunaMain(mainDoc, mainUrl)
            reports += r
            claims += c
        }
        
        // Scrape long-range posts for offshore action (tuna, wahoo, yellowtail)
        val longRangeUrl = "https://www.976-tuna.com/posts/long-range"
        val longRangeDoc = fetchWithRetry(longRangeUrl, RateLimiters.tuna976)
        
        if (longRangeDoc != null) {
            FishingIntelDb.saveRawPage("976-tuna-longrange", longRangeUrl, longRangeDoc.html(), 200, null, null)
            val (r, c) = parse976TunaLongRange(longRangeDoc, longRangeUrl)
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
    
    /**
     * Parse 976-TUNA long-range posts page for offshore action.
     * Extracts trip reports from long-range boats (Independence, Red Rooster, Excel, etc.)
     */
    private fun parse976TunaLongRange(doc: Document, url: String): Pair<Int, Int> {
        var reports = 0
        var claims = 0
        
        // Find all post links - they contain boat names and report content
        val postLinks = doc.select("a[href*='/posts/']")
        val processedPosts = mutableSetOf<String>()
        
        for (postLink in postLinks) {
            try {
                val postUrl = postLink.attr("href")
                if (postUrl.isBlank() || processedPosts.contains(postUrl)) continue
                if (!postUrl.contains("/posts/") || postUrl.contains("/long-range")) continue
                
                val linkText = postLink.text().trim()
                if (!linkText.contains("Fish Report", ignoreCase = true)) continue
                
                processedPosts.add(postUrl)
                
                // Extract boat name from link text (e.g., "Independence Long Range Sportfishing Fish Report")
                val boatName = linkText
                    .replace(Regex("""(?i)\s*Long[- ]?Range.*Fish Report.*"""), "")
                    .replace(Regex("""(?i)\s*Fish Report.*"""), "")
                    .trim()
                
                if (boatName.isBlank()) continue
                
                // Find the date and report text in siblings
                var dateText: String? = null
                var reportText: String? = null
                var currentElement = postLink.parent()
                
                // Look for date pattern like "Wed Feb 4th 8:26 PM"
                for (i in 0..10) {
                    if (currentElement == null) break
                    val text = currentElement.text()
                    
                    // Look for date pattern
                    if (dateText == null) {
                        val dateMatch = Regex("""(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d+(?:st|nd|rd|th)\s+\d+:\d+\s*(?:AM|PM)""", RegexOption.IGNORE_CASE).find(text)
                        if (dateMatch != null) {
                            dateText = dateMatch.value
                        }
                    }
                    
                    // Check if we've found the report text (longer text after date)
                    if (text.length > 100 && !text.contains("Fish Report")) {
                        reportText = text
                        break
                    }
                    
                    currentElement = currentElement.nextElementSibling() ?: currentElement.parent()
                }
                
                // If no report text found, try to get text from parent container
                if (reportText == null) {
                    reportText = postLink.parent()?.parent()?.text() ?: ""
                }
                
                if (reportText.isBlank()) continue
                
                // Parse date or use today
                val reportDate = if (dateText != null) {
                    try {
                        DateParser.parse976TunaPost(dateText) ?: LocalDate.now()
                    } catch (e: Exception) {
                        LocalDate.now()
                    }
                } else LocalDate.now()
                
                // Extract fish species and counts from report text
                val fishClaims = parseLongRangeReportText(reportText)
                if (fishClaims.isEmpty()) continue
                
                val fingerprint = Deduplicator.buildFingerprint(
                    "976-TUNA-LR", boatName, postUrl, reportDate, null, fishClaims
                )
                
                if (FishingIntelDb.fingerprintExists(fingerprint)) continue
                
                val fullPostUrl = if (postUrl.startsWith("http")) postUrl else "https://www.976-tuna.com$postUrl"
                
                val report = FishingReport(
                    sourceId = "976-tuna",
                    url = fullPostUrl,
                    publishedAt = reportDate.atStartOfDay().toInstant(ZoneOffset.UTC),
                    observedAt = Instant.now(),
                    reportType = ReportType.NARRATIVE,
                    title = "$boatName Long Range - ${reportDate}",
                    rawExcerpt = reportText.take(300),
                    fingerprint = fingerprint,
                    confidence = 0.9
                )
                
                val reportId = FishingIntelDb.saveReport(report)
                reports++
                
                for (fishCount in fishClaims) {
                    val claim = FishingClaim(
                        claimType = ClaimType.CATCH,
                        species = SpeciesNormalizer.normalize(fishCount.species),
                        countKept = fishCount.kept,
                        countReleased = fishCount.released,
                        boatName = boatName,
                        landingName = "Long Range Fleet"
                    )
                    FishingIntelDb.saveClaim(reportId, claim)
                    claims++
                }
                
                // Geotag to San Diego (where long-range boats depart) with large radius
                // so data shows up for all SoCal coastal spots
                FishingIntelDb.saveReportGeo(reportId, 32.7157, -117.1611, GeoType.REGION_FALLBACK, 150000)
                
            } catch (e: Exception) {
                logger.debug("Error parsing 976-TUNA long-range post: ${e.message}")
            }
        }
        
        return reports to claims
    }
    
    /**
     * Parse long-range report text to extract species and estimated counts.
     * Looks for patterns like:
     * - "21 bluefin over 100 pounds"
     * - "nice yellowfin from 40 to 130 lbs"
     * - "252 pounder" / "200 pound class"
     * - "bluefin and yellowfin"
     */
    private fun parseLongRangeReportText(text: String): List<FishCount> {
        val claims = mutableListOf<FishCount>()
        val textLower = text.lowercase()
        
        // Species to look for in long-range reports
        val offshoreSpecies = mapOf(
            "bluefin" to "Bluefin Tuna",
            "yellowfin" to "Yellowfin Tuna",
            "bigeye" to "Bigeye Tuna",
            "yellowtail" to "Yellowtail",
            "wahoo" to "Wahoo",
            "dorado" to "Dorado",
            "mahi" to "Dorado",
            "swordfish" to "Swordfish",
            "marlin" to "Marlin",
            "skipjack" to "Skipjack Tuna",
            "tuna" to "Tuna"  // Generic tuna if not specified
        )
        
        // Look for count patterns first: "21 bluefin", "a couple of bluefin", etc.
        val countPatterns = listOf(
            Regex("""(\d+)\s+(bluefin|yellowfin|bigeye|yellowtail|wahoo|dorado|mahi|swordfish|marlin|skipjack|tuna)""", RegexOption.IGNORE_CASE),
            Regex("""(bluefin|yellowfin|bigeye|yellowtail|wahoo|dorado|mahi|swordfish|marlin|skipjack|tuna)[s]?\s+(?:from|ranging|between)?\s*(\d+)""", RegexOption.IGNORE_CASE)
        )
        
        val foundSpecies = mutableSetOf<String>()
        
        // Try count patterns first
        for (pattern in countPatterns) {
            val matches = pattern.findAll(text)
            for (match in matches) {
                val groups = match.groupValues
                val count = groups.find { it.matches(Regex("""\d+""")) }?.toIntOrNull()
                val speciesKey = groups.find { offshoreSpecies.containsKey(it.lowercase()) }?.lowercase()
                
                if (speciesKey != null && !foundSpecies.contains(speciesKey)) {
                    val normalizedSpecies = offshoreSpecies[speciesKey] ?: continue
                    // Don't double count generic "tuna" if we found specific tuna
                    if (speciesKey == "tuna" && (foundSpecies.contains("bluefin") || foundSpecies.contains("yellowfin"))) continue
                    
                    foundSpecies.add(speciesKey)
                    claims.add(FishCount(normalizedSpecies, count ?: 1, 0))
                }
            }
        }
        
        // Also check for species mentioned without counts
        for ((key, normalized) in offshoreSpecies) {
            if (foundSpecies.contains(key)) continue
            if (key == "tuna" && (foundSpecies.contains("bluefin") || foundSpecies.contains("yellowfin"))) continue
            
            if (textLower.contains(key)) {
                foundSpecies.add(key)
                claims.add(FishCount(normalized, 1, 0))
            }
        }
        
        return claims
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
    
    // =============================================================================
    // BD Outdoors Forum Explorer (for data analysis)
    // =============================================================================
    
    /**
     * Explore BD Outdoors forum structure and dump sample data for analysis.
     * This is a development/analysis function, not for production scraping.
     */
    /**
     * Explore BD Outdoors using pre-exported cookies (bypasses Cloudflare).
     */
    suspend fun exploreBDOutdoorsWithCookies(cookieString: String): String {
        val results = StringBuilder()
        results.appendLine("=== BD Outdoors Forum Exploration (Cookie Mode) ===\n")
        
        val session = com.shaka.fishing_intel.auth.BDOutdoorsSession
        val cookiesLoaded = session.setCookiesFromString(cookieString)
        results.appendLine("Cookies loaded: ${if (cookiesLoaded) "SUCCESS" else "FAILED"}")
        results.appendLine("Cookies: ${session.getCookies().keys}\n")
        
        if (!cookiesLoaded) {
            return results.toString()
        }
        
        return exploreBDOutdoorsInternal(results, session)
    }
    
    suspend fun exploreBDOutdoors(username: String, password: String): String {
        val results = StringBuilder()
        results.appendLine("=== BD Outdoors Forum Exploration (Login Mode) ===\n")
        
        // Login
        val session = com.shaka.fishing_intel.auth.BDOutdoorsSession
        val loginSuccess = session.login(username, password)
        results.appendLine("Login: ${if (loginSuccess) "SUCCESS" else "FAILED"}")
        
        // Include debug info
        results.appendLine("\n--- Login Debug Info ---")
        results.appendLine(session.lastLoginDebug)
        results.appendLine("--- End Debug Info ---\n")
        
        if (!loginSuccess) {
            return results.toString()
        }
        
        return exploreBDOutdoorsInternal(results, session)
    }
    
    private suspend fun exploreBDOutdoorsInternal(
        results: StringBuilder,
        session: com.shaka.fishing_intel.auth.BDOutdoorsSession
    ): String {
        
        // Delay to be polite
        delay(2000)
        
        // Fishing Reports category page
        val fishingReportsUrl = "https://www.bdoutdoors.com/forums/categories/fishing-reports.399/"
        results.appendLine("--- Fishing Reports Category ---")
        results.appendLine("URL: $fishingReportsUrl\n")
        
        val categoryPage = session.fetchAuthenticated(fishingReportsUrl)
        if (categoryPage == null) {
            results.appendLine("FAILED to fetch category page")
            results.appendLine("Error: ${session.lastFetchError}")
            return results.toString()
        }
        
        // List all sub-forums in this category
        val subForums = categoryPage.select("a[href*='/forums/']")
            .toList()
            .filter { it.attr("href").contains("/forums/forums/") }
            .map { it.text().trim() to it.attr("href") }
            .filter { it.first.isNotBlank() }
            .distinctBy { it.second }
        
        results.appendLine("Sub-forums found: ${subForums.size}")
        subForums.forEach { (name, url) -> results.appendLine("  - $name: $url") }
        results.appendLine("")
        
        // Try to find Southern California related forums
        val socalForums = subForums.filter { (name, _) -> 
            name.contains("southern", ignoreCase = true) || 
            name.contains("socal", ignoreCase = true) ||
            name.contains("california", ignoreCase = true)
        }
        results.appendLine("SoCal forums: ${socalForums.size}")
        socalForums.forEach { (name, url) -> results.appendLine("  - $name: $url") }
        results.appendLine("")
        
        // Fetch first SoCal forum or first available forum
        val targetForum = socalForums.firstOrNull() ?: subForums.firstOrNull()
        if (targetForum == null) {
            results.appendLine("No forums found to explore")
            return results.toString()
        }
        
        delay(3000)  // Polite delay
        
        val (forumName, forumUrl) = targetForum
        val fullForumUrl = if (forumUrl.startsWith("http")) forumUrl else "https://www.bdoutdoors.com$forumUrl"
        results.appendLine("--- Exploring: $forumName ---")
        results.appendLine("URL: $fullForumUrl\n")
        
        val forumPage = session.fetchAuthenticated(fullForumUrl)
        if (forumPage == null) {
            results.appendLine("FAILED to fetch forum page")
            results.appendLine("Error: ${session.lastFetchError}")
            return results.toString()
        }
        
        // Find thread listings
        val threads = forumPage.select(".structItem--thread, .structItem, [class*=thread]")
        results.appendLine("Found ${threads.size} thread elements\n")
        
        // Debug: show HTML structure if no threads found
        if (threads.isEmpty()) {
            results.appendLine("DEBUG - Page title: ${forumPage.title()}")
            results.appendLine("DEBUG - Body classes: ${forumPage.body().className()}")
            val allDivs = forumPage.select("div[class]").take(20)
            results.appendLine("DEBUG - First 20 div classes:")
            allDivs.forEach { results.appendLine("  ${it.className()}") }
        }
        
        // Analyze first 5 threads
        for ((index, thread) in threads.take(5).withIndex()) {
            results.appendLine("--- Thread ${index + 1} ---")
            
            // Title
            val titleEl = thread.selectFirst("a[href*='/threads/']")
            val title = titleEl?.text() ?: "NO TITLE"
            val threadUrl = titleEl?.absUrl("href") ?: ""
            results.appendLine("Title: $title")
            results.appendLine("URL: $threadUrl")
            
            // Author
            val author = thread.selectFirst("a.username, [class*=username]")?.text() ?: "unknown"
            results.appendLine("Author: $author")
            
            // Date
            val dateEl = thread.selectFirst("time")
            val date = dateEl?.attr("datetime") ?: dateEl?.text() ?: "unknown"
            results.appendLine("Date: $date")
            
            results.appendLine("")
        }
        
        // Now fetch one thread to see post structure
        val firstThreadUrl = threads.firstOrNull()?.selectFirst("a[href*='/threads/']")?.absUrl("href")
        if (firstThreadUrl != null && firstThreadUrl.isNotBlank()) {
            delay(3000)  // Polite delay
            
            results.appendLine("\n=== SAMPLE POST DETAIL ===")
            results.appendLine("Fetching: $firstThreadUrl\n")
            
            val threadPage = session.fetchAuthenticated(firstThreadUrl)
            if (threadPage != null) {
                // First post content
                val firstPost = threadPage.selectFirst("article.message, .message--post, [class*=message]")
                if (firstPost != null) {
                    // Post author
                    val postAuthor = firstPost.selectFirst("a.username, [class*=username]")?.text() ?: "unknown"
                    results.appendLine("Post Author: $postAuthor")
                    
                    // Post date
                    val postDate = firstPost.selectFirst("time")?.attr("datetime") ?: "unknown"
                    results.appendLine("Post Date: $postDate")
                    
                    // Post content
                    val content = firstPost.selectFirst(".message-body, .bbWrapper, [class*=content]")?.text() ?: firstPost.text()
                    results.appendLine("\nPost Content (first 1500 chars):")
                    results.appendLine(content.take(1500))
                    
                    // Look for any structured data (images, attachments)
                    val images = firstPost.select("img")
                    results.appendLine("\nImages found: ${images.size}")
                    
                    // Check for location tags or other metadata
                    val tags = threadPage.select(".tagList a, .p-tags a, [class*=tag] a")
                    if (tags.isNotEmpty()) {
                        results.appendLine("Tags: ${tags.joinToString(", ") { it.text() }}")
                    }
                } else {
                    results.appendLine("Could not find post content element")
                    results.appendLine("DEBUG - Page title: ${threadPage.title()}")
                }
            } else {
                results.appendLine("FAILED to fetch thread page")
                results.appendLine("Error: ${session.lastFetchError}")
            }
        }
        
        return results.toString()
    }
}
