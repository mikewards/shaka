package com.shaka.data.client

import com.shaka.model.TideChartData
import com.shaka.model.TideData
import com.shaka.model.TideExtreme
import com.shaka.model.TidePoint
import io.ktor.client.request.*
import io.ktor.client.statement.*
import kotlinx.serialization.json.*
import org.slf4j.LoggerFactory
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

/**
 * Tide client backed by the FES2022 Python microservice (shaka-tide).
 *
 * Calls the internal Railway service via private networking.
 * Circuit breaker prevents cascading failures during deploys.
 */
class FES2022TideClient : TideClient {

    override val provider = "fes2022"

    private val logger = LoggerFactory.getLogger(FES2022TideClient::class.java)
    private val client = HttpClientFactory.shared
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    private val baseUrl = System.getenv("TIDE_SERVICE_URL") ?: "http://localhost:8000"

    // Simple circuit breaker: trip after 5 consecutive failures, reset after 60s
    private val consecutiveFailures = AtomicInteger(0)
    private val circuitOpenUntil = AtomicLong(0)
    private val failureThreshold = 5
    private val resetMs = 60_000L

    private fun isCircuitOpen(): Boolean {
        if (consecutiveFailures.get() < failureThreshold) return false
        if (System.currentTimeMillis() > circuitOpenUntil.get()) {
            consecutiveFailures.set(0)
            return false
        }
        return true
    }

    private fun recordSuccess() {
        consecutiveFailures.set(0)
    }

    private fun recordFailure() {
        if (consecutiveFailures.incrementAndGet() >= failureThreshold) {
            circuitOpenUntil.set(System.currentTimeMillis() + resetMs)
            logger.warn("Circuit breaker OPEN for tide service (${consecutiveFailures.get()} consecutive failures)")
        }
    }

    override suspend fun getTideData(lat: Double, lon: Double, date: String): TideData {
        if (isCircuitOpen()) {
            logger.debug("Circuit open, returning empty tide data")
            return noTideData()
        }

        return try {
            val response: String = client.get("$baseUrl/tide/summary") {
                parameter("lat", lat)
                parameter("lon", lon)
            }.bodyAsText()

            val obj = json.parseToJsonElement(response).jsonObject
            recordSuccess()

            TideData(
                currentHeight = obj["current_height_ft"]?.jsonPrimitive?.doubleOrNull ?: 0.0,
                nextHighTide = formatTideText(obj, "next_high_tide_ft", "next_high_tide_epoch_ms"),
                nextLowTide = formatTideText(obj, "next_low_tide_ft", "next_low_tide_epoch_ms"),
                tideState = obj["tide_state"]?.jsonPrimitive?.contentOrNull ?: "unknown",
                nextHighTideTime = obj["next_high_tide_epoch_ms"]?.jsonPrimitive?.longOrNull,
                nextLowTideTime = obj["next_low_tide_epoch_ms"]?.jsonPrimitive?.longOrNull
            )
        } catch (e: Exception) {
            recordFailure()
            logger.warn("FES2022 tide summary failed for ($lat, $lon): ${e.message}")
            noTideData()
        }
    }

    /**
     * Fetch chart + inline summary in a single HTTP call.
     * Returns Pair(chartData, summaryTideData) or null on failure.
     */
    suspend fun getChartWithSummary(lat: Double, lon: Double, date: String): Pair<TideChartData, TideData>? {
        if (isCircuitOpen()) {
            logger.debug("Circuit open, skipping chart fetch")
            return null
        }

        return try {
            val response: String = client.get("$baseUrl/tide/chart") {
                parameter("lat", lat)
                parameter("lon", lon)
                parameter("date", date)
                parameter("days", 1)
                parameter("step_minutes", 30)
            }.bodyAsText()

            val obj = json.parseToJsonElement(response).jsonObject
            recordSuccess()

            val points = obj["points"]?.jsonArray?.mapNotNull { el ->
                val p = el.jsonObject
                val epochMs = p["epoch_ms"]?.jsonPrimitive?.longOrNull ?: return@mapNotNull null
                val heightFt = p["height_ft"]?.jsonPrimitive?.doubleOrNull ?: return@mapNotNull null
                TidePoint(epochMs = epochMs, heightFt = heightFt)
            } ?: emptyList()

            val extremes = obj["extremes"]?.jsonArray?.mapNotNull { el ->
                val e = el.jsonObject
                val epochMs = e["epoch_ms"]?.jsonPrimitive?.longOrNull ?: return@mapNotNull null
                val heightFt = e["height_ft"]?.jsonPrimitive?.doubleOrNull ?: return@mapNotNull null
                val type = e["type"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
                TideExtreme(epochMs = epochMs, heightFt = heightFt, type = type)
            } ?: emptyList()

            if (points.isEmpty()) return null

            val timezoneId = obj["timezoneId"]?.jsonPrimitive?.contentOrNull ?: "Etc/UTC"
            val localDate = obj["local_date"]?.jsonPrimitive?.contentOrNull ?: ""

            val datum = obj["datum"]?.jsonPrimitive?.contentOrNull ?: "MSL"

            val chart = TideChartData(
                provider = "fes2022",
                stationId = "",
                stationName = "FES2022",
                stationDistanceMi = 0.0,
                datum = datum,
                timezoneId = timezoneId,
                points = points,
                extremes = extremes,
                localDate = localDate
            )

            val s = obj["summary"]?.jsonObject
            val summary = if (s != null) {
                TideData(
                    currentHeight = s["current_height_ft"]?.jsonPrimitive?.doubleOrNull ?: 0.0,
                    nextHighTide = formatTideText(s, "next_high_tide_ft", "next_high_tide_epoch_ms"),
                    nextLowTide = formatTideText(s, "next_low_tide_ft", "next_low_tide_epoch_ms"),
                    tideState = s["tide_state"]?.jsonPrimitive?.contentOrNull ?: "unknown",
                    nextHighTideTime = s["next_high_tide_epoch_ms"]?.jsonPrimitive?.longOrNull,
                    nextLowTideTime = s["next_low_tide_epoch_ms"]?.jsonPrimitive?.longOrNull
                )
            } else {
                noTideData()
            }

            Pair(chart, summary)
        } catch (e: Exception) {
            recordFailure()
            logger.warn("FES2022 tide chart failed for ($lat, $lon) on $date: ${e.message}")
            null
        }
    }

    override suspend fun getTideChartData(lat: Double, lon: Double, date: String): TideChartData? {
        return getChartWithSummary(lat, lon, date)?.first
    }

    private fun formatTideText(obj: JsonObject, ftKey: String, msKey: String): String {
        val ft = obj[ftKey]?.jsonPrimitive?.doubleOrNull ?: return "N/A"
        val ms = obj[msKey]?.jsonPrimitive?.longOrNull ?: return String.format("%.1fft", ft)
        val instant = java.time.Instant.ofEpochMilli(ms)
        val time = instant.atZone(java.time.ZoneId.systemDefault())
            .format(DateTimeFormatter.ofPattern("h:mma"))
        return "$time (${String.format("%.1f", ft)}ft)"
    }

    private fun noTideData() = TideData(
        currentHeight = 0.0,
        nextHighTide = "Unavailable",
        nextLowTide = "Unavailable",
        tideState = "unknown"
    )
}
