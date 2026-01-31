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
            
            // Filter out generic jurisdictional zones to find specific MPAs
            val specificMPAs = response.features.filter { feature ->
                val designation = feature.attributes.designation ?: ""
                val siteName = feature.attributes.site_name ?: ""
                
                designation != "Jurisdictional Authority" &&
                !siteName.contains("EEZ") &&
                !siteName.contains("State Waters") &&
                !siteName.contains("Territorial Sea")
            }
            
            // If specific MPAs exist, use those; otherwise fall back to all features
            val relevantMPAs = specificMPAs.ifEmpty { response.features }
            
            // Priority: highest LFP (5=most protected), then spearfishing=1 (prohibited)
            val selected = relevantMPAs
                .sortedWith(
                    compareByDescending<EsriFeature> { it.attributes.lfp ?: 0 }
                        .thenBy { it.attributes.spear_fishing ?: 3 }  // 1 (prohibited) < 2 (restricted) < 3 (unknown)
                )
                .firstOrNull()
            
            return selected?.toMPAInfo()
        } catch (e: Exception) {
            logger.warn("MPA response parsing failed: ${e.message}")
            return null
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
