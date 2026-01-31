package com.shaka.api.routes

import com.shaka.data.cache.OceanDataCache
import com.shaka.data.client.CopernicusClient
import com.shaka.data.client.ERDDAPSectorClient
import com.shaka.data.client.SpotDatabase
import com.shaka.model.*
import com.shaka.service.SpotService
import com.shaka.service.ForecastService
import com.shaka.service.HealthService
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay

fun Application.configureRouting() {
    val spotService = SpotService()
    val forecastService = ForecastService()
    val copernicusClient = CopernicusClient()
    val healthService = HealthService()

    routing {
        route("/v1") {
            // Health check - keep simple for Railway healthcheck
            get("/health") {
                call.respond(mapOf("status" to "ok", "service" to "shaka-api"))
            }
            
            // Detailed health with external service checks
            // Used by Flutter app to auto-degrade features
            get("/health/detailed") {
                val serviceHealth = healthService.checkHealth()
                val cacheStats = OceanDataCache.getStats()
                call.respond(mapOf(
                    "status" to serviceHealth.status,
                    "service" to "shaka-api",
                    "services" to serviceHealth.services,
                    "realtimeSatelliteAvailable" to copernicusClient.isDirectAccessAvailable(),
                    "cache" to cacheStats,
                    "timestamp" to serviceHealth.timestamp
                ))
            }

            // Search for spots by location
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
            
            // Search spots by name (for type-ahead search)
            get("/spots/search/name") {
                val query = call.parameters["q"]
                    ?: return@get call.respond(HttpStatusCode.BadRequest, mapOf("error" to "q (query) required"))
                val limit = call.parameters["limit"]?.toIntOrNull() ?: 20
                
                val results = spotService.searchSpotsByName(query, limit)
                call.respond(results)
            }
            
            // Batch fetch spots by IDs (for favorites/home screen)
            get("/spots/batch") {
                val ids = call.parameters["ids"]
                    ?: return@get call.respond(HttpStatusCode.BadRequest, mapOf("error" to "ids required (comma-separated)"))
                val date = call.parameters["date"] ?: java.time.LocalDate.now().toString()
                
                val spotIds = ids.split(",").map { it.trim() }.filter { it.isNotEmpty() }
                if (spotIds.isEmpty()) {
                    return@get call.respond(HttpStatusCode.BadRequest, mapOf("error" to "at least one spot ID required"))
                }
                if (spotIds.size > 20) {
                    return@get call.respond(HttpStatusCode.BadRequest, mapOf("error" to "maximum 20 spots per request"))
                }
                
                val results = spotService.getSpotsBatch(spotIds, date)
                call.respond(results)
            }
            
            // Get all regions (for search autocomplete)
            get("/regions") {
                val regions = spotService.getAllRegions()
                call.respond(regions)
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

                // Check if direct Sentinel-3 access is available
                if (!copernicusClient.isDirectAccessAvailable()) {
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
            
            // Clear all chlorophyll values (removes fake climatology data)
            post("/admin/chlorophyll/clear") {
                val cleared = com.shaka.data.cache.SpotDataCache.clearAllChlorophyll()
                call.respondText("""{"status":"ok","cleared":$cleared}""", io.ktor.http.ContentType.Application.Json)
            }
            
            // Get chlorophyll stats
            get("/admin/chlorophyll/stats") {
                call.respondText(
                    com.shaka.data.cache.SpotDataCache.getChlorophyllStatsJson(),
                    io.ktor.http.ContentType.Application.Json
                )
            }
            
            // Identify fake climatology chlorophyll values
            get("/admin/chlorophyll/identify-fake") {
                val fakeSpots = com.shaka.data.cache.SpotDataCache.identifyFakeChlorophyll(SpotDatabase)
                val grouped = fakeSpots.groupBy { it.second }.mapValues { it.value.size }
                call.respondText(
                    """{"totalFake":${fakeSpots.size},"byValue":${grouped.entries.joinToString(",", "{", "}") { "\"${it.key}\":${it.value}" }},"spots":${fakeSpots.take(20).joinToString(",", "[", "]") { "\"${it.first}\"" }}}""",
                    io.ktor.http.ContentType.Application.Json
                )
            }
            
            // Clear only fake climatology values (preserves real data)
            post("/admin/chlorophyll/clear-fake") {
                val cleared = com.shaka.data.cache.SpotDataCache.clearFakeChlorophyll(SpotDatabase)
                call.respondText("""{"status":"ok","cleared":$cleared}""", io.ktor.http.ContentType.Application.Json)
            }
            
            // Trigger refetch for all spots without chlorophyll
            post("/admin/chlorophyll/refetch") {
                val spotsToFetch = com.shaka.data.cache.SpotDataCache.getSpotsWithoutChlorophyll()
                val total = spotsToFetch.size
                
                // Return immediately with count - actual fetch happens in background
                // This avoids timeout for long-running operations
                kotlinx.coroutines.GlobalScope.launch {
                    var success = 0
                    var failed = 0
                    val today = java.time.LocalDate.now().toString()
                    
                    for (spotId in spotsToFetch) {
                        try {
                            val spot = SpotDatabase.findSpotById(spotId) ?: continue
                            val waterQuality = copernicusClient.getWaterQuality(
                                spot.coordinates.lat, 
                                spot.coordinates.lon, 
                                today
                            )
                            waterQuality.chlorophyllA?.let { chl ->
                                com.shaka.data.cache.SpotDataCache.updateChlorophyll(
                                    spotId,
                                    com.shaka.data.cache.SpotDataCache.CachedValue(
                                        value = chl,
                                        fetchedAt = java.time.Instant.now(),
                                        dataValidAt = java.time.Instant.now()
                                    )
                                )
                                com.shaka.data.cache.SpotDataCache.saveToDatabase(spotId)
                                success++
                            } ?: run { failed++ }
                        } catch (e: Exception) {
                            failed++
                        }
                        // Rate limit
                        kotlinx.coroutines.delay(500)
                    }
                }
                
                call.respondText(
                    """{"status":"started","spotsToFetch":$total,"message":"Refetch started in background. Check /admin/chlorophyll/stats for progress."}""",
                    io.ktor.http.ContentType.Application.Json
                )
            }
            
            // ==================== ERDDAP 300m Comparison Endpoints ====================
            // These are for comparing ERDDAP data vs existing Copernicus data
            // They do NOT modify any existing data
            
            // Get sector info for a specific location
            get("/admin/erddap/sector-info") {
                val lat = call.parameters["lat"]?.toDoubleOrNull()
                    ?: return@get call.respondText("""{"error":"lat required"}""", io.ktor.http.ContentType.Application.Json, HttpStatusCode.BadRequest)
                val lon = call.parameters["lon"]?.toDoubleOrNull()
                    ?: return@get call.respondText("""{"error":"lon required"}""", io.ktor.http.ContentType.Application.Json, HttpStatusCode.BadRequest)
                
                val sectorInfo = ERDDAPSectorClient.getSectorInfo(lat, lon)
                call.respondText(
                    """{"sector":"${sectorInfo["sector"]}","datasetId":"${sectorInfo["datasetId"]}","lonBand":${sectorInfo["lonBand"]},"latBand":${sectorInfo["latBand"]},"lonRange":"${sectorInfo["lonRange"]}","latRange":"${sectorInfo["latRange"]}"}""",
                    io.ktor.http.ContentType.Application.Json
                )
            }
            
            // Test ERDDAP fetch for a single spot
            get("/admin/erddap/test/{spotId}") {
                val spotId = call.parameters["spotId"]
                    ?: return@get call.respondText("""{"error":"spotId required"}""", io.ktor.http.ContentType.Application.Json, HttpStatusCode.BadRequest)
                
                val spot = SpotDatabase.findSpotById(spotId)
                    ?: return@get call.respondText("""{"error":"Spot not found"}""", io.ktor.http.ContentType.Application.Json, HttpStatusCode.NotFound)
                
                val sectorInfo = ERDDAPSectorClient.getSectorInfo(spot.coordinates.lat, spot.coordinates.lon)
                val erddapResult = ERDDAPSectorClient.getChlorophyll(spot.coordinates.lat, spot.coordinates.lon)
                val copernicusValue = com.shaka.data.cache.SpotDataCache.get(spotId)?.chlorophyll?.value
                
                val erddapJson = if (erddapResult != null) 
                    """{"chlorophyll":${erddapResult.chlorophyll},"sector":"${erddapResult.sector}","dataDate":"${erddapResult.dataDate}","source":"${erddapResult.source}"}"""
                else "null"
                val diff = if (erddapResult != null && copernicusValue != null) 
                    kotlin.math.abs(erddapResult.chlorophyll - copernicusValue).toString() else "null"
                
                call.respondText(
                    """{"spotId":"$spotId","spotName":"${spot.name}","lat":${spot.coordinates.lat},"lon":${spot.coordinates.lon},"sector":"${sectorInfo["sector"]}","erddap":$erddapJson,"copernicus":${copernicusValue ?: "null"},"difference":$diff}""",
                    io.ktor.http.ContentType.Application.Json
                )
            }
            
            // Get current comparison stats (from cached ERDDAP data)
            get("/admin/erddap/stats") {
                val stats = com.shaka.data.cache.SpotDataCache.getErddapComparisonStats()
                call.respondText(
                    """{"totalSpots":${stats["totalSpots"]},"bothHaveData":${stats["bothHaveData"]},"onlyCopernicus":${stats["onlyCopernicus"]},"onlyErddap":${stats["onlyErddap"]},"neither":${stats["neither"]},"erddapCached":${stats["erddapCached"]},"avgDifference":"${stats["avgDifference"]}"}""",
                    io.ktor.http.ContentType.Application.Json
                )
            }
            
            // Clear ERDDAP cache (for fresh run)
            post("/admin/erddap/clear") {
                val cleared = com.shaka.data.cache.SpotDataCache.clearErddapCache()
                call.respondText(
                    """{"status":"ok","cleared":$cleared}""",
                    io.ktor.http.ContentType.Application.Json
                )
            }
            
            // Fetch ERDDAP data for ALL spots and compare with Copernicus
            // This runs in background and populates the ERDDAP cache
            post("/admin/erddap/compare-all") {
                val allSpots = SpotDatabase.getAllSpots()
                val total = allSpots.size
                
                // Clear existing ERDDAP cache for fresh comparison
                com.shaka.data.cache.SpotDataCache.clearErddapCache()
                
                // Return immediately - fetch happens in background
                kotlinx.coroutines.GlobalScope.launch {
                    var fetched = 0
                    var withData = 0
                    var noData = 0
                    var errors = 0
                    
                    for (spot in allSpots) {
                        try {
                            val sectorInfo = ERDDAPSectorClient.getSectorInfo(spot.coordinates.lat, spot.coordinates.lon)
                            val sector = sectorInfo["sector"] as String
                            
                            val result = ERDDAPSectorClient.getChlorophyll(
                                spot.coordinates.lat,
                                spot.coordinates.lon
                            )
                            
                            if (result != null) {
                                com.shaka.data.cache.SpotDataCache.setErddapChlorophyll(
                                    spot.id,
                                    result.chlorophyll,
                                    result.sector,
                                    result.dataDate,
                                    result.source
                                )
                                withData++
                            } else {
                                // Store null result so we know we tried
                                com.shaka.data.cache.SpotDataCache.setErddapChlorophyll(
                                    spot.id,
                                    null,
                                    sector,
                                    null,
                                    "ERDDAP 300m (no data)"
                                )
                                noData++
                            }
                            fetched++
                        } catch (e: Exception) {
                            errors++
                        }
                        
                        // Rate limit to avoid overwhelming ERDDAP
                        kotlinx.coroutines.delay(100)
                    }
                }
                
                call.respondText(
                    """{"status":"started","totalSpots":$total,"message":"ERDDAP comparison started in background. Check /admin/erddap/stats for progress."}""",
                    io.ktor.http.ContentType.Application.Json
                )
            }
            
            // Get detailed comparison results (after compare-all completes)
            get("/admin/erddap/comparison-details") {
                val limit = call.parameters["limit"]?.toIntOrNull() ?: 100
                val allDetails = com.shaka.data.cache.SpotDataCache.getErddapComparisonDetails()
                val details = allDetails.take(limit)
                
                val resultsJson = details.joinToString(",") { d ->
                    val cop = d["copernicus"]?.toString() ?: "null"
                    val erd = d["erddap"]?.toString() ?: "null"
                    val sec = d["erddapSector"]?.let { "\"$it\"" } ?: "null"
                    val date = d["erddapDataDate"]?.let { "\"$it\"" } ?: "null"
                    val diff = d["difference"]?.toString() ?: "null"
                    """{"spotId":"${d["spotId"]}","copernicus":$cop,"erddap":$erd,"sector":$sec,"dataDate":$date,"difference":$diff}"""
                }
                
                call.respondText(
                    """{"total":${allDetails.size},"showing":${details.size},"results":[$resultsJson]}""",
                    io.ktor.http.ContentType.Application.Json
                )
            }
        }
    }
}
