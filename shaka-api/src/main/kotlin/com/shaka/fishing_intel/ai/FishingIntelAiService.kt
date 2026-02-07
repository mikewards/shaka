package com.shaka.fishing_intel.ai

import com.shaka.data.client.HttpClientFactory
import com.shaka.fishing_intel.SpeciesTier
import io.ktor.client.call.*
import io.ktor.client.request.*
import io.ktor.http.*
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.serializer
import org.slf4j.LoggerFactory

/**
 * Optional AI analysis for BD Outdoors narrative posts and threads.
 * Provider-agnostic: set FISHING_INTEL_AI_API_KEY + optional URL/model for Groq (default)
 * or OPENAI_API_KEY for OpenAI. Same OpenAI-compatible chat completions API.
 * Disabled when FISHING_INTEL_AI_ENABLED != true or no API key is set.
 */
object FishingIntelAiService {
    private val logger = LoggerFactory.getLogger(FishingIntelAiService::class.java)
    private const val TIMEOUT_MS = 15_000L
    private const val MAX_CONTENT_CHARS = 4000

    private const val DEFAULT_GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
    private const val DEFAULT_GROQ_MODEL = "llama-3.3-70b-versatile"
    private const val DEFAULT_OPENAI_URL = "https://api.openai.com/v1/chat/completions"
    private const val DEFAULT_OPENAI_MODEL = "gpt-4o-mini"

    private fun apiKey(): String? {
        val key = System.getenv("FISHING_INTEL_AI_API_KEY")?.takeIf { it.isNotBlank() }
            ?: System.getenv("OPENAI_API_KEY")?.takeIf { it.isNotBlank() }
        return key
    }

    private fun apiUrl(): String {
        val url = System.getenv("FISHING_INTEL_AI_API_URL")?.takeIf { it.isNotBlank() }
        if (url != null) return url
        return if (System.getenv("FISHING_INTEL_AI_API_KEY")?.isNotBlank() == true) DEFAULT_GROQ_URL else DEFAULT_OPENAI_URL
    }

    private fun apiModel(): String {
        val model = System.getenv("FISHING_INTEL_AI_MODEL")?.takeIf { it.isNotBlank() }
        if (model != null) return model
        return if (System.getenv("FISHING_INTEL_AI_API_KEY")?.isNotBlank() == true) DEFAULT_GROQ_MODEL else DEFAULT_OPENAI_MODEL
    }

    fun isEnabled(): Boolean =
        System.getenv("FISHING_INTEL_AI_ENABLED")?.equals("true", ignoreCase = true) == true &&
            !apiKey().isNullOrBlank()

    /**
     * Analyze a narrative post: return (species_caught list, tldr string) or null if disabled/failed.
     * Only call for BD narrative posts; caller should skip when not applicable.
     */
    suspend fun analyzePost(
        title: String,
        content: String,
        speciesMentioned: List<String>
    ): Pair<List<String>, String?>? {
        if (!isEnabled()) return null
        val key = apiKey() ?: return null
        val contentTruncated = content.take(MAX_CONTENT_CHARS)
        val systemPrompt = """You are a fishing report analyst. For the given forum post, output ONLY valid JSON with two keys (no markdown, no explanation):
(1) "species_caught": array of species actually caught on this trip, normalized with underscores (e.g. bluefin_tuna, yellowtail, calico_bass). Do NOT include species only mentioned as chum, bait, from the freezer, or from a past trip.
(2) "tldr": one or two sentences summarizing what was caught, where, and conditions if relevant. Standalone; no "read more" or links. Factual, angler-friendly tone."""
        val userPrompt = "Title: $title\n\nContent: $contentTruncated"
        val messagesJson = """[{"role":"system","content":${Json.encodeToString(serializer<String>(), systemPrompt)}},{"role":"user","content":${Json.encodeToString(serializer<String>(), userPrompt)}}]"""
        val requestBody = """{"model":"${apiModel()}","messages":$messagesJson,"temperature":0.2}"""

        return withTimeoutOrNull(TIMEOUT_MS) {
            try {
                val response = HttpClientFactory.shared.post(apiUrl()) {
                    header(HttpHeaders.Authorization, "Bearer $key")
                    contentType(ContentType.Application.Json)
                    setBody(requestBody)
                }
                val body = response.body<String>()
                val json = Json.parseToJsonElement(body).jsonObject
                val choices = json["choices"]?.jsonArray ?: return@withTimeoutOrNull null
                val first = choices.firstOrNull()?.jsonObject ?: return@withTimeoutOrNull null
                val message = first["message"]?.jsonObject ?: return@withTimeoutOrNull null
                val contentStr = message["content"]?.jsonPrimitive?.content ?: return@withTimeoutOrNull null
                val parsed = Json.parseToJsonElement(contentStr).jsonObject
                val speciesArr = parsed["species_caught"]?.jsonArray ?: return@withTimeoutOrNull null
                val speciesList = speciesArr.mapNotNull { it.jsonPrimitive.content }
                val tldr = parsed["tldr"]?.jsonPrimitive?.content?.take(500)?.trim()?.takeIf { it.isNotBlank() }
                speciesList to tldr
            } catch (e: Exception) {
                logger.warn("Fishing intel AI analysis failed: ${e.message}")
                null
            }
        }
    }

    /**
     * Analyze a full thread (title + combined posts): return (species_caught, tldr, is_catch_intel) or null.
     * Call once per thread; store result on thread-starter report only.
     */
    suspend fun analyzeThread(title: String, combinedContent: String): Triple<List<String>, String?, Boolean?>? {
        if (!isEnabled()) return null
        val key = apiKey() ?: return null
        val contentTruncated = combinedContent.take(MAX_CONTENT_CHARS)
        val systemPrompt = """You are a fishing report analyst. For the given forum thread, output ONLY valid JSON with three keys (no markdown, no explanation):
(1) "species_caught": array of species actually caught on this trip, normalized with underscores (e.g. bluefin_tuna, yellowtail). Do NOT include species only mentioned as chum, bait, from the freezer, or from a past trip.
(2) "tldr": one or two SHORT sentences (max 25 words) summarizing what was caught, where, and conditions. Must fit on a single mobile card. No "read more" or links. Factual, angler-friendly tone.
(3) "is_catch_intel": boolean. true if the thread is mostly actual catch reports or conditions intel; false if mostly off-topic (e.g. general chat, tackle shop visit with no report, non-fishing)."""
        val userPrompt = "Title: $title\n\nContent: $contentTruncated"
        val messagesJson = """[{"role":"system","content":${Json.encodeToString(serializer<String>(), systemPrompt)}},{"role":"user","content":${Json.encodeToString(serializer<String>(), userPrompt)}}]"""
        val requestBody = """{"model":"${apiModel()}","messages":$messagesJson,"temperature":0.2}"""

        return withTimeoutOrNull(TIMEOUT_MS) {
            try {
                val response = HttpClientFactory.shared.post(apiUrl()) {
                    header(HttpHeaders.Authorization, "Bearer $key")
                    contentType(ContentType.Application.Json)
                    setBody(requestBody)
                }
                val body = response.body<String>()
                val json = Json.parseToJsonElement(body).jsonObject
                val choices = json["choices"]?.jsonArray ?: return@withTimeoutOrNull null
                val first = choices.firstOrNull()?.jsonObject ?: return@withTimeoutOrNull null
                val message = first["message"]?.jsonObject ?: return@withTimeoutOrNull null
                val contentStr = message["content"]?.jsonPrimitive?.content ?: return@withTimeoutOrNull null
                val parsed = Json.parseToJsonElement(contentStr).jsonObject
                val speciesArr = parsed["species_caught"]?.jsonArray ?: return@withTimeoutOrNull null
                val speciesList = speciesArr.mapNotNull { it.jsonPrimitive.content }
                val tldr = parsed["tldr"]?.jsonPrimitive?.content?.take(500)?.trim()?.takeIf { it.isNotBlank() }
                val isCatchIntel = parsed["is_catch_intel"]?.let { el ->
                    when (el) {
                        is kotlinx.serialization.json.JsonPrimitive -> el.content.lowercase() == "true"
                        else -> null
                    }
                }
                Triple(speciesList, tldr, isCatchIntel)
            } catch (e: Exception) {
                logger.warn("Fishing intel thread AI analysis failed: ${e.message}")
                null
            }
        }
    }

    /** True if we should call AI for this post (BD narrative with at least one trophy species mentioned). */
    fun shouldAnalyze(speciesMentioned: List<String>): Boolean {
        if (!isEnabled()) return false
        return speciesMentioned.any { it in SpeciesTier.TROPHY_SPECIES }
    }

    /**
     * Generate 3–5 short key insights for a region report.
     * Style: Ernest Hemingway, Old Man and the Sea — simple, direct, but uplifting and easy to read.
     * Max 2 lines per insight. Uses species trends and narrative TL;DRs.
     */
    suspend fun generateRegionInsights(
        speciesSummary: String,
        narrativeTldrs: List<String>,
        totalReports: Int,
        regionLabel: String = "SoCal"
    ): List<String>? {
        if (!isEnabled()) return null
        val key = apiKey() ?: return null
        val tldrsText = narrativeTldrs.take(5).joinToString("\n") { it.take(200) }.take(800)
        val systemPrompt = """You are a fishing report writer in the style of Ernest Hemingway's The Old Man and the Sea: short sentences, plain words, no fluff. Be specific and concrete — name species, numbers, and conditions. Never write vague or ambiguous lines like "good times on the water" or "fishing is good." Your tone is uplifting and hopeful: the sea gives, the fisherman endures. Every insight must be punchy and actionable.
Output ONLY a JSON array of 3 to 5 strings. Each string is one key insight, maximum 2 lines (about 15–20 words). No numbering, no markdown, no explanation. Be specific: e.g. "Yellowtail counts are up. The fleet put 40 on the deck yesterday." or "Calm seas through Thursday. Go early.""""
        val userPrompt = """Region: $regionLabel. Total reports: $totalReports.

Species catch trends (last 48h vs 5-day trailing):
$speciesSummary

Recent report TL;DRs:
$tldrsText

Generate 3 to 5 key insights as a JSON array of strings. Each insight max 2 lines. Hemingway: simple, direct, uplifting. Be specific — name fish, numbers, or conditions. No vague or generic lines."""

        val messagesJson = """[{"role":"system","content":${Json.encodeToString(serializer<String>(), systemPrompt)}},{"role":"user","content":${Json.encodeToString(serializer<String>(), userPrompt)}}]"""
        val requestBody = """{"model":"${apiModel()}","messages":$messagesJson,"temperature":0.4}"""

        return withTimeoutOrNull(TIMEOUT_MS) {
            try {
                val response = HttpClientFactory.shared.post(apiUrl()) {
                    header(HttpHeaders.Authorization, "Bearer $key")
                    contentType(ContentType.Application.Json)
                    setBody(requestBody)
                }
                val body = response.body<String>()
                val json = Json.parseToJsonElement(body).jsonObject
                val choices = json["choices"]?.jsonArray ?: return@withTimeoutOrNull null
                val first = choices.firstOrNull()?.jsonObject ?: return@withTimeoutOrNull null
                val message = first["message"]?.jsonObject ?: return@withTimeoutOrNull null
                val contentStr = message["content"]?.jsonPrimitive?.content ?: return@withTimeoutOrNull null
                val arr = Json.parseToJsonElement(contentStr.trim().removeSurrounding("```json", "```").trim()).jsonArray
                arr.mapNotNull { it.jsonPrimitive?.content?.trim()?.take(200)?.takeIf { s -> s.length in 5..200 } }
            } catch (e: Exception) {
                logger.warn("Region insights AI failed: ${e.message}")
                null
            }
        }
    }
}
