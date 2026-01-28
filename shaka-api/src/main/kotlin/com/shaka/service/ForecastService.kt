package com.shaka.service

import com.shaka.data.client.CopernicusClient
import com.shaka.data.client.OpenMeteoClient
import com.shaka.data.client.SpotDatabase
import com.shaka.model.*
import com.shaka.scoring.ShakaScorer
import java.time.LocalDate

/**
 * Service for generating multi-day forecasts for spearfishing spots.
 * Uses real data from:
 * - Open-Meteo for weather and swell (free, no auth)
 * - NOAA for SST (free, no auth) 
 * - Copernicus for chlorophyll/visibility (requires credentials)
 */
class ForecastService {

    private val openMeteo = OpenMeteoClient()
    private val copernicus = CopernicusClient()
    private val spotDb = SpotDatabase

    /**
     * Generate forecast for a spot for the specified number of days.
     */
    suspend fun getForecast(spotId: String, days: Int): List<DayForecast> {
        val spot = spotDb.findSpotById(spotId) ?: return emptyList()
        val forecasts = mutableListOf<DayForecast>()

        val today = LocalDate.now()

        for (i in 0 until days.coerceAtMost(14)) { // Limit to 14 days for realistic forecasts
            val date = today.plusDays(i.toLong())
            val dateStr = date.toString()

            val weather = openMeteo.getWeather(spot.coordinates.lat, spot.coordinates.lon, dateStr)
            val ocean = openMeteo.getMarineData(spot.coordinates.lat, spot.coordinates.lon, dateStr)
            val waterQuality = copernicus.getWaterQuality(spot.coordinates.lat, spot.coordinates.lon, dateStr)

            // Use real SST - prefer NOAA, fallback to Open-Meteo (both real data!)
            val actualSST = waterQuality.seaSurfaceTemp ?: ocean.waterTemperature

            val score = ShakaScorer.generateScore(
                targetDate = dateStr,
                weather = weather,
                ocean = ocean,
                waterQuality = waterQuality,
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
                    visibility = "${waterQuality.visibility?.toInt() ?: 15}m (${waterQuality.visibilityCategory})",
                    waterTemp = "${actualSST.toInt()}°C / ${((actualSST * 9/5) + 32).toInt()}°F",
                    swell = "${ocean.waveHeight.toInt()}-${(ocean.waveHeight + 1).toInt()}ft @ ${ocean.wavePeriod.toInt()}s",
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
