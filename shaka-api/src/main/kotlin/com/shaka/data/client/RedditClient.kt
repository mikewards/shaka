package com.shaka.data.client

import com.shaka.model.CommunityReport
import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.engine.cio.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * Client for fetching spearfishing community reports from Reddit.
 * 
 * Uses Reddit's public JSON API (no authentication required for read-only).
 * Fetches recent posts from r/spearfishing and related subreddits.
 */
class RedditClient {

    private val client = HttpClient(CIO) {
        install(ContentNegotiation) {
            json(Json {
                ignoreUnknownKeys = true
                isLenient = true
            })
        }
    }

    companion object {
        private val SPEARFISHING_SUBREDDITS = listOf(
            "spearfishing",
            "Freediving",
            "scuba"
        )

        // Keywords to identify dive reports
        private val REPORT_KEYWORDS = listOf(
            "visibility", "vis", "clear", "murky", "conditions",
            "caught", "shot", "landed", "dive report",
            "water temp", "swell", "current", "fish"
        )

        // Region keywords for filtering
        private val REGION_KEYWORDS = mapOf(
            "hawaii" to listOf("hawaii", "oahu", "maui", "kona", "big island", "north shore"),
            "california" to listOf("california", "socal", "norcal", "la jolla", "catalina", "san diego"),
            "florida" to listOf("florida", "keys", "miami", "gulf", "atlantic"),
            "caribbean" to listOf("caribbean", "bahamas", "mexico", "baja", "cozumel")
        )
    }

    /**
     * Get recent community reports for a region.
     */
    suspend fun getReportsForRegion(region: String, limit: Int = 10): List<CommunityReport> {
        val reports = mutableListOf<CommunityReport>()
        val regionKeywords = REGION_KEYWORDS[region.lowercase()] ?: listOf(region.lowercase())

        for (subreddit in SPEARFISHING_SUBREDDITS) {
            try {
                val subredditReports = fetchSubredditPosts(subreddit, regionKeywords, limit)
                reports.addAll(subredditReports)
            } catch (e: Exception) {
                // Continue with other subreddits if one fails
                continue
            }
        }

        return reports
            .sortedByDescending { it.date }
            .take(limit)
    }

    /**
     * Fetch posts from a subreddit and filter for dive reports.
     */
    private suspend fun fetchSubredditPosts(
        subreddit: String,
        regionKeywords: List<String>,
        limit: Int
    ): List<CommunityReport> {
        val response: RedditListingResponse = client.get(
            "https://www.reddit.com/r/$subreddit/new.json"
        ) {
            parameter("limit", 100)
            header("User-Agent", "Shaka/1.0")
        }.body()

        return response.data.children
            .map { it.data }
            .filter { post ->
                // Filter for posts that look like dive reports
                val content = "${post.title} ${post.selftext}".lowercase()
                
                // Must contain at least one report keyword
                val hasReportKeyword = REPORT_KEYWORDS.any { content.contains(it) }
                
                // Should match region if specified
                val matchesRegion = regionKeywords.isEmpty() || 
                    regionKeywords.any { content.contains(it) }
                
                hasReportKeyword && matchesRegion
            }
            .take(limit)
            .map { post ->
                CommunityReport(
                    source = "r/$subreddit",
                    date = formatTimestamp(post.created_utc),
                    summary = extractSummary(post.title, post.selftext),
                    url = "https://reddit.com${post.permalink}"
                )
            }
    }

    /**
     * Extract a brief summary from the post.
     */
    private fun extractSummary(title: String, body: String): String {
        // Start with title
        val summary = StringBuilder(title)
        
        // Add relevant excerpt from body if available
        if (body.isNotBlank()) {
            val sentences = body.split(Regex("[.!?]"))
                .map { it.trim() }
                .filter { sentence ->
                    REPORT_KEYWORDS.any { sentence.lowercase().contains(it) }
                }
            
            if (sentences.isNotEmpty()) {
                val excerpt = sentences.first().take(150)
                if (excerpt.isNotBlank()) {
                    summary.append(". ")
                    summary.append(excerpt)
                    if (excerpt.length >= 150) summary.append("...")
                }
            }
        }
        
        return summary.toString().take(250)
    }

    /**
     * Format Unix timestamp to ISO date string.
     */
    private fun formatTimestamp(timestamp: Double): String {
        val instant = Instant.ofEpochSecond(timestamp.toLong())
        val date = instant.atZone(ZoneId.systemDefault()).toLocalDate()
        return date.format(DateTimeFormatter.ISO_LOCAL_DATE)
    }
}

// Reddit API response models

@Serializable
data class RedditListingResponse(
    val data: RedditListingData
)

@Serializable
data class RedditListingData(
    val children: List<RedditPostWrapper>
)

@Serializable
data class RedditPostWrapper(
    val data: RedditPost
)

@Serializable
data class RedditPost(
    val title: String,
    val selftext: String = "",
    val permalink: String,
    val created_utc: Double,
    val subreddit: String
)
