package com.shaka.data.client

import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import kotlinx.coroutines.delay
import org.slf4j.LoggerFactory
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.zip.Inflater
import kotlin.math.ln
import kotlin.math.pow

/**
 * Result containing chlorophyll data from all GIBS satellites for today and yesterday.
 */
data class GIBSChlorophyllData(
    val paceToday: Double?,
    val paceYesterday: Double?,
    val noaa20Today: Double?,
    val noaa20Yesterday: Double?,
    val noaa21Today: Double?,
    val noaa21Yesterday: Double?,
    val sentinel3aToday: Double?,
    val sentinel3aYesterday: Double?,
    val sentinel3bToday: Double?,
    val sentinel3bYesterday: Double?,
    val dataDate: LocalDate  // "Today" when this was fetched
)

/**
 * Client for fetching chlorophyll-a data from NASA GIBS (Global Imagery Browse Services).
 * 
 * Fetches data from all 5 chlorophyll satellites for both today and yesterday:
 * - PACE OCI (newest hyperspectral sensor)
 * - NOAA-20 VIIRS (best coverage)
 * - NOAA-21 VIIRS (backup)
 * - Sentinel-3A OLCI (morning pass)
 * - Sentinel-3B OLCI (backup morning)
 * 
 * Uses WMS GetMap to fetch 10x10 pixel images and converts RGB to chlorophyll
 * concentration using the standard GIBS chlorophyll colormap (logarithmic 0.01-50 mg/m³).
 */
object GIBSClient {
    
    private val logger = LoggerFactory.getLogger(GIBSClient::class.java)
    private val httpClient = HttpClientFactory.shared
    
    private const val WMS_BASE = "https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi"
    private val dateFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
    
    /**
     * Satellite configurations: displayName to GIBS layer ID
     */
    private val SATELLITES = listOf(
        "PACE" to "OCI_PACE_Chlorophyll_a",
        "NOAA-20" to "VIIRS_NOAA20_Chlorophyll_a",
        "NOAA-21" to "VIIRS_NOAA21_Chlorophyll_a",
        "Sentinel-3A" to "S3A_OLCI_Chlorophyll_a",
        "Sentinel-3B" to "S3B_OLCI_Chlorophyll_a"
    )
    
    /**
     * Fetch chlorophyll from ALL satellites for today and yesterday.
     * 
     * @param lat Latitude in decimal degrees
     * @param lon Longitude in decimal degrees
     * @return GIBSChlorophyllData with values from all satellites (nulls where no data)
     */
    suspend fun getAllChlorophyll(lat: Double, lon: Double): GIBSChlorophyllData {
        val today = LocalDate.now()
        val yesterday = today.minusDays(1)
        val todayStr = today.format(dateFormatter)
        val yesterdayStr = yesterday.format(dateFormatter)
        
        val results = mutableMapOf<String, Double?>()
        
        // Fetch from each satellite for today and yesterday
        for ((satName, layerId) in SATELLITES) {
            // Today
            val todayKey = "${satName}_today"
            results[todayKey] = fetchFromSatellite(lat, lon, todayStr, satName, layerId)
            
            // Small delay between requests to not overwhelm GIBS
            delay(50)
            
            // Yesterday
            val yesterdayKey = "${satName}_yesterday"
            results[yesterdayKey] = fetchFromSatellite(lat, lon, yesterdayStr, satName, layerId)
            
            delay(50)
        }
        
        return GIBSChlorophyllData(
            paceToday = results["PACE_today"],
            paceYesterday = results["PACE_yesterday"],
            noaa20Today = results["NOAA-20_today"],
            noaa20Yesterday = results["NOAA-20_yesterday"],
            noaa21Today = results["NOAA-21_today"],
            noaa21Yesterday = results["NOAA-21_yesterday"],
            sentinel3aToday = results["Sentinel-3A_today"],
            sentinel3aYesterday = results["Sentinel-3A_yesterday"],
            sentinel3bToday = results["Sentinel-3B_today"],
            sentinel3bYesterday = results["Sentinel-3B_yesterday"],
            dataDate = today
        )
    }
    
    /**
     * Fetch chlorophyll from a specific satellite for a specific date.
     * Uses a 10x10 pixel area (~20km) to find any non-transparent pixel (handles cloud gaps).
     * 
     * @return Chlorophyll value in mg/m³ if data available, null otherwise
     */
    private suspend fun fetchFromSatellite(
        lat: Double,
        lon: Double,
        dateStr: String,
        satelliteName: String,
        layerId: String
    ): Double? {
        try {
            // Use ~20km area to find data (handles cloud gaps)
            val delta = 0.1
            val bbox = "${lon - delta},${lat - delta},${lon + delta},${lat + delta}"
            
            val url = buildString {
                append(WMS_BASE)
                append("?SERVICE=WMS")
                append("&REQUEST=GetMap")
                append("&VERSION=1.1.1")
                append("&LAYERS=$layerId")
                append("&STYLES=")
                append("&FORMAT=image/png")
                append("&TRANSPARENT=true")
                append("&WIDTH=10")
                append("&HEIGHT=10")
                append("&SRS=EPSG:4326")
                append("&BBOX=$bbox")
                append("&TIME=$dateStr")
            }
            
            val response = httpClient.get(url)
            
            if (response.status != HttpStatusCode.OK) {
                logger.debug("GIBS $satelliteName returned ${response.status} for ($lat, $lon) on $dateStr")
                return null
            }
            
            val bytes = response.readBytes()
            
            // Parse PNG and find first non-transparent pixel
            val rgba = findFirstNonTransparentPixel(bytes)
            if (rgba == null) {
                logger.debug("$satelliteName: no data for ($lat, $lon) on $dateStr")
                return null
            }
            
            val (r, g, b) = rgba
            val chlorophyll = rgbToChlorophyll(r, g, b)
            
            logger.debug("$satelliteName ($dateStr): ${String.format("%.3f", chlorophyll)} mg/m³ at ($lat, $lon) [RGB: $r,$g,$b]")
            return chlorophyll
            
        } catch (e: Exception) {
            logger.debug("Error fetching $satelliteName for ($lat, $lon) on $dateStr: ${e.message}")
            return null
        }
    }
    
    /**
     * Parse PNG image and find the first non-transparent pixel.
     * 
     * @return Triple(R, G, B) if found, null if all transparent
     */
    private fun findFirstNonTransparentPixel(pngBytes: ByteArray): Triple<Int, Int, Int>? {
        try {
            if (pngBytes.size < 8) return null
            
            // Verify PNG signature
            val pngSignature = byteArrayOf(
                0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
            )
            if (!pngBytes.slice(0..7).toByteArray().contentEquals(pngSignature)) {
                return null
            }
            
            // Parse chunks to find IHDR and IDAT
            var offset = 8
            var width = 0
            var height = 0
            var idatData = byteArrayOf()
            
            while (offset < pngBytes.size - 12) {
                val length = ((pngBytes[offset].toInt() and 0xFF) shl 24) or
                            ((pngBytes[offset + 1].toInt() and 0xFF) shl 16) or
                            ((pngBytes[offset + 2].toInt() and 0xFF) shl 8) or
                            (pngBytes[offset + 3].toInt() and 0xFF)
                
                val type = String(pngBytes.slice(offset + 4..offset + 7).toByteArray())
                
                when (type) {
                    "IHDR" -> {
                        width = ((pngBytes[offset + 8].toInt() and 0xFF) shl 24) or
                                ((pngBytes[offset + 9].toInt() and 0xFF) shl 16) or
                                ((pngBytes[offset + 10].toInt() and 0xFF) shl 8) or
                                (pngBytes[offset + 11].toInt() and 0xFF)
                        height = ((pngBytes[offset + 12].toInt() and 0xFF) shl 24) or
                                ((pngBytes[offset + 13].toInt() and 0xFF) shl 16) or
                                ((pngBytes[offset + 14].toInt() and 0xFF) shl 8) or
                                (pngBytes[offset + 15].toInt() and 0xFF)
                    }
                    "IDAT" -> {
                        idatData += pngBytes.slice(offset + 8 until offset + 8 + length).toByteArray()
                    }
                    "IEND" -> break
                }
                
                offset += 12 + length
            }
            
            if (idatData.isEmpty() || width == 0 || height == 0) return null
            
            // Decompress IDAT
            val inflater = Inflater()
            inflater.setInput(idatData)
            val decompressed = ByteArray(width * height * 4 + height + 1000)
            val decompressedLength = inflater.inflate(decompressed)
            inflater.end()
            
            if (decompressedLength < 5) return null
            
            // Scan for first non-transparent pixel (RGBA format, +1 per row for filter byte)
            val stride = width * 4 + 1
            
            for (y in 0 until height) {
                val rowStart = y * stride + 1  // Skip filter byte
                for (x in 0 until width) {
                    val pxStart = rowStart + x * 4
                    if (pxStart + 4 <= decompressedLength) {
                        val r = decompressed[pxStart].toInt() and 0xFF
                        val g = decompressed[pxStart + 1].toInt() and 0xFF
                        val b = decompressed[pxStart + 2].toInt() and 0xFF
                        val a = decompressed[pxStart + 3].toInt() and 0xFF
                        
                        if (a > 0) {  // Found non-transparent pixel
                            return Triple(r, g, b)
                        }
                    }
                }
            }
            
            return null  // All pixels transparent
            
        } catch (e: Exception) {
            logger.debug("PNG parsing error: ${e.message}")
            return null
        }
    }
    
    /**
     * Convert RGB color to chlorophyll-a concentration using GIBS colormap.
     * 
     * The GIBS chlorophyll colormap uses a logarithmic scale from 0.01 to 50 mg/m³.
     * Colors progress: Purple -> Blue -> Cyan -> Green -> Yellow -> Orange -> Red
     */
    fun rgbToChlorophyll(r: Int, g: Int, b: Int): Double {
        val position = colorToPosition(r, g, b)
        
        // Logarithmic scale: log10(0.01) = -2, log10(50) = 1.7
        val logMin = ln(0.01) / ln(10.0)  // -2
        val logMax = ln(50.0) / ln(10.0)  // ~1.7
        val logValue = logMin + position * (logMax - logMin)
        
        return 10.0.pow(logValue)
    }
    
    /**
     * Map RGB color to position (0-1) in the colormap gradient.
     */
    private fun colorToPosition(r: Int, g: Int, b: Int): Double {
        val rf = r / 255.0
        val gf = g / 255.0
        val bf = b / 255.0
        
        return when {
            // Purple region (high blue, some red, low green)
            bf > 0.4 && rf > 0.3 && gf < 0.1 -> {
                0.0 + (rf / (rf + bf)) * 0.1
            }
            
            // Blue region (high blue, low red, low-medium green)
            bf > 0.8 && rf < 0.2 -> {
                0.15 + gf * 0.25
            }
            
            // Cyan-green region (high green, decreasing blue)
            gf > 0.5 && bf > 0.2 && rf < 0.3 -> {
                0.35 + (1.0 - bf) * 0.15
            }
            
            // Green region (high green, low blue, low-medium red)
            gf > 0.7 && bf < 0.3 && rf < 0.7 -> {
                0.45 + rf * 0.2
            }
            
            // Yellow region (high red, high green, low blue)
            rf > 0.7 && gf > 0.7 && bf < 0.2 -> {
                0.60 + (1.0 - minOf(rf, gf)) * 0.1
            }
            
            // Orange region (high red, medium green, low blue)
            rf > 0.8 && gf > 0.2 && gf < 0.8 && bf < 0.2 -> {
                0.70 + (1.0 - gf) * 0.2
            }
            
            // Red region (high red, low green, low blue)
            rf > 0.5 && gf < 0.3 && bf < 0.2 -> {
                0.85 + (1.0 - rf) * 0.3
            }
            
            // Default: estimate based on warmth
            else -> {
                val warmth = (rf - bf + 1.0) / 2.0
                warmth.coerceIn(0.0, 1.0)
            }
        }
    }
    
    /**
     * Get list of satellite names.
     */
    fun getSatelliteNames(): List<String> = SATELLITES.map { it.first }
}
