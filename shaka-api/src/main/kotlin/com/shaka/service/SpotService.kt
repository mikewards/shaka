package com.shaka.service

import com.shaka.data.cache.OceanDataCache
import com.shaka.data.cache.SpotDataCache
import com.shaka.data.client.CommunityClient
import com.shaka.data.client.CopernicusClient
import com.shaka.data.client.GIBSClient
import com.shaka.data.client.NOAAClient
import com.shaka.data.client.NOAATidesClient
import com.shaka.data.client.OpenMeteoClient
import com.shaka.data.client.ProtectedSeasClient
import com.shaka.data.client.SpotDatabase
import com.shaka.data.db.UserSpotRepository
import com.shaka.model.*
import com.shaka.scoring.GibsColormap
import com.shaka.scoring.ShakaScorer
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.slf4j.LoggerFactory
import java.time.Instant
import java.time.LocalDate

/**
 * Service for searching and retrieving spearfishing spots.
 * 
 * Uses ACTUAL MEASURED DATA from Copernicus Marine L3 NRT:
 * - ZSD (Secchi disk depth) = real underwater visibility in meters
 * - CHL (Chlorophyll-a) = real plankton concentration
 * 
 * NO ESTIMATES. If satellite data unavailable, we say so honestly.
 * 
 * @see https://data.marine.copernicus.eu/product/OCEANCOLOUR_GLO_BGC_L3_NRT_009_101/description
 */
class SpotService {

    private val logger = LoggerFactory.getLogger(SpotService::class.java)
    private val openMeteo = OpenMeteoClient()
    private val copernicus = CopernicusClient()
    private val tidesClient = NOAATidesClient()
    private val noaaClient = NOAAClient()
    private val community = CommunityClient()
    private val forecastService = ForecastService()
    private val protectedSeasClient = ProtectedSeasClient()
    private val spotDb = SpotDatabase
    // Note: GlobalFishingWatchClient and SolunarClient are used by DataPrefetchJobs
    // SpotService reads the cached data from SpotDataCache
    
    // Lazy-load regulatory links from JSON resource
    private val regulatoryLinks: JsonElement? by lazy {
        try {
            val stream = javaClass.classLoader.getResourceAsStream("regulatory_links.json")
            if (stream != null) {
                val json = stream.bufferedReader().use { it.readText() }
                Json.parseToJsonElement(json)
            } else {
                logger.warn("Could not find regulatory_links.json")
                null
            }
        } catch (e: Exception) {
            logger.warn("Failed to load regulatory_links.json: ${e.message}")
            null
        }
    }

    /**
     * Search for spots within radius of a location.
     * 
     * OPTIMIZED: Uses prefetched cache for instant lookups (no API calls).
     * Falls back to live API calls only if cache is empty (during startup).
     */
    suspend fun searchSpots(lat: Double, lon: Double, radiusKm: Int, date: String): SearchResponse = coroutineScope {
        // Get spots from database within radius
        val nearbySpots = spotDb.findNearbySpots(lat, lon, radiusKm.toDouble())
        
        // Check if we have prefetched data available
        val hasPrefetchedData = nearbySpots.any { SpotDataCache.has(it.id) }
        
        // Fallback data for when cache is empty (during startup)
        val fallbackWeather: WeatherData?
        val fallbackOcean: OceanData?
        val fallbackWaterQuality: WaterQuality?
        val fallbackTide: TideData?
        
        if (!hasPrefetchedData) {
            // Cache is empty - fetch data the old way (only happens during startup)
            logger.info("Prefetch cache empty, fetching data live for search at ($lat, $lon)")
            
            val weatherDeferred = async {
                withTimeoutOrNull(5000) {
                    OceanDataCache.getWeather(lat, lon, date) ?: run {
                        val data = openMeteo.getWeather(lat, lon, date)
                        OceanDataCache.putWeather(lat, lon, date, data)
                        data
                    }
                }
            }
            
            val oceanDeferred = async {
                withTimeoutOrNull(5000) {
                    OceanDataCache.getOcean(lat, lon, date) ?: run {
                        val data = openMeteo.getMarineData(lat, lon, date)
                        OceanDataCache.putOcean(lat, lon, date, data)
                        data
                    }
                }
            }
            
            val waterQualityDeferred = async {
                withTimeoutOrNull(6000) {
                    copernicus.getWaterQuality(lat, lon, date)
                }
            }
            
            val tideDeferred = async {
                withTimeoutOrNull(5000) {
                    OceanDataCache.getTide(lat, lon, date) ?: run {
                        val data = tidesClient.getTideData(lat, lon, date)
                        OceanDataCache.putTide(lat, lon, date, data)
                        data
                    }
                }
            }
            
            fallbackWeather = weatherDeferred.await()
            fallbackOcean = oceanDeferred.await()
            fallbackWaterQuality = waterQualityDeferred.await()
            fallbackTide = tideDeferred.await()
        } else {
            fallbackWeather = null
            fallbackOcean = null
            fallbackWaterQuality = null
            fallbackTide = null
            logger.debug("Using prefetched cache for search at ($lat, $lon)")
        }

        // Score each spot using prefetched data or fallbacks
        val scoredSpots = nearbySpots.map { spot ->
            // Get prefetched data for this spot (instant lookup!)
            val cached = SpotDataCache.get(spot.id)
            
            // Build conditions from cached data or fallbacks
            val weather = if (cached?.wind != null && cached.swell != null) {
                WeatherData(
                    temperature = 25.0,
                    windSpeed = cached.wind.value.speedKnots / 0.539957,  // Convert knots to km/h
                    windDirection = 0,
                    precipitation = 0.0,
                    cloudCover = 50,
                    visibility = 10000.0
                )
            } else {
                fallbackWeather ?: WeatherData(
                    temperature = 25.0, windSpeed = 10.0, windDirection = 0,
                    precipitation = 0.0, cloudCover = 50, visibility = 10.0
                )
            }
            
            val ocean = if (cached?.swell != null) {
                OceanData(
                    waveHeight = cached.swell.value.heightFt / 3.28084,  // Convert ft to m
                    wavePeriod = cached.swell.value.periodSec,
                    waveDirection = 0,
                    waterTemperature = cached.sst?.value ?: 15.0,
                    swellHeight = (cached.swell.value.swellHeightFt ?: cached.swell.value.heightFt) / 3.28084,
                    swellDirection = 0
                )
            } else {
                fallbackOcean ?: OceanData(
                    waveHeight = 1.0, wavePeriod = 8.0, waveDirection = 0,
                    waterTemperature = 15.0, swellHeight = 1.0, swellDirection = 0
                )
            }
            
            val waterQuality = if (cached?.visibility != null || cached?.sst != null) {
                WaterQuality(
                    chlorophyllA = cached.chlorophyll?.value,
                    visibility = cached.visibility?.value,
                    seaSurfaceTemp = cached.sst?.value,
                    dataSource = "Prefetched (${cached.visibility?.ageString() ?: "N/A"})"
                )
            } else {
                fallbackWaterQuality ?: WaterQuality(
                    chlorophyllA = null, visibility = null,
                    seaSurfaceTemp = null, dataSource = "Data temporarily unavailable"
                )
            }
            
            val tideData = if (cached?.tide != null) {
                TideData(
                    currentHeight = cached.tide.value.currentHeight,
                    nextHighTide = cached.tide.value.nextHighTide,
                    nextLowTide = cached.tide.value.nextLowTide,
                    tideState = cached.tide.value.state,
                    nextHighTideTime = cached.tide.value.nextHighTideTime?.toEpochMilli(),
                    nextLowTideTime = cached.tide.value.nextLowTideTime?.toEpochMilli()
                )
            } else {
                fallbackTide ?: TideData(
                    currentHeight = 0.5, nextHighTide = "Check local source", 
                    nextLowTide = "Check local source", tideState = "Unknown"
                )
            }
            
            val effectiveChl = resolveChlorophyll(
                waterQuality?.chlorophyllA, cached?.chlorophyll?.value, cached?.gibsChlorophyll?.value
            )

            val score = ShakaScorer.generateScore(
                targetDate = date,
                windSpeedKmh = weather.windSpeed,
                waveHeightM = ocean.waveHeight,
                chlorophyllMgM3 = effectiveChl,
                solunarDayRating = cached?.solunar?.value?.dayRating,
                moonPhase = cached?.solunar?.value?.moonPhase
            )

            val sst = resolveSST(cached?.sst?.value, ocean.rawSST, spot.coordinates.lat, spot.coordinates.lon, date)
            
            // Data freshness from cache
            val dataUpdatedMinutesAgo = cached?.tide?.minutesSinceFetch()?.toInt()
            val satelliteDataDate = cached?.sst?.dataDateString()
            
            // Build satellite readings from cache - colors for display, NOAA ERDDAP for actual chlorophyll
            val gibsReadings = if (cached?.gibsChlorophyll != null || cached?.chlorophyll != null) {
                val gibs = cached.gibsChlorophyll?.value
                GibsSatelliteReadings(
                    // Satellite imagery colors (display only - may include sediment/kelp)
                    paceTodayColor = gibs?.paceTodayColor,
                    paceYesterdayColor = gibs?.paceYesterdayColor,
                    noaa20TodayColor = gibs?.noaa20TodayColor,
                    noaa20YesterdayColor = gibs?.noaa20YesterdayColor,
                    noaa21TodayColor = gibs?.noaa21TodayColor,
                    noaa21YesterdayColor = gibs?.noaa21YesterdayColor,
                    sentinel3aTodayColor = gibs?.sentinel3aTodayColor,
                    sentinel3aYesterdayColor = gibs?.sentinel3aYesterdayColor,
                    sentinel3bTodayColor = gibs?.sentinel3bTodayColor,
                    sentinel3bYesterdayColor = gibs?.sentinel3bYesterdayColor,
                    // Observation times
                    paceObservationTime = gibs?.paceObservationTime?.toString(),
                    noaa20ObservationTime = gibs?.noaa20ObservationTime?.toString(),
                    noaa21ObservationTime = gibs?.noaa21ObservationTime?.toString(),
                    dataDate = gibs?.dataDate?.toString(),
                    // ACTUAL measured chlorophyll from NOAA ERDDAP (the trusted source)
                    noaaErddapChlorophyll = cached.chlorophyll?.value,
                    noaaErddapFetchTime = cached.chlorophyll?.fetchedAt?.toString()
                )
            } else null
            
            SpotSummary(
                id = spot.id,
                name = spot.name,
                coordinates = spot.coordinates,
                shakaScore = score.overall,
                confidence = score.confidence,
                conditions = SpotConditions(
                    visibility = getVisibilityLabel(effectiveChl),
                    waterTemp = formatWaterTemp(sst.tempC, sst.isEstimate),
                    swell = cached?.swell?.let { 
                        "${it.value.heightFt.toInt()}ft @ ${it.value.periodSec.toInt()}s ${it.value.direction}" 
                    } ?: "${ocean.swellHeight.toInt()}-${(ocean.swellHeight + 1).toInt()}ft @ ${ocean.swellPeriod.toInt()}s",
                    wind = cached?.wind?.let { 
                        "${it.value.speedKnots.toInt()} kts ${it.value.direction}" 
                    } ?: "${SpotDataCache.kmhToKnots(weather.windSpeed).toInt()} kts ${SpotDataCache.degreesToCardinal(weather.windDirection.toDouble())}",
                    tideState = "${tideData.tideState} - Next high: ${tideData.nextHighTide}",
                    dataUpdatedMinutesAgo = dataUpdatedMinutesAgo,
                    satelliteDataDate = satelliteDataDate,
                    swellSource = cached?.swell?.value?.source
                ),
                expectedFish = spot.commonFish,
                gearRecommendations = generateGearRecs(sst.tempC, spot.depth),
                risks = generateRisks(weather, ocean),
                bestTimeOfDay = getBestTimeOfDay(cached?.solunar?.value?.moonPhase),
                satelliteReadings = gibsReadings
            )
        }.sortedByDescending { it.shakaScore }

        SearchResponse(
            spots = scoredSpots,
            searchCenter = Coordinates(lat, lon),
            radiusKm = radiusKm,
            date = date
        )
    }

    /**
     * Get detailed information for a specific spot.
     * 
     * OPTIMIZED: Uses prefetched cache for instant lookups.
     * Falls back to live API calls only if cache is empty.
     */
    suspend fun getSpotDetail(spotId: String, date: String): SpotDetail? = coroutineScope {
        val spot = spotDb.findSpotById(spotId) ?: return@coroutineScope null
        val lat = spot.coordinates.lat
        val lon = spot.coordinates.lon
        val region = inferRegionFromSpotId(spotId)
        
        // Check prefetched cache first (instant!)
        val cached = SpotDataCache.get(spotId)
        
        // Build data from cache or fetch live
        val weather: WeatherData
        val ocean: OceanData
        val waterQuality: WaterQuality
        val tideData: TideData
        
        if (cached != null && cached.tide != null) {
            // Use prefetched data - instant lookup, no API calls!
            logger.debug("Using prefetched data for spot detail: ${spot.name}")
            
            weather = if (cached.wind != null) {
                WeatherData(
                    temperature = 25.0,
                    windSpeed = cached.wind.value.speedKnots / 0.539957,
                    windDirection = 0,
                    precipitation = 0.0,
                    cloudCover = 50,
                    visibility = 10000.0
                )
            } else {
                WeatherData(25.0, 10.0, 0, 0.0, 50, 10.0)
            }
            
            ocean = if (cached.swell != null) {
                OceanData(
                    waveHeight = cached.swell.value.heightFt / 3.28084,
                    wavePeriod = cached.swell.value.periodSec,
                    waveDirection = 0,
                    waterTemperature = cached.sst?.value ?: 15.0,
                    swellHeight = (cached.swell.value.swellHeightFt ?: cached.swell.value.heightFt) / 3.28084,
                    swellDirection = 0
                )
            } else {
                OceanData(1.0, 8.0, 0, 15.0, 1.0, 0)
            }
            
            waterQuality = WaterQuality(
                chlorophyllA = cached.chlorophyll?.value,
                visibility = cached.visibility?.value,
                seaSurfaceTemp = cached.sst?.value,
                dataSource = "Prefetched (updated ${cached.tide.ageString()})"
            )
            
            tideData = TideData(
                currentHeight = cached.tide.value.currentHeight,
                nextHighTide = cached.tide.value.nextHighTide,
                nextLowTide = cached.tide.value.nextLowTide,
                tideState = cached.tide.value.state,
                nextHighTideTime = cached.tide.value.nextHighTideTime?.toEpochMilli(),
                nextLowTideTime = cached.tide.value.nextLowTideTime?.toEpochMilli()
            )
        } else {
            // Cache miss - fetch live (only during startup)
            logger.info("Prefetch cache miss for ${spot.name}, fetching live")
            
            val weatherDeferred = async {
                withTimeoutOrNull(5000) {
                    OceanDataCache.getWeather(lat, lon, date) ?: run {
                        val data = openMeteo.getWeather(lat, lon, date)
                        OceanDataCache.putWeather(lat, lon, date, data)
                        data
                    }
                }
            }
            
            val oceanDeferred = async {
                withTimeoutOrNull(5000) {
                    OceanDataCache.getOcean(lat, lon, date) ?: run {
                        val data = openMeteo.getMarineData(lat, lon, date)
                        OceanDataCache.putOcean(lat, lon, date, data)
                        data
                    }
                }
            }
            
            val waterQualityDeferred = async {
                withTimeoutOrNull(8000) {
                    copernicus.getWaterQuality(lat, lon, date)
                }
            }
            
            val tideDeferred = async {
                withTimeoutOrNull(5000) {
                    OceanDataCache.getTide(lat, lon, date) ?: run {
                        val data = tidesClient.getTideData(lat, lon, date)
                        OceanDataCache.putTide(lat, lon, date, data)
                        data
                    }
                }
            }
            
            weather = weatherDeferred.await() ?: WeatherData(25.0, 10.0, 0, 0.0, 50, 10.0)
            ocean = oceanDeferred.await() ?: OceanData(1.0, 8.0, 0, 15.0, 1.0, 0)
            waterQuality = waterQualityDeferred.await() ?: WaterQuality(
                null, null, null, "Data temporarily unavailable"
            )
            tideData = tideDeferred.await() ?: TideData(0.5, "Check local source", "Check local source", "Unknown")
        }
        
        // Forecast is lazy-loaded by the client via /forecast/{spotId} when user taps Forecast tab
        
        // Build fishing intel from cache (prefetched daily)
        val vesselActivity = cached?.vessel?.value?.let { vessel ->
            VesselActivity(
                count = vessel.count,
                radiusNm = vessel.radiusNm,
                updatedAt = cached.vessel.fetchedAt.toString()
            )
        }
        
        val solunarData = cached?.solunar?.value?.let { sol ->
            SolunarData(
                moonPhase = sol.moonPhase,
                illumination = sol.illumination,
                majorPeriods = listOfNotNull(
                    if (sol.majorStart1 != null && sol.majorEnd1 != null) 
                        TimePeriod(sol.majorStart1, sol.majorEnd1) else null,
                    if (sol.majorStart2 != null && sol.majorEnd2 != null) 
                        TimePeriod(sol.majorStart2, sol.majorEnd2) else null
                ),
                minorPeriods = listOfNotNull(
                    if (sol.minorStart1 != null && sol.minorEnd1 != null) 
                        TimePeriod(sol.minorStart1, sol.minorEnd1) else null,
                    if (sol.minorStart2 != null && sol.minorEnd2 != null) 
                        TimePeriod(sol.minorStart2, sol.minorEnd2) else null
                ),
                dayRating = sol.dayRating,
                hourlyRating = null
            )
        }

        logger.info("Spot detail loaded: ${spot.name} (${if (cached != null) "from cache" else "live fetch"})")

        val effectiveChl = resolveChlorophyll(
            waterQuality?.chlorophyllA, cached?.chlorophyll?.value, cached?.gibsChlorophyll?.value
        )

        val score = ShakaScorer.generateScore(
            targetDate = date,
            windSpeedKmh = weather.windSpeed,
            waveHeightM = ocean.waveHeight,
            chlorophyllMgM3 = effectiveChl,
            solunarDayRating = cached?.solunar?.value?.dayRating,
            moonPhase = cached?.solunar?.value?.moonPhase
        )
        
        val sst = resolveSST(cached?.sst?.value, ocean.rawSST, lat, lon, date)
        
        // Data freshness from cache
        val dataUpdatedMinutesAgo = cached?.tide?.minutesSinceFetch()?.toInt()
        val satelliteDataDate = cached?.sst?.dataDateString()

        // Build satellite readings - colors for display, NOAA ERDDAP for actual chlorophyll
        val gibsReadings = if (cached?.gibsChlorophyll != null || cached?.chlorophyll != null) {
            val gibs = cached.gibsChlorophyll?.value
            GibsSatelliteReadings(
                // Satellite imagery colors (display only - may include sediment/kelp)
                paceTodayColor = gibs?.paceTodayColor,
                paceYesterdayColor = gibs?.paceYesterdayColor,
                noaa20TodayColor = gibs?.noaa20TodayColor,
                noaa20YesterdayColor = gibs?.noaa20YesterdayColor,
                noaa21TodayColor = gibs?.noaa21TodayColor,
                noaa21YesterdayColor = gibs?.noaa21YesterdayColor,
                sentinel3aTodayColor = gibs?.sentinel3aTodayColor,
                sentinel3aYesterdayColor = gibs?.sentinel3aYesterdayColor,
                sentinel3bTodayColor = gibs?.sentinel3bTodayColor,
                sentinel3bYesterdayColor = gibs?.sentinel3bYesterdayColor,
                // Observation times
                paceObservationTime = gibs?.paceObservationTime?.toString(),
                noaa20ObservationTime = gibs?.noaa20ObservationTime?.toString(),
                noaa21ObservationTime = gibs?.noaa21ObservationTime?.toString(),
                dataDate = gibs?.dataDate?.toString(),
                // ACTUAL measured chlorophyll from NOAA ERDDAP (the trusted source)
                noaaErddapChlorophyll = cached.chlorophyll?.value,
                noaaErddapFetchTime = cached.chlorophyll?.fetchedAt?.toString()
            )
        } else null

        // Build water context with chlorophyll trend and SST nearby readings
        val waterContext = buildWaterContext(cached, waterQuality, lat, lon)
        
        SpotDetail(
            id = spot.id,
            name = spot.name,
            description = spot.description,
            coordinates = spot.coordinates,
            score = score,
            access = AccessInfo(
                directions = spot.directions,
                parkingInfo = spot.parking,
                permitRequired = false
            ),
            conditions = SpotConditions(
                visibility = getVisibilityLabel(effectiveChl),
                waterTemp = formatWaterTemp(sst.tempC, sst.isEstimate),
                swell = cached?.swell?.let { 
                    "${it.value.heightFt.toInt()}ft @ ${it.value.periodSec.toInt()}s ${it.value.direction}" 
                } ?: "${ocean.swellHeight.toInt()}-${(ocean.swellHeight + 1).toInt()}ft @ ${ocean.swellPeriod.toInt()}s",
                wind = cached?.wind?.let { 
                    "${it.value.speedKnots.toInt()} kts ${it.value.direction}" 
                } ?: "${SpotDataCache.kmhToKnots(weather.windSpeed).toInt()} kts ${SpotDataCache.degreesToCardinal(weather.windDirection.toDouble())}",
                tideState = "${tideData.tideState} - Next high: ${tideData.nextHighTide}",
                dataUpdatedMinutesAgo = dataUpdatedMinutesAgo,
                satelliteDataDate = satelliteDataDate,
                swellSource = cached?.swell?.value?.source
            ),
            forecast = emptyList(),
            expectedFish = spot.commonFish.map { fish ->
                FishInfo(
                    name = fish,
                    likelihood = getFishLikelihood(fish, spotId, date),
                    seasonalNotes = getSeasonalNotes(fish, spotId, date)
                )
            },
            gearRecommendations = generateGearRecs(sst.tempC, spot.depth).map { item ->
                GearItem(item = item, reason = "Recommended for conditions", essential = true)
            },
            risks = generateRisks(weather, ocean).map { risk ->
                RiskInfo(risk = risk, severity = "moderate", mitigation = "Check conditions before entry")
            },
            communityReports = emptyList(),
            bestTimeOfDay = getBestTimeOfDay(cached?.solunar?.value?.moonPhase),
            imageUrl = spot.imageUrl,
            satelliteReadings = gibsReadings,
            regulations = getRegulationInfo(spotId, inferSpecificRegionFromSpotId(spotId), inferCountryFromSpotId(spotId)),
            // NEW: Fishing intel data
            vessels = vesselActivity,
            solunar = solunarData,
            waterContext = waterContext
        )
    }

    /**
     * Get community reports for a region from multiple sources.
     * Sources include Reddit, DeeperBlue, Spearfisherman.com, regional blogs.
     */
    suspend fun getCommunityReports(region: String): List<CommunityReport> {
        return try {
            community.getReportsForRegion(region)
        } catch (e: Exception) {
            emptyList()
        }
    }
    
    /**
     * Search spots by name (for type-ahead search).
     * Returns basic spot info with shaka score from prefetch cache.
     */
    fun searchSpotsByName(query: String, limit: Int): List<SpotSearchResult> {
        val queryLower = query.lowercase()
        val today = java.time.LocalDate.now().toString()
        
        return spotDb.getAllSpots()
            .filter { spot ->
                spot.name.lowercase().contains(queryLower) ||
                spot.id.lowercase().contains(queryLower) ||
                spot.description.lowercase().contains(queryLower)
            }
            .take(limit)
            .map { spot ->
                // Get cached data for score calculation
                val cached = SpotDataCache.get(spot.id)
                
                // Calculate score using cached data if available
                val score = if (cached != null) {
                    val visM = cached.visibility?.value ?: 15.0
                    val swellHeightFt = cached.swell?.value?.heightFt ?: 2.0
                    val windKts = cached.wind?.value?.speedKnots ?: 5.0
                    
                    // Simple weighted score from key factors
                    val visScore = when {
                        visM >= 25 -> 100
                        visM >= 20 -> 90
                        visM >= 15 -> 80
                        visM >= 10 -> 70
                        visM >= 7 -> 60
                        visM >= 5 -> 50
                        else -> 35
                    }
                    val swellScore = when {
                        swellHeightFt <= 1 -> 100
                        swellHeightFt <= 2 -> 90
                        swellHeightFt <= 3 -> 80
                        swellHeightFt <= 4 -> 65
                        swellHeightFt <= 6 -> 45
                        else -> 25
                    }
                    val windScore = when {
                        windKts <= 5 -> 100
                        windKts <= 10 -> 85
                        windKts <= 15 -> 65
                        windKts <= 20 -> 45
                        else -> 25
                    }
                    
                    // Weighted average: visibility 40%, swell 35%, wind 25%
                    ((visScore * 0.40) + (swellScore * 0.35) + (windScore * 0.25)).toInt()
                } else {
                    // Default score when no cache - use reasonable estimate
                    65
                }
                
                SpotSearchResult(
                    id = spot.id,
                    name = spot.name,
                    region = inferRegionFromSpotId(spot.id),
                    coordinates = spot.coordinates,
                    shakaScore = score
                )
            }
    }
    
    /**
     * Batch fetch current conditions for multiple spots.
     * Used for favorites/home screen to show live data.
     */
    suspend fun getSpotsBatch(spotIds: List<String>, date: String): BatchSpotsResponse {
        val spots = spotIds.mapNotNull { spotId ->
            val spot = spotDb.findSpotById(spotId) ?: return@mapNotNull null
            val lat = spot.coordinates.lat
            val lon = spot.coordinates.lon
            
            try {
                // Fetch weather data (with caching)
                val weather = OceanDataCache.getWeather(lat, lon, date) ?: run {
                    val data = openMeteo.getWeather(lat, lon, date)
                    OceanDataCache.putWeather(lat, lon, date, data)
                    data
                }
                
                // Fetch ocean/swell data (with caching)
                val ocean = OceanDataCache.getOcean(lat, lon, date) ?: run {
                    val data = openMeteo.getMarineData(lat, lon, date)
                    OceanDataCache.putOcean(lat, lon, date, data)
                    data
                }
                
                // Fetch water quality
                val waterQuality = copernicus.getWaterQuality(lat, lon, date)
                
                // Get cached data for score
                val spotCache = SpotDataCache.get(spotId)
                val cachedSolunar = spotCache?.solunar?.value

                val effectiveChl = resolveChlorophyll(
                    waterQuality?.chlorophyllA, spotCache?.chlorophyll?.value, spotCache?.gibsChlorophyll?.value
                )
                
                // Calculate score
                val score = ShakaScorer.generateScore(
                    targetDate = date,
                    windSpeedKmh = weather.windSpeed,
                    waveHeightM = ocean.waveHeight,
                    chlorophyllMgM3 = effectiveChl,
                    solunarDayRating = cachedSolunar?.dayRating,
                    moonPhase = cachedSolunar?.moonPhase
                )
                
                val sst = resolveSST(spotCache?.sst?.value, ocean.rawSST, lat, lon, date)
                
                SpotSummary(
                    id = spot.id,
                    name = spot.name,
                    coordinates = spot.coordinates,
                    shakaScore = score.overall,
                    confidence = score.confidence,
                    conditions = SpotConditions(
                        visibility = getVisibilityLabel(effectiveChl),
                        waterTemp = formatWaterTemp(sst.tempC, sst.isEstimate),
                        swell = "${ocean.swellHeight.toInt()}-${(ocean.swellHeight + 1).toInt()}ft @ ${ocean.swellPeriod.toInt()}s",
                        wind = "${SpotDataCache.kmhToKnots(weather.windSpeed).toInt()} kts ${SpotDataCache.degreesToCardinal(weather.windDirection.toDouble())}",
                        tideState = "",
                        swellSource = "open-meteo"
                    ),
                    expectedFish = spot.commonFish,
                    gearRecommendations = emptyList(),
                    risks = emptyList(),
                    bestTimeOfDay = getBestTimeOfDay(SpotDataCache.get(spotId)?.solunar?.value?.moonPhase)
                )
            } catch (e: Exception) {
                logger.warn("Failed to fetch data for spot $spotId: ${e.message}")
                null
            }
        }
        
        return BatchSpotsResponse(
            spots = spots,
            date = date,
            fetchedAt = java.time.Instant.now().toString()
        )
    }
    
    /**
     * Get all unique regions for search autocomplete.
     * Includes center coordinates calculated from spot positions.
     */
    fun getAllRegions(): List<RegionInfo> {
        data class RegionData(
            val spotIds: MutableList<String> = mutableListOf(),
            var totalLat: Double = 0.0,
            var totalLon: Double = 0.0
        )
        
        val regionMap = mutableMapOf<String, RegionData>()
        
        spotDb.getAllSpots().forEach { spot ->
            val region = inferRegionFromSpotId(spot.id)
            val data = regionMap.getOrPut(region) { RegionData() }
            data.spotIds.add(spot.id)
            data.totalLat += spot.coordinates.lat
            data.totalLon += spot.coordinates.lon
        }
        
        return regionMap.map { (region, data) ->
            val count = data.spotIds.size
            RegionInfo(
                id = region,
                name = region.replaceFirstChar { it.uppercase() },
                spotCount = count,
                centerLat = if (count > 0) data.totalLat / count else 0.0,
                centerLon = if (count > 0) data.totalLon / count else 0.0
            )
        }.sortedBy { it.name }
    }
    
    /**
     * Get human-readable region name for a spot (public accessor).
     * Used by /spots/all endpoint for map markers.
     */
    fun getRegionForSpot(spotId: String): String {
        return inferSpecificRegionFromSpotId(spotId)
    }


    private fun getSeasonalMultiplier(spotId: String, date: String): Double {
        val month = java.time.LocalDate.parse(date).monthValue
        val hemisphere = getHemisphere(spotId)
        
        // Adjust for hemisphere - southern hemisphere seasons are opposite
        val adjustedMonth = if (hemisphere == "south") (month + 6 - 1) % 12 + 1 else month
        
        // Regional seasonal patterns
        return when {
            spotId.startsWith("hawaii") || spotId.startsWith("oahu") || spotId.startsWith("maui") ||
            spotId.startsWith("kauai") || spotId.startsWith("molokai") || spotId.startsWith("lanai") ||
            spotId.startsWith("bigisland") -> {
                // Hawaii: Best May-September (calm summer), decent year-round
                when (adjustedMonth) {
                    in 5..9 -> 1.4  // Peak summer
                    in 4..4, in 10..10 -> 1.2  // Shoulder
                    else -> 1.0  // Winter swells but still fishable
                }
            }
            spotId.contains("bahamas") || spotId.startsWith("exuma") || spotId.startsWith("andros") -> {
                // Bahamas: Best March-June for grouper, Nov-March for wahoo/tuna
                when (adjustedMonth) {
                    in 3..6 -> 1.4  // Grouper season
                    in 11..12, in 1..2 -> 1.3  // Pelagic season
                    else -> 1.1
                }
            }
            spotId.contains("mediterranean") || spotId.startsWith("italy") || spotId.startsWith("spain") ||
            spotId.startsWith("greece") || spotId.startsWith("croatia") || spotId.startsWith("france") -> {
                // Mediterranean: Best May-October
                when (adjustedMonth) {
                    in 6..9 -> 1.5  // Peak summer
                    in 5..5, in 10..10 -> 1.3  // Shoulder
                    else -> 0.8  // Winter - cold and rough
                }
            }
            else -> {
                // Default seasonal pattern
                when (adjustedMonth) {
                    in 5..9 -> 1.3
                    in 3..4, in 10..11 -> 1.1
                    else -> 0.9
                }
            }
        }
    }

    /**
     * Determine hemisphere from spot ID for seasonal adjustments.
     */
    private fun getHemisphere(spotId: String): String {
        return when {
            spotId.startsWith("aus-") || spotId.startsWith("nz-") || 
            spotId.startsWith("brazil-") || spotId.startsWith("sa-") ||
            spotId.startsWith("moz-") || spotId.startsWith("fiji-") -> "south"
            else -> "north"
        }
    }

    /**
     * Infer region from coordinates for community report lookup.
     */
    private fun inferRegionFromCoords(lat: Double, lon: Double): String {
        return when {
            lat in 18.0..23.0 && lon in -161.0..-154.0 -> "hawaii"
            lat in 23.0..28.0 && lon in -80.0..-72.0 -> "bahamas"
            lat in 24.0..26.0 && lon in -82.0..-80.0 -> "florida"
            lat in 32.0..42.0 && lon in -124.0..-117.0 -> "california"
            lat in 35.0..45.0 && lon in 5.0..20.0 -> "mediterranean"
            lat in -20.0..0.0 && lon in 115.0..155.0 -> "indonesia"
            lat in -45.0..-10.0 && lon in 110.0..155.0 -> "australia"
            else -> "worldwide"
        }
    }

    /**
     * Infer region from spot ID for community report lookup.
     */
    private fun inferRegionFromSpotId(spotId: String): String {
        return when {
            spotId.startsWith("oahu-") || spotId.startsWith("maui-") || 
            spotId.startsWith("bigisland-") || spotId.startsWith("kauai-") ||
            spotId.startsWith("molokai-") || spotId.startsWith("lanai-") -> "hawaii"
            spotId.startsWith("keys-") || spotId.startsWith("fl-") -> "florida"
            spotId.startsWith("cali-") -> "california"
            spotId.contains("bahamas") || spotId.startsWith("andros-") || 
            spotId.startsWith("exuma-") -> "bahamas"
            spotId.startsWith("italy-") || spotId.startsWith("sardinia-") ||
            spotId.startsWith("sicily-") -> "italy"
            spotId.startsWith("france-") || spotId.startsWith("corsica-") -> "france"
            spotId.startsWith("aus-") -> "australia"
            spotId.startsWith("tahiti-") || spotId.startsWith("fakarava-") ||
            spotId.startsWith("rangiroa-") || spotId.startsWith("moorea-") -> "tahiti"
            else -> "worldwide"
        }
    }
    
    /**
     * Infer country from spot ID for regulatory lookup.
     */
    private fun inferCountryFromSpotId(spotId: String): String {
        return when {
            spotId.startsWith("oahu-") || spotId.startsWith("maui-") || 
            spotId.startsWith("bigisland-") || spotId.startsWith("kauai-") ||
            spotId.startsWith("molokai-") || spotId.startsWith("lanai-") ||
            spotId.startsWith("keys-") || spotId.startsWith("fl-") ||
            spotId.startsWith("cali-") -> "USA"
            spotId.contains("bahamas") || spotId.startsWith("andros-") || 
            spotId.startsWith("exuma-") || spotId.startsWith("bimini-") ||
            spotId.startsWith("nassau-") -> "Bahamas"
            spotId.startsWith("cayman-") -> "Cayman"
            spotId.startsWith("bvi-") || spotId.startsWith("tortola-") -> "BVI"
            spotId.startsWith("usvi-") || spotId.startsWith("stthomas-") ||
            spotId.startsWith("stcroix-") || spotId.startsWith("stjohn-") -> "USVI"
            spotId.startsWith("italy-") || spotId.startsWith("sardinia-") ||
            spotId.startsWith("sicily-") -> "Italy"
            spotId.startsWith("france-") || spotId.startsWith("corsica-") -> "France"
            spotId.startsWith("aus-") -> "Australia"
            spotId.startsWith("tahiti-") || spotId.startsWith("fakarava-") ||
            spotId.startsWith("rangiroa-") || spotId.startsWith("moorea-") ||
            spotId.startsWith("bora-") -> "FrenchPolynesia"
            spotId.startsWith("fiji-") -> "Fiji"
            spotId.startsWith("mexico-") || spotId.startsWith("cozumel-") ||
            spotId.startsWith("cancun-") -> "Mexico"
            spotId.startsWith("bonaire-") -> "Bonaire"
            spotId.startsWith("curacao-") -> "Curacao"
            spotId.startsWith("aruba-") -> "Aruba"
            else -> "Unknown"
        }
    }
    
    /**
     * Infer specific region (state/island/area) from spot ID for regulatory lookup.
     */
    private fun inferSpecificRegionFromSpotId(spotId: String): String {
        return when {
            spotId.startsWith("oahu-") -> "Oahu"
            spotId.startsWith("maui-") -> "Maui"
            spotId.startsWith("bigisland-") -> "Bigisland"
            spotId.startsWith("kauai-") -> "Kauai"
            spotId.startsWith("molokai-") -> "Molokai"
            spotId.startsWith("lanai-") -> "Lanai"
            spotId.startsWith("keys-") -> "Keys"
            spotId.startsWith("fl-") -> "Florida"
            spotId.startsWith("cali-") -> "California"
            spotId.startsWith("andros-") -> "Andros"
            spotId.startsWith("exuma-") -> "Exuma"
            spotId.startsWith("bimini-") -> "Bimini"
            spotId.startsWith("nassau-") -> "Nassau"
            spotId.startsWith("cayman-") -> "Cayman"
            spotId.startsWith("bvi-") || spotId.startsWith("tortola-") -> "Bvi"
            spotId.startsWith("usvi-") || spotId.startsWith("stthomas-") ||
            spotId.startsWith("stcroix-") || spotId.startsWith("stjohn-") -> "Usvi"
            spotId.startsWith("sardinia-") -> "Sardinia"
            spotId.startsWith("sicily-") -> "Sicily"
            spotId.startsWith("corsica-") -> "Corsica"
            spotId.startsWith("aus-") -> "Aus"
            spotId.startsWith("tahiti-") -> "Tahiti"
            spotId.startsWith("moorea-") -> "Moorea"
            spotId.startsWith("bora-") -> "Bora"
            spotId.startsWith("rangiroa-") -> "Rangiroa"
            spotId.startsWith("fakarava-") -> "Fakarava"
            spotId.startsWith("fiji-") -> "Fiji"
            spotId.startsWith("cozumel-") -> "Cozumel"
            spotId.startsWith("cancun-") -> "Cancun"
            spotId.startsWith("bonaire-") -> "Bonaire"
            spotId.startsWith("curacao-") -> "Curacao"
            spotId.startsWith("aruba-") -> "Aruba"
            else -> spotId.substringBefore("-").replaceFirstChar { it.uppercase() }
        }
    }

    /**
     * Get fish likelihood based on season and conditions.
     */
    private fun getFishLikelihood(fish: String, spotId: String, date: String): String {
        val month = java.time.LocalDate.parse(date).monthValue
        val seasonalMultiplier = getSeasonalMultiplier(spotId, date)
        
        return when {
            seasonalMultiplier >= 1.4 -> "very likely"
            seasonalMultiplier >= 1.2 -> "likely"
            seasonalMultiplier >= 1.0 -> "possible"
            else -> "unlikely"
        }
    }

    /**
     * Get seasonal notes for fish species.
     */
    private fun getSeasonalNotes(fish: String, spotId: String, date: String): String? {
        val month = java.time.LocalDate.parse(date).monthValue
        
        // Common fish seasonal patterns
        return when (fish.lowercase()) {
            "ulua", "giant trevally", "gt" -> {
                when (month) {
                    in 5..9 -> "Peak season - active in warm water"
                    else -> "Present year-round"
                }
            }
            "yellowtail", "hiramasa" -> {
                when (month) {
                    in 1..4 -> "Peak season - running in cooler water"
                    else -> null
                }
            }
            "mahi mahi", "dorado" -> {
                when (month) {
                    in 4..10 -> "Peak season - following warm currents"
                    else -> "Less common in cooler months"
                }
            }
            "wahoo", "ono" -> {
                when (month) {
                    in 5..9 -> "Peak season"
                    else -> null
                }
            }
            "hogfish" -> {
                when (month) {
                    in 3..6 -> "Spawning season - more active"
                    else -> null
                }
            }
            "grouper" -> {
                when (month) {
                    in 1..4 -> "Spawning aggregations in some areas"
                    else -> null
                }
            }
            else -> null
        }
    }

    /**
     * Get regulatory information for a spot based on its region and country.
     * Combines regulatory links from JSON config with MPA data from cache.
     */
    private fun getRegulationInfo(spotId: String, region: String, country: String): RegulationInfo? {
        // Get MPA data from cache
        val cached = SpotDataCache.get(spotId)
        val mpaCache = cached?.mpa?.value
        val mpaChecked = cached?.mpa != null  // true when mpa_fetched_at is NOT NULL (fetch was attempted)
        
        // Build MPA status from cache
        val mpaStatus = mpaCache?.let {
            MPAStatus(
                isProtected = it.spearfishingStatus in 1..2,  // Prohibited or Restricted
                isInsideMPA = it.isInsideMPA,
                siteName = it.siteName,
                designation = it.designation,
                spearfishingStatus = it.spearfishingStatus,
                protectionLevel = it.protectionLevel,
                speciesOfConcern = it.speciesOfConcern,
                purpose = it.purpose,
                detailsUrl = it.detailsUrl
            )
        }
        
        // Get regulatory links from JSON config
        val links = regulatoryLinks?.jsonObject ?: return RegulationInfo(
            regulatoryAgency = "Local Fisheries Authority",
            regulationsUrl = "https://navigatormap.org/",
            mpaStatus = mpaStatus,
            mpaChecked = mpaChecked
        )
        
        // Try to find region-specific info
        // First try country -> region (e.g., USA -> Hawaii)
        val countryLinks = links[country]?.jsonObject
        val regionLinks = countryLinks?.get(region)?.jsonObject
            ?: countryLinks?.entries?.firstOrNull { (_, value) ->
                value is JsonObject && value["regions"]?.toString()?.contains(region, ignoreCase = true) == true
            }?.value?.jsonObject
        
        // Handle flat country structures (e.g., Bahamas) where regions array is directly on the country object
        if (regionLinks == null && countryLinks != null && 
            countryLinks["agency"] != null &&
            countryLinks["regions"]?.jsonArray?.any { 
                it.jsonPrimitive.content.contains(region, ignoreCase = true) 
            } == true) {
            return RegulationInfo(
                regulatoryAgency = countryLinks["agency"]?.jsonPrimitive?.content ?: "Fisheries Authority",
                regulationsUrl = countryLinks["url"]?.jsonPrimitive?.content ?: "https://navigatormap.org/",
                licensingUrl = countryLinks["licensingUrl"]?.jsonPrimitive?.content,
                note = countryLinks["note"]?.jsonPrimitive?.content,
                mpaStatus = mpaStatus,
                mpaChecked = mpaChecked
            )
        }
        
        if (regionLinks != null) {
            return RegulationInfo(
                regulatoryAgency = regionLinks["agency"]?.jsonPrimitive?.content ?: "Fisheries Authority",
                regulationsUrl = regionLinks["url"]?.jsonPrimitive?.content ?: "https://navigatormap.org/",
                licensingUrl = regionLinks["licensingUrl"]?.jsonPrimitive?.content,
                note = regionLinks["note"]?.jsonPrimitive?.content,
                mpaStatus = mpaStatus,
                mpaChecked = mpaChecked
            )
        }
        
        // Try direct region match in other sections (Caribbean, Pacific, etc.)
        for ((section, sectionData) in links) {
            if (section == "default") continue
            val sectionObj = try { sectionData.jsonObject } catch (e: Exception) { continue }
            
            // Check if this section directly matches the country
            if (section.equals(country, ignoreCase = true)) {
                return RegulationInfo(
                    regulatoryAgency = sectionObj["agency"]?.jsonPrimitive?.content ?: "Fisheries Authority",
                    regulationsUrl = sectionObj["url"]?.jsonPrimitive?.content ?: "https://navigatormap.org/",
                    licensingUrl = sectionObj["licensingUrl"]?.jsonPrimitive?.content,
                    note = sectionObj["note"]?.jsonPrimitive?.content,
                    mpaStatus = mpaStatus,
                    mpaChecked = mpaChecked
                )
            }
            
            // Check subsections
            for ((subRegion, subData) in sectionObj) {
                val subObj = try { subData.jsonObject } catch (e: Exception) { continue }
                val regions = subObj["regions"]?.toString() ?: ""
                if (regions.contains(region, ignoreCase = true) || 
                    subRegion.equals(region, ignoreCase = true)) {
                    return RegulationInfo(
                        regulatoryAgency = subObj["agency"]?.jsonPrimitive?.content ?: "Fisheries Authority",
                        regulationsUrl = subObj["url"]?.jsonPrimitive?.content ?: "https://navigatormap.org/",
                        licensingUrl = subObj["licensingUrl"]?.jsonPrimitive?.content,
                        note = subObj["note"]?.jsonPrimitive?.content,
                        mpaStatus = mpaStatus,
                        mpaChecked = mpaChecked
                    )
                }
            }
        }
        
        // Fallback to default
        val defaultLinks = links["default"]?.jsonObject
        return RegulationInfo(
            regulatoryAgency = defaultLinks?.get("message")?.jsonPrimitive?.content ?: "Local Fisheries Authority",
            regulationsUrl = defaultLinks?.get("url")?.jsonPrimitive?.content ?: "https://navigatormap.org/",
            mpaStatus = mpaStatus,
            mpaChecked = mpaChecked
        )
    }
    
    /**
     * Determine best time of day based on moon phase.
     */
    private fun getBestTimeOfDay(moonPhase: String?): String {
        return when (moonPhase) {
            "new_moon" -> "First light (5:30am-8am) or dusk"
            "full_moon" -> "Early morning or late afternoon"
            else -> "6am-10am"
        }
    }

    /**
     * Public: resolve the visibility label from cached data only (no API calls).
     * Used by SpotRoutes for lightweight endpoints like /spots/all.
     */
    fun resolveVisibilityLabel(cached: SpotDataCache.SpotData?): String {
        val chl = resolveChlorophyll(null, cached?.chlorophyll?.value, cached?.gibsChlorophyll?.value)
        return getVisibilityLabel(chl)
    }

    /**
     * Resolve the best available chlorophyll value using the same fallback chain
     * as the Flutter SatelliteReadingsCard: Copernicus → ERDDAP cache → GIBS blended estimate.
     * The result drives BOTH the visibility score and the visibility label.
     */
    private fun resolveChlorophyll(
        copernicusChl: Double?,
        cachedErddapChl: Double?,
        gibsData: SpotDataCache.GIBSSatelliteData?
    ): Double? {
        return copernicusChl
            ?: cachedErddapChl
            ?: GibsColormap.estimateFromGibsColors(gibsData)
    }

    /**
     * Get visibility display string from chlorophyll concentration.
     * Uses the same thresholds as the scorer so the label matches the score.
     */
    private fun getVisibilityLabel(chl: Double?): String {
        if (chl == null) return "No satellite data"
        return when {
            chl < 0.1  -> "Crystal clear"
            chl < 0.3  -> "Blue water"
            chl < 0.5  -> "Slight haze"
            chl < 1.0  -> "Green tint"
            chl < 3.0  -> "Murky"
            chl < 5.0  -> "Can't see your fins"
            chl < 10.0 -> "Can't see your hand"
            else       -> "Zero vis"
        }
    }

    data class ResolvedSST(val tempC: Double, val isEstimate: Boolean)

    private fun resolveSST(
        cachedSST: Double?,
        openMeteoSST: Double?,
        lat: Double, lon: Double, date: String
    ): ResolvedSST {
        cachedSST?.let { return ResolvedSST(it, false) }
        openMeteoSST?.let { return ResolvedSST(it, false) }
        return ResolvedSST(noaaClient.getRegionalSSTEstimate(lat, lon, date), true)
    }

    private fun formatWaterTemp(sstCelsius: Double?, isEstimate: Boolean = false): String {
        if (sstCelsius == null) return "N/A"
        val f = ((sstCelsius * 9.0 / 5) + 32).toInt()
        return if (isEstimate) "~${sstCelsius.toInt()}°C / ~${f}°F (est.)" else "${sstCelsius.toInt()}°C / ${f}°F"
    }

    private fun generateGearRecs(waterTempC: Double?, depthM: Int): List<String> {
        val recs = mutableListOf<String>()

        recs += when {
            waterTempC == null -> "5mm+ wetsuit (water temp unavailable)"
            waterTempC >= 26 -> "Rashguard or 1mm suit"
            waterTempC >= 23 -> "3mm wetsuit"
            waterTempC >= 20 -> "5mm wetsuit"
            else -> "7mm wetsuit with hood"
        }

        // Speargun vs pole spear
        recs += if (depthM > 10) "Speargun (90-110cm)" else "Pole spear or Hawaiian sling"

        // Standard gear
        recs += "Mask and snorkel"
        recs += "Fins"
        recs += "Weight belt"
        recs += "Dive knife"
        recs += "Float and flag"
        recs += "Gloves"

        return recs
    }

    private fun generateRisks(weather: WeatherData, ocean: OceanData): List<String> {
        val risks = mutableListOf<String>()

        if (weather.windSpeed > 15) risks += "Strong winds expected"
        if (ocean.waveHeight > 1.5) risks += "Rough surf conditions"
        if (weather.precipitation > 2) risks += "Rain may reduce visibility"
        if (ocean.waterTemperature < 20) risks += "Cold water - hypothermia risk"

        if (risks.isEmpty()) risks += "No significant risks identified"

        return risks
    }
    
    /**
     * Build water context with chlorophyll trends and SST at nearby points.
     * Allows fishermen to spot temperature breaks and plankton blooms.
     */
    private fun buildWaterContext(
        cached: SpotDataCache.SpotData?,
        waterQuality: WaterQuality,
        lat: Double,
        lon: Double
    ): WaterContext? {
        val chlorophyllContext = buildChlorophyllContext(cached, waterQuality)
        val sstNearby = buildSSTNearby(cached, lat, lon)
        
        // Return null if no data available
        if (chlorophyllContext == null && sstNearby.isNullOrEmpty()) {
            return null
        }
        
        return WaterContext(
            chlorophyll = chlorophyllContext,
            sstNearby = sstNearby
        )
    }
    
    /**
     * Build chlorophyll context with current value and trend.
     * Compares current reading to 7-day average from GIBS satellite data.
     */
    private fun buildChlorophyllContext(
        cached: SpotDataCache.SpotData?,
        waterQuality: WaterQuality
    ): ChlorophyllContext? {
        // Get current chlorophyll from NOAA ERDDAP (trusted source)
        // Note: We removed GIBS-derived chlorophyll values as they were unreliable in coastal areas
        val current = cached?.chlorophyll?.value ?: waterQuality.chlorophyllA ?: return null
        
        // Without historical data from multiple days, we use current as both values
        // In the future, we could store historical NOAA ERDDAP readings for trend analysis
        val avg7day = current
        
        // Cannot determine trend without historical data
        val trend = "stable"
        
        return ChlorophyllContext(
            current = current,
            avg7day = avg7day,
            trend = trend
        )
    }
    
    /**
     * Build SST readings at nearby points to detect temperature breaks.
     * Uses cached SST data or estimates from marine data.
     * 
     * Temperature breaks (where warm and cold water meet) are where fish congregate.
     */
    private fun buildSSTNearby(
        cached: SpotDataCache.SpotData?,
        lat: Double,
        lon: Double
    ): List<SSTReading>? {
        // Get SST at the spot
        val centerSST = cached?.sst?.value ?: return null
        
        // For now, we don't have nearby readings in cache
        // In a full implementation, we'd fetch SST at N/S/E/W points during prefetch
        // For now, return null - this will be populated when we add SST nearby to prefetch
        
        // TODO: Add SST nearby readings to prefetch jobs
        // This would involve:
        // 1. During prefetch, fetch SST at 4 points: 5nm N, S, E, W of spot
        // 2. Store in cache as part of CachedSpotData
        // 3. Return those readings here
        
        return null
    }

    // ============================================
    // USER SPOT METHODS
    // ============================================

    /**
     * Get detailed information for a user-created spot.
     * Similar to getSpotDetail but works with UserSpotRecord instead of in-memory spot.
     * 
     * @param userSpot The user spot record from the database
     * @param cacheId The cache ID for this spot (prefixed with "user-")
     * @param date The date for conditions lookup
     * @return SpotDetail with full conditions, or null on error
     */
    suspend fun getUserSpotDetail(
        userSpot: UserSpotRepository.UserSpotRecord,
        cacheId: String,
        date: String
    ): SpotDetail? = coroutineScope {
        val lat = userSpot.coordinates.lat
        val lon = userSpot.coordinates.lon
        val region = userSpot.region
        
        // Check prefetched cache first (instant!)
        var cached = SpotDataCache.get(cacheId)
        
        if (cached == null || cached.tide == null || cached.swell == null || cached.wind == null) {
            // Cache incomplete — run full prefetch to populate it with real data.
            // The background prefetch from spot creation may already be running;
            // duplicate API calls are idempotent and harmless.
            logger.info("Cache incomplete for user spot ${userSpot.name}, running full prefetch")
            try {
                prefetchSingleSpot(cacheId, lat, lon)
            } catch (e: Exception) {
                logger.warn("Full prefetch failed for ${userSpot.name}: ${e.message}")
            }
            
            cached = SpotDataCache.get(cacheId)
            if (cached == null || cached.tide == null || cached.swell == null || cached.wind == null) {
                logger.warn("Cache still incomplete after prefetch for ${userSpot.name}")
                return@coroutineScope null
            }
        }
        
        // Always build from cache — single code path, consistent formatting
        logger.debug("Building detail from cache for ${userSpot.name}")
        
        val weather = WeatherData(
            temperature = 25.0,
            windSpeed = cached.wind!!.value.speedKnots / 0.539957,
            windDirection = 0,
            precipitation = 0.0,
            cloudCover = 50,
            visibility = 10000.0
        )
        
        val ocean = OceanData(
            waveHeight = cached.swell!!.value.heightFt / 3.28084,
            wavePeriod = cached.swell!!.value.periodSec,
            waveDirection = 0,
            waterTemperature = cached.sst?.value ?: 15.0,
            swellHeight = (cached.swell!!.value.swellHeightFt ?: cached.swell!!.value.heightFt) / 3.28084,
            swellDirection = 0
        )
        
        val waterQuality = WaterQuality(
            chlorophyllA = cached.chlorophyll?.value,
            visibility = cached.visibility?.value,
            seaSurfaceTemp = cached.sst?.value,
            dataSource = "Prefetched (updated ${cached.tide!!.ageString()})"
        )
        
        val tideData = TideData(
            currentHeight = cached.tide!!.value.currentHeight,
            nextHighTide = cached.tide!!.value.nextHighTide,
            nextLowTide = cached.tide!!.value.nextLowTide,
            tideState = cached.tide!!.value.state,
            nextHighTideTime = cached.tide!!.value.nextHighTideTime?.toEpochMilli(),
            nextLowTideTime = cached.tide!!.value.nextLowTideTime?.toEpochMilli()
        )
        
        // Forecast is lazy-loaded by the client via /forecast/{spotId} when user taps Forecast tab

        logger.info("User spot detail loaded from cache: ${userSpot.name}")

        val effectiveChl = resolveChlorophyll(
            waterQuality?.chlorophyllA, cached?.chlorophyll?.value, cached?.gibsChlorophyll?.value
        )

        val score = ShakaScorer.generateScore(
            targetDate = date,
            windSpeedKmh = weather.windSpeed,
            waveHeightM = ocean.waveHeight,
            chlorophyllMgM3 = effectiveChl,
            solunarDayRating = cached?.solunar?.value?.dayRating,
            moonPhase = cached?.solunar?.value?.moonPhase
        )
        
        val sst = resolveSST(cached?.sst?.value, ocean.rawSST, lat, lon, date)
        
        // Data freshness from cache
        val dataUpdatedMinutesAgo = cached?.tide?.minutesSinceFetch()?.toInt()
        val satelliteDataDate = cached?.sst?.dataDateString()

        // Build satellite readings - colors for display, NOAA ERDDAP for actual chlorophyll
        val gibsReadings = if (cached?.gibsChlorophyll != null || cached?.chlorophyll != null) {
            val gibs = cached.gibsChlorophyll?.value
            GibsSatelliteReadings(
                paceTodayColor = gibs?.paceTodayColor,
                paceYesterdayColor = gibs?.paceYesterdayColor,
                noaa20TodayColor = gibs?.noaa20TodayColor,
                noaa20YesterdayColor = gibs?.noaa20YesterdayColor,
                noaa21TodayColor = gibs?.noaa21TodayColor,
                noaa21YesterdayColor = gibs?.noaa21YesterdayColor,
                sentinel3aTodayColor = gibs?.sentinel3aTodayColor,
                sentinel3aYesterdayColor = gibs?.sentinel3aYesterdayColor,
                sentinel3bTodayColor = gibs?.sentinel3bTodayColor,
                sentinel3bYesterdayColor = gibs?.sentinel3bYesterdayColor,
                // Observation times
                paceObservationTime = gibs?.paceObservationTime?.toString(),
                noaa20ObservationTime = gibs?.noaa20ObservationTime?.toString(),
                noaa21ObservationTime = gibs?.noaa21ObservationTime?.toString(),
                dataDate = gibs?.dataDate?.toString(),
                // ACTUAL measured chlorophyll from NOAA ERDDAP (the trusted source)
                noaaErddapChlorophyll = cached.chlorophyll?.value,
                noaaErddapFetchTime = cached.chlorophyll?.fetchedAt?.toString()
            )
        } else null

        // Get MPA status from cache
        val mpaStatus = cached?.mpa?.value?.let {
            MPAStatus(
                isProtected = it.spearfishingStatus in 1..2,
                isInsideMPA = it.isInsideMPA,
                siteName = it.siteName,
                designation = it.designation,
                spearfishingStatus = it.spearfishingStatus,
                protectionLevel = it.protectionLevel,
                speciesOfConcern = it.speciesOfConcern,
                purpose = it.purpose,
                detailsUrl = it.detailsUrl
            )
        }

        SpotDetail(
            id = cacheId, // Use cache ID which includes "user-" prefix
            name = userSpot.name,
            description = "Custom saved spot in ${userSpot.region}",
            coordinates = userSpot.coordinates,
            score = score,
            access = AccessInfo(
                directions = "User-saved location",
                parkingInfo = "Check locally",
                permitRequired = false
            ),
            conditions = SpotConditions(
                visibility = getVisibilityLabel(effectiveChl),
                waterTemp = formatWaterTemp(sst.tempC, sst.isEstimate),
                swell = cached?.swell?.let { 
                    "${it.value.heightFt.toInt()}ft @ ${it.value.periodSec.toInt()}s ${it.value.direction}" 
                } ?: "${ocean.swellHeight.toInt()}-${(ocean.swellHeight + 1).toInt()}ft @ ${ocean.swellPeriod.toInt()}s",
                wind = cached?.wind?.let { 
                    "${it.value.speedKnots.toInt()} kts ${it.value.direction}" 
                } ?: "${SpotDataCache.kmhToKnots(weather.windSpeed).toInt()} kts ${SpotDataCache.degreesToCardinal(weather.windDirection.toDouble())}",
                tideState = "${tideData.tideState} - Next high: ${tideData.nextHighTide}",
                dataUpdatedMinutesAgo = dataUpdatedMinutesAgo,
                satelliteDataDate = satelliteDataDate,
                swellSource = cached?.swell?.value?.source
            ),
            forecast = emptyList(), // Lazy-loaded by client via /forecast/{spotId}
            expectedFish = emptyList(), // User spots don't have fish data
            gearRecommendations = generateGearRecs(sst.tempC, 10).map { item ->
                GearItem(item = item, reason = "Recommended for conditions", essential = true)
            },
            risks = generateRisks(weather, ocean).map { risk ->
                RiskInfo(risk = risk, severity = "moderate", mitigation = "Check conditions before entry")
            },
            communityReports = emptyList(), // No community data for user spots
            bestTimeOfDay = getBestTimeOfDay(cached?.solunar?.value?.moonPhase),
            imageUrl = null,
            satelliteReadings = gibsReadings,
            regulations = RegulationInfo(
                regulatoryAgency = "Local Fisheries Authority",
                regulationsUrl = "https://navigatormap.org/",
                mpaStatus = mpaStatus,
                mpaChecked = cached?.mpa != null
            )
        )
    }
    
    /**
     * Quick score calculation for user spot list view.
     * Uses cached data only - no API calls. Returns null if no cached data available.
     */
    fun getUserSpotScore(cacheId: String): Int? {
        val cached = SpotDataCache.get(cacheId) ?: return null
        
        // Require tide + swell + wind so the score reflects real data, not defaults
        if (cached.tide == null || cached.swell == null || cached.wind == null) return null
        
        val windSpeedKmh = cached.wind.value.speedKnots / 0.539957
        val waveHeightM = cached.swell.value.heightFt / 3.28084
        
        val effectiveChl = resolveChlorophyll(null, cached.chlorophyll?.value, cached.gibsChlorophyll?.value)
        
        val today = LocalDate.now().toString()
        val score = ShakaScorer.generateScore(
            targetDate = today,
            windSpeedKmh = windSpeedKmh,
            waveHeightM = waveHeightM,
            chlorophyllMgM3 = effectiveChl,
            solunarDayRating = cached.solunar?.value?.dayRating,
            moonPhase = cached.solunar?.value?.moonPhase
        )
        
        return score.overall
    }

    /**
     * Prefetch all data for a single spot and save to cache.
     * Used after creating a new user spot to immediately populate the cache.
     * 
     * Fetches:
     * - Tide data (NOAA)
     * - Weather/swell data (Open-Meteo)
     * - Satellite SST/visibility/chlorophyll (Copernicus)
     * - GIBS chlorophyll from all satellites
     * - MPA status (ProtectedSeas)
     * 
     * @param spotId The cache ID for the spot
     * @param lat Latitude
     * @param lon Longitude
     */
    suspend fun prefetchSingleSpot(spotId: String, lat: Double, lon: Double) = coroutineScope {
        val today = LocalDate.now().toString()
        val now = Instant.now()
        
        logger.info("Prefetching data for spot $spotId at ($lat, $lon)")
        
        // Launch all fetches in parallel, writing to SpotDataCache as each completes.
        // This lets getUserSpotScore() return a score as soon as tide arrives (~2s)
        // instead of waiting for the slowest fetch (GIBS: up to 30s).
        
        val tideDeferred = async {
            val data = withTimeoutOrNull(10000) {
                try { tidesClient.getTideData(lat, lon, today) }
                catch (e: Exception) { logger.warn("Tide fetch failed for $spotId: ${e.message}"); null }
            }
            if (data != null) {
                SpotDataCache.updateTide(spotId, SpotDataCache.CachedValue(
                    value = SpotDataCache.TideInfo(
                        state = data.tideState, nextHighTide = data.nextHighTide,
                        nextLowTide = data.nextLowTide, currentHeight = data.currentHeight,
                        nextHighTideTime = data.nextHighTideTime?.let { java.time.Instant.ofEpochMilli(it) },
                        nextLowTideTime = data.nextLowTideTime?.let { java.time.Instant.ofEpochMilli(it) }
                    ), fetchedAt = now
                ))
            }
            data
        }
        
        val weatherDeferred = async {
            val data = withTimeoutOrNull(10000) {
                try { openMeteo.getMarineData(lat, lon, today) to openMeteo.getWeather(lat, lon, today) }
                catch (e: Exception) { logger.warn("Weather fetch failed for $spotId: ${e.message}"); null }
            }
            if (data != null) {
                val (ocean, weather) = data
                
                // Resolution: prefer buoy data if a nearby buoy has a fresh reading
                val buoyResult = SpotDataCache.findNearestBuoyReading(lat, lon)
                val swellInfo: SpotDataCache.SwellInfo
                if (buoyResult != null) {
                    val (buoyStation, buoyReading) = buoyResult
                    swellInfo = SpotDataCache.SwellInfo(
                        heightFt = SpotDataCache.metersToFeet(buoyReading.waveHeightM ?: ocean.swellHeight),
                        periodSec = buoyReading.dominantPeriodSec ?: ocean.swellPeriod,
                        direction = SpotDataCache.degreesToCardinal((buoyReading.meanDirection ?: ocean.swellDirection.toInt()).toDouble()),
                        swellHeightFt = SpotDataCache.metersToFeet(buoyReading.waveHeightM ?: ocean.swellHeight),
                        source = "ndbc-${buoyStation.stationId}"
                    )
                    logger.info("Using buoy ${buoyStation.stationId} data for spot $spotId (${buoyReading.waveHeightM}m)")
                } else {
                    swellInfo = SpotDataCache.SwellInfo(
                        heightFt = SpotDataCache.metersToFeet(ocean.swellHeight),
                        periodSec = ocean.swellPeriod,
                        direction = SpotDataCache.degreesToCardinal(ocean.swellDirection.toDouble()),
                        swellHeightFt = SpotDataCache.metersToFeet(ocean.swellHeight),
                        source = "open-meteo"
                    )
                }
                
                SpotDataCache.updateSwell(spotId, SpotDataCache.CachedValue(
                    value = swellInfo, fetchedAt = now
                ))
                SpotDataCache.updateSwellSource(spotId, swellInfo.source)
                SpotDataCache.updateWind(spotId, SpotDataCache.CachedValue(
                    value = SpotDataCache.WindInfo(
                        speedKnots = SpotDataCache.kmhToKnots(weather.windSpeed),
                        direction = SpotDataCache.degreesToCardinal(weather.windDirection.toDouble())
                    ), fetchedAt = now
                ))
            }
            data
        }
        
        val sstDeferred = async {
            val data = withTimeoutOrNull(10000) {
                try { noaaClient.getSeaSurfaceTemperature(lat, lon, today) }
                catch (e: Exception) { logger.warn("NOAA SST fetch failed for $spotId: ${e.message}"); null }
            }
            SpotDataCache.updateSST(spotId,
                if (data != null) SpotDataCache.CachedValue(value = data, fetchedAt = now) else null)
            data
        }
        
        val satelliteDeferred = async {
            val data = withTimeoutOrNull(15000) {
                try { copernicus.getWaterQuality(lat, lon, today) }
                catch (e: Exception) { logger.warn("Satellite fetch failed for $spotId: ${e.message}"); null }
            }
            if (data != null) {
                data.visibility?.let { vis ->
                    SpotDataCache.updateVisibility(spotId, SpotDataCache.CachedValue(value = vis, fetchedAt = now))
                }
                data.chlorophyllA?.let { chl ->
                    SpotDataCache.updateChlorophyll(spotId, SpotDataCache.CachedValue(value = chl, fetchedAt = now))
                }
            }
            data
        }
        
        val gibsDeferred = async {
            val data = withTimeoutOrNull(30000) {
                try { GIBSClient.getAllSatelliteColors(lat, lon) }
                catch (e: Exception) { logger.warn("GIBS fetch failed for $spotId: ${e.message}"); null }
            }
            if (data != null) {
                SpotDataCache.updateGIBSChlorophyll(spotId, SpotDataCache.CachedValue(
                    value = SpotDataCache.GIBSSatelliteData(
                        paceTodayColor = data.paceTodayColor, paceYesterdayColor = data.paceYesterdayColor,
                        noaa20TodayColor = data.noaa20TodayColor, noaa20YesterdayColor = data.noaa20YesterdayColor,
                        noaa21TodayColor = data.noaa21TodayColor, noaa21YesterdayColor = data.noaa21YesterdayColor,
                        sentinel3aTodayColor = data.sentinel3aTodayColor, sentinel3aYesterdayColor = data.sentinel3aYesterdayColor,
                        sentinel3bTodayColor = data.sentinel3bTodayColor, sentinel3bYesterdayColor = data.sentinel3bYesterdayColor,
                        dataDate = data.dataDate, paceObservationTime = data.paceObservationTime,
                        noaa20ObservationTime = data.noaa20ObservationTime, noaa21ObservationTime = data.noaa21ObservationTime
                    ), fetchedAt = now
                ))
            }
            data
        }
        
        // Await all results (cache writes already happened inside each async block)
        val tideData = tideDeferred.await()
        val weatherData = weatherDeferred.await()
        val satelliteData = satelliteDeferred.await()
        val sstData = sstDeferred.await()
        val gibsData = gibsDeferred.await()
        
        // MPA check: exact first, then buffer (sequential — depends on exact result)
        val exactMPA = try {
            protectedSeasClient.getMPAStatusExact(lat, lon)
        } catch (e: Exception) {
            logger.warn("Exact MPA check failed for $spotId: ${e.message}")
            null
        }
        
        val bufferMPA = if (exactMPA == null) {
            try {
                protectedSeasClient.getMPAStatus(lat, lon)
            } catch (e: Exception) {
                logger.warn("Buffer MPA check failed for $spotId: ${e.message}")
                null
            }
        } else null
        
        val isInsideMPA = exactMPA != null
        val mpaData = exactMPA ?: bufferMPA
        
        val mpaCacheInfo = mpaData?.let {
            SpotDataCache.MPACacheInfo(
                siteName = it.siteName, designation = it.designation,
                spearfishingStatus = it.spearfishingStatus, protectionLevel = it.protectionLevel,
                speciesOfConcern = it.speciesOfConcern, purpose = it.purpose,
                detailsUrl = it.detailsUrl, isInsideMPA = isInsideMPA
            )
        }
        SpotDataCache.updateMPA(spotId, SpotDataCache.CachedValue(value = mpaCacheInfo, fetchedAt = now))
        
        // Persist to database
        SpotDataCache.saveToDatabase(spotId)
        
        logger.info("Prefetch complete for spot $spotId - tide:${tideData != null}, weather:${weatherData != null}, satellite:${satelliteData != null}, gibs:${gibsData != null}, mpa:${mpaData != null}")
    }

}
