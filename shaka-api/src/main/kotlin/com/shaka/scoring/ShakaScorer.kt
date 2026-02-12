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
 *   chlorophyllMgM3 → Visibility score (35%)  — satellite chlorophyll-a concentration
 *   solunarDayRating → Solunar score   (15%)  — from api.solunar.org (0-5 scale), with moon phase fallback
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
     * Calculate visibility score from chlorophyll-a concentration (mg/m³).
     * Lower chlorophyll = clearer water = higher score.
     * Scored on a log scale (ocean chlorophyll ranges ~0.01 to 20+).
     * Falls back to 40 (below average) when no satellite data available.
     */
    fun scoreVisibility(chlorophyllMgM3: Double?): Int {
        if (chlorophyllMgM3 == null) return 40  // Unknown = below average

        return when {
            chlorophyllMgM3 < 0.1  -> 100  // Ultra-clear open ocean
            chlorophyllMgM3 < 0.3  -> 85   // Clear tropical
            chlorophyllMgM3 < 0.5  -> 65   // Average ocean (log midpoint)
            chlorophyllMgM3 < 1.0  -> 45   // Below average, slightly green
            chlorophyllMgM3 < 3.0  -> 25   // Green, murky coastal
            chlorophyllMgM3 < 5.0  -> 10   // Can't see your fins
            chlorophyllMgM3 < 10.0 -> 5    // Stay home
            else                   -> 0    // Algae bloom
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
     * Calculate solunar score from the API's day rating.
     * 
     * The api.solunar.org dayRating is on a 0-5 scale:
     *   0 = Poor, 1 = Below average, 2 = Average,
     *   3 = Good, 4 = Very good, 5 = Excellent
     * 
     * We map this to our 0-100 scorer scale.
     * Falls back to named moon phase, then to a neutral default.
     * 
     * @param solunarDayRating  0-5 from api.solunar.org (null if not cached)
     * @param moonPhase         Named phase string: "new_moon", "full_moon", etc. (null if not cached)
     */
    fun scoreSolunar(solunarDayRating: Int?, moonPhase: String?): Int {
        // Best: map the Solunar API's 0-5 day rating to our 0-100 scale
        if (solunarDayRating != null) {
            return when (solunarDayRating) {
                0 -> 30     // Poor
                1 -> 40     // Below average
                2 -> 55     // Average
                3 -> 65     // Good
                4 -> 80     // Very good
                5 -> 90     // Excellent
                else -> 55  // Unknown value, treat as average
            }
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
     * - Solunar: 15% (moon transit, feeding periods, day rating)
     */
    fun calculateOverall(breakdown: ScoreBreakdown): Int {
        val weightedSum = 
            breakdown.visibility * 0.35 +
            breakdown.weather * 0.28 +
            breakdown.swell * 0.22 +
            breakdown.solunar * 0.15
        
        return weightedSum.toInt()
    }

    /**
     * Generate complete Shaka Score for a spot and date.
     * 
     * @param targetDate       ISO date string (for confidence calculation)
     * @param windSpeedKmh     Wind speed in km/h (from Open-Meteo or cache)
     * @param waveHeightM      Wave height in meters (from Open-Meteo or cache)
     * @param chlorophyllMgM3   Chlorophyll-a in mg/m³ (from satellite), null = fallback score 40
     * @param solunarDayRating 0-100 day rating from api.solunar.org, null = use moonPhase fallback
     * @param moonPhase        Named phase string ("new_moon", "full_moon", etc.), null = neutral fallback
     */
    fun generateScore(
        targetDate: String,
        windSpeedKmh: Double,
        waveHeightM: Double,
        chlorophyllMgM3: Double?,
        solunarDayRating: Int?,
        moonPhase: String?
    ): ShakaScore {
        val breakdown = ScoreBreakdown(
            visibility = scoreVisibility(chlorophyllMgM3),
            weather = scoreWeather(windSpeedKmh),
            swell = scoreSwell(waveHeightM),
            solunar = scoreSolunar(solunarDayRating, moonPhase)
        )

        return ShakaScore(
            overall = calculateOverall(breakdown),
            confidence = confidenceForDate(targetDate),
            breakdown = breakdown
        )
    }
}
