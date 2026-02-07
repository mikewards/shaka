package com.shaka.data.cache

import com.shaka.fishing_intel.api.SpotIntelResponse
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap

/**
 * In-memory cache for spot fishing intel. Key = "intel:$spotId:$since", TTL = 20 min (lazy eviction).
 */
object IntelCache {
    private val cache = ConcurrentHashMap<String, Pair<SpotIntelResponse, Instant>>()

    fun get(spotId: String, since: String): SpotIntelResponse? {
        val key = "intel:$spotId:$since"
        val entry = cache[key] ?: return null
        if (Instant.now().isAfter(entry.second)) return null
        return entry.first
    }

    fun set(spotId: String, since: String, response: SpotIntelResponse, ttlMinutes: Int = 20) {
        val key = "intel:$spotId:$since"
        val expiresAt = Instant.now().plusSeconds(ttlMinutes * 60L)
        cache[key] = response to expiresAt
    }
}
