package com.shaka.data.client

import com.shaka.data.cache.OceanDataCache
import com.shaka.model.WaterQuality
import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.engine.cio.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.client.request.forms.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory

/**
 * Client for water quality data - combines multiple sources for best performance.
 * 
 * Default (fast) path:
 * - SST from NOAA ERDDAP (~2-3s)
 * - Chlorophyll from NOAA VIIRS (~2-3s)
 * - Results cached for 12 hours
 * 
 * Optional real-time satellite path:
 * - Chlorophyll from Copernicus Sentinel-3 OLCI (~30-60s)
 * - Processes latest satellite pass for most current data
 * - Requires COPERNICUS_CLIENT_ID and COPERNICUS_CLIENT_SECRET env vars
 * 
 * Data interpretation:
 * - Chlorophyll-a: 0.1-0.5 mg/m³ = clear, 1-5 = productive, >10 = bloom
 * - Turbidity (NTU): <1 = clear, 1-5 = moderate, >5 = murky
 * - Visibility: Estimated from Secchi depth relationships
 */
class CopernicusClient(
    private val clientId: String = System.getenv("COPERNICUS_CLIENT_ID") ?: "",
    private val clientSecret: String = System.getenv("COPERNICUS_CLIENT_SECRET") ?: ""
) {
    private val logger = LoggerFactory.getLogger(CopernicusClient::class.java)
    private val noaaClient = NOAAClient()
    
    private val client = HttpClient(CIO) {
        install(ContentNegotiation) {
            json(Json {
                ignoreUnknownKeys = true
                isLenient = true
            })
        }
    }

    private var accessToken: String? = null
    private var tokenExpiry: Long = 0

    companion object {
        private const val AUTH_URL = "https://identity.dataspace.copernicus.eu/auth/realms/CDSE/protocol/openid-connect/token"
        private const val PROCESS_URL = "https://sh.dataspace.copernicus.eu/api/v1/process"
        private const val OLCI_COLLECTION = "sentinel-3-olci"
    }

    /**
     * Get water quality data using FAST path (NOAA ERDDAP).
     * Typical response time: 2-5 seconds (first call), <1 second (cached).
     * 
     * Uses caching with 12-hour TTL for chlorophyll/visibility data.
     */
    suspend fun getWaterQuality(lat: Double, lon: Double, date: String): WaterQuality {
        // Check cache first
        OceanDataCache.getWaterQuality(lat, lon, date)?.let { 
            logger.debug("Returning cached water quality for ($lat, $lon)")
            return it 
        }
        
        // Fetch SST from NOAA (fast) - always returns a value now
        val sst = noaaClient.getSeaSurfaceTemperature(lat, lon, date)
        
        // Fetch chlorophyll from NOAA VIIRS satellite (REAL DATA)
        val chlorophyll = try {
            noaaClient.getChlorophyll(lat, lon, date)
        } catch (e: Exception) {
            logger.warn("NOAA chlorophyll fetch failed: ${e.message}")
            null
        }
        
        // Only calculate turbidity/visibility if we have real chlorophyll data
        val turbidity = chlorophyll?.let { calculateTurbidity(it, lat, lon) }
        val visibility = if (chlorophyll != null && turbidity != null) {
            calculateVisibility(chlorophyll, turbidity)
        } else null
        
        val dataSource = if (chlorophyll != null) {
            "NOAA CoastWatch (SST + VIIRS Chlorophyll)"
        } else {
            "NOAA CoastWatch (SST only - chlorophyll unavailable)"
        }
        
        val result = WaterQuality(
            chlorophyllA = chlorophyll,
            turbidity = turbidity,
            visibility = visibility,
            seaSurfaceTemp = sst,
            dataSource = dataSource
        )
        
        // Cache the result
        OceanDataCache.putWaterQuality(lat, lon, date, result)
        
        logger.info("Water quality for ($lat, $lon): chl=${String.format("%.2f", chlorophyll)} mg/m³, vis=${String.format("%.0f", visibility)}m, SST=${String.format("%.1f", sst)}°C")
        
        return result
    }

    /**
     * Get water quality using REAL-TIME satellite data from Copernicus Sentinel-3.
     * 
     * WARNING: This is SLOW (30-60 seconds) but provides the most current data.
     * Only use when user explicitly requests real-time satellite data.
     * 
     * Requires COPERNICUS_CLIENT_ID and COPERNICUS_CLIENT_SECRET environment variables.
     * 
     * @throws IllegalStateException if Copernicus credentials are not configured
     */
    suspend fun getRealTimeWaterQuality(lat: Double, lon: Double, date: String): WaterQuality {
        if (clientId.isBlank() || clientSecret.isBlank()) {
            throw IllegalStateException("Copernicus credentials not configured. Set COPERNICUS_CLIENT_ID and COPERNICUS_CLIENT_SECRET environment variables.")
        }
        
        logger.info("Fetching REAL-TIME satellite data for ($lat, $lon) - this may take 30-60 seconds...")
        
        // Always get fresh SST from NOAA (fast, doesn't need Copernicus)
        val sst = noaaClient.getSeaSurfaceTemperature(lat, lon, date)
        
        // Authenticate with Copernicus
        ensureAuthenticated()
        
        // Query Sentinel-3 OLCI for latest chlorophyll, fall back to NOAA VIIRS
        val chlorophyll = try {
            queryChlorophyllFromSentinel(lat, lon, date)
        } catch (e: Exception) {
            logger.warn("Sentinel-3 query failed: ${e.message}")
            // Fall back to NOAA VIIRS (still real data)
            noaaClient.getChlorophyll(lat, lon, date)
        }
        
        // Only calculate turbidity/visibility if we have real chlorophyll data
        val turbidity = chlorophyll?.let { calculateTurbidity(it, lat, lon) }
        val visibility = if (chlorophyll != null && turbidity != null) {
            calculateVisibility(chlorophyll, turbidity)
        } else null
        
        val dataSource = if (chlorophyll != null) {
            "Copernicus Sentinel-3 OLCI (Real-time)"
        } else {
            "NOAA CoastWatch (SST only - chlorophyll unavailable)"
        }
        
        val result = WaterQuality(
            chlorophyllA = chlorophyll,
            turbidity = turbidity,
            visibility = visibility,
            seaSurfaceTemp = sst,
            dataSource = dataSource
        )
        
        // Cache this premium data too
        OceanDataCache.putWaterQuality(lat, lon, date, result)
        
        if (chlorophyll != null && visibility != null) {
            logger.info("REAL-TIME water quality for ($lat, $lon): chl=${String.format("%.2f", chlorophyll)} mg/m³, vis=${String.format("%.0f", visibility)}m")
        } else {
            logger.warn("REAL-TIME water quality for ($lat, $lon): chlorophyll unavailable")
        }
        
        return result
    }

    /**
     * Check if real-time satellite data is available (credentials configured).
     */
    fun isRealTimeAvailable(): Boolean = clientId.isNotBlank() && clientSecret.isNotBlank()

    /**
     * Authenticate with Copernicus Data Space using OAuth2 client credentials.
     */
    private suspend fun ensureAuthenticated() {
        if (accessToken != null && System.currentTimeMillis() < tokenExpiry) {
            return
        }

        logger.info("Authenticating with Copernicus Data Space...")
        
        val response: CopernicusAuthResponse = client.submitForm(
            url = AUTH_URL,
            formParameters = Parameters.build {
                append("grant_type", "client_credentials")
                append("client_id", clientId)
                append("client_secret", clientSecret)
            }
        ).body()

        accessToken = response.access_token
        tokenExpiry = System.currentTimeMillis() + (response.expires_in * 1000) - 60000
        
        logger.info("Copernicus authentication successful, token expires in ${response.expires_in}s")
    }

    /**
     * Query chlorophyll-a concentration from Sentinel-3 OLCI using Sentinel Hub Process API.
     * This is the SLOW path (~30-60 seconds) that processes raw satellite data.
     * Returns null if data is unavailable (e.g., cloud cover).
     */
    private suspend fun queryChlorophyllFromSentinel(lat: Double, lon: Double, date: String): Double? {
        val bbox = listOf(lon - 0.01, lat - 0.01, lon + 0.01, lat + 0.01)
        
        val evalscript = """
            //VERSION=3
            function setup() {
                return {
                    input: ["CHL_OC4ME"],
                    output: { bands: 1, sampleType: "FLOAT32" }
                };
            }
            function evaluatePixel(sample) {
                return [sample.CHL_OC4ME];
            }
        """.trimIndent()
        
        val requestBody = """
            {
                "input": {
                    "bounds": {
                        "bbox": [${bbox.joinToString(",")}],
                        "properties": {"crs": "http://www.opengis.net/def/crs/EPSG/0/4326"}
                    },
                    "data": [{
                        "type": "$OLCI_COLLECTION",
                        "dataFilter": {
                            "timeRange": {
                                "from": "${date}T00:00:00Z",
                                "to": "${date}T23:59:59Z"
                            }
                        }
                    }]
                },
                "output": {
                    "width": 10,
                    "height": 10,
                    "responses": [{"format": {"type": "application/json"}}]
                },
                "evalscript": ${Json.encodeToString(kotlinx.serialization.serializer<String>(), evalscript)}
            }
        """.trimIndent()
        
        val response: HttpResponse = client.post(PROCESS_URL) {
            header("Authorization", "Bearer $accessToken")
            contentType(ContentType.Application.Json)
            setBody(requestBody)
        }
        
        return if (response.status.isSuccess()) {
            parseChlorophyllResponse(response.bodyAsText())
        } else {
            logger.warn("Sentinel Hub request failed: ${response.status}")
            null
        }
    }

    private fun parseChlorophyllResponse(response: String): Double? {
        return try {
            val valueRegex = """"mean"\s*:\s*([\d.]+)""".toRegex()
            val match = valueRegex.find(response)
            match?.groupValues?.get(1)?.toDoubleOrNull()
        } catch (e: Exception) {
            logger.debug("Chlorophyll parsing failed: ${e.message}")
            null
        }
    }

    /**
     * Calculate turbidity from chlorophyll and regional factors.
     */
    fun calculateTurbidity(chlorophyll: Double, lat: Double, lon: Double): Double {
        var turbidity = 0.3 + (chlorophyll * 0.6)
        
        // Regional adjustments
        if (lat in 32.0..42.0 && lon in -125.0..-117.0) turbidity *= 1.3  // California
        if (lat in 18.0..23.0 && lon in -161.0..-154.0) turbidity *= 0.7  // Hawaii
        if (lat in 24.0..26.0 && lon in -82.0..-80.0) turbidity *= 0.8    // Florida Keys
        
        return turbidity.coerceIn(0.1, 15.0)
    }

    /**
     * Calculate visibility from chlorophyll and turbidity using Secchi depth relationships.
     */
    fun calculateVisibility(chlorophyll: Double, turbidity: Double): Double {
        val kd = 0.027 * Math.pow(chlorophyll.coerceAtLeast(0.1), 0.6) + 
                 0.066 * Math.pow(turbidity.coerceAtLeast(0.1), 0.7) +
                 0.04
        val secchiDepth = 1.7 / kd
        return (secchiDepth * 2.7).coerceIn(1.0, 45.0)
    }

}

@Serializable
data class CopernicusAuthResponse(
    val access_token: String,
    val expires_in: Int,
    val token_type: String
)
