package com.shaka.data.client

import io.ktor.client.*
import io.ktor.client.engine.cio.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory
import java.net.URLEncoder

/**
 * Client for ProtectedSeas Navigator - Esri Feature Service.
 * Provides Marine Protected Area (MPA) data by coordinates.
 * 
 * Free, no authentication required.
 * Coverage: 70+ countries including USA, Caribbean, Europe, Pacific.
 * Last updated: December 2025.
 * 
 * API: https://services9.arcgis.com/lm7wE8a9YA9rKfzy/arcgis/rest/services/Navigator_AllSites_010925_attributes/FeatureServer/0
 */
class ProtectedSeasClient {
    
    private val logger = LoggerFactory.getLogger(ProtectedSeasClient::class.java)
    
    private val client = HttpClient(CIO) {
        engine {
            requestTimeout = 10_000 // 10 seconds
        }
        install(ContentNegotiation) {
            json(Json {
                ignoreUnknownKeys = true
                isLenient = true
            })
        }
    }

    companion object {
        private const val BASE_URL = "https://services9.arcgis.com/lm7wE8a9YA9rKfzy/arcgis/rest/services/Navigator_AllSites_010925_attributes/FeatureServer/0/query"
    }

    /**
     * Get MPA (Marine Protected Area) status for a location.
     * 
     * @param lat Latitude
     * @param lon Longitude
     * @return MPAInfo with protection details, or null if no specific MPA found
     */
    suspend fun getMPAStatus(lat: Double, lon: Double): MPAInfo? {
        return try {
            // JSON geometry format is REQUIRED - simple "lon,lat" doesn't work reliably
            val geometry = URLEncoder.encode(
                """{"x":$lon,"y":$lat,"spatialReference":{"wkid":4326}}""",
                "UTF-8"
            )
            
            val url = "$BASE_URL?" +
                "geometry=$geometry" +
                "&geometryType=esriGeometryPoint" +
                "&spatialRel=esriSpatialRelIntersects" +
                "&distance=1500" +                    // 1.5km buffer - catches nearby MPAs
                "&units=esriSRUnit_Meter" +           // Buffer distance in meters
                "&outFields=site_name,spear_fishing,species_of_concern,purpose,lfp,navigator_link,designation" +
                "&returnGeometry=false" +  // Don't return polygon geometry (huge!)
                "&f=json"
            
            logger.debug("Fetching MPA data: $url")
            val response: String = client.get(url).bodyAsText()
            
            parseMPAResponse(response)
        } catch (e: Exception) {
            logger.warn("MPA data fetch failed for ($lat, $lon): ${e.message}")
            null
        }
    }

    /**
     * Parse MPA response and select the most relevant/restrictive zone.
     * Spatial queries often return multiple overlapping zones (EEZ, state waters, sanctuaries).
     */
    private fun parseMPAResponse(jsonResponse: String): MPAInfo? {
        try {
            val json = Json { ignoreUnknownKeys = true }
            val response = json.decodeFromString<EsriQueryResponse>(jsonResponse)
            
            if (response.features.isEmpty()) {
                logger.debug("No MPA features found")
                return null
            }
            
            logger.debug("Found ${response.features.size} MPA features")
            
            // PRIORITY 1: Find Marine Life Conservation Districts (MLCDs) - most relevant for spearfishing
            val mlcds = response.features.filter { feature ->
                val designation = feature.attributes.designation ?: ""
                designation.contains("Marine Life Conservation District", ignoreCase = true) ||
                designation.contains("MLCD", ignoreCase = true)
            }
            
            // PRIORITY 2: If no MLCD, look for sanctuaries/reserves with spearfishing restrictions
            val sanctuaries = response.features.filter { feature ->
                val designation = feature.attributes.designation ?: ""
                val spearStatus = feature.attributes.spear_fishing ?: 3
                spearStatus == 1 && (  // Has spearfishing prohibition
                    designation.contains("Sanctuary", ignoreCase = true) ||
                    designation.contains("Reserve", ignoreCase = true) ||
                    designation.contains("Conservation", ignoreCase = true)
                )
            }
            
            // PRIORITY 3: Filter out generic/irrelevant zones
            val filtered = response.features.filter { feature ->
                val designation = feature.attributes.designation ?: ""
                val siteName = feature.attributes.site_name ?: ""
                
                designation != "Jurisdictional Authority" &&
                designation != "Recreational Activity Area" &&
                designation != "Restricted Area" &&
                !siteName.contains("EEZ") &&
                !siteName.contains("State Waters") &&
                !siteName.contains("Territorial Sea") &&
                !siteName.contains("Longline", ignoreCase = true) &&
                !siteName.contains("Thrill Craft", ignoreCase = true) &&
                !siteName.contains("Speed Zone", ignoreCase = true) &&
                !siteName.contains("Zone A", ignoreCase = true) &&
                !siteName.contains("Zone B", ignoreCase = true) &&
                !siteName.contains("Zone C", ignoreCase = true) &&
                !siteName.contains("Zone D", ignoreCase = true) &&
                !siteName.contains("Zone E", ignoreCase = true)
            }
            
            // Select best result: MLCD > Sanctuary > Filtered > Any
            val relevantMPAs = mlcds.ifEmpty { sanctuaries.ifEmpty { filtered.ifEmpty { response.features } } }
            
            // Sort by: spearfishing=1 first (prohibited), then highest LFP
            val selected = relevantMPAs
                .sortedWith(
                    compareBy<EsriFeature> { it.attributes.spear_fishing ?: 3 }  // 1 (prohibited) first
                        .thenByDescending { it.attributes.lfp ?: 0 }
                )
                .firstOrNull()
            
            return selected?.toMPAInfo()
        } catch (e: Exception) {
            logger.warn("MPA response parsing failed: ${e.message}")
            return null
        }
    }

    /**
     * Check if a point is EXACTLY inside an MPA (no buffer).
     * Use this after getMPAStatus returns data to determine if spot is inside vs nearby.
     * 
     * @param lat Latitude
     * @param lon Longitude
     * @return MPAInfo if the point is inside an MPA boundary, null if not
     */
    suspend fun getMPAStatusExact(lat: Double, lon: Double): MPAInfo? {
        return try {
            // JSON geometry format is REQUIRED - simple "lon,lat" doesn't work reliably
            val geometry = URLEncoder.encode(
                """{"x":$lon,"y":$lat,"spatialReference":{"wkid":4326}}""",
                "UTF-8"
            )
            
            // NO distance parameter - exact intersection only
            val url = "$BASE_URL?" +
                "geometry=$geometry" +
                "&geometryType=esriGeometryPoint" +
                "&spatialRel=esriSpatialRelIntersects" +
                "&outFields=site_name,spear_fishing,species_of_concern,purpose,lfp,navigator_link,designation" +
                "&returnGeometry=false" +
                "&f=json"
            
            logger.debug("Fetching exact MPA data: $url")
            val response: String = client.get(url).bodyAsText()
            
            parseMPAResponse(response)
        } catch (e: Exception) {
            logger.warn("Exact MPA check failed for ($lat, $lon): ${e.message}")
            null
        }
    }

    private fun EsriFeature.toMPAInfo(): MPAInfo {
        return MPAInfo(
            siteName = attributes.site_name,
            designation = attributes.designation,
            spearfishingStatus = attributes.spear_fishing ?: 3,  // Default to unknown
            protectionLevel = attributes.lfp ?: 0,
            speciesOfConcern = attributes.species_of_concern,
            purpose = attributes.purpose,
            detailsUrl = attributes.navigator_link
        )
    }
}

/**
 * MPA information from ProtectedSeas Navigator.
 */
data class MPAInfo(
    val siteName: String?,
    val designation: String?,
    val spearfishingStatus: Int,        // 0=Allowed, 1=Prohibited, 2=Restricted, 3=Unknown
    val protectionLevel: Int,           // 1-5 Level of Fishing Protection (higher = more protected)
    val speciesOfConcern: String?,
    val purpose: String?,
    val detailsUrl: String?
)

// Esri API response data classes
@Serializable
data class EsriQueryResponse(
    val features: List<EsriFeature> = emptyList()
)

@Serializable
data class EsriFeature(
    val attributes: EsriAttributes
)

@Serializable
data class EsriAttributes(
    val site_name: String? = null,
    val spear_fishing: Int? = null,        // 0=Allowed, 1=Prohibited, 2=Restricted, 3=Unknown
    val species_of_concern: String? = null,
    val purpose: String? = null,
    val lfp: Int? = null,                  // 1-5, higher = more protected
    val navigator_link: String? = null,
    val designation: String? = null
)
