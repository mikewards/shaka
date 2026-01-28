package com.shaka.api.routes

import com.shaka.data.cache.OceanDataCache
import com.shaka.data.client.CopernicusClient
import com.shaka.data.client.SpotDatabase
import com.shaka.model.*
import com.shaka.service.SpotService
import com.shaka.service.ForecastService
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

fun Application.configureRouting() {
    val spotService = SpotService()
    val forecastService = ForecastService()
    val copernicusClient = CopernicusClient()

    routing {
        route("/v1") {
            // Health check
            get("/health") {
                val cacheStats = OceanDataCache.getStats()
                call.respond(mapOf(
                    "status" to "ok", 
                    "service" to "shaka-api",
                    "realtimeSatelliteAvailable" to copernicusClient.isRealTimeAvailable(),
                    "cache" to cacheStats
                ))
            }

            // Search for spots
            get("/spots/search") {
                val lat = call.parameters["lat"]?.toDoubleOrNull()
                    ?: return@get call.respond(HttpStatusCode.BadRequest, mapOf("error" to "lat required"))
                val lon = call.parameters["lon"]?.toDoubleOrNull()
                    ?: return@get call.respond(HttpStatusCode.BadRequest, mapOf("error" to "lon required"))
                val radiusKm = call.parameters["radius"]?.toIntOrNull() ?: 50
                val date = call.parameters["date"]
                    ?: return@get call.respond(HttpStatusCode.BadRequest, mapOf("error" to "date required"))

                val results = spotService.searchSpots(lat, lon, radiusKm, date)
                call.respond(results)
            }

            // Get spot detail
            get("/spots/{id}") {
                val spotId = call.parameters["id"]
                    ?: return@get call.respond(HttpStatusCode.BadRequest, mapOf("error" to "id required"))
                val date = call.parameters["date"] ?: java.time.LocalDate.now().toString()

                val spot = spotService.getSpotDetail(spotId, date)
                if (spot != null) {
                    call.respond(spot)
                } else {
                    call.respond(HttpStatusCode.NotFound, mapOf("error" to "Spot not found"))
                }
            }

            /**
             * Get REAL-TIME satellite water clarity data for a spot.
             * 
             * WARNING: This endpoint is SLOW (30-60 seconds) because it processes
             * raw Sentinel-3 satellite imagery on-demand for the most current data.
             * 
             * Use the regular /spots/{id} endpoint for fast (2-5s) cached data.
             * Only call this endpoint when user explicitly requests real-time satellite data.
             * 
             * Requires COPERNICUS_CLIENT_ID and COPERNICUS_CLIENT_SECRET to be configured.
             */
            get("/spots/{id}/realtime-clarity") {
                val spotId = call.parameters["id"]
                    ?: return@get call.respond(HttpStatusCode.BadRequest, mapOf("error" to "id required"))
                val date = call.parameters["date"] ?: java.time.LocalDate.now().toString()

                // Check if real-time satellite is available
                if (!copernicusClient.isRealTimeAvailable()) {
                    return@get call.respond(
                        HttpStatusCode.ServiceUnavailable,
                        mapOf(
                            "error" to "Real-time satellite data not available",
                            "reason" to "Copernicus credentials not configured",
                            "suggestion" to "Use /spots/{id} for standard water quality data"
                        )
                    )
                }

                // Get spot coordinates
                val spot = SpotDatabase.findSpotById(spotId)
                    ?: return@get call.respond(HttpStatusCode.NotFound, mapOf("error" to "Spot not found"))

                try {
                    // Fetch real-time satellite data (SLOW - 30-60 seconds)
                    val waterQuality = copernicusClient.getRealTimeWaterQuality(
                        spot.coordinates.lat,
                        spot.coordinates.lon,
                        date
                    )

                    call.respond(mapOf(
                        "spotId" to spotId,
                        "spotName" to spot.name,
                        "date" to date,
                        "dataSource" to waterQuality.dataSource,
                        "waterClarity" to mapOf(
                            "visibility" to mapOf(
                                "meters" to waterQuality.visibility,
                                "category" to waterQuality.visibilityCategory
                            ),
                            "chlorophyll" to mapOf(
                                "value" to waterQuality.chlorophyllA,
                                "unit" to "mg/m³",
                                "category" to waterQuality.chlorophyllCategory
                            ),
                            "turbidity" to mapOf(
                                "value" to waterQuality.turbidity,
                                "unit" to "NTU",
                                "category" to waterQuality.turbidityCategory
                            ),
                            "seaSurfaceTemp" to mapOf(
                                "celsius" to waterQuality.seaSurfaceTemp,
                                "fahrenheit" to waterQuality.seaSurfaceTemp?.let { (it * 9/5) + 32 }
                            )
                        ),
                        "note" to "Real-time Sentinel-3 satellite data. Updated from latest available pass."
                    ))
                } catch (e: Exception) {
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        mapOf(
                            "error" to "Failed to fetch real-time satellite data",
                            "message" to e.message,
                            "suggestion" to "Use /spots/{id} for standard water quality data"
                        )
                    )
                }
            }

            // Get forecast for a spot
            get("/forecast/{spotId}") {
                val spotId = call.parameters["spotId"]
                    ?: return@get call.respond(HttpStatusCode.BadRequest, mapOf("error" to "spotId required"))
                val days = call.parameters["days"]?.toIntOrNull() ?: 7

                val forecast = forecastService.getForecast(spotId, days)
                call.respond(forecast)
            }

            // Get community reports for a region
            get("/reports/{region}") {
                val region = call.parameters["region"]
                    ?: return@get call.respond(HttpStatusCode.BadRequest, mapOf("error" to "region required"))

                val reports = spotService.getCommunityReports(region)
                call.respond(reports)
            }

            // Clear cache (admin endpoint)
            post("/admin/cache/clear") {
                OceanDataCache.clearAll()
                call.respond(mapOf("status" to "ok", "message" to "Cache cleared"))
            }

            // Get cache stats
            get("/admin/cache/stats") {
                call.respond(OceanDataCache.getStats())
            }
        }
    }
}
