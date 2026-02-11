package com.shaka.service

import com.shaka.data.cache.SpotDataCache
import com.shaka.data.client.OpenMeteoClient
import com.shaka.data.client.SpotDatabase
import com.shaka.model.*
import com.shaka.scoring.ShakaScorer
import org.slf4j.LoggerFactory
import java.time.LocalDate

/**
 * Service for generating multi-day forecasts for spearfishing spots.
 * 
 * OPTIMIZED:
 * - Day 0 (today): Uses cached data from SpotDataCache (instant!)
 * - Days 1-5: Uses batch Open-Meteo calls (2 API calls instead of 10+)
 * - Visibility: Uses cached value for all days (doesn't change much day-to-day)
 */
class ForecastService {

    private val logger = LoggerFactory.getLogger(ForecastService::class.java)
    private val openMeteo = OpenMeteoClient()
    private val spotDb = SpotDatabase

    /**
     * Generate forecast for a spot for the specified number of days.
     * Uses cached data where available for instant response.
     */
    suspend fun getForecast(spotId: String, days: Int): List<DayForecast> {
        val spot = spotDb.findSpotById(spotId) ?: return emptyList()
        val cached = SpotDataCache.get(spotId)
        val forecasts = mutableListOf<DayForecast>()
        val today = LocalDate.now()
        
        // Get cached visibility for all forecast days (doesn't change much)
        val cachedVisibility = cached?.visibility?.value
        val visibilityStr = cachedVisibility?.let { 
            "${it.toInt()}m (${getVisibilityCategory(it)})" 
        } ?: "15m (Good)"
        
        // Day 0: Use fully cached data (instant!)
        if (cached != null && cached.swell != null && cached.wind != null) {
            val sst = cached.sst?.value ?: 24.0
            val chlorophyll = cached.chlorophyll?.value
            
            val weather = WeatherData(
                temperature = 25.0,
                windSpeed = cached.wind.value.speedKnots / 0.539957,
                windDirection = 0,
                precipitation = 0.0,
                cloudCover = 50,
                visibility = 10000.0
            )
            
            val ocean = OceanData(
                waveHeight = cached.swell.value.heightFt / 3.28084,
                wavePeriod = cached.swell.value.periodSec,
                waveDirection = 0,
                waterTemperature = sst,
                swellHeight = (cached.swell.value.swellHeightFt ?: cached.swell.value.heightFt) / 3.28084,
                swellDirection = 0
            )
            
            val waterQuality = WaterQuality(
                chlorophyllA = chlorophyll,
                turbidity = null,
                visibility = cachedVisibility,
                seaSurfaceTemp = sst,
                dataSource = "Cached"
            )
            
            val score = ShakaScorer.generateScore(
                targetDate = today.toString(),
                weather = weather,
                ocean = ocean,
                waterQuality = waterQuality,
                moonPhase = getMoonPhase(today.toString()),
                seasonalMultiplier = 1.0,
                recentSightings = 0,
                hasParking = true,
                permitRequired = false
            )
            
            forecasts += DayForecast(
                date = today.toString(),
                shakaScore = score.overall,
                confidence = score.confidence,
                conditions = SpotConditions(
                    visibility = visibilityStr,
                    waterTemp = "${sst.toInt()}°C / ${((sst * 9/5) + 32).toInt()}°F",
                    swell = "${cached.swell.value.heightFt.toInt()}ft @ ${cached.swell.value.periodSec.toInt()}s ${cached.swell.value.direction}",
                    wind = "${cached.wind.value.speedKnots.toInt()} kts ${cached.wind.value.direction}"
                )
            )
        }
        
        // Days 1-N: Fetch from Open-Meteo (just 2 API calls for all days)
        val startDay = if (forecasts.isNotEmpty()) 1 else 0
        val remainingDays = days - startDay
        
        if (remainingDays > 0) {
            try {
                val startDate = today.plusDays(startDay.toLong())
                val endDate = today.plusDays((days - 1).toLong())
                
                // Batch weather fetch
                val weatherData = openMeteo.getWeatherRange(spot.coordinates.lat, spot.coordinates.lon, startDate.toString(), endDate.toString())
                val oceanData = openMeteo.getMarineDataRange(spot.coordinates.lat, spot.coordinates.lon, startDate.toString(), endDate.toString())
                
                for (i in startDay until days) {
                    val date = today.plusDays(i.toLong())
                    val dateStr = date.toString()
                    val dayIndex = i - startDay
                    
                    val weather = weatherData.getOrNull(dayIndex) ?: WeatherData(25.0, 10.0, 0, 0.0, 50, 10000.0)
                    val ocean = oceanData.getOrNull(dayIndex) ?: OceanData(1.0, 8.0, 0, 24.0, 1.0, 0)
                    val sst = cached?.sst?.value ?: ocean.waterTemperature
                    
                    val waterQuality = WaterQuality(
                        chlorophyllA = cached?.chlorophyll?.value,
                        turbidity = null,
                        visibility = cachedVisibility,
                        seaSurfaceTemp = sst,
                        dataSource = "Forecast"
                    )
                    
                    val score = ShakaScorer.generateScore(
                        targetDate = dateStr,
                        weather = weather,
                        ocean = ocean,
                        waterQuality = waterQuality,
                        moonPhase = getMoonPhase(dateStr),
                        seasonalMultiplier = 1.0,
                        recentSightings = 0,
                        hasParking = true,
                        permitRequired = false
                    )
                    
                    forecasts += DayForecast(
                        date = dateStr,
                        shakaScore = score.overall,
                        confidence = score.confidence - (i * 5), // Confidence decreases further out
                        conditions = SpotConditions(
                            visibility = visibilityStr,
                            waterTemp = "${sst.toInt()}°C / ${((sst * 9/5) + 32).toInt()}°F",
                            swell = "${ocean.waveHeight.toInt()}-${(ocean.waveHeight + 1).toInt()}ft @ ${ocean.wavePeriod.toInt()}s",
                            wind = "${weather.windSpeed.toInt()} knots"
                        )
                    )
                }
            } catch (e: Exception) {
                logger.warn("Forecast fetch failed for $spotId: ${e.message}")
                // Return at least today's forecast if we have it
            }
        }

        return forecasts
    }

    private fun getMoonPhase(date: String): Double {
        val dayOfYear = LocalDate.parse(date).dayOfYear
        return ((dayOfYear % 29) / 29.0)
    }
    
    private fun getVisibilityCategory(meters: Double): String {
        return when {
            meters >= 30 -> "Excellent"
            meters >= 15 -> "Good"
            meters >= 8 -> "Fair"
            else -> "Poor"
        }
    }

    /**
     * Generate forecast for a location by coordinates.
     * Used for user-created spots that don't exist in the spot database.
     * 
     * @param lat Latitude
     * @param lon Longitude
     * @param days Number of days to forecast
     * @return List of day forecasts
     */
    suspend fun getForecastForLocation(lat: Double, lon: Double, days: Int): List<DayForecast> {
        val forecasts = mutableListOf<DayForecast>()
        val today = LocalDate.now()
        
        try {
            val endDate = today.plusDays((days - 1).toLong())
            
            // Batch weather fetch for all days
            val weatherData = openMeteo.getWeatherRange(lat, lon, today.toString(), endDate.toString())
            val oceanData = openMeteo.getMarineDataRange(lat, lon, today.toString(), endDate.toString())
            
            for (i in 0 until days) {
                val date = today.plusDays(i.toLong())
                val dateStr = date.toString()
                
                val weather = weatherData.getOrNull(i) ?: WeatherData(25.0, 10.0, 0, 0.0, 50, 10000.0)
                val ocean = oceanData.getOrNull(i) ?: OceanData(1.0, 8.0, 0, 24.0, 1.0, 0)
                val sst = ocean.waterTemperature
                
                val waterQuality = WaterQuality(
                    chlorophyllA = null,
                    turbidity = null,
                    visibility = null,
                    seaSurfaceTemp = sst,
                    dataSource = "Forecast"
                )
                
                val score = ShakaScorer.generateScore(
                    targetDate = dateStr,
                    weather = weather,
                    ocean = ocean,
                    waterQuality = waterQuality,
                    moonPhase = getMoonPhase(dateStr),
                    seasonalMultiplier = 1.0,
                    recentSightings = 0,
                    hasParking = true,
                    permitRequired = false
                )
                
                forecasts += DayForecast(
                    date = dateStr,
                    shakaScore = score.overall,
                    confidence = score.confidence - (i * 5), // Confidence decreases further out
                    conditions = SpotConditions(
                        visibility = "Check conditions",
                        waterTemp = "${sst.toInt()}°C / ${((sst * 9/5) + 32).toInt()}°F",
                        swell = "${ocean.waveHeight.toInt()}-${(ocean.waveHeight + 1).toInt()}ft @ ${ocean.wavePeriod.toInt()}s",
                        wind = "${weather.windSpeed.toInt()} knots"
                    )
                )
            }
        } catch (e: Exception) {
            logger.warn("Forecast fetch failed for ($lat, $lon): ${e.message}")
        }

        return forecasts
    }
}
