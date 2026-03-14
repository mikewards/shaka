package com.shaka.data.client

import com.shaka.model.TideChartData
import com.shaka.model.TideData

/**
 * Abstraction over tide data providers (NOAA CO-OPS, FES2022, etc.).
 * Allows swapping implementations via the TIDE_SOURCE env var.
 */
interface TideClient {

    /** The provider identifier stored in spot_tide_days (e.g. "noaa", "fes2022"). */
    val provider: String

    /** Fetch summary tide info: current height, state, next high/low. */
    suspend fun getTideData(lat: Double, lon: Double, date: String): TideData

    /** Fetch structured chart data (hourly points + extremes) for a single day. Returns null on failure. */
    suspend fun getTideChartData(lat: Double, lon: Double, date: String): TideChartData?

    companion object {
        fun create(): TideClient {
            val source = System.getenv("TIDE_SOURCE")?.lowercase() ?: "noaa"
            return when (source) {
                "fes2022" -> FES2022TideClient()
                else -> NOAATidesClient()
            }
        }
    }
}
