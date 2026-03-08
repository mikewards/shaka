package com.shaka.api.routes

import com.shaka.data.cache.OceanDataCache
import com.shaka.data.cache.SpotDataCache
import com.shaka.data.client.CopernicusClient
import com.shaka.data.client.LandWaterClient
import com.shaka.data.client.SpotDatabase
import com.shaka.data.db.UserSpotRepository
import com.shaka.model.*
import com.shaka.fishing_intel.api.FishingIntelRoutes
import com.shaka.fishing_intel.api.IngestPostRequest
import com.shaka.fishing_intel.api.IngestResponse
import com.shaka.fishing_intel.db.FishingIntelDb
import com.shaka.fishing_intel.ai.FishingIntelAiService
import com.shaka.fishing_intel.processing.Deduplicator
import com.shaka.fishing_intel.processing.GeoResolver
import com.shaka.fishing_intel.processing.ResolvedGeo
import com.shaka.fishing_intel.processing.SpeciesNormalizer
import com.shaka.fishing_intel.processing.SoCalGazetteer
import com.shaka.fishing_intel.models.*
import com.shaka.service.SpotService
import com.shaka.service.ForecastService
import com.shaka.service.HealthService
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import java.util.UUID

/** Parse BD thread title for leading general location tag (Inshore, Offshore, Islands, Bay, Harbor). Returns (zone, cleanedTitle) or (null, null). */
private fun parseBdTitleForLocationTag(title: String?): Pair<String?, String?> {
    if (title.isNullOrBlank()) return null to null
    val regex = Regex("^(Inshore|Offshore|Islands|Bay|Harbor)\\s*(.*)$", RegexOption.IGNORE_CASE)
    val match = regex.find(title.trim()) ?: return null to null
    val zone = match.groupValues[1].replaceFirstChar { it.uppercase() }
    val rest = match.groupValues[2].trim()
    return zone to rest.ifBlank { null }
}

fun Application.configureRouting() {
    val spotService = SpotService()
    val forecastService = ForecastService()
    val copernicusClient = CopernicusClient()
    val healthService = HealthService()
    val userSpotRepository = UserSpotRepository()
    val landWaterClient = LandWaterClient()

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
            
            /**
             * Get ALL spots for map display.
             * Returns SpotMapMarker with score and basic conditions from cache.
             * Used by Explore map to load all ~800 spots once on startup.
             */
            get("/spots/all") {
                val allSpots = SpotDatabase.getAllSpots()
                
                val markers = allSpots.map { spot ->
                    // Get cached score if available (fast lookup, no API calls)
                    val score = spotService.getUserSpotScore(spot.id)
                    // Get region from spot ID (e.g., "oahu-sharks-cove" -> "Oahu")
                    val region = spotService.getRegionForSpot(spot.id)
                    // Get cached condition data for display
                    val cached = SpotDataCache.get(spot.id)
                    
                    SpotMapMarker(
                        id = spot.id,
                        name = spot.name,
                        coordinates = spot.coordinates,
                        region = region,
                        shakaScore = score,
                        visibility = spotService.resolveVisibilityLabel(cached),
                        swell = cached?.swell?.value?.let { s ->
                            val ht = s.correctedHeightFt ?: s.heightFt
                            "${ht.toInt()}ft @ ${s.periodSec.toInt()}s ${s.direction}"
                        },
                        wind = cached?.wind?.value?.let { 
                            "${it.speedKnots.toInt()} kts ${it.direction}" 
                        },
                        waterTemp = cached?.sst?.value?.let { sst ->
                            "${sst.toInt()}°C / ${((sst * 9/5) + 32).toInt()}°F"
                        }
                    )
                }
                
                call.respond(AllSpotsResponse(
                    spots = markers,
                    count = markers.size
                ))
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

            // Get forecast for a spot (curated or user-created)
            get("/forecast/{spotId}") {
                val spotId = call.parameters["spotId"]
                    ?: return@get call.respond(HttpStatusCode.BadRequest, mapOf("error" to "spotId required"))
                val days = call.parameters["days"]?.toIntOrNull() ?: 7

                val curated = SpotDatabase.findSpotById(spotId)
                val forecast = if (curated != null) {
                    forecastService.getForecast(spotId, days)
                } else {
                    val userSpot = userSpotRepository.findById(spotId)
                    if (userSpot != null) {
                        forecastService.getForecastForLocation(
                            userSpot.coordinates.lat,
                            userSpot.coordinates.lon,
                            days
                        )
                    } else {
                        emptyList()
                    }
                }
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
            
            post("/admin/depth/refetch") {
                val bathymetryClient = com.shaka.data.client.BathymetryClient()
                val allSpots = SpotDatabase.getAllSpots()
                val spotsNeedingDepth = allSpots.filter { spot ->
                    val cached = com.shaka.data.cache.SpotDataCache.get(spot.id.toString())
                    cached?.exposure != null && cached.exposure.depthM == null
                }
                val total = spotsNeedingDepth.size

                GlobalScope.launch {
                    val logger = org.slf4j.LoggerFactory.getLogger("DepthRefetch")
                    var success = 0
                    var failed = 0
                    for (spot in spotsNeedingDepth) {
                        try {
                            val depth = bathymetryClient.fetchDepthOnly(spot.coordinates.lat, spot.coordinates.lon) ?: continue
                            val cacheId = spot.id.toString()
                            val existing = com.shaka.data.cache.SpotDataCache.get(cacheId)?.exposure ?: continue
                            val updated = existing.copy(depthM = depth)
                            com.shaka.data.cache.SpotDataCache.updateExposure(cacheId, updated)
                            success++
                            if (success % 50 == 0) logger.info("Depth refetch progress: $success/$total")
                        } catch (e: Exception) {
                            failed++
                        }
                    }
                    logger.info("Depth refetch complete: $success success, $failed failed out of $total")
                }

                call.respondText(
                    """{"status":"started","spotsToFetch":$total,"message":"Depth refetch started in background."}""",
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
            
            // Clear all GIBS data (to force refetch with new color fields)
            post("/admin/gibs/clear") {
                val cleared = com.shaka.data.cache.SpotDataCache.clearAllGIBS()
                call.respondText(
                    """{"status":"ok","cleared":$cleared}""",
                    io.ktor.http.ContentType.Application.Json
                )
            }
            
            // Trigger GIBS satellite color fetch for all spots without GIBS data
            post("/admin/gibs/refetch") {
                val spotsToFetch = com.shaka.data.cache.SpotDataCache.getSpotsWithoutGIBS()
                val total = spotsToFetch.size
                
                kotlinx.coroutines.GlobalScope.launch {
                    for (spotId in spotsToFetch) {
                        try {
                            val spot = SpotDatabase.findSpotById(spotId) ?: continue
                            val gibsColors = com.shaka.data.client.GIBSClient.getAllSatelliteColors(
                                spot.coordinates.lat, 
                                spot.coordinates.lon
                            )
                            com.shaka.data.cache.SpotDataCache.updateGIBSChlorophyll(
                                spotId,
                                com.shaka.data.cache.SpotDataCache.CachedValue(
                                    value = com.shaka.data.cache.SpotDataCache.GIBSSatelliteData(
                                        paceTodayColor = gibsColors.paceTodayColor,
                                        paceYesterdayColor = gibsColors.paceYesterdayColor,
                                        noaa20TodayColor = gibsColors.noaa20TodayColor,
                                        noaa20YesterdayColor = gibsColors.noaa20YesterdayColor,
                                        noaa21TodayColor = gibsColors.noaa21TodayColor,
                                        noaa21YesterdayColor = gibsColors.noaa21YesterdayColor,
                                        sentinel3aTodayColor = gibsColors.sentinel3aTodayColor,
                                        sentinel3aYesterdayColor = gibsColors.sentinel3aYesterdayColor,
                                        sentinel3bTodayColor = gibsColors.sentinel3bTodayColor,
                                        sentinel3bYesterdayColor = gibsColors.sentinel3bYesterdayColor,
                                        dataDate = gibsColors.dataDate,
                                        paceObservationTime = gibsColors.paceObservationTime,
                                        noaa20ObservationTime = gibsColors.noaa20ObservationTime,
                                        noaa21ObservationTime = gibsColors.noaa21ObservationTime
                                    ),
                                    fetchedAt = java.time.Instant.now()
                                )
                            )
                            com.shaka.data.cache.SpotDataCache.saveToDatabase(spotId)
                        } catch (e: Exception) { /* continue */ }
                    }
                }
                
                call.respondText(
                    """{"status":"started","spotsToFetch":$total,"message":"GIBS fetch started in background."}""",
                    io.ktor.http.ContentType.Application.Json
                )
            }
            
            // Clear all tide data (to force refetch after code changes)
            post("/admin/tide/clear") {
                val cleared = com.shaka.data.cache.SpotDataCache.clearAllTides()
                call.respondText(
                    """{"status":"ok","cleared":$cleared}""",
                    io.ktor.http.ContentType.Application.Json
                )
            }
            
            // Trigger tide fetch for all spots without tide data
            post("/admin/tide/refetch") {
                val spotsToFetch = com.shaka.data.cache.SpotDataCache.getSpotsWithoutTide()
                val total = spotsToFetch.size
                
                val tidesClient = com.shaka.data.client.NOAATidesClient()
                val today = java.time.LocalDate.now().toString()
                
                kotlinx.coroutines.GlobalScope.launch {
                    var success = 0
                    var failed = 0
                    for (spotId in spotsToFetch) {
                        try {
                            val spot = SpotDatabase.findSpotById(spotId) ?: continue
                            val tideData = tidesClient.getTideData(
                                spot.coordinates.lat,
                                spot.coordinates.lon,
                                today
                            )
                            val stationId = tidesClient.findNearestStation(
                                spot.coordinates.lat,
                                spot.coordinates.lon
                            )
                            com.shaka.data.cache.SpotDataCache.updateTide(
                                spotId,
                                com.shaka.data.cache.SpotDataCache.CachedValue(
                                    value = com.shaka.data.cache.SpotDataCache.TideInfo(
                                        state = tideData.tideState,
                                        nextHighTide = tideData.nextHighTide,
                                        nextLowTide = tideData.nextLowTide,
                                        currentHeight = tideData.currentHeight,
                                        stationId = stationId,
                                        nextHighTideTime = tideData.nextHighTideTime?.let { java.time.Instant.ofEpochMilli(it) },
                                        nextLowTideTime = tideData.nextLowTideTime?.let { java.time.Instant.ofEpochMilli(it) }
                                    ),
                                    fetchedAt = java.time.Instant.now()
                                )
                            )
                            com.shaka.data.cache.SpotDataCache.saveToDatabase(spotId)
                            success++
                        } catch (e: Exception) { 
                            failed++
                        }
                    }
                    org.slf4j.LoggerFactory.getLogger("TideRefetch").info("Tide refetch complete: $success success, $failed failed")
                }
                
                call.respondText(
                    """{"status":"started","spotsToFetch":$total,"message":"Tide fetch started in background."}""",
                    io.ktor.http.ContentType.Application.Json
                )
            }
            
            // Clear all weather/swell data (to force refetch after code changes)
            post("/admin/weather/clear") {
                val cleared = com.shaka.data.cache.SpotDataCache.clearAllWeather()
                call.respondText(
                    """{"status":"ok","cleared":$cleared}""",
                    io.ktor.http.ContentType.Application.Json
                )
            }
            
            // Trigger weather/swell fetch for all spots without weather data
            post("/admin/weather/refetch") {
                val spotsToFetch = com.shaka.data.cache.SpotDataCache.getSpotsWithoutWeather()
                val total = spotsToFetch.size
                
                val openMeteo = com.shaka.data.client.OpenMeteoClient()
                val today = java.time.LocalDate.now().toString()
                
                kotlinx.coroutines.GlobalScope.launch {
                    var success = 0
                    var failed = 0
                    for (spotId in spotsToFetch) {
                        try {
                            // Look up coordinates from curated spots or user spots
                            val curatedSpot = SpotDatabase.findSpotById(spotId)
                            val coords = if (curatedSpot != null) {
                                curatedSpot.coordinates
                            } else {
                                val userSpotId = spotId.removePrefix("user-")
                                userSpotRepository.findById(userSpotId)?.coordinates ?: continue
                            }
                            val ocean = openMeteo.getMarineData(coords.lat, coords.lon, today)
                            val weather = openMeteo.getWeather(coords.lat, coords.lon, today)
                            val now = java.time.Instant.now()
                            
                            com.shaka.data.cache.SpotDataCache.updateSwell(
                                spotId,
                                com.shaka.data.cache.SpotDataCache.CachedValue(
                                    value = com.shaka.data.cache.SpotDataCache.SwellInfo(
                                        heightFt = com.shaka.data.cache.SpotDataCache.metersToFeet(ocean.waveHeight),
                                        periodSec = ocean.wavePeriod,
                                        direction = com.shaka.data.cache.SpotDataCache.degreesToCardinal(ocean.waveDirection.toDouble()),
                                        swellHeightFt = com.shaka.data.cache.SpotDataCache.metersToFeet(ocean.waveHeight)
                                    ),
                                    fetchedAt = now
                                )
                            )
                            com.shaka.data.cache.SpotDataCache.updateWind(
                                spotId,
                                com.shaka.data.cache.SpotDataCache.CachedValue(
                                    value = com.shaka.data.cache.SpotDataCache.WindInfo(
                                        speedKnots = com.shaka.data.cache.SpotDataCache.kmhToKnots(weather.windSpeed),
                                        direction = com.shaka.data.cache.SpotDataCache.degreesToCardinal(weather.windDirection.toDouble())
                                    ),
                                    fetchedAt = now
                                )
                            )
                            com.shaka.data.cache.SpotDataCache.saveToDatabase(spotId)
                            success++
                        } catch (e: Exception) {
                            failed++
                        }
                    }
                    org.slf4j.LoggerFactory.getLogger("WeatherRefetch").info("Weather refetch complete: $success success, $failed failed")
                }
                
                call.respondText(
                    """{"status":"started","spotsToFetch":$total,"message":"Weather/swell fetch started in background."}""",
                    io.ktor.http.ContentType.Application.Json
                )
            }
            
            // Get MPA cache stats
            get("/admin/mpa/stats") {
                val withMPA = com.shaka.data.cache.SpotDataCache.getAllSpotIds().count { spotId ->
                    com.shaka.data.cache.SpotDataCache.get(spotId)?.mpa != null
                }
                val withoutMPA = com.shaka.data.cache.SpotDataCache.getSpotsWithoutMPA().size
                val total = com.shaka.data.cache.SpotDataCache.size()
                
                call.respondText(
                    """{"total":$total,"withMPA":$withMPA,"withoutMPA":$withoutMPA}""",
                    io.ktor.http.ContentType.Application.Json
                )
            }
            
            // Trigger MPA fetch for all spots without MPA data
            post("/admin/mpa/refetch") {
                val spotsToFetch = com.shaka.data.cache.SpotDataCache.getSpotsWithoutMPA()
                val total = spotsToFetch.size
                
                val protectedSeasClient = com.shaka.data.client.ProtectedSeasClient()
                
                kotlinx.coroutines.GlobalScope.launch {
                    for (spotId in spotsToFetch) {
                        try {
                            val spot = SpotDatabase.findSpotById(spotId) ?: continue
                            
                            // Step 1: Check EXACT location (is spot INSIDE an MPA?)
                            val exactResult = protectedSeasClient.getMPAStatusExact(
                                spot.coordinates.lat, 
                                spot.coordinates.lon
                            )
                            
                            // Step 2: If not inside, check with buffer (is spot NEARBY an MPA?)
                            val bufferResult = if (exactResult == null) {
                                protectedSeasClient.getMPAStatus(spot.coordinates.lat, spot.coordinates.lon)
                            } else null
                            
                            val isInside = exactResult != null
                            val mpaInfo = exactResult ?: bufferResult
                            
                            val cacheInfo = mpaInfo?.let {
                                com.shaka.data.cache.SpotDataCache.MPACacheInfo(
                                    siteName = it.siteName,
                                    designation = it.designation,
                                    spearfishingStatus = it.spearfishingStatus,
                                    protectionLevel = it.protectionLevel,
                                    speciesOfConcern = it.speciesOfConcern,
                                    purpose = it.purpose,
                                    detailsUrl = it.detailsUrl,
                                    isInsideMPA = isInside
                                )
                            }
                            
                            com.shaka.data.cache.SpotDataCache.updateMPA(
                                spotId,
                                com.shaka.data.cache.SpotDataCache.CachedValue(cacheInfo, java.time.Instant.now())
                            )
                            com.shaka.data.cache.SpotDataCache.saveToDatabase(spotId)
                            
                            // Small delay to be nice to the API
                            kotlinx.coroutines.delay(300)
                        } catch (e: Exception) { /* continue */ }
                    }
                }
                
                call.respondText(
                    """{"status":"started","spotsToFetch":$total,"message":"MPA fetch started in background."}""",
                    io.ktor.http.ContentType.Application.Json
                )
            }
            
            // Test MPA fetch for a single spot (bypasses cache, uses exact-first logic)
            get("/admin/mpa/test/{spotId}") {
                val spotId = call.parameters["spotId"] ?: return@get call.respond(
                    HttpStatusCode.BadRequest, mapOf("error" to "spotId required")
                )
                val spot = SpotDatabase.findSpotById(spotId) ?: return@get call.respond(
                    HttpStatusCode.NotFound, mapOf("error" to "Spot not found")
                )
                
                val protectedSeasClient = com.shaka.data.client.ProtectedSeasClient()
                
                // Step 1: Check EXACT location (is spot INSIDE an MPA?)
                val exactResult = protectedSeasClient.getMPAStatusExact(spot.coordinates.lat, spot.coordinates.lon)
                
                // Step 2: If not inside, check with buffer (is spot NEARBY an MPA?)
                val bufferResult = if (exactResult == null) {
                    protectedSeasClient.getMPAStatus(spot.coordinates.lat, spot.coordinates.lon)
                } else null
                
                val isInside = exactResult != null
                val mpaInfo = exactResult ?: bufferResult
                
                call.respondText(
                    """{"spotId":"$spotId","lat":${spot.coordinates.lat},"lon":${spot.coordinates.lon},"isInsideMPA":$isInside,"mpa":${if (mpaInfo != null) """{"siteName":"${mpaInfo.siteName}","designation":"${mpaInfo.designation}","spearfishingStatus":${mpaInfo.spearfishingStatus},"protectionLevel":${mpaInfo.protectionLevel}}""" else "null"}}""",
                    io.ktor.http.ContentType.Application.Json
                )
            }
            
            // Clear all MPA data and re-fetch everything (use after query changes)
            post("/admin/mpa/refetch-all") {
                val allSpots = com.shaka.data.cache.SpotDataCache.getAllSpotIds()
                val total = allSpots.size
                
                val protectedSeasClient = com.shaka.data.client.ProtectedSeasClient()
                
                kotlinx.coroutines.GlobalScope.launch {
                    var processed = 0
                    for (spotId in allSpots) {
                        try {
                            val spot = SpotDatabase.findSpotById(spotId) ?: continue
                            
                            // Step 1: Check EXACT location (is spot INSIDE an MPA?)
                            val exactResult = protectedSeasClient.getMPAStatusExact(
                                spot.coordinates.lat, 
                                spot.coordinates.lon
                            )
                            
                            // Step 2: If not inside, check with buffer (is spot NEARBY an MPA?)
                            val bufferResult = if (exactResult == null) {
                                protectedSeasClient.getMPAStatus(spot.coordinates.lat, spot.coordinates.lon)
                            } else null
                            
                            val isInside = exactResult != null
                            val mpaInfo = exactResult ?: bufferResult
                            
                            val cacheInfo = mpaInfo?.let {
                                com.shaka.data.cache.SpotDataCache.MPACacheInfo(
                                    siteName = it.siteName,
                                    designation = it.designation,
                                    spearfishingStatus = it.spearfishingStatus,
                                    protectionLevel = it.protectionLevel,
                                    speciesOfConcern = it.speciesOfConcern,
                                    purpose = it.purpose,
                                    detailsUrl = it.detailsUrl,
                                    isInsideMPA = isInside
                                )
                            }
                            
                            com.shaka.data.cache.SpotDataCache.updateMPA(
                                spotId,
                                com.shaka.data.cache.SpotDataCache.CachedValue(cacheInfo, java.time.Instant.now())
                            )
                            com.shaka.data.cache.SpotDataCache.saveToDatabase(spotId)
                            processed++
                            
                            // Log progress every 50 spots
                            if (processed % 50 == 0) {
                                println("MPA refetch progress: $processed / $total (isInside=${if (isInside) "YES" else "no"})")
                            }
                            
                            // Small delay to be nice to the API
                            kotlinx.coroutines.delay(300)
                        } catch (e: Exception) { 
                            println("MPA refetch error for $spotId: ${e.message}")
                        }
                    }
                    println("MPA refetch complete: $processed / $total spots updated")
                }
                
                call.respondText(
                    """{"status":"started","spotsToFetch":$total,"message":"Full MPA refetch started in background."}""",
                    io.ktor.http.ContentType.Application.Json
                )
            }
            
            // ============================================
            // USER SPOTS ENDPOINTS
            // ============================================
            
            /**
             * Create a new user spot.
             * Requires X-Device-ID header.
             * Validates coordinates and enforces 100 spot limit per device.
             */
            post("/user-spots") {
                val deviceId = call.request.header("X-Device-ID")
                    ?: return@post call.respond(
                        HttpStatusCode.BadRequest,
                        mapOf("error" to "X-Device-ID header required")
                    )
                
                val request = try {
                    call.receive<CreateUserSpotRequest>()
                } catch (e: Exception) {
                    return@post call.respond(
                        HttpStatusCode.BadRequest,
                        mapOf("error" to "Invalid request body: ${e.message}")
                    )
                }
                
                // Validate name
                if (request.name.isBlank() || request.name.length > 100) {
                    return@post call.respond(
                        HttpStatusCode.BadRequest,
                        mapOf("error" to "Name must be 1-100 characters")
                    )
                }
                
                // Validate coordinates
                if (request.latitude < -90 || request.latitude > 90) {
                    return@post call.respond(
                        HttpStatusCode.BadRequest,
                        mapOf("error" to "Latitude must be between -90 and 90")
                    )
                }
                if (request.longitude < -180 || request.longitude > 180) {
                    return@post call.respond(
                        HttpStatusCode.BadRequest,
                        mapOf("error" to "Longitude must be between -180 and 180")
                    )
                }
                
                // Land/water check — block spots on land
                val isWater = landWaterClient.isWater(request.latitude, request.longitude)
                if (isWater == false) {
                    return@post call.respond(
                        HttpStatusCode.BadRequest,
                        mapOf("error" to "That location is on land. Move the pin into the water to save a spot.")
                    )
                }
                // If isWater == null the classifier is unavailable — allow creation (log only)
                if (isWater == null) {
                    org.slf4j.LoggerFactory.getLogger("SpotRoutes")
                        .warn("Land/water check unavailable for user spot at (${request.latitude}, ${request.longitude}) — allowing creation")
                }
                
                // Check limit
                val currentCount = userSpotRepository.countByDevice(deviceId)
                if (currentCount >= 100) {
                    return@post call.respond(
                        HttpStatusCode.Conflict,
                        mapOf(
                            "error" to "Maximum 100 spots per device",
                            "currentCount" to currentCount
                        )
                    )
                }
                
                // Infer region/country from coordinates
                val (region, country) = UserSpotRepository.inferRegionAndCountry(
                    request.latitude, request.longitude
                )
                
                // Create the spot
                val created = userSpotRepository.create(
                    deviceId = deviceId,
                    name = request.name,
                    latitude = request.latitude,
                    longitude = request.longitude,
                    region = region,
                    country = country
                )
                
                if (created == null) {
                    return@post call.respond(
                        HttpStatusCode.InternalServerError,
                        mapOf("error" to "Failed to create spot")
                    )
                }
                
                // Trigger background prefetch for the new spot
                val cacheId = userSpotRepository.getCacheId(created.id.toString())
                GlobalScope.launch {
                    try {
                        spotService.prefetchSingleSpot(
                            spotId = cacheId,
                            lat = created.coordinates.lat,
                            lon = created.coordinates.lon
                        )
                    } catch (e: Exception) {
                        // Log but don't fail - prefetch is best-effort
                        println("Background prefetch failed for user spot ${created.id}: ${e.message}")
                    }
                }
                
                val response = UserSpotResponse(
                    id = created.id.toString(),
                    name = created.name,
                    coordinates = created.coordinates,
                    region = created.region,
                    country = created.country,
                    createdAt = created.createdAt.toString(),
                    isUserSpot = true,
                    shakaScore = null  // No cached data yet for new spot
                )
                
                call.respond(HttpStatusCode.Created, response)
            }
            
            /**
             * List all user spots for the device.
             * Requires X-Device-ID header.
             */
            get("/user-spots") {
                val deviceId = call.request.header("X-Device-ID")
                    ?: return@get call.respond(
                        HttpStatusCode.BadRequest,
                        mapOf("error" to "X-Device-ID header required")
                    )
                
                val spots = userSpotRepository.findByDeviceId(deviceId)
                val response = UserSpotListResponse(
                    spots = spots.map { spot ->
                        // Calculate score from cached data (fast, no API calls)
                        val cacheId = userSpotRepository.getCacheId(spot.id.toString())
                        val score = spotService.getUserSpotScore(cacheId)
                        // Get cached condition data for display (same pattern as /spots/all)
                        val cached = SpotDataCache.get(cacheId)
                        
                        UserSpotResponse(
                            id = spot.id.toString(),
                            name = spot.name,
                            coordinates = spot.coordinates,
                            region = spot.region,
                            country = spot.country,
                            createdAt = spot.createdAt.toString(),
                            isUserSpot = true,
                            shakaScore = score,
                            visibility = spotService.resolveVisibilityLabel(cached),
                            swell = cached?.swell?.value?.let { s ->
                                val ht = s.correctedHeightFt ?: s.heightFt
                                "${ht.toInt()}ft @ ${s.periodSec.toInt()}s ${s.direction}"
                            },
                            wind = cached?.wind?.value?.let { 
                                "${it.speedKnots.toInt()} kts ${it.direction}" 
                            },
                            waterTemp = cached?.sst?.value?.let { sst ->
                                "${sst.toInt()}°C / ${((sst * 9/5) + 32).toInt()}°F"
                            }
                        )
                    },
                    count = spots.size,
                    limit = 100
                )
                
                call.respond(response)
            }
            
            /**
             * Search user spots by name.
             * Requires X-Device-ID header.
             */
            get("/user-spots/search") {
                val deviceId = call.request.header("X-Device-ID")
                    ?: return@get call.respond(
                        HttpStatusCode.BadRequest,
                        mapOf("error" to "X-Device-ID header required")
                    )
                
                val query = call.parameters["q"]
                    ?: return@get call.respond(
                        HttpStatusCode.BadRequest,
                        mapOf("error" to "Query parameter 'q' required")
                    )
                
                val limit = call.parameters["limit"]?.toIntOrNull() ?: 20
                
                val spots = userSpotRepository.searchByName(deviceId, query, limit)
                val response = UserSpotListResponse(
                    spots = spots.map { spot ->
                        // Calculate score from cached data (fast, no API calls)
                        val cacheId = userSpotRepository.getCacheId(spot.id.toString())
                        val score = spotService.getUserSpotScore(cacheId)
                        
                        UserSpotResponse(
                            id = spot.id.toString(),
                            name = spot.name,
                            coordinates = spot.coordinates,
                            region = spot.region,
                            country = spot.country,
                            createdAt = spot.createdAt.toString(),
                            isUserSpot = true,
                            shakaScore = score  // null if no cached data
                        )
                    },
                    count = spots.size,
                    limit = limit
                )
                
                call.respond(response)
            }
            
            /**
             * Get user spot detail with full conditions.
             * Requires X-Device-ID header.
             */
            get("/user-spots/{id}") {
                val deviceId = call.request.header("X-Device-ID")
                    ?: return@get call.respond(
                        HttpStatusCode.BadRequest,
                        mapOf("error" to "X-Device-ID header required")
                    )
                
                val spotId = call.parameters["id"]
                    ?: return@get call.respond(
                        HttpStatusCode.BadRequest,
                        mapOf("error" to "Spot ID required")
                    )
                
                val date = call.parameters["date"] ?: java.time.LocalDate.now().toString()
                
                // Find the user spot
                val userSpot = userSpotRepository.findByIdAndDevice(spotId, deviceId)
                    ?: return@get call.respond(
                        HttpStatusCode.NotFound,
                        mapOf("error" to "Spot not found")
                    )
                
                // Get detailed conditions using the service
                val cacheId = userSpotRepository.getCacheId(spotId)
                val spotDetail = spotService.getUserSpotDetail(userSpot, cacheId, date)
                
                if (spotDetail == null) {
                    return@get call.respond(
                        HttpStatusCode.InternalServerError,
                        mapOf("error" to "Failed to fetch spot conditions")
                    )
                }
                
                val response = UserSpotDetailResponse(
                    spot = spotDetail,
                    isUserSpot = true
                )
                
                call.respond(response)
            }
            
            /**
             * Delete a user spot.
             * Requires X-Device-ID header.
             * Also removes the spot from cache.
             */
            delete("/user-spots/{id}") {
                val deviceId = call.request.header("X-Device-ID")
                    ?: return@delete call.respond(
                        HttpStatusCode.BadRequest,
                        mapOf("error" to "X-Device-ID header required")
                    )
                
                val spotId = call.parameters["id"]
                    ?: return@delete call.respond(
                        HttpStatusCode.BadRequest,
                        mapOf("error" to "Spot ID required")
                    )
                
                // Delete from database
                val deleted = userSpotRepository.delete(spotId, deviceId)
                
                if (!deleted) {
                    return@delete call.respond(
                        HttpStatusCode.NotFound,
                        mapOf("error" to "Spot not found or already deleted")
                    )
                }
                
                // Remove from cache
                val cacheId = userSpotRepository.getCacheId(spotId)
                SpotDataCache.remove(cacheId)
                
                call.respond(mapOf("status" to "ok", "deleted" to spotId))
            }
            
            // ============================================
            // FISHING INTEL ENDPOINTS (ISOLATED)
            // ============================================
            
            /**
             * Get fishing intel for a spot.
             * Returns highlights, species summary, and bait status.
             */
            get("/spots/{spotId}/intel") {
                val spotId = call.parameters["spotId"]
                    ?: return@get call.respond(HttpStatusCode.BadRequest, mapOf("error" to "spotId required"))
                val since = call.parameters["since"] ?: "72h"
                val tzOffset = call.parameters["tzOffset"]?.toIntOrNull()
                
                val intel = FishingIntelRoutes.getSpotIntel(spotId, since, tzOffset)
                if (intel != null) {
                    call.respond(intel)
                } else {
                    call.respond(HttpStatusCode.NotFound, mapOf(
                        "error" to "No fishing intel available for this spot",
                        "spotId" to spotId
                    ))
                }
            }
            
            /**
             * Get raw evidence cards for a spot (optionally filtered by species).
             */
            get("/spots/{spotId}/intel/evidence") {
                val spotId = call.parameters["spotId"]
                    ?: return@get call.respond(HttpStatusCode.BadRequest, mapOf("error" to "spotId required"))
                val species = call.parameters["species"]
                
                val evidence = FishingIntelRoutes.getSpotEvidence(spotId, species)
                call.respond(evidence)
            }
            
            /**
             * Get fishing intel for a region (by sources.regional_report). No geo.
             * e.g. GET /regions/socal/intel?since=72h&tzOffset=-8
             */
            get("/regions/{regionId}/intel") {
                val regionId = call.parameters["regionId"]
                    ?: return@get call.respond(HttpStatusCode.BadRequest, mapOf("error" to "regionId required"))
                val since = call.parameters["since"] ?: "72h"
                val tzOffset = call.parameters["tzOffset"]?.toIntOrNull()

                val intel = FishingIntelRoutes.getIntelForRegion(regionId, since, tzOffset)
                if (intel != null) {
                    call.respond(intel)
                } else {
                    call.respond(HttpStatusCode.NotFound, mapOf(
                        "error" to "No fishing intel available for this region",
                        "regionId" to regionId
                    ))
                }
            }

            /**
             * Get trending species for SoCal (based on report frequency).
             */
            get("/regions/socal/trending") {
                val hours = call.parameters["hours"]?.toIntOrNull() ?: 72
                val trending = FishingIntelRoutes.getTrending(hours)
                call.respond(trending)
            }
            
            /**
             * Fishing intel health check (admin endpoint).
             */
            get("/admin/fishing-intel/health") {
                val health = FishingIntelRoutes.getHealth()
                call.respond(health)
            }
            
            /**
             * Toggle source enabled/disabled (admin endpoint).
             */
            post("/admin/fishing-intel/sources/{sourceId}/toggle") {
                val sourceId = call.parameters["sourceId"]
                    ?: return@post call.respond(HttpStatusCode.BadRequest, mapOf("error" to "sourceId required"))
                val enabled = call.parameters["enabled"]?.toBoolean() ?: true
                
                val result = FishingIntelRoutes.toggleSource(sourceId, enabled)
                call.respond(result)
            }
            
            /**
             * Explore BD Outdoors forums for data analysis (admin endpoint).
             * Returns raw forum data for schema design.
             * 
             * Can use either:
             * - cookies parameter (full cookie string from browser)
             * - Individual cookie params: bdo_user, bdo_session, bdo_csrf, cf_clearance
             * - username/password (may fail due to Cloudflare)
             */
            get("/admin/fishing-intel/explore-bdoutdoors") {
                // Try cookies first (most reliable)
                val cookies = call.parameters["cookies"]
                val bdoUser = call.parameters["bdo_user"] ?: System.getenv("BDO_USER")
                val bdoSession = call.parameters["bdo_session"] ?: System.getenv("BDO_SESSION")
                val bdoCsrf = call.parameters["bdo_csrf"] ?: System.getenv("BDO_CSRF")
                val cfClearance = call.parameters["cf_clearance"] ?: System.getenv("CF_CLEARANCE")
                
                val result = if (cookies != null) {
                    com.shaka.fishing_intel.jobs.FishingIntelPrefetchJob.exploreBDOutdoorsWithCookies(cookies)
                } else if (bdoUser != null && bdoSession != null && bdoCsrf != null) {
                    com.shaka.fishing_intel.jobs.FishingIntelPrefetchJob.exploreBDOutdoorsWithCookies(
                        "bdo_user=$bdoUser; bdo_session=$bdoSession; bdo_csrf=$bdoCsrf" +
                        (if (cfClearance != null) "; cf_clearance=$cfClearance" else "")
                    )
                } else {
                    // Fall back to login attempt
                    val username = call.parameters["username"] ?: System.getenv("BD_USERNAME")
                    val password = call.parameters["password"] ?: System.getenv("BD_PASSWORD")
                    
                    if (username != null && password != null) {
                        com.shaka.fishing_intel.jobs.FishingIntelPrefetchJob.exploreBDOutdoors(username, password)
                    } else {
                        "Error: Provide either 'cookies' param, individual cookie params (bdo_user, bdo_session, bdo_csrf), or username/password"
                    }
                }
                
                call.respondText(result, ContentType.Text.Plain)
            }
            
            /**
             * Ingest fishing intel from local BD Outdoors scraper.
             * Accepts JSON array of forum posts with extracted fishing data.
             * 
             * POST /v1/intel/ingest
             * Body: [{"threadUrl": "...", "title": "...", ...}]
             */
            post("/intel/ingest") {
                val errors = mutableListOf<String>()
                var saved = 0
                var skipped = 0
                val clearSource = call.request.queryParameters["clearSource"]
                if (clearSource == "bd-outdoors") {
                    val deleted = FishingIntelDb.deleteReportsBySource("bd-outdoors")
                    org.slf4j.LoggerFactory.getLogger("SpotRoutes").info("Cleared bd-outdoors before ingest: deleted $deleted reports")
                }
                try {
                    val posts = call.receive<List<IngestPostRequest>>()
                    fun norm(u: String) = u.split("#").first().trimEnd('/').take(512)
                    val byThread = posts.groupBy { norm(it.threadUrl) }
                    val threadTldr = mutableMapOf<String, Pair<String?, Boolean?>>()
                    val threadSpecies = mutableMapOf<String, List<String>>()
                    for ((threadUrl, threadPosts) in byThread) {
                        val title = threadPosts.firstOrNull { it.postRole == "thread_starter" }?.title ?: threadPosts.first().title
                        val combinedContent = threadPosts.sortedBy { it.date }.map { it.content }.joinToString("\n\n").take(4000)
                        if (FishingIntelAiService.isEnabled()) {
                            val result = FishingIntelAiService.analyzeThread(title, combinedContent)
                            if (result != null) {
                                threadTldr[threadUrl] = result.second to result.third
                                threadSpecies[threadUrl] = result.first
                            } else {
                                val fallbackSpecies = threadPosts.flatMap { it.speciesCaught }.distinct()
                                val summary = "Caught ${fallbackSpecies.joinToString(", ").ifBlank { "fish" }}. ${combinedContent.take(120).trim()}".replace(Regex("\\s+"), " ").trim().take(300)
                                threadTldr[threadUrl] = summary to null
                                threadSpecies[threadUrl] = fallbackSpecies
                            }
                        } else {
                            val fallbackSpecies = threadPosts.flatMap { it.speciesCaught }.distinct()
                            val summary = "Caught ${fallbackSpecies.joinToString(", ").ifBlank { "fish" }}. ${combinedContent.take(120).trim()}".replace(Regex("\\s+"), " ").trim().take(300)
                            threadTldr[threadUrl] = summary to null
                            threadSpecies[threadUrl] = fallbackSpecies
                        }
                    }
                    for ((index, post) in posts.withIndex()) {
                        try {
                            // Parse date: accept ISO-8601 with offset (e.g. -0800). Never use now().
                            val publishedDate = try {
                                java.time.OffsetDateTime.parse(post.date).toInstant()
                            } catch (e: Exception) {
                                // OffsetDateTime may reject -0800 (no colon); try with colon in offset
                                try {
                                    val normalized = post.date.replace(Regex("([+-])(\\d{2})(\\d{2})$"), "$1$2:$3")
                                    java.time.OffsetDateTime.parse(normalized).toInstant()
                                } catch (e2: Exception) {
                                    errors.add("Post $index (${post.title.take(30)}): invalid date format")
                                    skipped++
                                    continue
                                }
                            }
                            val localDate = java.time.LocalDateTime.ofInstant(
                                publishedDate, java.time.ZoneOffset.UTC
                            ).toLocalDate()
                            
                            // Fingerprint: reply = thread+post; else narrative (thread, title, date)
                            val fingerprint = if (post.postRole == "reply" && !post.postUrl.isNullOrBlank()) {
                                Deduplicator.buildReplyFingerprint(post.threadUrl, post.postUrl)
                            } else {
                                Deduplicator.buildNarrativeFingerprint(post.threadUrl, post.title, localDate)
                            }
                            
                            if (FishingIntelDb.fingerprintExists(fingerprint)) {
                                skipped++
                                continue
                            }
                            
                            val lastActivityInstant = post.lastActivityAt?.let { s ->
                                try {
                                    java.time.OffsetDateTime.parse(s).toInstant()
                                } catch (e: Exception) {
                                    try {
                                        val norm = s.replace(Regex("([+-])(\\d{2})(\\d{2})$"), "$1$2:$3")
                                        java.time.OffsetDateTime.parse(norm).toInstant()
                                    } catch (e2: Exception) {
                                        null
                                    }
                                }
                            } ?: publishedDate
                            val reportUrl = post.postUrl?.take(512) ?: post.threadUrl
                            val threadUrl = norm(post.threadUrl)
                            val (parsedZone, cleanedTitle) = parseBdTitleForLocationTag(post.title)
                            val effectiveThreadZone = post.threadZone?.takeIf { it.isNotBlank() } ?: parsedZone
                            val effectiveTitle = cleanedTitle?.takeIf { it.isNotBlank() } ?: post.title
                            val isThreadStarter = post.postRole == "thread_starter"
                            val reportTldr = if (isThreadStarter) threadTldr[threadUrl]?.first else null
                            val reportIsCatchIntel = if (isThreadStarter) threadTldr[threadUrl]?.second else null
                            val speciesForCatch = if (isThreadStarter) (threadSpecies[threadUrl] ?: emptyList()) else post.speciesCaught
                            val report = FishingReport(
                                sourceId = "bd-outdoors",
                                url = reportUrl,
                                publishedAt = publishedDate,
                                observedAt = java.time.Instant.now(),
                                reportType = ReportType.NARRATIVE,
                                title = effectiveTitle.take(255),
                                rawExcerpt = post.content.take(500),
                                fingerprint = fingerprint,
                                confidence = 0.8,
                                threadZone = effectiveThreadZone,
                                contentType = post.contentType,
                                lastActivityAt = lastActivityInstant,
                                threadUrl = threadUrl,
                                tldr = reportTldr,
                                isCatchIntel = reportIsCatchIntel
                            )
                            
                            val reportId = FishingIntelDb.saveReport(report)
                            
                            // CATCH only from speciesCaught (or AI species_caught when AI ran)
                            for (species in speciesForCatch) {
                                val normalizedSpecies = SpeciesNormalizer.normalize(species)
                                val claim = FishingClaim(
                                    claimType = ClaimType.CATCH,
                                    species = normalizedSpecies,
                                    countKept = 1,
                                    landingName = post.locationMentioned ?: "BD Outdoors Forum"
                                )
                                FishingIntelDb.saveClaim(reportId, claim)
                            }
                            
                            val geo = GeoResolver.resolve("bd-outdoors", effectiveThreadZone, post.locationMentioned)
                                ?: ResolvedGeo(32.7157, -117.1611, 150_000, GeoType.REGION_FALLBACK)
                            FishingIntelDb.saveReportGeo(
                                reportId = reportId,
                                lat = geo.lat,
                                lon = geo.lon,
                                geoType = geo.geoType,
                                radiusM = geo.radiusM
                            )
                            
                            saved++
                        } catch (e: Exception) {
                            errors.add("Post $index (${post.title.take(30)}): ${e.message}")
                        }
                    }
                    
                    call.respond(IngestResponse(
                        status = if (errors.isEmpty()) "ok" else "partial",
                        saved = saved,
                        skipped = skipped,
                        errors = errors.take(10)
                    ))
                } catch (e: Exception) {
                    call.respond(
                        HttpStatusCode.BadRequest,
                        IngestResponse(
                            status = "error",
                            saved = 0,
                            skipped = 0,
                            errors = listOf(e.message ?: "Unknown error")
                        )
                    )
                }
            }
            
        }
    }
}
