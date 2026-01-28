package com.shaka.api.routes

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

    routing {
        route("/v1") {
            // Health check
            get("/health") {
                call.respond(mapOf("status" to "ok", "service" to "shaka-api"))
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
        }
    }
}
