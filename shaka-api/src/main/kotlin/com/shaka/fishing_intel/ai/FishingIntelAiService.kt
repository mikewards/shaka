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
 * Optional AI analysis for BD Outdoors narrative posts only.
 * Uses gpt-4o-mini to extract species actually caught and generate a TL;DR.
 * Disabled when FISHING_INTEL_AI_ENABLED != true or OPENAI_API_KEY is missing.
 */
object FishingIntelAiService {
    private val logger = LoggerFactory.getLogger(FishingIntelAiService::class.java)
    private const val OPENAI_URL = "https://api.openai.com/v1/chat/completions"
    private const val MODEL = "gpt-4o-mini"
    private const val TIMEOUT_MS = 15_000L
    private const val MAX_CONTENT_CHARS = 4000

    private fun isEnabled(): Boolean =
        System.getenv("FISHING_INTEL_AI_ENABLED")?.equals("true", ignoreCase = true) == true &&
            !System.getenv("OPENAI_API_KEY").isNullOrBlank()

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
        val key = System.getenv("OPENAI_API_KEY") ?: return null
        val contentTruncated = content.take(MAX_CONTENT_CHARS)
        val systemPrompt = """You are a fishing report analyst. For the given forum post, output ONLY valid JSON with two keys (no markdown, no explanation):
(1) "species_caught": array of species actually caught on this trip, normalized with underscores (e.g. bluefin_tuna, yellowtail, calico_bass). Do NOT include species only mentioned as chum, bait, from the freezer, or from a past trip.
(2) "tldr": one or two sentences summarizing what was caught, where, and conditions if relevant. Standalone; no "read more" or links. Factual, angler-friendly tone."""
        val userPrompt = "Title: $title\n\nContent: $contentTruncated"
        val messagesJson = """[{"role":"system","content":${Json.encodeToString(serializer<String>(), systemPrompt)}},{"role":"user","content":${Json.encodeToString(serializer<String>(), userPrompt)}}]"""
        val requestBody = """{"model":"$MODEL","messages":$messagesJson,"temperature":0.2}"""

        return withTimeoutOrNull(TIMEOUT_MS) {
            try {
                val response = HttpClientFactory.shared.post(OPENAI_URL) {
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

    /** True if we should call AI for this post (BD narrative with at least one trophy species mentioned). */
    fun shouldAnalyze(speciesMentioned: List<String>): Boolean {
        if (!isEnabled()) return false
        return speciesMentioned.any { it in SpeciesTier.TROPHY_SPECIES }
    }
}
