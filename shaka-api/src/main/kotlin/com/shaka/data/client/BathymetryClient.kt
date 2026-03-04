package com.shaka.data.client

import io.ktor.client.request.*
import io.ktor.client.statement.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory
import kotlin.math.*

/**
 * Client for Open Topo Data bathymetry/elevation API.
 * Uses the Mapzen dataset (~30m resolution, global, includes ocean bathymetry).
 *
 * Free, no auth required. Rate limit: 1 req/sec, 100 locations/req, 1000 calls/day.
 * https://www.opentopodata.org/
 */
class BathymetryClient {

    private val logger = LoggerFactory.getLogger(BathymetryClient::class.java)
    private val client = HttpClientFactory.shared
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    companion object {
        private const val BASE_URL = "https://api.opentopodata.org/v1/mapzen"
        private const val MAX_LOCATIONS_PER_REQUEST = 100
        private const val SAMPLE_DISTANCE_KM = 5.0
        private const val NUM_DIRECTIONS = 16
        private const val EARTH_RADIUS_KM = 6371.0
    }

    @Serializable
    data class TopoResponse(
        val results: List<TopoResult>? = null,
        val status: String? = null,
        val error: String? = null
    )

    @Serializable
    data class TopoResult(
        val elevation: Double? = null,
        val location: TopoLocation? = null
    )

    @Serializable
    data class TopoLocation(
        val lat: Double,
        val lng: Double
    )

    data class ExposureResult(
        val bearing: Int,
        val width: Int,
        val depthM: Double?
    )

    /**
     * Query elevation/bathymetry at a list of lat/lon pairs.
     * Negative = underwater, positive = land.
     */
    suspend fun getElevations(points: List<Pair<Double, Double>>): List<Double?> {
        if (points.isEmpty()) return emptyList()
        if (points.size > MAX_LOCATIONS_PER_REQUEST) {
            logger.warn("Too many points (${points.size}), truncating to $MAX_LOCATIONS_PER_REQUEST")
        }

        val locations = points.take(MAX_LOCATIONS_PER_REQUEST)
            .joinToString("|") { "${it.first},${it.second}" }

        return try {
            val response = client.get(BASE_URL) {
                parameter("locations", locations)
            }
            val body = response.bodyAsText()
            val parsed = json.decodeFromString<TopoResponse>(body)

            if (parsed.status != "OK") {
                logger.warn("Bathymetry API returned status=${parsed.status}, error=${parsed.error}")
                return List(points.size) { null }
            }

            parsed.results?.map { it.elevation } ?: List(points.size) { null }
        } catch (e: Exception) {
            logger.warn("Bathymetry API call failed: ${e.message}")
            List(points.size) { null }
        }
    }

    /**
     * Compute exposure bearing, width, and depth for a spot.
     *
     * Samples 16 points at 5km in each compass direction plus the spot center.
     * Classifies water (negative elevation) vs land (positive).
     * Returns the centroid direction and angular width of the open-water arc.
     * 5km avoids false land detection on headlands/peninsulas at shorter ranges.
     */
    suspend fun computeExposure(lat: Double, lon: Double): ExposureResult? {
        val points = mutableListOf<Pair<Double, Double>>()

        // 16 surrounding sample points
        for (i in 0 until NUM_DIRECTIONS) {
            val bearingDeg = i * (360.0 / NUM_DIRECTIONS)
            val (sLat, sLon) = offsetPoint(lat, lon, bearingDeg, SAMPLE_DISTANCE_KM)
            points.add(sLat to sLon)
        }
        // 17th point: spot center (for depth)
        points.add(lat to lon)

        val elevations = getElevations(points)
        if (elevations.size < NUM_DIRECTIONS + 1 || elevations.all { it == null }) {
            logger.warn("Bathymetry API returned insufficient data for ($lat, $lon)")
            return null
        }

        val spotDepth = elevations[NUM_DIRECTIONS]

        // Classify each direction as water or land
        val waterDirections = mutableListOf<Double>()
        val isWater = BooleanArray(NUM_DIRECTIONS)
        for (i in 0 until NUM_DIRECTIONS) {
            val elev = elevations[i]
            if (elev != null && elev < 0) {
                isWater[i] = true
                waterDirections.add(i * (360.0 / NUM_DIRECTIONS))
            }
        }

        if (waterDirections.isEmpty()) {
            logger.info("No water detected around ($lat, $lon) — likely inland spot")
            return ExposureResult(bearing = 0, width = 360, depthM = spotDepth)
        }

        if (waterDirections.size == NUM_DIRECTIONS) {
            return ExposureResult(bearing = 0, width = 360, depthM = spotDepth)
        }

        // Find the largest contiguous water arc
        val stepDeg = 360.0 / NUM_DIRECTIONS
        var bestStart = -1
        var bestLength = 0
        var currentStart = -1
        var currentLength = 0

        // Walk around twice to handle wrap-around
        for (pass in 0 until 2 * NUM_DIRECTIONS) {
            val idx = pass % NUM_DIRECTIONS
            if (isWater[idx]) {
                if (currentStart == -1) currentStart = pass
                currentLength++
                if (currentLength > bestLength) {
                    bestLength = currentLength
                    bestStart = currentStart
                }
            } else {
                currentStart = -1
                currentLength = 0
            }
        }
        // Cap at full circle
        if (bestLength > NUM_DIRECTIONS) bestLength = NUM_DIRECTIONS

        val width = (bestLength * stepDeg).toInt().coerceIn(0, 360)

        // Bearing = center of the best arc
        val arcCenterIdx = (bestStart + bestLength / 2.0) % NUM_DIRECTIONS
        val bearing = ((arcCenterIdx * stepDeg) % 360).toInt()

        val depthPositive = spotDepth?.let { if (it < 0) -it else 0.0 }
        logger.info("Exposure for ($lat, $lon): bearing=$bearing, width=$width, depth=${depthPositive}m")
        return ExposureResult(bearing = bearing, width = width, depthM = depthPositive)
    }

    private fun offsetPoint(lat: Double, lon: Double, bearingDeg: Double, distKm: Double): Pair<Double, Double> {
        val latRad = Math.toRadians(lat)
        val lonRad = Math.toRadians(lon)
        val bearingRad = Math.toRadians(bearingDeg)
        val angularDist = distKm / EARTH_RADIUS_KM

        val newLat = asin(
            sin(latRad) * cos(angularDist) +
                cos(latRad) * sin(angularDist) * cos(bearingRad)
        )
        val newLon = lonRad + atan2(
            sin(bearingRad) * sin(angularDist) * cos(latRad),
            cos(angularDist) - sin(latRad) * sin(newLat)
        )

        return Math.toDegrees(newLat) to Math.toDegrees(newLon)
    }
}
