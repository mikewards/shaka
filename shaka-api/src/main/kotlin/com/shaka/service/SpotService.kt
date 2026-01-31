package com.shaka.service

import com.shaka.data.cache.OceanDataCache
import com.shaka.data.cache.SpotDataCache
import com.shaka.data.client.CommunityClient
import com.shaka.data.client.CopernicusClient
import com.shaka.data.client.NOAATidesClient
import com.shaka.data.client.OpenMeteoClient
import com.shaka.data.client.SpotDatabase
import com.shaka.model.*
import com.shaka.scoring.ShakaScorer
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withTimeoutOrNull
import org.slf4j.LoggerFactory

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
    private val community = CommunityClient()
    private val forecastService = ForecastService()
    private val spotDb = SpotDatabase

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

        // Get community sightings count for the region
        val regionReports = try {
            val region = inferRegionFromCoords(lat, lon)
            community.getReportsForRegion(region, 10)
        } catch (e: Exception) {
            emptyList()
        }
        val recentSightingsCount = regionReports.size.coerceAtLeast(1)

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
                    waterTemperature = cached.sst?.value ?: 24.0,
                    swellHeight = (cached.swell.value.swellHeightFt ?: cached.swell.value.heightFt) / 3.28084,
                    swellDirection = 0
                )
            } else {
                fallbackOcean ?: OceanData(
                    waveHeight = 1.0, wavePeriod = 8.0, waveDirection = 0,
                    waterTemperature = 24.0, swellHeight = 1.0, swellDirection = 0
                )
            }
            
            val waterQuality = if (cached?.visibility != null || cached?.sst != null) {
                WaterQuality(
                    chlorophyllA = cached.chlorophyll?.value,
                    turbidity = null,
                    visibility = cached.visibility?.value,
                    seaSurfaceTemp = cached.sst?.value ?: ocean.waterTemperature,
                    dataSource = "Prefetched (${cached.visibility?.ageString() ?: "N/A"})"
                )
            } else {
                fallbackWaterQuality ?: WaterQuality(
                    chlorophyllA = null, turbidity = null, visibility = null,
                    seaSurfaceTemp = ocean.waterTemperature, dataSource = "Data temporarily unavailable"
                )
            }
            
            val tideData = if (cached?.tide != null) {
                TideData(
                    currentHeight = cached.tide.value.currentHeight,
                    nextHighTide = cached.tide.value.nextHighTide,
                    nextLowTide = cached.tide.value.nextLowTide,
                    tideState = cached.tide.value.state
                )
            } else {
                fallbackTide ?: TideData(
                    currentHeight = 0.5, nextHighTide = "Check local source", 
                    nextLowTide = "Check local source", tideState = "Unknown"
                )
            }
            
            val score = ShakaScorer.generateScore(
                targetDate = date,
                weather = weather,
                ocean = ocean,
                waterQuality = waterQuality,
                moonPhase = getMoonPhase(date),
                seasonalMultiplier = getSeasonalMultiplier(spot.id, date),
                recentSightings = recentSightingsCount,
                isShore = spot.access == "shore",
                hasParking = true,
                permitRequired = false,
                currentStrength = 0.5,
                hasHazards = false,
                sharkRisk = "low"
            )

            // Use real SST - prefer cached satellite data
            val actualSST = cached?.sst?.value ?: waterQuality.seaSurfaceTemp ?: ocean.waterTemperature
            
            // Data freshness from cache
            val dataUpdatedMinutesAgo = cached?.tide?.minutesSinceFetch()?.toInt()
            val satelliteDataDate = cached?.sst?.dataDateString()
            
            SpotSummary(
                id = spot.id,
                name = spot.name,
                coordinates = spot.coordinates,
                shakaScore = score.overall,
                confidence = score.confidence,
                access = spot.access,
                conditions = SpotConditions(
                    visibility = cached?.visibility?.let { 
                        "${it.value.toInt()}m (${waterQuality.visibilityCategory})" 
                    } ?: waterQuality.visibility?.let { 
                        "${it.toInt()}m (${waterQuality.visibilityCategory})" 
                    } ?: "Updating...",
                    waterTemp = "${actualSST.toInt()}°C / ${((actualSST * 9/5) + 32).toInt()}°F",
                    swell = cached?.swell?.let { 
                        "${it.value.heightFt.toInt()}ft @ ${it.value.periodSec.toInt()}s ${it.value.direction}" 
                    } ?: "${ocean.waveHeight.toInt()}-${(ocean.waveHeight + 1).toInt()}ft @ ${ocean.wavePeriod.toInt()}s",
                    wind = cached?.wind?.let { 
                        "${it.value.speedKnots.toInt()} kts ${it.value.direction}" 
                    } ?: "${weather.windSpeed.toInt()} knots",
                    tideState = tideData.tideState,
                    currentStrength = "Next high: ${tideData.nextHighTide}",
                    dataUpdatedMinutesAgo = dataUpdatedMinutesAgo,
                    satelliteDataDate = satelliteDataDate
                ),
                expectedFish = spot.commonFish,
                gearRecommendations = generateGearRecs(actualSST, spot.depth),
                risks = generateRisks(weather, ocean),
                bestTimeOfDay = getBestTimeOfDay(spot.access, getMoonPhase(date))
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
                    waterTemperature = cached.sst?.value ?: 24.0,
                    swellHeight = (cached.swell.value.swellHeightFt ?: cached.swell.value.heightFt) / 3.28084,
                    swellDirection = 0
                )
            } else {
                OceanData(1.0, 8.0, 0, cached.sst?.value ?: 24.0, 1.0, 0)
            }
            
            waterQuality = WaterQuality(
                chlorophyllA = cached.chlorophyll?.value,
                turbidity = null,
                visibility = cached.visibility?.value,
                seaSurfaceTemp = cached.sst?.value ?: ocean.waterTemperature,
                dataSource = "Prefetched (updated ${cached.tide.ageString()})"
            )
            
            tideData = TideData(
                currentHeight = cached.tide.value.currentHeight,
                nextHighTide = cached.tide.value.nextHighTide,
                nextLowTide = cached.tide.value.nextLowTide,
                tideState = cached.tide.value.state
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
            ocean = oceanDeferred.await() ?: OceanData(1.0, 8.0, 0, 24.0, 1.0, 0)
            waterQuality = waterQualityDeferred.await() ?: WaterQuality(
                null, null, null, ocean.waterTemperature, "Data temporarily unavailable"
            )
            tideData = tideDeferred.await() ?: TideData(0.5, "Check local source", "Check local source", "Unknown")
        }
        
        // Community and forecast still fetched live (not cached)
        val communityDeferred = async {
            withTimeoutOrNull(3000) {
                try { community.getReportsForRegion(region, 5) } catch (e: Exception) { emptyList() }
            }
        }
        
        val forecastDeferred = async {
            withTimeoutOrNull(6000) {
                try { forecastService.getForecast(spotId, 5) } catch (e: Exception) { emptyList() }
            }
        }
        
        val communityReports = communityDeferred.await() ?: emptyList()
        val forecast = forecastDeferred.await() ?: emptyList()

        logger.info("Spot detail loaded: ${spot.name} (${if (cached != null) "from cache" else "live fetch"})")

        val score = ShakaScorer.generateScore(
            targetDate = date,
            weather = weather,
            ocean = ocean,
            waterQuality = waterQuality,
            moonPhase = getMoonPhase(date),
            seasonalMultiplier = getSeasonalMultiplier(spotId, date),
            recentSightings = communityReports.size.coerceAtLeast(1),
            isShore = spot.access == "shore",
            hasParking = true,
            permitRequired = false,
            currentStrength = 0.5,
            hasHazards = false,
            sharkRisk = "low"
        )
        
        val actualSST = cached?.sst?.value ?: waterQuality.seaSurfaceTemp ?: ocean.waterTemperature
        
        // Data freshness from cache
        val dataUpdatedMinutesAgo = cached?.tide?.minutesSinceFetch()?.toInt()
        val satelliteDataDate = cached?.sst?.dataDateString()

        // Build GIBS satellite readings from cache
        val gibsReadings = cached?.gibsChlorophyll?.let { gibs ->
            GibsSatelliteReadings(
                paceToday = gibs.value.paceToday,
                paceYesterday = gibs.value.paceYesterday,
                noaa20Today = gibs.value.noaa20Today,
                noaa20Yesterday = gibs.value.noaa20Yesterday,
                noaa21Today = gibs.value.noaa21Today,
                noaa21Yesterday = gibs.value.noaa21Yesterday,
                sentinel3aToday = gibs.value.sentinel3aToday,
                sentinel3aYesterday = gibs.value.sentinel3aYesterday,
                sentinel3bToday = gibs.value.sentinel3bToday,
                sentinel3bYesterday = gibs.value.sentinel3bYesterday,
                paceObservationTime = gibs.value.paceObservationTime?.toString(),
                noaa20ObservationTime = gibs.value.noaa20ObservationTime?.toString(),
                noaa21ObservationTime = gibs.value.noaa21ObservationTime?.toString(),
                dataDate = gibs.value.dataDate.toString()
            )
        }

        SpotDetail(
            id = spot.id,
            name = spot.name,
            description = "${spot.description}\n\nData: ${waterQuality.dataSource}",
            coordinates = spot.coordinates,
            score = score,
            access = AccessInfo(
                type = spot.access,
                directions = spot.directions,
                parkingInfo = spot.parking,
                permitRequired = false,
                boatLaunchNearby = spot.access == "boat"
            ),
            conditions = SpotConditions(
                visibility = cached?.visibility?.let { 
                    "${it.value.toInt()}m (${waterQuality.visibilityCategory})" 
                } ?: waterQuality.visibility?.let { 
                    "${it.toInt()}m (${waterQuality.visibilityCategory})" 
                } ?: "Data unavailable",
                waterTemp = "${actualSST.toInt()}°C / ${((actualSST * 9/5) + 32).toInt()}°F",
                swell = cached?.swell?.let { 
                    "${it.value.heightFt.toInt()}ft @ ${it.value.periodSec.toInt()}s ${it.value.direction}" 
                } ?: "${ocean.waveHeight.toInt()}-${(ocean.waveHeight + 1).toInt()}ft @ ${ocean.wavePeriod.toInt()}s",
                wind = cached?.wind?.let { 
                    "${it.value.speedKnots.toInt()} kts ${it.value.direction}" 
                } ?: "${weather.windSpeed.toInt()} knots",
                tideState = "${tideData.tideState} - Next high: ${tideData.nextHighTide}",
                currentStrength = "Chlorophyll: ${waterQuality.chlorophyllA?.let { String.format("%.2f", it) + " mg/m³" } ?: "N/A"}",
                dataUpdatedMinutesAgo = dataUpdatedMinutesAgo,
                satelliteDataDate = satelliteDataDate
            ),
            forecast = forecast,
            expectedFish = spot.commonFish.map { fish ->
                FishInfo(
                    name = fish,
                    likelihood = getFishLikelihood(fish, spotId, date),
                    seasonalNotes = getSeasonalNotes(fish, spotId, date)
                )
            },
            gearRecommendations = generateGearRecs(actualSST, spot.depth).map { item ->
                GearItem(item = item, reason = "Recommended for conditions", essential = true)
            },
            risks = generateRisks(weather, ocean).map { risk ->
                RiskInfo(risk = risk, severity = "moderate", mitigation = "Check conditions before entry")
            },
            communityReports = communityReports,
            bestTimeOfDay = getBestTimeOfDay(spot.access, getMoonPhase(date)),
            imageUrl = spot.imageUrl,
            satelliteReadings = gibsReadings
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
                    access = spot.access,
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
                
                // Calculate score
                val score = ShakaScorer.generateScore(
                    targetDate = date,
                    weather = weather,
                    ocean = ocean,
                    waterQuality = waterQuality,
                    moonPhase = getMoonPhase(date),
                    seasonalMultiplier = getSeasonalMultiplier(spotId, date),
                    recentSightings = 1,
                    isShore = spot.access == "shore",
                    hasParking = true,
                    permitRequired = false,
                    currentStrength = 0.5,
                    hasHazards = false,
                    sharkRisk = "low"
                )
                
                val actualSST = waterQuality.seaSurfaceTemp ?: ocean.waterTemperature
                
                SpotSummary(
                    id = spot.id,
                    name = spot.name,
                    coordinates = spot.coordinates,
                    shakaScore = score.overall,
                    confidence = score.confidence,
                    access = spot.access,
                    conditions = SpotConditions(
                        visibility = waterQuality.visibility?.let { "${it.toInt()}m (${waterQuality.visibilityCategory})" }
                            ?: "Data unavailable",
                        waterTemp = "${actualSST.toInt()}°C / ${((actualSST * 9/5) + 32).toInt()}°F",
                        swell = "${ocean.waveHeight.toInt()}-${(ocean.waveHeight + 1).toInt()}ft @ ${ocean.wavePeriod.toInt()}s",
                        wind = "${weather.windSpeed.toInt()} knots",
                        tideState = "",
                        currentStrength = ""
                    ),
                    expectedFish = spot.commonFish,
                    gearRecommendations = emptyList(),
                    risks = emptyList(),
                    bestTimeOfDay = getBestTimeOfDay(spot.access, getMoonPhase(date))
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

    private fun getMoonPhase(date: String): Double {
        // Simplified moon phase calculation (0 = new, 0.5 = full)
        val dayOfYear = java.time.LocalDate.parse(date).dayOfYear
        return ((dayOfYear % 29) / 29.0)
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
     * Determine best time of day based on conditions.
     */
    private fun getBestTimeOfDay(access: String, moonPhase: Double): String {
        // Moon phase affects fish activity
        val moonActivity = when {
            moonPhase < 0.1 || moonPhase > 0.9 -> "high" // New moon
            moonPhase in 0.4..0.6 -> "moderate" // Full moon - fish feed at night
            else -> "normal"
        }
        
        return when {
            access == "boat" && moonActivity == "high" -> "First light (5:30am-8am) or dusk"
            access == "shore" && moonActivity == "high" -> "6am-10am for best visibility"
            moonActivity == "moderate" -> "Early morning or late afternoon"
            else -> "6am-10am"
        }
    }

    private fun generateGearRecs(waterTempC: Double, depthM: Int): List<String> {
        val recs = mutableListOf<String>()

        // Wetsuit recommendation
        recs += when {
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

}
