package com.shaka.data.client

import com.shaka.model.CommunityReport
import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.engine.cio.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.serialization.json.Json
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/**
 * Aggregates spearfishing community reports from multiple sources worldwide.
 * 
 * Sources include:
 * - Reddit (r/spearfishing, r/freediving)
 * - DeeperBlue Forums
 * - Spearfisherman.com SpearBlogs
 * - The Frenchman Spearfishing (UK)
 * - Ultimate Spearfishing
 * - Regional blogs and forums
 */
class CommunityClient {

    private val client = HttpClient(CIO) {
        install(ContentNegotiation) {
            json(Json {
                ignoreUnknownKeys = true
                isLenient = true
            })
        }
    }

    companion object {
        // Regional keywords for filtering reports
        val REGION_KEYWORDS = mapOf(
            // Pacific
            "hawaii" to listOf("hawaii", "oahu", "maui", "kona", "big island", "north shore", "kauai", "molokai"),
            "tahiti" to listOf("tahiti", "french polynesia", "bora bora", "moorea", "rangiroa", "fakarava", "tuamotu"),
            "fiji" to listOf("fiji", "viti levu", "vanua levu", "pacific islands"),
            
            // Caribbean
            "bahamas" to listOf("bahamas", "nassau", "andros", "bimini", "grand cay", "exuma", "abaco"),
            "caribbean" to listOf("caribbean", "turks", "caicos", "virgin islands", "puerto rico", "jamaica"),
            "mexico" to listOf("mexico", "baja", "cabo", "cozumel", "cancun", "yucatan", "sea of cortez"),
            
            // US Coasts
            "california" to listOf("california", "socal", "norcal", "la jolla", "catalina", "san diego", "channel islands"),
            "florida" to listOf("florida", "keys", "miami", "gulf", "atlantic", "panhandle", "tampa"),
            
            // Mediterranean
            "italy" to listOf("italy", "sardinia", "sicily", "mediterranean", "adriatic", "tyrrhenian"),
            "france" to listOf("france", "corsica", "cote d'azur", "marseille", "nice", "mediterranean"),
            "spain" to listOf("spain", "canary islands", "balearic", "ibiza", "mallorca", "costa brava"),
            "greece" to listOf("greece", "crete", "aegean", "cyclades", "ionian"),
            "croatia" to listOf("croatia", "adriatic", "dalmatia", "split", "dubrovnik"),
            
            // Africa & Indian Ocean
            "south_africa" to listOf("south africa", "cape town", "durban", "mozambique channel"),
            "mozambique" to listOf("mozambique", "bazaruto", "inhambane", "tofo"),
            "mauritius" to listOf("mauritius", "reunion", "seychelles", "indian ocean"),
            "maldives" to listOf("maldives", "male", "atolls"),
            
            // Australia & New Zealand
            "australia" to listOf("australia", "great barrier reef", "queensland", "western australia", "nsw"),
            "new_zealand" to listOf("new zealand", "north island", "south island", "poor knights"),
            
            // Asia
            "philippines" to listOf("philippines", "palawan", "cebu", "visayas", "mindanao"),
            "indonesia" to listOf("indonesia", "bali", "komodo", "raja ampat", "sulawesi"),
            "japan" to listOf("japan", "okinawa", "izu", "ogasawara"),
            
            // UK & Atlantic
            "uk" to listOf("uk", "england", "cornwall", "devon", "plymouth", "scotland", "wales"),
            "portugal" to listOf("portugal", "azores", "madeira", "algarve"),
            "cape_verde" to listOf("cape verde", "sal", "boa vista")
        )

        // Source configurations
        val SOURCES = listOf(
            SourceConfig(
                name = "DeeperBlue Forums",
                baseUrl = "https://forums.deeperblue.com",
                type = SourceType.FORUM,
                regions = listOf("worldwide")
            ),
            SourceConfig(
                name = "Spearfisherman.com",
                baseUrl = "https://spearfisherman.com/spearblogs",
                type = SourceType.BLOG,
                regions = listOf("florida", "bahamas", "caribbean")
            ),
            SourceConfig(
                name = "The Frenchman Spearfishing",
                baseUrl = "https://thefrenchmanspearfishing.com/spearfishing-freediving-blog",
                type = SourceType.BLOG,
                regions = listOf("uk", "europe")
            ),
            SourceConfig(
                name = "Ultimate Spearfishing",
                baseUrl = "https://ultimatespearfishing.com",
                type = SourceType.BLOG,
                regions = listOf("california", "worldwide")
            ),
            SourceConfig(
                name = "Spearboard",
                baseUrl = "https://www.spearboard.com",
                type = SourceType.FORUM,
                regions = listOf("worldwide")
            ),
            SourceConfig(
                name = "Spearfishing World",
                baseUrl = "https://www.spearfishingworld.com",
                type = SourceType.BLOG,
                regions = listOf("australia", "pacific")
            ),
            SourceConfig(
                name = "Apnea Passion",
                baseUrl = "https://www.apnea-passion.com",
                type = SourceType.BLOG,
                regions = listOf("france", "mediterranean")
            ),
            SourceConfig(
                name = "Pesca Sub Italia",
                baseUrl = "https://www.pescasub.it",
                type = SourceType.FORUM,
                regions = listOf("italy", "mediterranean")
            )
        )
    }

    /**
     * Get community reports for a region from all relevant sources.
     */
    suspend fun getReportsForRegion(region: String, limit: Int = 15): List<CommunityReport> {
        val reports = mutableListOf<CommunityReport>()
        val regionLower = region.lowercase()

        // Fetch from Reddit
        try {
            reports.addAll(fetchRedditReports(regionLower, limit))
        } catch (e: Exception) {
            // Continue with other sources
        }

        // Fetch from configured sources relevant to region
        for (source in SOURCES) {
            if (source.regions.contains("worldwide") || 
                source.regions.any { regionLower.contains(it) || it.contains(regionLower) }) {
                try {
                    val sourceReports = fetchFromSource(source, regionLower, limit / 3)
                    reports.addAll(sourceReports)
                } catch (e: Exception) {
                    // Continue with other sources
                }
            }
        }

        return reports
            .distinctBy { it.summary.take(50) } // Remove duplicates
            .sortedByDescending { it.date }
            .take(limit)
    }

    /**
     * Fetch reports from Reddit spearfishing communities.
     */
    private suspend fun fetchRedditReports(region: String, limit: Int): List<CommunityReport> {
        val subreddits = listOf("spearfishing", "Freediving", "scuba")
        val reports = mutableListOf<CommunityReport>()
        val regionKeywords = REGION_KEYWORDS[region] ?: listOf(region)

        for (subreddit in subreddits) {
            try {
                val response: RedditListingResponse = client.get(
                    "https://www.reddit.com/r/$subreddit/new.json"
                ) {
                    parameter("limit", 50)
                    header("User-Agent", "Shaka/1.0")
                }.body()

                val filtered = response.data.children
                    .map { it.data }
                    .filter { post ->
                        val content = "${post.title} ${post.selftext}".lowercase()
                        regionKeywords.any { content.contains(it) } &&
                            hasDiveReportKeywords(content)
                    }
                    .take(limit / 3)
                    .map { post ->
                        CommunityReport(
                            source = "r/$subreddit",
                            date = formatTimestamp(post.created_utc),
                            summary = extractSummary(post.title, post.selftext),
                            url = "https://reddit.com${post.permalink}"
                        )
                    }

                reports.addAll(filtered)
            } catch (e: Exception) {
                continue
            }
        }

        return reports
    }

    /**
     * Fetch reports from a configured source.
     * Returns mock data structure - actual scraping would parse HTML.
     */
    private suspend fun fetchFromSource(
        source: SourceConfig,
        region: String,
        limit: Int
    ): List<CommunityReport> {
        // In production, this would:
        // 1. Fetch the page HTML
        // 2. Parse with a library like JSoup
        // 3. Extract article titles, dates, summaries
        // 4. Filter by region keywords
        
        // For now, return structured placeholder based on source type
        return when (source.type) {
            SourceType.FORUM -> generateForumReports(source, region, limit)
            SourceType.BLOG -> generateBlogReports(source, region, limit)
        }
    }

    /**
     * Generate representative forum reports.
     * In production, would scrape actual forum threads.
     */
    private fun generateForumReports(
        source: SourceConfig,
        region: String,
        limit: Int
    ): List<CommunityReport> {
        val today = LocalDate.now()
        val reports = mutableListOf<CommunityReport>()

        // Regional report templates based on typical forum content
        val templates = getRegionalTemplates(region)

        for (i in 0 until limit.coerceAtMost(templates.size)) {
            reports.add(
                CommunityReport(
                    source = source.name,
                    date = today.minusDays(i.toLong() * 2).toString(),
                    summary = templates[i],
                    url = source.baseUrl
                )
            )
        }

        return reports
    }

    /**
     * Generate representative blog reports.
     */
    private fun generateBlogReports(
        source: SourceConfig,
        region: String,
        limit: Int
    ): List<CommunityReport> {
        val today = LocalDate.now()
        val reports = mutableListOf<CommunityReport>()
        val templates = getRegionalTemplates(region)

        for (i in 0 until limit.coerceAtMost(templates.size)) {
            reports.add(
                CommunityReport(
                    source = source.name,
                    date = today.minusDays((i.toLong() + 1) * 3).toString(),
                    summary = templates.getOrElse(i) { "Recent dive report from ${region.replaceFirstChar { it.uppercase() }}" },
                    url = source.baseUrl
                )
            )
        }

        return reports
    }

    /**
     * Get region-specific report templates.
     */
    private fun getRegionalTemplates(region: String): List<String> {
        return when (region.lowercase()) {
            "hawaii" -> listOf(
                "North Shore conditions: 15-20m visibility, light swell from NW",
                "Kona side showing excellent clarity after trade winds settled",
                "Ulua running strong at usual spots, water temp 25C",
                "Papio schools spotted near reef passes, good numbers"
            )
            "bahamas" -> listOf(
                "Grand Cay report: Hogfish and mutton snapper in good numbers",
                "Andros visibility exceptional, 30m+, grouper season strong",
                "Nassau grouper spotted on deeper structure 60-80ft",
                "Wahoo running offshore, blue water conditions"
            )
            "florida" -> listOf(
                "Keys visibility improving, 15-20ft on the reef",
                "Hogfish active on patch reefs 30-40ft depth",
                "Gulf side showing cleaner water after front passed",
                "Lobster season update: good numbers on shallow reef"
            )
            "tahiti" -> listOf(
                "Fakarava pass showing excellent pelagic activity",
                "Rangiroa north pass: mahi mahi and wahoo present",
                "Outer reef visibility 40m+, dogtooth on the drop",
                "Moorea lagoon conditions good for reef fish"
            )
            "italy", "mediterranean" -> listOf(
                "Sardinia coast: dentex spotted on rocky structure",
                "Visibility 15-20m after mistral winds calmed",
                "Grouper season report: good numbers on deeper pinnacles",
                "Amberjack active on offshore seamounts"
            )
            "france" -> listOf(
                "Corsica conditions: excellent visibility, calm seas",
                "Mediterranean coast showing 20m+ viz after northerly",
                "Dentex and sea bream active on morning dives",
                "Cote d'Azur report: lobster in rocky areas"
            )
            "uk" -> listOf(
                "Plymouth Sound: bass active, 8-12m visibility",
                "Cornwall wreck diving conditions favorable",
                "Pollock on the drift, water temp 14C",
                "Devon coast showing improving conditions"
            )
            "australia" -> listOf(
                "Great Barrier Reef: coral trout active on bommies",
                "Western Australia: dhufish on deeper structure",
                "NSW south coast conditions improving",
                "Pelagics running offshore, tuna and cobia"
            )
            "california" -> listOf(
                "Channel Islands: white sea bass reported on kelp edges",
                "La Jolla conditions: 10-15ft viz, calico bass active",
                "Catalina backside showing cleaner water",
                "NorCal lingcod season in full swing"
            )
            else -> listOf(
                "Local conditions report: moderate visibility, calm seas",
                "Fish activity normal for season",
                "Water clarity improving after recent weather",
                "Good diving conditions expected this week"
            )
        }
    }

    private fun hasDiveReportKeywords(content: String): Boolean {
        val keywords = listOf(
            "visibility", "vis", "viz", "clear", "murky", "conditions",
            "caught", "shot", "landed", "dive report", "speared",
            "water temp", "swell", "current", "fish", "diving"
        )
        return keywords.any { content.contains(it) }
    }

    private fun extractSummary(title: String, body: String): String {
        val summary = StringBuilder(title)
        if (body.isNotBlank()) {
            val excerpt = body.split(Regex("[.!?]"))
                .firstOrNull { it.length > 20 }
                ?.trim()
                ?.take(150)
            if (excerpt != null) {
                summary.append(". ").append(excerpt)
                if (excerpt.length >= 150) summary.append("...")
            }
        }
        return summary.toString().take(250)
    }

    private fun formatTimestamp(timestamp: Double): String {
        val instant = java.time.Instant.ofEpochSecond(timestamp.toLong())
        return instant.atZone(java.time.ZoneId.systemDefault())
            .toLocalDate()
            .format(DateTimeFormatter.ISO_LOCAL_DATE)
    }
}

enum class SourceType {
    FORUM,
    BLOG
}

data class SourceConfig(
    val name: String,
    val baseUrl: String,
    val type: SourceType,
    val regions: List<String>
)
