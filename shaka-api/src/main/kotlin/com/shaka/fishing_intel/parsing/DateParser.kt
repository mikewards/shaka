package com.shaka.fishing_intel.parsing

import java.time.LocalDate
import java.time.Month
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Parses various date formats from fishing report sites.
 */
object DateParser {
    private val PACIFIC_ZONE = ZoneId.of("America/Los_Angeles")
    
    // SoCalFishReports: "December 17, 2025"
    private val SCFR_FORMAT = DateTimeFormatter.ofPattern("MMMM d, yyyy", Locale.US)
    
    // 976-TUNA counts: "Monday June 17th 2024"
    private val TUNA_COUNTS_FORMAT = DateTimeFormatter.ofPattern("EEEE MMMM d['st']['nd']['rd']['th'] yyyy", Locale.US)
    
    // 976-TUNA reports: "Thu Feb 5th 3:38 PM"
    private val TUNA_REPORTS_PATTERN = Regex(
        """(\w+)\s+(\w+)\s+(\d+)(?:st|nd|rd|th)\s+(\d+):(\d+)\s*(AM|PM)""",
        RegexOption.IGNORE_CASE
    )
    
    fun parseSoCalFishReports(dateStr: String): LocalDate? {
        return try {
            LocalDate.parse(dateStr.trim(), SCFR_FORMAT)
        } catch (e: Exception) {
            null
        }
    }
    
    fun parse976TunaCounts(dateStr: String): LocalDate? {
        return try {
            // Remove ordinal suffixes for parsing
            val cleaned = dateStr
                .replace(Regex("(\\d+)(st|nd|rd|th)"), "$1")
            LocalDate.parse(cleaned, DateTimeFormatter.ofPattern("EEEE MMMM d yyyy", Locale.US))
        } catch (e: Exception) {
            null
        }
    }
    
    fun parse976TunaReports(dateStr: String, year: Int = LocalDate.now().year): ZonedDateTime? {
        val match = TUNA_REPORTS_PATTERN.find(dateStr) ?: return null
        
        return try {
            val monthStr = match.groupValues[2]
            val day = match.groupValues[3].toInt()
            val hour = match.groupValues[4].toInt()
            val minute = match.groupValues[5].toInt()
            val amPm = match.groupValues[6].uppercase()
            
            val month = Month.valueOf(monthStr.uppercase().take(3).let {
                when (it) {
                    "JAN" -> "JANUARY"
                    "FEB" -> "FEBRUARY"
                    "MAR" -> "MARCH"
                    "APR" -> "APRIL"
                    "MAY" -> "MAY"
                    "JUN" -> "JUNE"
                    "JUL" -> "JULY"
                    "AUG" -> "AUGUST"
                    "SEP" -> "SEPTEMBER"
                    "OCT" -> "OCTOBER"
                    "NOV" -> "NOVEMBER"
                    "DEC" -> "DECEMBER"
                    else -> it
                }
            })
            
            val hour24 = when {
                amPm == "AM" && hour == 12 -> 0
                amPm == "PM" && hour != 12 -> hour + 12
                else -> hour
            }
            
            ZonedDateTime.of(year, month.value, day, hour24, minute, 0, 0, PACIFIC_ZONE)
        } catch (e: Exception) {
            null
        }
    }
}
