package com.shaka.service

import com.shaka.data.cache.OceanDataCache
import com.shaka.data.client.CommunityClient
import com.shaka.data.client.CopernicusClient
import com.shaka.data.client.NOAATidesClient
import com.shaka.data.client.OpenMeteoClient
import com.shaka.data.client.SpotDatabase
import com.shaka.model.*
import com.shaka.scoring.ShakaScorer
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
     */
    suspend fun searchSpots(lat: Double, lon: Double, radiusKm: Int, date: String): SearchResponse {
        // Get spots from database within radius
        val nearbySpots = spotDb.findNearbySpots(lat, lon, radiusKm.toDouble())

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
        
        // Fetch ACTUAL MEASURED water quality from Copernicus L3 NRT
        // This is REAL satellite data (ZSD, CHL), NOT estimates
        val waterQuality = copernicus.getWaterQuality(lat, lon, date)
        
        // Fetch tide data (with caching)
        val tideData = OceanDataCache.getTide(lat, lon, date) ?: run {
            val data = tidesClient.getTideData(lat, lon, date)
            OceanDataCache.putTide(lat, lon, date, data)
            data
        }

        logger.info("Water quality for ($lat, $lon): vis=${waterQuality.visibility?.let { "${it.toInt()}m" } ?: "N/A"}, " +
                   "chl=${waterQuality.chlorophyllA?.let { String.format("%.2f", it) } ?: "N/A"} mg/m³ - ${waterQuality.dataSource}")

        // Get community sightings count for the region
        val regionReports = try {
            val region = inferRegionFromCoords(lat, lon)
            community.getReportsForRegion(region, 10)
        } catch (e: Exception) {
            emptyList()
        }
        val recentSightingsCount = regionReports.size.coerceAtLeast(1)

        // Score each spot
        val scoredSpots = nearbySpots.map { spot ->
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

            // Use real SST - prefer NOAA satellite data, fallback to Open-Meteo (both are real now!)
            val actualSST = waterQuality.seaSurfaceTemp ?: ocean.waterTemperature
            
            SpotSummary(
                id = spot.id,
                name = spot.name,
                coordinates = spot.coordinates,
                shakaScore = score.overall,
                confidence = score.confidence,
                access = spot.access,
                conditions = SpotConditions(
                    // ACTUAL MEASURED visibility from Copernicus L3 NRT (or "N/A" if unavailable)
                    visibility = waterQuality.visibility?.let { "${it.toInt()}m (${waterQuality.visibilityCategory})" } 
                        ?: "Data unavailable (cloud cover)",
                    waterTemp = "${actualSST.toInt()}°C / ${((actualSST * 9/5) + 32).toInt()}°F",
                    swell = "${ocean.waveHeight.toInt()}-${(ocean.waveHeight + 1).toInt()}ft @ ${ocean.wavePeriod.toInt()}s",
                    wind = "${weather.windSpeed.toInt()} knots",
                    tideState = tideData.tideState,
                    currentStrength = "Next high: ${tideData.nextHighTide}"
                ),
                expectedFish = spot.commonFish,
                gearRecommendations = generateGearRecs(actualSST, spot.depth),
                risks = generateRisks(weather, ocean),
                bestTimeOfDay = getBestTimeOfDay(spot.access, getMoonPhase(date))
            )
        }.sortedByDescending { it.shakaScore }

        return SearchResponse(
            spots = scoredSpots,
            searchCenter = Coordinates(lat, lon),
            radiusKm = radiusKm,
            date = date
        )
    }

    /**
     * Get detailed information for a specific spot.
     */
    suspend fun getSpotDetail(spotId: String, date: String): SpotDetail? {
        val spot = spotDb.findSpotById(spotId) ?: return null
        val lat = spot.coordinates.lat
        val lon = spot.coordinates.lon

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
        
        // Fetch water quality - already cached internally
        val waterQuality = copernicus.getWaterQuality(lat, lon, date)
        
        // Fetch tide data (with caching)
        val tideData = OceanDataCache.getTide(lat, lon, date) ?: run {
            val data = tidesClient.getTideData(lat, lon, date)
            OceanDataCache.putTide(lat, lon, date, data)
            data
        }

        logger.info("Water quality for ${spot.name}: vis=${waterQuality.visibility?.let { "${it.toInt()}m" } ?: "N/A"}, " +
                   "chl=${waterQuality.chlorophyllA?.let { String.format("%.2f", it) } ?: "N/A"} mg/m³")

        // Get community reports for the spot's region
        val region = inferRegionFromSpotId(spotId)
        val communityReports = try {
            community.getReportsForRegion(region, 5)
        } catch (e: Exception) {
            emptyList()
        }

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
        
        // Use real SST - prefer NOAA satellite data, fallback to Open-Meteo
        val actualSST = waterQuality.seaSurfaceTemp ?: ocean.waterTemperature

        // Generate 7-day forecast
        val forecast = forecastService.getForecast(spotId, 7)

        return SpotDetail(
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
                // ACTUAL MEASURED visibility from Copernicus L3 NRT satellite
                visibility = waterQuality.visibility?.let { "${it.toInt()}m (${waterQuality.visibilityCategory})" }
                    ?: "Data unavailable (cloud cover)",
                waterTemp = "${actualSST.toInt()}°C / ${((actualSST * 9/5) + 32).toInt()}°F",
                swell = "${ocean.waveHeight.toInt()}-${(ocean.waveHeight + 1).toInt()}ft @ ${ocean.wavePeriod.toInt()}s",
                wind = "${weather.windSpeed.toInt()} knots",
                tideState = "${tideData.tideState} - Next high: ${tideData.nextHighTide}",
                currentStrength = "Chlorophyll: ${waterQuality.chlorophyllA?.let { String.format("%.2f", it) + " mg/m³" } ?: "N/A"}"
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
            imageUrl = spot.imageUrl
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
