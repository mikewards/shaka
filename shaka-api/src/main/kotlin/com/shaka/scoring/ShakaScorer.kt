package com.shaka.scoring

import com.shaka.model.ScoreBreakdown
import com.shaka.model.ShakaScore
import java.time.LocalDate
import java.time.temporal.ChronoUnit

/**
 * Shaka Score Calculator
 * 
 * Calculates an overall score (0-100) for spearfishing conditions.
 * Takes ONLY the primitive values it actually uses — no unused fields.
 * 
 * Inputs:
 *   windSpeedKmh    → Weather score   (28%)
 *   waveHeightM     → Swell score     (22%)
 *   visibilityM     → Visibility score (35%)
 *   solunarDayRating → Fish Activity   (15%)  — from api.solunar.org, with moon phase fallback
 */
object ShakaScorer {

    /**
     * Calculate confidence based on days until target date.
     * Same-day forecasts are most reliable, 30-day out are least.
     */
    fun confidenceForDate(targetDate: String): Int {
        val target = LocalDate.parse(targetDate)
        val today = LocalDate.now()
        val daysOut = ChronoUnit.DAYS.between(today, target).toInt()

        return when {
            daysOut <= 0 -> 95
            daysOut <= 1 -> 90
            daysOut <= 3 -> 85
            daysOut <= 5 -> 75
            daysOut <= 7 -> 70
            daysOut <= 10 -> 60
            daysOut <= 14 -> 50
            daysOut <= 21 -> 40
            else -> 30
        }
    }

    /**
     * Calculate visibility score based on underwater visibility in meters.
     * Falls back to 10m (score 70) when no satellite data available.
     */
    fun scoreVisibility(visibilityM: Double?): Int {
        val visM = visibilityM ?: 10.0

        return when {
            visM >= 25 -> 100  // Crystal clear
            visM >= 20 -> 90
            visM >= 15 -> 80
            visM >= 10 -> 70
            visM >= 7 -> 60
            visM >= 5 -> 50
            visM >= 3 -> 35
            else -> 20        // Very murky
        }
    }

    /**
     * Calculate weather score based on wind speed in km/h.
     */
    fun scoreWeather(windSpeedKmh: Double): Int {
        var score = 100

        score -= when {
            windSpeedKmh <= 5 -> 0
            windSpeedKmh <= 10 -> 10
            windSpeedKmh <= 15 -> 25
            windSpeedKmh <= 20 -> 40
            else -> 60
        }

        return score.coerceIn(0, 100)
    }

    /**
     * Calculate swell score based on wave height in meters.
     */
    fun scoreSwell(waveHeightM: Double): Int {
        val waveHeightFt = waveHeightM * 3.28084

        return when {
            waveHeightFt <= 1 -> 100  // Flat
            waveHeightFt <= 2 -> 90
            waveHeightFt <= 3 -> 80
            waveHeightFt <= 4 -> 65
            waveHeightFt <= 6 -> 45
            waveHeightFt <= 8 -> 25
            else -> 10              // Dangerous
        }
    }

    /**
     * Calculate fish activity score.
     * 
     * Uses the Solunar API's day rating (0-100) when available — this is a
     * professional composite that factors in moon transit, altitude, and
     * feeding period quality. Falls back to named moon phase, then to a
     * neutral default.
     * 
     * @param solunarDayRating  0-100 from api.solunar.org (null if not cached)
     * @param moonPhase         Named phase string: "new_moon", "full_moon", etc. (null if not cached)
     */
    fun scoreFishActivity(solunarDayRating: Int?, moonPhase: String?): Int {
        // Best: use the Solunar API's own day rating directly
        if (solunarDayRating != null) {
            return solunarDayRating.coerceIn(0, 100)
        }

        // Fallback: use named moon phase from cache
        if (moonPhase != null) {
            return when (moonPhase) {
                "new_moon" -> 70
                "full_moon" -> 65
                "waxing_gibbous", "waning_gibbous" -> 60
                "first_quarter", "last_quarter" -> 55
                "waxing_crescent", "waning_crescent" -> 50
                else -> 55
            }
        }

        // Last resort: no solunar data at all
        return 55
    }

    /**
     * Calculate overall Shaka Score from all components.
     * 
     * Weights (total 100%):
     * - Visibility: 35% (most important for spearfishing)
     * - Weather: 28% (wind speed — affects surface conditions and comfort)
     * - Swell: 22% (wave height — affects underwater vis and entry safety)
     * - Fish Activity: 15% (moon phase)
     */
    fun calculateOverall(breakdown: ScoreBreakdown): Int {
        val weightedSum = 
            breakdown.visibility * 0.35 +
            breakdown.weather * 0.28 +
            breakdown.swell * 0.22 +
            breakdown.fishActivity * 0.15
        
        return weightedSum.toInt()
    }

    /**
     * Generate complete Shaka Score for a spot and date.
     * 
     * @param targetDate       ISO date string (for confidence calculation)
     * @param windSpeedKmh     Wind speed in km/h (from Open-Meteo or cache)
     * @param waveHeightM      Wave height in meters (from Open-Meteo or cache)
     * @param visibilityM      Underwater visibility in meters (from Copernicus), null = fallback to 10m
     * @param solunarDayRating 0-100 day rating from api.solunar.org, null = use moonPhase fallback
     * @param moonPhase        Named phase string ("new_moon", "full_moon", etc.), null = neutral fallback
     */
    fun generateScore(
        targetDate: String,
        windSpeedKmh: Double,
        waveHeightM: Double,
        visibilityM: Double?,
        solunarDayRating: Int?,
        moonPhase: String?
    ): ShakaScore {
        val breakdown = ScoreBreakdown(
            visibility = scoreVisibility(visibilityM),
            weather = scoreWeather(windSpeedKmh),
            swell = scoreSwell(waveHeightM),
            fishActivity = scoreFishActivity(solunarDayRating, moonPhase)
        )

        return ShakaScore(
            overall = calculateOverall(breakdown),
            confidence = confidenceForDate(targetDate),
            breakdown = breakdown
        )
    }
}
