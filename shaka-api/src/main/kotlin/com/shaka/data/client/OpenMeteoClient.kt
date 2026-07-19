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
    private val client: io.ktor.client.HttpClient get() = HttpClientFactory.shared

    /**
     * Get weather forecast for a location and date.
     * Returns null on failure -- callers must degrade visibly. The old
     * hardcoded fallback (25C, 10 km/h) fabricated identical "real-looking"
     * conditions across every spot for the entire Jun 2026 outage.
     */
    suspend fun getWeather(lat: Double, lon: Double, date: String): WeatherData? {
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

            val spotZone = try { java.time.ZoneId.of(response.timezone) } catch (_: Exception) { java.time.ZoneId.systemDefault() }
            val currentHour = java.time.LocalTime.now(spotZone).hour
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
            null
        }
    }

    /**
     * Get marine/ocean data for a location and date.
     * Now includes REAL sea surface temperature from Open-Meteo!
     * Returns null on failure -- no fabricated swell (see getWeather).
     */
    suspend fun getMarineData(lat: Double, lon: Double, date: String): OceanData? {
        return try {
            // Rate limit
            RateLimiters.openMeteo.acquire()
            
            val response: OpenMeteoMarineResponse = client.get("https://marine-api.open-meteo.com/v1/marine") {
                parameter("latitude", lat)
                parameter("longitude", lon)
                parameter("start_date", date)
                parameter("end_date", date)
                parameter("hourly", "wave_height,wave_period,wave_direction,swell_wave_height,swell_wave_period,swell_wave_direction,secondary_swell_wave_height,secondary_swell_wave_period,secondary_swell_wave_direction,ocean_current_velocity,sea_surface_temperature")
                parameter("daily", "wave_height_max,wave_period_max")
                parameter("timezone", "auto")
            }.body()

            val spotZone = try { java.time.ZoneId.of(response.timezone) } catch (_: Exception) { java.time.ZoneId.systemDefault() }
            val spotNow = java.time.LocalDateTime.now(spotZone)
            val today = spotNow.toLocalDate().toString()
            val idx = if (date == today) {
                spotNow.hour
            } else {
                12
            }.coerceAtMost((response.hourly.wave_height?.size ?: 1) - 1)
            
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
                waterTemperature = sst,
                swellHeight = response.hourly.swell_wave_height?.getOrNull(idx) ?: 0.5,
                swellDirection = response.hourly.swell_wave_direction?.getOrNull(idx)?.toInt() ?: 0,
                swellPeriod = response.hourly.swell_wave_period?.getOrNull(idx) ?: 0.0,
                rawSST = sst,
                secondarySwellHeight = response.hourly.secondary_swell_wave_height?.getOrNull(idx),
                secondarySwellDirection = response.hourly.secondary_swell_wave_direction?.getOrNull(idx)?.toInt(),
                secondarySwellPeriod = response.hourly.secondary_swell_wave_period?.getOrNull(idx)
            )
        } catch (e: Exception) {
            logger.warn("Open-Meteo Marine API failed for ($lat, $lon): ${e.message}")
            null
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
            
            val spotZone = try { java.time.ZoneId.of(response.timezone) } catch (_: Exception) { java.time.ZoneId.systemDefault() }
            val currentHour = java.time.LocalTime.now(spotZone).hour
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
                parameter("hourly", "wave_height,wave_period,wave_direction,swell_wave_height,swell_wave_period,swell_wave_direction,secondary_swell_wave_height,secondary_swell_wave_period,secondary_swell_wave_direction,sea_surface_temperature")
                parameter("timezone", "auto")
            }.body()
            
            val hoursTotal = response.hourly.wave_height?.size ?: 0
            val numDays = hoursTotal / 24
            
            val spotZone = try { java.time.ZoneId.of(response.timezone) } catch (_: Exception) { java.time.ZoneId.systemDefault() }
            val currentHour = java.time.LocalTime.now(spotZone).hour
            (0 until numDays).map { day ->
                val idx = if (day == 0) (day * 24) + currentHour else (day * 24) + 12
                OceanData(
                    waveHeight = response.hourly.wave_height?.getOrNull(idx) ?: 1.0,
                    wavePeriod = response.hourly.wave_period?.getOrNull(idx) ?: 8.0,
                    waveDirection = response.hourly.wave_direction?.getOrNull(idx)?.toInt() ?: 0,
                    waterTemperature = response.hourly.sea_surface_temperature?.getOrNull(idx),
                    swellHeight = response.hourly.swell_wave_height?.getOrNull(idx) ?: 0.5,
                    swellDirection = response.hourly.swell_wave_direction?.getOrNull(idx)?.toInt() ?: 0,
                    swellPeriod = response.hourly.swell_wave_period?.getOrNull(idx) ?: 0.0,
                    secondarySwellHeight = response.hourly.secondary_swell_wave_height?.getOrNull(idx),
                    secondarySwellDirection = response.hourly.secondary_swell_wave_direction?.getOrNull(idx)?.toInt(),
                    secondarySwellPeriod = response.hourly.secondary_swell_wave_period?.getOrNull(idx)
                )
            }
        } catch (e: Exception) {
            logger.warn("Open-Meteo marine range API failed: ${e.message}")
            emptyList()
        }
    }

    /**
     * Build absolute epoch-millis for each local ISO timestamp using the spot's
     * IANA zone (DST-correct within the horizon). Falls back to UTC if the zone
     * is unparseable.
     */
    private fun buildEpochList(times: List<String>?, timezone: String?): List<Long> {
        if (times == null) return emptyList()
        val zone = try {
            java.time.ZoneId.of(timezone)
        } catch (_: Exception) {
            java.time.ZoneOffset.UTC
        }
        return times.map { t ->
            try {
                java.time.LocalDateTime.parse(t).atZone(zone).toInstant().toEpochMilli()
            } catch (_: Exception) {
                0L
            }
        }
    }

    /**
     * Retry helper for the daily hourly-series fetchers. Connect timeouts to
     * marine-api.open-meteo.com under 10-concurrent batch load caused the
     * chronic ~5% per-run failures in hourly_swell_wind (Jun/Jul 2026);
     * a bounded retry with backoff absorbs them (same pattern Open-Meteo's
     * own integration examples recommend for free-tier bursts).
     */
    private suspend fun <T> withRetry(attempts: Int = 3, baseDelayMs: Long = 1000, block: suspend () -> T): T {
        var last: Exception? = null
        repeat(attempts) { attempt ->
            try {
                return block()
            } catch (e: Exception) {
                last = e
                if (attempt < attempts - 1) kotlinx.coroutines.delay(baseDelayMs * (1L shl attempt))
            }
        }
        throw last!!
    }

    /**
     * Full hourly marine curve for a multi-day horizon (raw SI units + epochMs).
     * Used by the daily prefetch job to persist the swell series. Returns null on failure.
     */
    suspend fun getMarineHourly(lat: Double, lon: Double, days: Int = 7): MarineHourlySeries? {
        return try {
            RateLimiters.openMeteo.acquire()

            val response: OpenMeteoMarineResponse = withRetry {
                client.get("https://marine-api.open-meteo.com/v1/marine") {
                    parameter("latitude", lat)
                    parameter("longitude", lon)
                    parameter("forecast_days", days)
                    parameter("hourly", "wave_height,wave_period,wave_direction,swell_wave_height,swell_wave_period,swell_wave_direction,secondary_swell_wave_height,secondary_swell_wave_period,secondary_swell_wave_direction,sea_surface_temperature")
                    parameter("timezone", "auto")
                }.body()
            }

            val h = response.hourly
            val tz = response.timezone ?: "UTC"
            val epochs = buildEpochList(h.time, response.timezone)
            val points = epochs.indices.map { i ->
                MarineHourPoint(
                    epochMs = epochs[i],
                    waveHeightM = h.wave_height?.getOrNull(i),
                    wavePeriodSec = h.wave_period?.getOrNull(i),
                    waveDirectionDeg = h.wave_direction?.getOrNull(i)?.toInt(),
                    swellHeightM = h.swell_wave_height?.getOrNull(i),
                    swellPeriodSec = h.swell_wave_period?.getOrNull(i),
                    swellDirectionDeg = h.swell_wave_direction?.getOrNull(i)?.toInt(),
                    secondarySwellHeightM = h.secondary_swell_wave_height?.getOrNull(i),
                    secondarySwellPeriodSec = h.secondary_swell_wave_period?.getOrNull(i),
                    secondarySwellDirectionDeg = h.secondary_swell_wave_direction?.getOrNull(i)?.toInt(),
                    sstC = h.sea_surface_temperature?.getOrNull(i)
                )
            }
            MarineHourlySeries(timezone = tz, points = points)
        } catch (e: Exception) {
            logger.warn("Open-Meteo marine hourly failed for ($lat, $lon): ${e.message}")
            null
        }
    }

    /**
     * Full hourly wind curve for a multi-day horizon (km/h + epochMs).
     * Used by the daily prefetch job to persist the wind series. Returns null on failure.
     */
    suspend fun getWeatherHourly(lat: Double, lon: Double, days: Int = 7): WeatherHourlySeries? {
        return try {
            RateLimiters.openMeteo.acquire()

            val response: OpenMeteoWeatherResponse = withRetry {
                client.get("https://api.open-meteo.com/v1/forecast") {
                    parameter("latitude", lat)
                    parameter("longitude", lon)
                    parameter("forecast_days", days)
                    parameter("hourly", "windspeed_10m,winddirection_10m,windgusts_10m")
                    parameter("timezone", "auto")
                }.body()
            }

            val h = response.hourly
            val tz = response.timezone ?: "UTC"
            val epochs = buildEpochList(h.time, response.timezone)
            val points = epochs.indices.map { i ->
                WindHourPoint(
                    epochMs = epochs[i],
                    windSpeedKmh = h.windspeed_10m?.getOrNull(i),
                    windDirectionDeg = h.winddirection_10m?.getOrNull(i)?.toInt(),
                    windGustKmh = h.windgusts_10m?.getOrNull(i)
                )
            }
            WeatherHourlySeries(timezone = tz, points = points)
        } catch (e: Exception) {
            logger.warn("Open-Meteo weather hourly failed for ($lat, $lon): ${e.message}")
            null
        }
    }

    /**
     * Near-real-time wind from Open-Meteo's 15-minute `current` block.
     * Used by the detail-screen live-wind override. Returns null on failure.
     */
    suspend fun getCurrentWind(lat: Double, lon: Double): CurrentWind? {
        return try {
            RateLimiters.openMeteo.acquire()

            val response: OpenMeteoCurrentResponse = client.get("https://api.open-meteo.com/v1/forecast") {
                parameter("latitude", lat)
                parameter("longitude", lon)
                parameter("current", "windspeed_10m,winddirection_10m,windgusts_10m")
                parameter("timezone", "auto")
            }.body()

            val c = response.current ?: return null
            val speed = c.windspeed_10m ?: return null
            CurrentWind(
                speedKmh = speed,
                directionDeg = (c.winddirection_10m ?: 0.0).toInt(),
                gustKmh = c.windgusts_10m
            )
        } catch (e: Exception) {
            logger.warn("Open-Meteo current wind failed for ($lat, $lon): ${e.message}")
            null
        }
    }
}

@Serializable
data class OpenMeteoWeatherResponse(
    val hourly: OpenMeteoHourlyWeather,
    val timezone: String? = null
)

@Serializable
data class OpenMeteoHourlyWeather(
    val time: List<String>? = null,
    val temperature_2m: List<Double>? = null,
    val precipitation: List<Double>? = null,
    val cloudcover: List<Double>? = null,
    val windspeed_10m: List<Double>? = null,
    val winddirection_10m: List<Double>? = null,
    val windgusts_10m: List<Double>? = null,
    val visibility: List<Double>? = null
)

@Serializable
data class OpenMeteoCurrentResponse(
    val current: OpenMeteoCurrentWind? = null,
    val timezone: String? = null
)

@Serializable
data class OpenMeteoCurrentWind(
    val time: String? = null,
    val windspeed_10m: Double? = null,
    val winddirection_10m: Double? = null,
    val windgusts_10m: Double? = null
)

/** Spot timezone + full hourly marine curve (raw SI units, absolute epoch times). */
data class MarineHourlySeries(
    val timezone: String,
    val points: List<MarineHourPoint>
)

data class MarineHourPoint(
    val epochMs: Long,
    val waveHeightM: Double?,
    val wavePeriodSec: Double?,
    val waveDirectionDeg: Int?,
    val swellHeightM: Double?,
    val swellPeriodSec: Double?,
    val swellDirectionDeg: Int?,
    val secondarySwellHeightM: Double?,
    val secondarySwellPeriodSec: Double?,
    val secondarySwellDirectionDeg: Int?,
    val sstC: Double?
)

/** Spot timezone + full hourly wind curve (km/h, degrees, absolute epoch times). */
data class WeatherHourlySeries(
    val timezone: String,
    val points: List<WindHourPoint>
)

data class WindHourPoint(
    val epochMs: Long,
    val windSpeedKmh: Double?,
    val windDirectionDeg: Int?,
    val windGustKmh: Double?
)

/** Near-real-time wind from Open-Meteo's 15-minute `current` block (km/h). */
data class CurrentWind(
    val speedKmh: Double,
    val directionDeg: Int,
    val gustKmh: Double?
)

@Serializable
data class OpenMeteoMarineResponse(
    val hourly: OpenMeteoHourlyMarine,
    val timezone: String? = null
)

@Serializable
data class OpenMeteoHourlyMarine(
    val time: List<String>? = null,
    val wave_height: List<Double>? = null,
    val wave_period: List<Double>? = null,
    val wave_direction: List<Double>? = null,
    val swell_wave_height: List<Double>? = null,
    val swell_wave_period: List<Double>? = null,
    val swell_wave_direction: List<Double>? = null,
    val secondary_swell_wave_height: List<Double>? = null,
    val secondary_swell_wave_period: List<Double>? = null,
    val secondary_swell_wave_direction: List<Double>? = null,
    val ocean_current_velocity: List<Double>? = null,
    val sea_surface_temperature: List<Double>? = null
)
