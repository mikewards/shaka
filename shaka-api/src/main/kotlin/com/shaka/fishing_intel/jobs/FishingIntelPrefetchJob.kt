package com.shaka.fishing_intel.jobs

import com.shaka.fishing_intel.api.FishingIntelRoutes
import com.shaka.fishing_intel.db.FishingIntelDb
import kotlinx.coroutines.*
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.slf4j.LoggerFactory

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
                    // bd-outdoors is ingested via external scraper POST endpoint, not here
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

        // Pre-generate AI insights for the current time slot so the request path never blocks on AI
        try {
            FishingIntelRoutes.prefetchRegionInsights("so_cal")
        } catch (e: Exception) {
            logger.warn("Region insight pre-generation failed: ${e.message}")
        }
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
        
        // Debug: show page info
        results.appendLine("Page title: ${categoryPage.title()}")
        results.appendLine("Body length: ${categoryPage.body().text().length} chars")
        
        // Find ALL links on the page for debugging
        val allLinks = categoryPage.select("a[href]").toList().take(30)
        results.appendLine("\nFirst 30 links on page:")
        allLinks.forEach { results.appendLine("  ${it.text().take(50)} -> ${it.attr("href")}") }
        results.appendLine("")
        
        // List all sub-forums in this category
        val subForums = categoryPage.select("a[href*='/forums/']")
            .toList()
            .filter { it.attr("href").contains("/forums/forums/") || it.attr("href").matches(Regex(".*/forums/[a-z-]+\\.\\d+/")) }
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
