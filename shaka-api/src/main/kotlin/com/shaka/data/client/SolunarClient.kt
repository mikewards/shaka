package com.shaka.data.client

import com.shaka.model.SolunarData
import com.shaka.model.TimePeriod
import io.ktor.client.call.*
import io.ktor.client.request.*
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import org.slf4j.LoggerFactory
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * Client for Solunar API - FREE, works worldwide.
 * 
 * Provides moon phase and major/minor feeding periods.
 * Fishermen have used solunar tables for decades to predict fish activity.
 * 
 * Major periods: ~2 hours around moon overhead and underfoot
 * Minor periods: ~1 hour around moonrise and moonset
 * 
 * API: https://api.solunar.org/
 */
class SolunarClient {

    private val logger = LoggerFactory.getLogger(SolunarClient::class.java)
    private val client = HttpClientFactory.shared
    
    companion object {
        private const val BASE_URL = "https://api.solunar.org/solunar"
    }
    
    /**
     * Get solunar data for a location and date.
     * 
     * @param lat Latitude
     * @param lon Longitude
     * @param date Date (defaults to today)
     * @param timezoneOffset UTC offset in hours (e.g., -5 for EST, 9 for JST)
     * @return SolunarData with moon phase and feeding periods
     */
    suspend fun getSolunarData(
        lat: Double,
        lon: Double,
        date: LocalDate = LocalDate.now(),
        timezoneOffset: Int? = null
    ): SolunarData? {
        return try {
            RateLimiters.solunar.acquire()
            
            // Calculate timezone offset from longitude if not provided
            // Rough estimate: 15 degrees = 1 hour
            val offset = timezoneOffset ?: (lon / 15).toInt()
            
            val dateStr = date.format(DateTimeFormatter.BASIC_ISO_DATE) // YYYYMMDD
            
            // API format: /solunar/{lat},{lon},{date},{timezone}
            val url = "$BASE_URL/$lat,$lon,$dateStr,$offset"
            
            val response: SolunarApiResponse = client.get(url) {
                header("Accept", "application/json")
            }.body()
            
            logger.info("Solunar: Moon ${response.moonPhase} (${response.moonIllumination}%) for ($lat, $lon)")
            
            SolunarData(
                moonPhase = normalizeMoonPhase(response.moonPhase),
                illumination = response.moonIllumination?.toInt() ?: 0,
                majorPeriods = parsePeriods(response.major1Start, response.major1Stop) +
                               parsePeriods(response.major2Start, response.major2Stop),
                minorPeriods = parsePeriods(response.minor1Start, response.minor1Stop) +
                               parsePeriods(response.minor2Start, response.minor2Stop),
                dayRating = response.dayRating,
                hourlyRating = response.hourlyRating
            )
            
        } catch (e: Exception) {
            logger.warn("Solunar API failed for ($lat, $lon): ${e.message}")
            
            // Fallback: calculate basic moon phase from date
            getFallbackSolunarData(date)
        }
    }
    
    /**
     * Parse time period from start/stop strings.
     */
    private fun parsePeriods(start: String?, stop: String?): List<TimePeriod> {
        if (start.isNullOrBlank() || stop.isNullOrBlank()) return emptyList()
        
        return listOf(
            TimePeriod(
                start = formatTime(start),
                end = formatTime(stop)
            )
        )
    }
    
    /**
     * Format time string to HH:mm format.
     */
    private fun formatTime(time: String): String {
        // API returns times like "5:30 AM" or "14:30"
        return try {
            val parts = time.trim().uppercase().split(" ")
            val timePart = parts[0]
            val isPM = parts.getOrNull(1) == "PM"
            val isAM = parts.getOrNull(1) == "AM"
            
            val (hour, minute) = timePart.split(":").let {
                it[0].toInt() to it.getOrElse(1) { "00" }.toInt()
            }
            
            val hour24 = when {
                isPM && hour != 12 -> hour + 12
                isAM && hour == 12 -> 0
                else -> hour
            }
            
            "%02d:%02d".format(hour24, minute)
        } catch (e: Exception) {
            time // Return original if parsing fails
        }
    }
    
    /**
     * Normalize moon phase name to consistent format.
     */
    private fun normalizeMoonPhase(phase: String?): String {
        return when (phase?.lowercase()?.trim()) {
            "new moon", "new" -> "new_moon"
            "waxing crescent" -> "waxing_crescent"
            "first quarter" -> "first_quarter"
            "waxing gibbous" -> "waxing_gibbous"
            "full moon", "full" -> "full_moon"
            "waning gibbous" -> "waning_gibbous"
            "last quarter", "third quarter" -> "last_quarter"
            "waning crescent" -> "waning_crescent"
            else -> phase?.lowercase()?.replace(" ", "_") ?: "unknown"
        }
    }
    
    /**
     * Fallback solunar data when API fails.
     * Calculates approximate moon phase from date.
     */
    private fun getFallbackSolunarData(date: LocalDate): SolunarData {
        // Lunar cycle is ~29.53 days
        // Reference: Jan 1, 2000 was a new moon
        val reference = LocalDate.of(2000, 1, 6)
        val daysSinceNew = java.time.temporal.ChronoUnit.DAYS.between(reference, date) % 29.53
        
        val (phase, illumination) = when {
            daysSinceNew < 1.85 -> "new_moon" to 0
            daysSinceNew < 7.38 -> "waxing_crescent" to ((daysSinceNew / 7.38) * 50).toInt()
            daysSinceNew < 9.23 -> "first_quarter" to 50
            daysSinceNew < 14.76 -> "waxing_gibbous" to (50 + ((daysSinceNew - 9.23) / 5.53) * 50).toInt()
            daysSinceNew < 16.61 -> "full_moon" to 100
            daysSinceNew < 22.14 -> "waning_gibbous" to (100 - ((daysSinceNew - 16.61) / 5.53) * 50).toInt()
            daysSinceNew < 23.99 -> "last_quarter" to 50
            else -> "waning_crescent" to (50 - ((daysSinceNew - 23.99) / 5.54) * 50).toInt()
        }
        
        logger.info("Solunar fallback: $phase ($illumination%)")
        
        return SolunarData(
            moonPhase = phase,
            illumination = illumination.coerceIn(0, 100),
            majorPeriods = emptyList(), // Can't calculate without API
            minorPeriods = emptyList(),
            dayRating = null,
            hourlyRating = null
        )
    }
}

// Solunar API Response models

@Serializable
data class SolunarApiResponse(
    @SerialName("moonPhase")
    val moonPhase: String? = null,
    
    @SerialName("moonIllumination")
    val moonIllumination: Double? = null,
    
    @SerialName("moonrise")
    val moonrise: String? = null,
    
    @SerialName("moonset")
    val moonset: String? = null,
    
    @SerialName("major1Start")
    val major1Start: String? = null,
    
    @SerialName("major1Stop")
    val major1Stop: String? = null,
    
    @SerialName("major2Start")
    val major2Start: String? = null,
    
    @SerialName("major2Stop")
    val major2Stop: String? = null,
    
    @SerialName("minor1Start")
    val minor1Start: String? = null,
    
    @SerialName("minor1Stop")
    val minor1Stop: String? = null,
    
    @SerialName("minor2Start")
    val minor2Start: String? = null,
    
    @SerialName("minor2Stop")
    val minor2Stop: String? = null,
    
    @SerialName("dayRating")
    val dayRating: Int? = null,
    
    @SerialName("hourlyRating")
    val hourlyRating: Map<String, Int>? = null
)
