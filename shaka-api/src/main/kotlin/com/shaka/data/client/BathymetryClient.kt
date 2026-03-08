package com.shaka.data.client

import io.ktor.client.request.*
import io.ktor.client.statement.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory
import kotlin.math.*

/**
 * Computes coastal exposure profiles for spots using multi-ring land/water
 * sampling via LandWaterClient (is-on-water API) and depth from NCEI DEM_all
 * (NOAA's multi-resolution bathymetry mosaic) with GEBCO Latest WMS fallback.
 *
 * For each of 16 compass directions, samples at 1km, 2km, and 5km to
 * determine distance to nearest land. This produces a per-direction
 * sheltering profile that drives swell attenuation.
 */
class BathymetryClient(
    private val landWaterClient: LandWaterClient = LandWaterClient()
) {

    private val logger = LoggerFactory.getLogger(BathymetryClient::class.java)
    private val client = HttpClientFactory.shared
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    companion object {
        private const val NCEI_DEM_URL = "https://gis.ngdc.noaa.gov/arcgis/rest/services/DEM_mosaics/DEM_all/ImageServer/identify"
        private const val GEBCO_WMS_URL = "https://wms.gebco.net/mapserv"
        private const val NUM_DIRECTIONS = 16
        private const val EARTH_RADIUS_KM = 6371.0
        val RING_DISTANCES_KM = doubleArrayOf(1.0, 2.0, 5.0)
        const val DIRECTION_STEP_DEG = 360.0 / NUM_DIRECTIONS // 22.5°
    }

    @Serializable
    data class NceiIdentifyResponse(
        val value: String? = null
    )

    /**
     * Per-direction land distance in km. null = no land detected at any ring (fully open).
     * Values are 1.0, 2.0, or 5.0 based on which ring first detected land.
     */
    data class DirectionalExposure(
        val landDistanceKm: DoubleArray // 16 values, one per direction (N, NNE, NE, ... NNW)
    ) {
        companion object {
            const val OPEN = -1.0 // sentinel: no land detected in any ring
        }
    }

    data class ExposureResult(
        val bearing: Int,
        val width: Int,
        val depthM: Double?,
        val directional: DirectionalExposure
    )

    /**
     * Compute full exposure profile: multi-ring land/water + depth.
     *
     * For each of 16 directions, checks at 1km, 2km, 5km for land.
     * Stores the nearest land distance per direction (-1 = fully open).
     * Also derives legacy bearing/width from the largest contiguous water arc.
     */
    suspend fun computeExposure(lat: Double, lon: Double): ExposureResult? {
        val landDist = DoubleArray(NUM_DIRECTIONS) { DirectionalExposure.OPEN }
        var anyResult = false

        for (i in 0 until NUM_DIRECTIONS) {
            val bearingDeg = i * DIRECTION_STEP_DEG
            for (ringKm in RING_DISTANCES_KM) {
                val (sLat, sLon) = offsetPoint(lat, lon, bearingDeg, ringKm)
                val isWater = landWaterClient.isWater(sLat, sLon)
                if (isWater != null) anyResult = true
                if (isWater == false) {
                    landDist[i] = ringKm
                    break // land found at this ring, no need to check farther
                }
                // isWater == true → keep checking farther rings
                // isWater == null → unknown, treat as open (conservative)
            }
        }

        if (!anyResult) {
            logger.warn("Land/water API returned no results for ($lat, $lon)")
            return null
        }

        val directional = DirectionalExposure(landDist)

        // Derive legacy bearing/width from water arc
        val isOpen = BooleanArray(NUM_DIRECTIONS) { landDist[it] == DirectionalExposure.OPEN }
        val openCount = isOpen.count { it }

        if (openCount == 0) {
            logger.info("No open water detected around ($lat, $lon)")
            return ExposureResult(bearing = 0, width = 0, depthM = fetchDepth(lat, lon), directional = directional)
        }
        if (openCount == NUM_DIRECTIONS) {
            return ExposureResult(bearing = 0, width = 360, depthM = fetchDepth(lat, lon), directional = directional)
        }

        // Find largest contiguous open-water arc (wrap-around safe)
        var bestStart = -1
        var bestLength = 0
        var currentStart = -1
        var currentLength = 0
        for (pass in 0 until 2 * NUM_DIRECTIONS) {
            val idx = pass % NUM_DIRECTIONS
            if (isOpen[idx]) {
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
        if (bestLength > NUM_DIRECTIONS) bestLength = NUM_DIRECTIONS

        val width = (bestLength * DIRECTION_STEP_DEG).toInt().coerceIn(0, 360)
        val arcCenterIdx = (bestStart + bestLength / 2.0) % NUM_DIRECTIONS
        val bearing = ((arcCenterIdx * DIRECTION_STEP_DEG) % 360).toInt()

        val depthM = fetchDepth(lat, lon)

        logger.info("Exposure for ($lat, $lon): bearing=$bearing, width=$width, depth=${depthM}m, open=$openCount/16")
        return ExposureResult(bearing = bearing, width = width, depthM = depthM, directional = directional)
    }

    /**
     * Fetch depth independently of exposure computation. Use when exposure
     * geometry (land distances) is already cached but depth needs refreshing.
     */
    suspend fun fetchDepthOnly(lat: Double, lon: Double): Double? = fetchDepth(lat, lon)

    /**
     * Fetch depth using NCEI DEM_all (NOAA survey mosaic, ~1-10m resolution
     * near US coasts, global ETOPO/GEBCO composite elsewhere) with GEBCO
     * Latest WMS as fallback. Returns positive meters for underwater depth,
     * null on failure or confirmed land.
     */
    private suspend fun fetchDepth(lat: Double, lon: Double): Double? {
        val nceiDepth = fetchDepthFromNcei(lat, lon)
        if (nceiDepth != null) return nceiDepth

        val gebcoDepth = fetchDepthFromGebcoWms(lat, lon)
        if (gebcoDepth != null) return gebcoDepth

        return null
    }

    private suspend fun fetchDepthFromNcei(lat: Double, lon: Double): Double? {
        return try {
            RateLimiters.nceiDem.acquire()
            val geometryJson = """{"x":$lon,"y":$lat}"""
            val response = client.get(NCEI_DEM_URL) {
                parameter("geometry", geometryJson)
                parameter("geometryType", "esriGeometryPoint")
                parameter("returnGeometry", "false")
                parameter("returnCatalogItems", "false")
                parameter("f", "json")
            }
            val body = response.bodyAsText()
            val parsed = json.decodeFromString<NceiIdentifyResponse>(body)
            val value = parsed.value?.toDoubleOrNull() ?: return null
            if (value < 0) -value else null
        } catch (e: Exception) {
            logger.debug("NCEI depth fetch failed for ($lat, $lon): ${e.message}")
            null
        }
    }

    private suspend fun fetchDepthFromGebcoWms(lat: Double, lon: Double): Double? {
        return try {
            RateLimiters.gebcoWms.acquire()
            val offset = 0.001
            val bbox = "${lat - offset},${lon - offset},${lat + offset},${lon + offset}"
            val response = client.get(GEBCO_WMS_URL) {
                parameter("request", "getfeatureinfo")
                parameter("service", "wms")
                parameter("crs", "EPSG:4326")
                parameter("layers", "gebco_latest_2")
                parameter("query_layers", "gebco_latest_2")
                parameter("BBOX", bbox)
                parameter("info_format", "text/plain")
                parameter("x", "50")
                parameter("y", "50")
                parameter("width", "100")
                parameter("height", "100")
                parameter("version", "1.3.0")
            }
            val body = response.bodyAsText()
            val match = Regex("""value_list\s*=\s*'(-?\d+(?:\.\d+)?)'""").find(body)
            val value = match?.groupValues?.get(1)?.toDoubleOrNull() ?: return null
            if (value < 0) -value else null
        } catch (e: Exception) {
            logger.debug("GEBCO WMS depth fetch failed for ($lat, $lon): ${e.message}")
            null
        }
    }

    fun offsetPoint(lat: Double, lon: Double, bearingDeg: Double, distKm: Double): Pair<Double, Double> {
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
