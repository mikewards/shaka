package com.shaka.fishing_intel.processing

import com.shaka.fishing_intel.models.FishCount
import java.security.MessageDigest
import java.time.LocalDate

/**
 * Deduplication using SHA-256 fingerprints.
 * Same report from multiple sources produces the same fingerprint.
 */
object Deduplicator {
    
    /**
     * Build a canonical fingerprint for a fish count report.
     * Combines landing, boat, trip type, date, anglers, and sorted species counts.
     */
    fun buildFingerprint(
        landingName: String?,
        boatName: String?,
        tripType: String?,
        date: LocalDate,
        anglerCount: Int?,
        fishCounts: List<FishCount>
    ): String {
        val normalized = buildString {
            append(normalize(landingName ?: ""))
            append("|")
            append(normalize(boatName ?: ""))
            append("|")
            append(normalize(tripType ?: ""))
            append("|")
            append(date.toString())
            append("|")
            append(anglerCount?.toString() ?: "")
            append("|")
            // Sort species alphabetically for consistent fingerprint
            val sortedCounts = fishCounts.sortedBy { it.species.lowercase() }
            append(sortedCounts.joinToString(",") { 
                "${normalize(it.species)}:${it.kept}:${it.released}" 
            })
        }
        
        return sha256(normalized)
    }
    
    /**
     * Get fingerprint for a report: use existing canonical fingerprint if set,
     * otherwise compute from landing, boat, trip type, date, anglers, and fish counts.
     */
    fun getReportFingerprint(
        existing: String?,
        landingName: String?,
        boatName: String?,
        tripType: String?,
        date: LocalDate,
        anglerCount: Int?,
        fishCounts: List<FishCount>
    ): String {
        if (!existing.isNullOrBlank()) return existing
        return buildFingerprint(landingName, boatName, tripType, date, anglerCount, fishCounts)
    }
    
    /**
     * Build fingerprint for a narrative report (less structured).
     */
    fun buildNarrativeFingerprint(
        url: String,
        title: String?,
        date: LocalDate
    ): String {
        val normalized = buildString {
            append(url)
            append("|")
            append(normalize(title ?: ""))
            append("|")
            append(date.toString())
        }
        return sha256(normalized)
    }

    /**
     * Build fingerprint for a reply post (dedupe by thread + post).
     */
    fun buildReplyFingerprint(threadUrl: String, postUrl: String): String {
        val normalized = normalize(threadUrl) + "|" + normalize(postUrl)
        return sha256(normalized)
    }
    
    /**
     * Normalize a string for consistent comparison.
     */
    private fun normalize(s: String): String {
        return s.lowercase()
            .replace(Regex("""[^a-z0-9]"""), "")
            .trim()
    }
    
    /**
     * SHA-256 hash a string.
     */
    private fun sha256(input: String): String {
        return MessageDigest.getInstance("SHA-256")
            .digest(input.toByteArray())
            .joinToString("") { "%02x".format(it) }
    }
}
