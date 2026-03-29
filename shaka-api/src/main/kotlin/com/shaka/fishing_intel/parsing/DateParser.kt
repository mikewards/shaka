package com.shaka.fishing_intel.parsing

import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Parses various date formats from fishing report sites.
 */
object DateParser {
    // SoCalFishReports: "December 17, 2025"
    private val SCFR_FORMAT = DateTimeFormatter.ofPattern("MMMM d, yyyy", Locale.US)
    
    fun parseSoCalFishReports(dateStr: String): LocalDate? {
        return try {
            LocalDate.parse(dateStr.trim(), SCFR_FORMAT)
        } catch (e: Exception) {
            null
        }
    }
}
