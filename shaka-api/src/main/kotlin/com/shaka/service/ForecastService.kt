package com.shaka.service

import com.shaka.data.client.OpenMeteoClient
import com.shaka.data.client.SpotDatabase
import com.shaka.model.*
import com.shaka.scoring.ShakaScorer
import java.time.LocalDate

/**
 * Service for generating multi-day forecasts for spearfishing spots.
 */
class ForecastService {

    private val openMeteo = OpenMeteoClient()
    private val spotDb = SpotDatabase

    /**
     * Generate forecast for a spot for the specified number of days.
     */
    suspend fun getForecast(spotId: String, days: Int): List<DayForecast> {
        val spot = spotDb.findSpotById(spotId) ?: return emptyList()
        val forecasts = mutableListOf<DayForecast>()

        val today = LocalDate.now()

        for (i in 0 until days.coerceAtMost(30)) {
            val date = today.plusDays(i.toLong())
            val dateStr = date.toString()

            val weather = openMeteo.getWeather(spot.coordinates.lat, spot.coordinates.lon, dateStr)
            val ocean = openMeteo.getMarineData(spot.coordinates.lat, spot.coordinates.lon, dateStr)

            val score = ShakaScorer.generateScore(
                targetDate = dateStr,
                weather = weather,
                ocean = ocean,
                waterQuality = null,
                moonPhase = getMoonPhase(dateStr),
                seasonalMultiplier = 1.0,
                recentSightings = 0,
                isShore = spot.access == "shore",
                hasParking = true,
                permitRequired = false,
                currentStrength = 0.5,
                hasHazards = false,
                sharkRisk = "low"
            )

            forecasts += DayForecast(
                date = dateStr,
                shakaScore = score.overall,
                confidence = score.confidence,
                conditions = SpotConditions(
                    visibility = "${(score.breakdown.visibility / 5)}m",
                    waterTemp = "${ocean.waterTemperature.toInt()}C",
                    swell = "${ocean.waveHeight.toInt()}-${(ocean.waveHeight + 1).toInt()}ft",
                    wind = "${weather.windSpeed.toInt()} knots"
                )
            )
        }

        return forecasts
    }

    private fun getMoonPhase(date: String): Double {
        val dayOfYear = LocalDate.parse(date).dayOfYear
        return ((dayOfYear % 29) / 29.0)
    }
}
