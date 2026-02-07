package com.shaka.fishing_intel.processing

import com.shaka.fishing_intel.SpeciesTier
import com.shaka.fishing_intel.models.ReportWithClaims
import java.time.Duration
import java.time.Instant

/**
 * Scores a thread-level report for elevation: timeliness + interest + relevance.
 * Used to rank and take top 1-3 narrative insights.
 */
object ThreadIntelScorer {
    private val TIME_PHRASES = setOf("tonight", "tomorrow", "8pm", "at dawn", "this evening")

    fun score(report: ReportWithClaims, tldrText: String?): Double {
        val date = report.lastActivityAt ?: report.publishedAt ?: return 0.0
        val now = Instant.now()
        val age = Duration.between(date, now)

        // Relevance: do not elevate off-topic threads
        if (report.isCatchIntel == false) return 0.0
        if (report.isCatchIntel == null) {
            val text = ((tldrText ?: "") + " " + (report.rawExcerpt ?: "")).lowercase()
            if (("alien" in text || "tackle shop" in text) &&
                !("caught" in text || "limit" in text)
            ) return 0.0
        }

        var total = 0.0

        // Timeliness
        total += when {
            age.toHours() < 24 -> 30.0
            age.toDays() < 3 -> 15.0
            age.toDays() < 7 -> 5.0
            else -> 0.0
        }

        // Interest: trophy species
        for (claim in report.claims) {
            if (claim.claimType == com.shaka.fishing_intel.models.ClaimType.CATCH &&
                claim.species != null &&
                claim.species in SpeciesTier.TROPHY_SPECIES
            ) total += 10.0
        }

        // Interest: specific place mentioned
        val excerptAndTitle = (report.rawExcerpt ?: "") + (report.title ?: "")
        if (SoCalGazetteer.findInText(excerptAndTitle).isNotEmpty()) total += 15.0

        // Interest: time-sensitive phrases
        val tldrAndExcerpt = (tldrText ?: "") + (report.rawExcerpt ?: "")
        if (TIME_PHRASES.any { it in tldrAndExcerpt.lowercase() }) total += 5.0

        return total
    }
}
