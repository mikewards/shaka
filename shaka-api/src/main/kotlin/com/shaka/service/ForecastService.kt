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
 * - Chlorophyll: Uses cached value for all days (doesn't change much day-to-day)
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
        
        // Get cached chlorophyll for all forecast days (doesn't change much day-to-day)
        val cachedChlorophyll = cached?.chlorophyll?.value
        val visibilityStr = cachedChlorophyll?.let { chl ->
            getChlorophyllCategory(chl)
        } ?: "No satellite data"
        
        // Day 0: Use fully cached data (instant!)
        if (cached != null && cached.swell != null && cached.wind != null) {
            val sst = cached.sst?.value ?: 24.0
            
            // Extract only the values the scorer uses
            val windSpeedKmh = cached.wind.value.speedKnots / 0.539957
            val waveHeightM = cached.swell.value.heightFt / 3.28084
            
            val score = ShakaScorer.generateScore(
                targetDate = today.toString(),
                windSpeedKmh = windSpeedKmh,
                waveHeightM = waveHeightM,
                chlorophyllMgM3 = cachedChlorophyll,
                solunarDayRating = cached.solunar?.value?.dayRating,
                moonPhase = cached.solunar?.value?.moonPhase
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
                    
                    val score = ShakaScorer.generateScore(
                        targetDate = dateStr,
                        windSpeedKmh = weather.windSpeed,
                        waveHeightM = ocean.waveHeight,
                        chlorophyllMgM3 = cachedChlorophyll,
                        solunarDayRating = cached?.solunar?.value?.dayRating,
                        moonPhase = cached?.solunar?.value?.moonPhase
                    )
                    
                    forecasts += DayForecast(
                        date = dateStr,
                        shakaScore = score.overall,
                        confidence = score.confidence - (i * 5), // Confidence decreases further out
                        conditions = SpotConditions(
                            visibility = visibilityStr,
                            waterTemp = "${sst.toInt()}°C / ${((sst * 9/5) + 32).toInt()}°F",
                            swell = "${ocean.waveHeight.toInt()}-${(ocean.waveHeight + 1).toInt()}ft @ ${ocean.wavePeriod.toInt()}s",
                            wind = "${SpotDataCache.kmhToKnots(weather.windSpeed).toInt()} kts ${SpotDataCache.degreesToCardinal(weather.windDirection.toDouble())}"
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

    
    private fun getChlorophyllCategory(chl: Double): String {
        return when {
            chl < 0.1  -> "Crystal clear"
            chl < 0.3  -> "Blue water"
            chl < 0.5  -> "Slight haze"
            chl < 1.0  -> "Green tint"
            chl < 3.0  -> "Murky"
            chl < 5.0  -> "Can't see your fins"
            chl < 10.0 -> "Can't see your hand"
            else       -> "Zero vis"
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
                
                val score = ShakaScorer.generateScore(
                    targetDate = dateStr,
                    windSpeedKmh = weather.windSpeed,
                    waveHeightM = ocean.waveHeight,
                    chlorophyllMgM3 = null,        // No satellite data for ad-hoc locations
                    solunarDayRating = null,        // No cached solunar for ad-hoc locations
                    moonPhase = null                // Falls back to neutral 55
                )
                
                forecasts += DayForecast(
                    date = dateStr,
                    shakaScore = score.overall,
                    confidence = score.confidence - (i * 5), // Confidence decreases further out
                    conditions = SpotConditions(
                        visibility = "Check conditions",
                        waterTemp = "${sst.toInt()}°C / ${((sst * 9/5) + 32).toInt()}°F",
                        swell = "${ocean.waveHeight.toInt()}-${(ocean.waveHeight + 1).toInt()}ft @ ${ocean.wavePeriod.toInt()}s",
                        wind = "${SpotDataCache.kmhToKnots(weather.windSpeed).toInt()} kts ${SpotDataCache.degreesToCardinal(weather.windDirection.toDouble())}"
                    )
                )
            }
        } catch (e: Exception) {
            logger.warn("Forecast fetch failed for ($lat, $lon): ${e.message}")
        }

        return forecasts
    }
}
