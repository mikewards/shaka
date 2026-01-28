package com.shaka.scoring

import com.shaka.model.*
import java.time.LocalDate
import java.time.temporal.ChronoUnit

/**
 * Shaka Score Calculator
 * 
 * Calculates an overall score (0-100) for spearfishing conditions
 * based on visibility, weather, swell, fish activity, accessibility, and safety.
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
     * Calculate visibility score based on water clarity.
     * Uses turbidity and chlorophyll-a when available.
     */
    fun scoreVisibility(waterQuality: WaterQuality?, baseVisibilityM: Double?): Int {
        val visM = waterQuality?.visibility ?: baseVisibilityM ?: 10.0

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
     * Calculate weather score based on wind, rain, clouds.
     */
    fun scoreWeather(weather: WeatherData): Int {
        var score = 100

        // Wind penalty (knots)
        score -= when {
            weather.windSpeed <= 5 -> 0
            weather.windSpeed <= 10 -> 10
            weather.windSpeed <= 15 -> 25
            weather.windSpeed <= 20 -> 40
            else -> 60
        }

        // Rain penalty
        score -= when {
            weather.precipitation <= 0 -> 0
            weather.precipitation <= 1 -> 5
            weather.precipitation <= 5 -> 15
            else -> 30
        }

        // Cloud cover penalty (minor)
        score -= (weather.cloudCover / 20)

        return score.coerceIn(0, 100)
    }

    /**
     * Calculate swell score based on wave height and period.
     */
    fun scoreSwell(ocean: OceanData): Int {
        val waveHeightFt = ocean.waveHeight * 3.28084

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
     * Calculate fish activity score based on moon phase, season, recent sightings.
     */
    fun scoreFishActivity(moonPhase: Double, seasonalMultiplier: Double, recentSightings: Int): Int {
        var score = 50

        // Moon phase bonus (new moon and full moon best for pelagics)
        val moonBonus = when {
            moonPhase < 0.1 || moonPhase > 0.9 -> 20  // New moon
            moonPhase in 0.45..0.55 -> 15             // Full moon
            else -> 5
        }
        score += moonBonus

        // Seasonal multiplier (1.0 = average, 1.5 = peak season)
        score = (score * seasonalMultiplier).toInt()

        // Recent sightings bonus
        score += (recentSightings * 3).coerceAtMost(20)

        return score.coerceIn(0, 100)
    }

    /**
     * Calculate accessibility score.
     */
    fun scoreAccessibility(isShore: Boolean, hasParking: Boolean, permitRequired: Boolean): Int {
        var score = if (isShore) 90 else 60  // Shore dives more accessible

        if (hasParking) score += 5
        if (permitRequired) score -= 15

        return score.coerceIn(0, 100)
    }

    /**
     * Calculate safety score based on currents, hazards.
     */
    fun scoreSafety(currentStrength: Double, hasHazards: Boolean, sharkRisk: String): Int {
        var score = 100

        // Current penalty
        score -= when {
            currentStrength <= 0.5 -> 0
            currentStrength <= 1.0 -> 15
            currentStrength <= 2.0 -> 35
            else -> 60
        }

        // Hazards
        if (hasHazards) score -= 20

        // Shark risk
        score -= when (sharkRisk.lowercase()) {
            "low" -> 0
            "moderate" -> 10
            "high" -> 30
            else -> 5
        }

        return score.coerceIn(0, 100)
    }

    /**
     * Calculate overall Shaka Score from all components.
     */
    fun calculateOverall(breakdown: ScoreBreakdown): Int {
        // Weighted average
        val weights = mapOf(
            breakdown.visibility to 0.25,
            breakdown.weather to 0.20,
            breakdown.swell to 0.20,
            breakdown.fishActivity to 0.15,
            breakdown.accessibility to 0.10,
            breakdown.safety to 0.10
        )

        return weights.entries.sumOf { (score, weight) -> (score * weight).toInt() }
    }

    /**
     * Generate complete Shaka Score for a spot and date.
     */
    fun generateScore(
        targetDate: String,
        weather: WeatherData,
        ocean: OceanData,
        waterQuality: WaterQuality?,
        moonPhase: Double,
        seasonalMultiplier: Double,
        recentSightings: Int,
        isShore: Boolean,
        hasParking: Boolean,
        permitRequired: Boolean,
        currentStrength: Double,
        hasHazards: Boolean,
        sharkRisk: String
    ): ShakaScore {
        val breakdown = ScoreBreakdown(
            visibility = scoreVisibility(waterQuality, null),
            weather = scoreWeather(weather),
            swell = scoreSwell(ocean),
            fishActivity = scoreFishActivity(moonPhase, seasonalMultiplier, recentSightings),
            accessibility = scoreAccessibility(isShore, hasParking, permitRequired),
            safety = scoreSafety(currentStrength, hasHazards, sharkRisk)
        )

        return ShakaScore(
            overall = calculateOverall(breakdown),
            confidence = confidenceForDate(targetDate),
            breakdown = breakdown
        )
    }
}
