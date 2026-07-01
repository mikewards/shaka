package com.shaka.service

import com.shaka.data.cache.SpotDataCache
import com.shaka.data.client.OpenMeteoClient
import com.shaka.data.client.SpotDatabase
import com.shaka.model.*
import com.shaka.scoring.GibsColormap
import com.shaka.scoring.ShakaScorer
import com.shaka.util.SpotTime
import kotlin.math.abs
import kotlin.math.roundToInt
import org.slf4j.LoggerFactory
import java.time.Instant
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
        // Use the spot's real local date (not the server's UTC date) so forecast
        // days line up with the spot-local series and don't drift by a day.
        val seriesTz = cached?.swellSeries?.timezoneId ?: cached?.windSeries?.timezoneId
        val today = SpotTime.spotLocalDate(seriesTz, spot.coordinates.lon)
        
        // Resolve chlorophyll once for all forecast days (doesn't change much day-to-day)
        val effectiveChl = cached?.chlorophyll?.value
            ?: GibsColormap.estimateFromGibsColors(cached?.gibsChlorophyll?.value)
        val visibilityStr = effectiveChl?.let { chl ->
            getChlorophyllCategory(chl)
        } ?: "No satellite data"
        
        // Day 0: Use fully cached data (instant!)
        if (cached != null && cached.swell != null && cached.wind != null) {
            val sst = cached.sst?.value ?: 24.0
            
            // Extract only the values the scorer uses
            val windSpeedKmh = cached.wind.value.speedKnots / 0.539957
            val waveHeightM = (cached.swell.value.correctedHeightFt ?: cached.swell.value.heightFt) / 3.28084
            
            val score = ShakaScorer.generateScore(
                targetDate = today.toString(),
                windSpeedKmh = windSpeedKmh,
                waveHeightM = waveHeightM,
                chlorophyllMgM3 = effectiveChl,
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
                    swell = "${cached.swell.value.heightFt.roundToInt()}ft @ ${cached.swell.value.periodSec.toInt()}s ${cached.swell.value.direction}",
                    wind = "${cached.wind.value.speedKnots.toInt()} kts ${cached.wind.value.direction}",
                    swellCorrected = cached.swell.value.correctedHeightFt?.let { "${it.roundToInt()}ft @ ${cached.swell.value.periodSec.toInt()}s ${cached.swell.value.direction}" },
                    secondarySwell = cached.swell.value.secondaryHeightFt?.takeIf { it >= 0.5 }?.let { "${it.roundToInt()}ft @ ${cached.swell.value.secondaryPeriodSec?.toInt() ?: 0}s ${cached.swell.value.secondaryDirection ?: ""}" },
                    secondarySwellCorrected = cached.swell.value.secondaryCorrectedHeightFt?.takeIf { it >= 0.5 }?.let { "${it.roundToInt()}ft @ ${cached.swell.value.secondaryPeriodSec?.toInt() ?: 0}s ${cached.swell.value.secondaryDirection ?: ""}" },
                    exposureBearing = cached.exposure?.bearing,
                    exposureWidth = cached.exposure?.width,
                    bathymetryDepthM = cached.exposure?.depthM,
                    swellHeightFt = cached.swell.value.correctedHeightFt ?: cached.swell.value.heightFt,
                    swellPeriodSec = cached.swell.value.periodSec,
                    swellDirection = cached.swell.value.direction,
                    windSpeedKts = cached.wind.value.speedKnots,
                    windDirectionCardinal = cached.wind.value.direction,
                    waterTempC = sst
                )
            )
        }
        
        // Days 1-N: Prefer the already-prefetched in-memory hourly swell/wind
        // series (covers ~7 days, refreshed daily by prefetchHourlySwellWind).
        // This is the cache the pre-fetch system exists to serve; hitting it
        // keeps the forecast instant instead of making live Open-Meteo calls on
        // every open (the ~7s regression).
        val startDay = if (forecasts.isNotEmpty()) 1 else 0
        val remainingDays = days - startDay

        if (remainingDays > 0) {
            val fromSeries = buildForecastDaysFromSeries(
                cached, spot.coordinates.lon, startDay, days, effectiveChl, visibilityStr
            )
            if (fromSeries != null) {
                forecasts += fromSeries
                return forecasts
            }
        }

        // Fallback: series not loaded for this spot — fetch from Open-Meteo.
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

                    // Never fabricate identical fallback values: if a day is
                    // genuinely missing from the range response, skip it rather
                    // than emitting the same hardcoded numbers for every day
                    // (which made all future days look identical).
                    val weather = weatherData.getOrNull(dayIndex) ?: continue
                    val ocean = oceanData.getOrNull(dayIndex) ?: continue
                    val sst = cached?.sst?.value ?: ocean.waterTemperature
                    
                    val score = ShakaScorer.generateScore(
                        targetDate = dateStr,
                        windSpeedKmh = weather.windSpeed,
                        waveHeightM = ocean.waveHeight,
                        chlorophyllMgM3 = effectiveChl,
                        solunarDayRating = cached?.solunar?.value?.dayRating,
                        moonPhase = cached?.solunar?.value?.moonPhase
                    )
                    
                    val secSwell = ocean.secondarySwellHeight?.let { SpotDataCache.metersToFeet(it) }?.takeIf { it >= 0.5 }
                    val secPeriod = ocean.secondarySwellPeriod
                    val secDir = ocean.secondarySwellDirection?.toDouble()?.let { SpotDataCache.degreesToCardinal(it) }
                    
                    forecasts += DayForecast(
                        date = dateStr,
                        shakaScore = score.overall,
                        confidence = score.confidence - (i * 5),
                        conditions = SpotConditions(
                            visibility = visibilityStr,
                            waterTemp = "${sst.toInt()}°C / ${((sst * 9/5) + 32).toInt()}°F",
                            swell = "${ocean.waveHeight.toInt()}-${(ocean.waveHeight + 1).toInt()}ft @ ${ocean.wavePeriod.toInt()}s",
                            wind = "${SpotDataCache.kmhToKnots(weather.windSpeed).toInt()} kts ${SpotDataCache.degreesToCardinal(weather.windDirection.toDouble())}",
                            secondarySwell = secSwell?.let { "${it.toInt()}ft @ ${secPeriod?.toInt() ?: 0}s ${secDir ?: ""}" },
                            exposureBearing = cached?.exposure?.bearing,
                            exposureWidth = cached?.exposure?.width,
                            bathymetryDepthM = cached?.exposure?.depthM,
                            swellHeightFt = SpotDataCache.metersToFeet(ocean.waveHeight),
                            swellPeriodSec = ocean.wavePeriod,
                            swellDirection = SpotDataCache.degreesToCardinal(ocean.waveDirection.toDouble()),
                            windSpeedKts = SpotDataCache.kmhToKnots(weather.windSpeed),
                            windDirectionCardinal = SpotDataCache.degreesToCardinal(weather.windDirection.toDouble()),
                            waterTempC = sst
                        )
                    )
                }
            } catch (e: Exception) {
                logger.warn("Forecast fetch failed for $spotId: ${e.message}")
            }
        }

        return forecasts
    }

    
    /**
     * Build forecast days [startDay, days) from the prefetched in-memory hourly
     * swell/wind series (no API calls). Points are grouped by spot-local date
     * the same way /spots/{id}/hourly does, and each future day uses its
     * near-noon sample so days differ from one another. Returns null when the
     * series is missing or does not cover every requested day, so the caller
     * can fall back to a live fetch.
     */
    private fun buildForecastDaysFromSeries(
        cached: SpotDataCache.SpotData?,
        lon: Double,
        startDay: Int,
        days: Int,
        effectiveChl: Double?,
        visibilityStr: String
    ): List<DayForecast>? {
        val swellPts = cached?.swellSeries?.points.orEmpty()
        val windPts = cached?.windSeries?.points.orEmpty()
        if (swellPts.isEmpty() || windPts.isEmpty()) return null

        val tz = cached?.swellSeries?.timezoneId ?: cached?.windSeries?.timezoneId
        val zone = SpotTime.resolveZone(tz, lon)
        val today = SpotTime.spotLocalDate(tz, lon)

        fun hourInZone(epochMs: Long) = Instant.ofEpochMilli(epochMs).atZone(zone).hour

        val swellByDate = swellPts
            .groupBy { SpotTime.localDateOf(it.epochMs, zone).toString() }
            .mapValues { (_, pts) -> pts.minByOrNull { abs(hourInZone(it.epochMs) - 12) }!! }
        val windByDate = windPts
            .groupBy { SpotTime.localDateOf(it.epochMs, zone).toString() }
            .mapValues { (_, pts) -> pts.minByOrNull { abs(hourInZone(it.epochMs) - 12) }!! }

        val sstC = cached?.sst?.value ?: 24.0
        val result = ArrayList<DayForecast>(days - startDay)
        for (i in startDay until days) {
            val dateStr = today.plusDays(i.toLong()).toString()
            val sw = swellByDate[dateStr] ?: return null
            val wd = windByDate[dateStr] ?: return null

            val swellDir = SpotDataCache.degreesToCardinal(sw.directionDeg.toDouble())
            val windDir = SpotDataCache.degreesToCardinal(wd.directionDeg.toDouble())
            val heightFt = sw.correctedHeightFt ?: sw.heightFt

            val score = ShakaScorer.generateScore(
                targetDate = dateStr,
                windSpeedKmh = wd.speedKts / 0.539957,
                waveHeightM = heightFt / 3.28084,
                chlorophyllMgM3 = effectiveChl,
                solunarDayRating = cached?.solunar?.value?.dayRating,
                moonPhase = cached?.solunar?.value?.moonPhase
            )

            val secHt = sw.secondaryHeightFt?.takeIf { it >= 0.5 }
            result += DayForecast(
                date = dateStr,
                shakaScore = score.overall,
                confidence = score.confidence - (i * 5),
                conditions = SpotConditions(
                    visibility = visibilityStr,
                    waterTemp = "${sstC.toInt()}°C / ${((sstC * 9 / 5) + 32).toInt()}°F",
                    swell = "${sw.heightFt.roundToInt()}ft @ ${sw.periodSec.toInt()}s $swellDir",
                    wind = "${wd.speedKts.toInt()} kts $windDir",
                    swellCorrected = sw.correctedHeightFt?.let {
                        "${it.roundToInt()}ft @ ${sw.periodSec.toInt()}s $swellDir"
                    },
                    secondarySwell = secHt?.let {
                        val secDir = sw.secondaryDirectionDeg?.let { d -> SpotDataCache.degreesToCardinal(d.toDouble()) } ?: ""
                        "${it.roundToInt()}ft @ ${sw.secondaryPeriodSec?.toInt() ?: 0}s $secDir"
                    },
                    exposureBearing = cached?.exposure?.bearing,
                    exposureWidth = cached?.exposure?.width,
                    bathymetryDepthM = cached?.exposure?.depthM,
                    swellHeightFt = heightFt,
                    swellPeriodSec = sw.periodSec,
                    swellDirection = swellDir,
                    windSpeedKts = wd.speedKts,
                    windDirectionCardinal = windDir,
                    waterTempC = sstC
                )
            )
        }
        return result
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
                
                val secSwell2 = ocean.secondarySwellHeight?.let { SpotDataCache.metersToFeet(it) }?.takeIf { it >= 0.5 }
                val secPeriod2 = ocean.secondarySwellPeriod
                val secDir2 = ocean.secondarySwellDirection?.toDouble()?.let { SpotDataCache.degreesToCardinal(it) }
                
                forecasts += DayForecast(
                    date = dateStr,
                    shakaScore = score.overall,
                    confidence = score.confidence - (i * 5),
                    conditions = SpotConditions(
                        visibility = "Check conditions",
                        waterTemp = "${sst.toInt()}°C / ${((sst * 9/5) + 32).toInt()}°F",
                        swell = "${ocean.waveHeight.toInt()}-${(ocean.waveHeight + 1).toInt()}ft @ ${ocean.wavePeriod.toInt()}s",
                        wind = "${SpotDataCache.kmhToKnots(weather.windSpeed).toInt()} kts ${SpotDataCache.degreesToCardinal(weather.windDirection.toDouble())}",
                        secondarySwell = secSwell2?.let { "${it.toInt()}ft @ ${secPeriod2?.toInt() ?: 0}s ${secDir2 ?: ""}" },
                        swellHeightFt = SpotDataCache.metersToFeet(ocean.waveHeight),
                        swellPeriodSec = ocean.wavePeriod,
                        swellDirection = SpotDataCache.degreesToCardinal(ocean.waveDirection.toDouble()),
                        windSpeedKts = SpotDataCache.kmhToKnots(weather.windSpeed),
                        windDirectionCardinal = SpotDataCache.degreesToCardinal(weather.windDirection.toDouble()),
                        waterTempC = sst
                    )
                )
            }
        } catch (e: Exception) {
            logger.warn("Forecast fetch failed for ($lat, $lon): ${e.message}")
        }

        return forecasts
    }
}
