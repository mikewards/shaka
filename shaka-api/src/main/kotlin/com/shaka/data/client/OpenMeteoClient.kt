package com.shaka.data.client

import com.shaka.model.OceanData
import com.shaka.model.WeatherData
import io.ktor.client.call.*
import io.ktor.client.request.*
import kotlinx.serialization.Serializable
import org.slf4j.LoggerFactory

/**
 * Client for Open-Meteo weather and marine APIs.
 * Free, no API key required.
 * 
 * ENTERPRISE PATTERNS:
 * - Uses shared HttpClient (HttpClientFactory.shared)
 * - Rate limited (5 req/sec via RateLimiters.openMeteo)
 * - Graceful fallback to default values on failure
 * 
 * Weather: https://api.open-meteo.com/v1/forecast
 * Marine: https://marine-api.open-meteo.com/v1/marine (includes real SST data!)
 */
class OpenMeteoClient {

    private val logger = LoggerFactory.getLogger(OpenMeteoClient::class.java)

    // Use shared HTTP client - DO NOT create a new one
    private val client = HttpClientFactory.shared

    /**
     * Get weather forecast for a location and date.
     */
    suspend fun getWeather(lat: Double, lon: Double, date: String): WeatherData {
        return try {
            // Rate limit
            RateLimiters.openMeteo.acquire()
            
            val response: OpenMeteoWeatherResponse = client.get("https://api.open-meteo.com/v1/forecast") {
                parameter("latitude", lat)
                parameter("longitude", lon)
                parameter("start_date", date)
                parameter("end_date", date)
                parameter("hourly", "temperature_2m,precipitation,cloudcover,windspeed_10m,winddirection_10m,visibility")
                parameter("timezone", "auto")
            }.body()

            val currentHour = java.time.LocalTime.now().hour
            val idx = currentHour.coerceAtMost((response.hourly.temperature_2m?.size ?: 1) - 1)

            WeatherData(
                temperature = response.hourly.temperature_2m?.getOrNull(idx) ?: 25.0,
                windSpeed = response.hourly.windspeed_10m?.getOrNull(idx) ?: 10.0,
                windDirection = response.hourly.winddirection_10m?.getOrNull(idx)?.toInt() ?: 0,
                precipitation = response.hourly.precipitation?.getOrNull(idx) ?: 0.0,
                cloudCover = response.hourly.cloudcover?.getOrNull(idx)?.toInt() ?: 50,
                visibility = response.hourly.visibility?.getOrNull(idx) ?: 10000.0
            )
        } catch (e: Exception) {
            logger.warn("Open-Meteo weather API failed for ($lat, $lon): ${e.message}")
            // Return default values if API fails
            WeatherData(
                temperature = 25.0,
                windSpeed = 10.0,
                windDirection = 90,
                precipitation = 0.0,
                cloudCover = 30,
                visibility = 10000.0
            )
        }
    }

    /**
     * Get marine/ocean data for a location and date.
     * Now includes REAL sea surface temperature from Open-Meteo!
     */
    suspend fun getMarineData(lat: Double, lon: Double, date: String): OceanData {
        return try {
            // Rate limit
            RateLimiters.openMeteo.acquire()
            
            val response: OpenMeteoMarineResponse = client.get("https://marine-api.open-meteo.com/v1/marine") {
                parameter("latitude", lat)
                parameter("longitude", lon)
                parameter("start_date", date)
                parameter("end_date", date)
                parameter("hourly", "wave_height,wave_period,wave_direction,swell_wave_height,swell_wave_period,swell_wave_direction,ocean_current_velocity,sea_surface_temperature")
                parameter("daily", "wave_height_max,wave_period_max")
                parameter("timezone", "auto")
            }.body()

            // Get midday values
            val idx = 12.coerceAtMost((response.hourly.wave_height?.size ?: 1) - 1)
            
            // Get REAL SST from Open-Meteo
            val sst = response.hourly.sea_surface_temperature?.getOrNull(idx)
            if (sst != null) {
                logger.info("Open-Meteo SST for ($lat, $lon): ${String.format("%.1f", sst)}°C / ${String.format("%.0f", sst * 9/5 + 32)}°F")
            } else {
                logger.debug("Open-Meteo SST unavailable for ($lat, $lon)")
            }

            OceanData(
                waveHeight = response.hourly.wave_height?.getOrNull(idx) ?: 1.0,
                wavePeriod = response.hourly.wave_period?.getOrNull(idx) ?: 8.0,
                waveDirection = response.hourly.wave_direction?.getOrNull(idx)?.toInt() ?: 0,
                waterTemperature = sst ?: 15.0,
                swellHeight = response.hourly.swell_wave_height?.getOrNull(idx) ?: 0.5,
                swellDirection = response.hourly.swell_wave_direction?.getOrNull(idx)?.toInt() ?: 0,
                swellPeriod = response.hourly.swell_wave_period?.getOrNull(idx) ?: 0.0,
                rawSST = sst
            )
        } catch (e: Exception) {
            logger.warn("Open-Meteo Marine API failed for ($lat, $lon): ${e.message}")
            OceanData(
                waveHeight = 1.0,
                wavePeriod = 8.0,
                waveDirection = 270,
                waterTemperature = 15.0,
                swellHeight = 0.5,
                swellDirection = 270
            )
        }
    }
    
    /**
     * Get weather forecast for a date range (batch request - much faster than per-day).
     * Returns one WeatherData per day.
     */
    suspend fun getWeatherRange(lat: Double, lon: Double, startDate: String, endDate: String): List<WeatherData> {
        return try {
            RateLimiters.openMeteo.acquire()
            
            val response: OpenMeteoWeatherResponse = client.get("https://api.open-meteo.com/v1/forecast") {
                parameter("latitude", lat)
                parameter("longitude", lon)
                parameter("start_date", startDate)
                parameter("end_date", endDate)
                parameter("hourly", "temperature_2m,precipitation,cloudcover,windspeed_10m,winddirection_10m,visibility")
                parameter("timezone", "auto")
            }.body()
            
            // Extract midday values for each day (hourly data: 24 values per day)
            val hoursTotal = response.hourly.temperature_2m?.size ?: 0
            val numDays = hoursTotal / 24
            
            val currentHour = java.time.LocalTime.now().hour
            (0 until numDays).map { day ->
                val hourForDay = if (day == 0) currentHour else 12
                val idx = (day * 24) + hourForDay
                WeatherData(
                    temperature = response.hourly.temperature_2m?.getOrNull(idx) ?: 25.0,
                    windSpeed = response.hourly.windspeed_10m?.getOrNull(idx) ?: 10.0,
                    windDirection = response.hourly.winddirection_10m?.getOrNull(idx)?.toInt() ?: 0,
                    precipitation = response.hourly.precipitation?.getOrNull(idx) ?: 0.0,
                    cloudCover = response.hourly.cloudcover?.getOrNull(idx)?.toInt() ?: 50,
                    visibility = response.hourly.visibility?.getOrNull(idx) ?: 10000.0
                )
            }
        } catch (e: Exception) {
            logger.warn("Open-Meteo weather range API failed: ${e.message}")
            emptyList()
        }
    }
    
    /**
     * Get marine data for a date range (batch request - much faster than per-day).
     * Returns one OceanData per day.
     */
    suspend fun getMarineDataRange(lat: Double, lon: Double, startDate: String, endDate: String): List<OceanData> {
        return try {
            RateLimiters.openMeteo.acquire()
            
            val response: OpenMeteoMarineResponse = client.get("https://marine-api.open-meteo.com/v1/marine") {
                parameter("latitude", lat)
                parameter("longitude", lon)
                parameter("start_date", startDate)
                parameter("end_date", endDate)
                parameter("hourly", "wave_height,wave_period,wave_direction,swell_wave_height,swell_wave_period,swell_wave_direction,sea_surface_temperature")
                parameter("timezone", "auto")
            }.body()
            
            // Extract midday values for each day
            val hoursTotal = response.hourly.wave_height?.size ?: 0
            val numDays = hoursTotal / 24
            
            (0 until numDays).map { day ->
                val idx = (day * 24) + 12
                OceanData(
                    waveHeight = response.hourly.wave_height?.getOrNull(idx) ?: 1.0,
                    wavePeriod = response.hourly.wave_period?.getOrNull(idx) ?: 8.0,
                    waveDirection = response.hourly.wave_direction?.getOrNull(idx)?.toInt() ?: 0,
                    waterTemperature = response.hourly.sea_surface_temperature?.getOrNull(idx) ?: 20.0,
                    swellHeight = response.hourly.swell_wave_height?.getOrNull(idx) ?: 0.5,
                    swellDirection = response.hourly.swell_wave_direction?.getOrNull(idx)?.toInt() ?: 0,
                    swellPeriod = response.hourly.swell_wave_period?.getOrNull(idx) ?: 0.0
                )
            }
        } catch (e: Exception) {
            logger.warn("Open-Meteo marine range API failed: ${e.message}")
            emptyList()
        }
    }
}

@Serializable
data class OpenMeteoWeatherResponse(
    val hourly: OpenMeteoHourlyWeather
)

@Serializable
data class OpenMeteoHourlyWeather(
    val temperature_2m: List<Double>? = null,
    val precipitation: List<Double>? = null,
    val cloudcover: List<Double>? = null,
    val windspeed_10m: List<Double>? = null,
    val winddirection_10m: List<Double>? = null,
    val visibility: List<Double>? = null
)

@Serializable
data class OpenMeteoMarineResponse(
    val hourly: OpenMeteoHourlyMarine
)

@Serializable
data class OpenMeteoHourlyMarine(
    val wave_height: List<Double>? = null,
    val wave_period: List<Double>? = null,
    val wave_direction: List<Double>? = null,
    val swell_wave_height: List<Double>? = null,
    val swell_wave_period: List<Double>? = null,
    val swell_wave_direction: List<Double>? = null,
    val ocean_current_velocity: List<Double>? = null,
    val sea_surface_temperature: List<Double>? = null
)
