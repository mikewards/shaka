package com.shaka.data.client

import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import org.slf4j.LoggerFactory
import java.time.Instant
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.zip.Inflater

/**
 * Result containing RGB colors from all GIBS satellites for today and yesterday.
 * 
 * IMPORTANT: These colors are for DISPLAY ONLY - they do NOT represent accurate
 * chlorophyll concentrations. Satellite imagery in coastal areas often shows
 * contamination from sediment, kelp, and shallow bottom reflectance.
 * 
 * For actual chlorophyll measurements, use NOAA ERDDAP or Copernicus APIs.
 * 
 * Includes observation timestamps from NASA CMR for NASA satellites.
 */
data class GIBSSatelliteColors(
    // Colors only - "#RRGGBB" format, null if no data/cloud covered
    val paceTodayColor: String?,
    val paceYesterdayColor: String?,
    val noaa20TodayColor: String?,
    val noaa20YesterdayColor: String?,
    val noaa21TodayColor: String?,
    val noaa21YesterdayColor: String?,
    val sentinel3aTodayColor: String?,
    val sentinel3aYesterdayColor: String?,
    val sentinel3bTodayColor: String?,
    val sentinel3bYesterdayColor: String?,
    val dataDate: LocalDate,  // "Today" when this was fetched
    // Observation timestamps from NASA CMR (yesterday's pass times)
    val paceObservationTime: Instant? = null,
    val noaa20ObservationTime: Instant? = null,
    val noaa21ObservationTime: Instant? = null
    // Sentinel-3 times not available in NASA CMR
)

/**
 * Client for fetching satellite imagery colors from NASA GIBS (Global Imagery Browse Services).
 * 
 * Fetches RGB colors from all 5 chlorophyll satellite layers for both today and yesterday:
 * - PACE OCI (newest hyperspectral sensor)
 * - NOAA-20 VIIRS (best coverage)
 * - NOAA-21 VIIRS (backup)
 * - Sentinel-3A OLCI (morning pass)
 * - Sentinel-3B OLCI (backup morning)
 * 
 * IMPORTANT: These colors are for DISPLAY ONLY. Do NOT use them to derive chlorophyll
 * concentrations - coastal imagery is often contaminated by sediment, kelp, and bottom
 * reflectance. Use NOAA ERDDAP or Copernicus for actual chlorophyll measurements.
 */
object GIBSClient {
    
    private val logger = LoggerFactory.getLogger(GIBSClient::class.java)
    private val httpClient: io.ktor.client.HttpClient get() = HttpClientFactory.shared
    
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
     * Fetch satellite imagery colors from ALL satellites for today and yesterday.
     * Also fetches observation timestamps from NASA CMR for NASA satellites.
     * 
     * @param lat Latitude in decimal degrees
     * @param lon Longitude in decimal degrees
     * @return GIBSSatelliteColors with hex colors from all satellites (nulls where no data)
     */
    suspend fun getAllSatelliteColors(lat: Double, lon: Double): GIBSSatelliteColors = coroutineScope {
        val today = LocalDate.now()
        val yesterday = today.minusDays(1)
        val todayStr = today.format(dateFormatter)
        val yesterdayStr = yesterday.format(dateFormatter)
        
        // Fetch all 10 satellite images in parallel (5 satellites x 2 days)
        val colorDeferreds = SATELLITES.flatMap { (satName, layerId) ->
            listOf(
                async { "${satName}_today" to fetchColorFromSatellite(lat, lon, todayStr, satName, layerId) },
                async { "${satName}_yesterday" to fetchColorFromSatellite(lat, lon, yesterdayStr, satName, layerId) }
            )
        }
        
        val colors = colorDeferreds.awaitAll().toMap()
        
        // Fetch observation timestamps from NASA CMR (for yesterday's data)
        val observationTimes = try {
            CMRClient.getAllObservationTimes(lat, lon, yesterdayStr)
        } catch (e: Exception) {
            logger.debug("CMR observation times fetch failed: ${e.message}")
            emptyMap()
        }
        
        GIBSSatelliteColors(
            paceTodayColor = colors["PACE_today"],
            paceYesterdayColor = colors["PACE_yesterday"],
            noaa20TodayColor = colors["NOAA-20_today"],
            noaa20YesterdayColor = colors["NOAA-20_yesterday"],
            noaa21TodayColor = colors["NOAA-21_today"],
            noaa21YesterdayColor = colors["NOAA-21_yesterday"],
            sentinel3aTodayColor = colors["Sentinel-3A_today"],
            sentinel3aYesterdayColor = colors["Sentinel-3A_yesterday"],
            sentinel3bTodayColor = colors["Sentinel-3B_today"],
            sentinel3bYesterdayColor = colors["Sentinel-3B_yesterday"],
            dataDate = today,
            paceObservationTime = observationTimes["PACE"],
            noaa20ObservationTime = observationTimes["NOAA-20"],
            noaa21ObservationTime = observationTimes["NOAA-21"]
        )
    }
    
    /**
     * Fetch RGB color from a specific satellite for a specific date.
     * Uses a 10x10 pixel area (~20km) to find any non-transparent pixel (handles cloud gaps).
     * 
     * @return Hex color string "#RRGGBB", or null if no data/cloud covered
     */
    private suspend fun fetchColorFromSatellite(
        lat: Double,
        lon: Double,
        dateStr: String,
        satelliteName: String,
        layerId: String
    ): String? {
        try {
            // Use ~20km area to find data (accepts NULLs when cloud-covered)
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
            val colorHex = String.format("#%02X%02X%02X", r, g, b)
            
            logger.debug("$satelliteName ($dateStr): color $colorHex at ($lat, $lon)")
            return colorHex
            
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
     * Get list of satellite names.
     */
    fun getSatelliteNames(): List<String> = SATELLITES.map { it.first }
}
