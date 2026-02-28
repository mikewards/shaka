package com.shaka.data.client

import com.shaka.data.cache.SpotDataCache
import io.ktor.client.request.*
import io.ktor.client.statement.*
import org.slf4j.LoggerFactory
import java.time.*
import java.time.format.DateTimeFormatter

/**
 * Client for NOAA National Data Buoy Center (NDBC) real-time wave data.
 * Free, no authentication required.
 *
 * Data:
 * - Station list: https://www.ndbc.noaa.gov/data/stations/station_table.txt
 * - Real-time obs: https://www.ndbc.noaa.gov/data/realtime2/{station_id}.txt
 *
 * Stations report hourly. Data available ~25 minutes after the hour.
 * Missing values are encoded as "MM".
 */
class NDBCBuoyClient {

    private val logger = LoggerFactory.getLogger(NDBCBuoyClient::class.java)
    private val client = HttpClientFactory.shared

    companion object {
        private const val STATION_TABLE_URL = "https://www.ndbc.noaa.gov/data/stations/station_table.txt"
        private const val REALTIME_BASE_URL = "https://www.ndbc.noaa.gov/data/realtime2"
    }

    /**
     * Fetch ALL active NDBC stations that report wave data (WVHT).
     * Parses the NDBC station_table.txt which has pipe-delimited fields.
     */
    /**
     * Parse lat/lon from NDBC LOCATION field.
     * Format: "44.794 N 87.313 W (...)" or "12.000 N 23.000 W (...)"
     */
    private fun parseLocation(location: String): Pair<Double, Double>? {
        val pattern = Regex("""(\d+\.?\d*)\s*([NS])\s+(\d+\.?\d*)\s*([EW])""")
        val match = pattern.find(location) ?: return null
        val (latVal, latDir, lonVal, lonDir) = match.destructured
        val lat = latVal.toDoubleOrNull() ?: return null
        val lon = lonVal.toDoubleOrNull() ?: return null
        return Pair(
            if (latDir == "S") -lat else lat,
            if (lonDir == "W") -lon else lon
        )
    }
    
    suspend fun fetchWaveStations(): List<SpotDataCache.BuoyStation> {
        return try {
            val body = client.get(STATION_TABLE_URL).bodyAsText()
            val stations = mutableListOf<SpotDataCache.BuoyStation>()

            // Format: STATION_ID | OWNER | TTYPE | HULL | NAME | PAYLOAD | LOCATION | ...
            for (line in body.lines()) {
                if (line.startsWith("#") || line.isBlank()) continue
                val parts = line.split("|").map { it.trim() }
                if (parts.size < 7) continue

                val stationId = parts[0].trim()
                if (stationId.isBlank()) continue
                
                val name = parts.getOrNull(4)?.trim() ?: stationId
                val locationStr = parts.getOrNull(6) ?: continue
                val (lat, lon) = parseLocation(locationStr) ?: continue
                
                if (lat == 0.0 && lon == 0.0) continue

                stations += SpotDataCache.BuoyStation(
                    stationId = stationId,
                    lat = lat,
                    lon = lon,
                    name = name.ifBlank { stationId }
                )
            }

            logger.info("Parsed ${stations.size} NDBC stations from station table")
            stations
        } catch (e: Exception) {
            logger.error("Failed to fetch NDBC station table: ${e.message}")
            emptyList()
        }
    }

    /**
     * Fetch the latest wave observation from a single NDBC station.
     * Parses the realtime2 .txt file (space-separated, 2 header rows).
     *
     * Returns null if station doesn't report wave data or data is unavailable.
     */
    suspend fun fetchLatestReading(stationId: String): SpotDataCache.BuoyReading? {
        return try {
            val url = "$REALTIME_BASE_URL/$stationId.txt"
            val body = client.get(url).bodyAsText()
            val lines = body.lines()

            // First 2 lines are headers: column names and units
            if (lines.size < 3) return null

            val header = lines[0].trim().split("\\s+".toRegex())
            val dataLine = lines[2].trim().split("\\s+".toRegex())

            if (dataLine.size < header.size) return null

            val colMap = header.withIndex().associate { (i, name) -> name to i }

            fun col(name: String): String? {
                val idx = colMap[name] ?: return null
                val value = dataLine.getOrNull(idx) ?: return null
                return if (value == "MM" || value == "99.00" || value == "999") null else value
            }

            val wvht = col("WVHT")?.toDoubleOrNull() ?: return null
            val dpd = col("DPD")?.toDoubleOrNull()
            val mwd = col("MWD")?.toIntOrNull()

            // Parse timestamp — "MM" column name collides with missing-data sentinel,
            // so read month by index directly to avoid the sentinel check
            val year = col("#YY")?.toIntOrNull() ?: col("YY")?.toIntOrNull() ?: return null
            val monthIdx = colMap["MM"] ?: return null
            val monthVal = dataLine.getOrNull(monthIdx)?.toIntOrNull() ?: return null
            val day = col("DD")?.toIntOrNull() ?: return null
            val hour = col("hh")?.toIntOrNull() ?: return null
            val min = col("mm")?.toIntOrNull() ?: 0

            val observedAt = try {
                LocalDateTime.of(year, monthVal, day, hour, min)
                    .atZone(ZoneOffset.UTC)
                    .toInstant()
            } catch (e: Exception) {
                logger.debug("Bad timestamp for $stationId: $year-$monthVal-$day $hour:$min")
                return null
            }

            SpotDataCache.BuoyReading(
                stationId = stationId,
                observedAt = observedAt,
                waveHeightM = wvht,
                dominantPeriodSec = dpd,
                meanDirection = mwd
            )
        } catch (e: Exception) {
            logger.debug("Failed to fetch reading for buoy $stationId: ${e.message}")
            null
        }
    }
}
