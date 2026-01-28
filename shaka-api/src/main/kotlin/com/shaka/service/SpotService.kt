package com.shaka.service

import com.shaka.data.client.CommunityClient
import com.shaka.data.client.CopernicusClient
import com.shaka.data.client.OpenMeteoClient
import com.shaka.data.client.SpotDatabase
import com.shaka.model.*
import com.shaka.scoring.ShakaScorer

/**
 * Service for searching and retrieving spearfishing spots.
 */
class SpotService {

    private val openMeteo = OpenMeteoClient()
    private val copernicus = CopernicusClient()
    private val community = CommunityClient()
    private val spotDb = SpotDatabase

    /**
     * Search for spots within radius of a location.
     */
    suspend fun searchSpots(lat: Double, lon: Double, radiusKm: Int, date: String): SearchResponse {
        // Get spots from database within radius
        val nearbySpots = spotDb.getSpotsNear(lat, lon, radiusKm)

        // Fetch weather and ocean data for the area
        val weather = openMeteo.getWeather(lat, lon, date)
        val ocean = openMeteo.getMarineData(lat, lon, date)
        val waterQuality = copernicus.getWaterQuality(lat, lon, date)

        // Score each spot
        val scoredSpots = nearbySpots.map { spot ->
            val score = ShakaScorer.generateScore(
                targetDate = date,
                weather = weather,
                ocean = ocean,
                waterQuality = waterQuality,
                moonPhase = getMoonPhase(date),
                seasonalMultiplier = getSeasonalMultiplier(spot.id, date),
                recentSightings = 3, // TODO: Get from community data
                isShore = spot.access == "shore",
                hasParking = true,
                permitRequired = false,
                currentStrength = 0.5,
                hasHazards = false,
                sharkRisk = "low"
            )

            SpotSummary(
                id = spot.id,
                name = spot.name,
                coordinates = spot.coordinates,
                shakaScore = score.overall,
                confidence = score.confidence,
                access = spot.access,
                conditions = SpotConditions(
                    visibility = "${waterQuality.visibility?.toInt() ?: 15}m",
                    waterTemp = "${ocean.waterTemperature.toInt()}C",
                    swell = "${ocean.waveHeight.toInt()}-${(ocean.waveHeight + 1).toInt()}ft",
                    wind = "${weather.windSpeed.toInt()} knots",
                    tideState = "rising"
                ),
                expectedFish = spot.commonFish,
                gearRecommendations = generateGearRecs(ocean.waterTemperature, spot.depth),
                risks = generateRisks(weather, ocean),
                bestTimeOfDay = "6am-10am"
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
        val spot = spotDb.getSpot(spotId) ?: return null

        val weather = openMeteo.getWeather(spot.coordinates.lat, spot.coordinates.lon, date)
        val ocean = openMeteo.getMarineData(spot.coordinates.lat, spot.coordinates.lon, date)

        val score = ShakaScorer.generateScore(
            targetDate = date,
            weather = weather,
            ocean = ocean,
            waterQuality = null,
            moonPhase = getMoonPhase(date),
            seasonalMultiplier = getSeasonalMultiplier(spotId, date),
            recentSightings = 3,
            isShore = spot.access == "shore",
            hasParking = true,
            permitRequired = false,
            currentStrength = 0.5,
            hasHazards = false,
            sharkRisk = "low"
        )

        return SpotDetail(
            id = spot.id,
            name = spot.name,
            description = spot.description,
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
                visibility = "${(score.breakdown.visibility / 5)}m",
                waterTemp = "${ocean.waterTemperature.toInt()}C",
                swell = "${ocean.waveHeight.toInt()}-${(ocean.waveHeight + 1).toInt()}ft",
                wind = "${weather.windSpeed.toInt()} knots",
                tideState = "rising"
            ),
            forecast = emptyList(), // TODO: Generate multi-day forecast
            expectedFish = spot.commonFish.map { fish ->
                FishInfo(
                    name = fish,
                    likelihood = "likely",
                    seasonalNotes = null
                )
            },
            gearRecommendations = generateGearRecs(ocean.waterTemperature, spot.depth).map { item ->
                GearItem(item = item, reason = "Recommended for conditions", essential = true)
            },
            risks = generateRisks(weather, ocean).map { risk ->
                RiskInfo(risk = risk, severity = "moderate", mitigation = "Check conditions before entry")
            },
            communityReports = emptyList(), // TODO: Fetch from Reddit/forums
            bestTimeOfDay = "6am-10am",
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
        // TODO: Implement seasonal fish patterns
        val month = java.time.LocalDate.parse(date).monthValue
        return when (month) {
            in 5..9 -> 1.3  // Summer - peak season
            in 3..4, in 10..11 -> 1.1  // Shoulder seasons
            else -> 0.9  // Winter
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
