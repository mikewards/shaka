package com.shaka.fishing_intel.processing

import com.shaka.fishing_intel.models.GeoType

/**
 * Result of resolving a report's location to coordinates.
 * Used by ingest to geotag BD Outdoors (and future) forum posts.
 */
data class ResolvedGeo(
    val lat: Double,
    val lon: Double,
    val radiusM: Int,
    val geoType: GeoType
)

/**
 * Region-aware geo resolution for forum ingest.
 * For sourceId "bd-outdoors" we use SoCal resolver (zone + locationMentioned).
 * Other sources can plug in later.
 */
object GeoResolver {

    // SoCal zone defaults (threadZone from BD forum: Inshore, Offshore, Islands, Bay / Harbor)
    private val SOCAL_ZONE_DEFAULTS = mapOf(
        "inshore" to ResolvedGeo(33.6, -117.9, 40_000, GeoType.REGION_FALLBACK),
        "offshore" to ResolvedGeo(32.5, -117.5, 80_000, GeoType.REGION_FALLBACK),
        "islands" to ResolvedGeo(33.38, -118.42, 35_000, GeoType.REGION_FALLBACK),
        "bay / harbor" to ResolvedGeo(32.72, -117.23, 25_000, GeoType.REGION_FALLBACK),
        "bay" to ResolvedGeo(32.72, -117.23, 25_000, GeoType.REGION_FALLBACK),
        "harbor" to ResolvedGeo(32.72, -117.23, 25_000, GeoType.REGION_FALLBACK)
    )

    private val SOCAL_FALLBACK = ResolvedGeo(32.7157, -117.1611, 150_000, GeoType.REGION_FALLBACK)

    /**
     * Resolve (sourceId, threadZone, locationMentioned) to lat/lon/radius for ingest.
     * Returns null only if source is unknown; otherwise always returns a geo (with fallback).
     */
    fun resolve(sourceId: String, threadZone: String?, locationMentioned: String?): ResolvedGeo? {
        if (sourceId != "bd-outdoors") return null
        return resolveSoCal(threadZone, locationMentioned)
    }

    private fun resolveSoCal(threadZone: String?, locationMentioned: String?): ResolvedGeo {
        // 1) Try locationMentioned -> landing or named place
        if (!locationMentioned.isNullOrBlank()) {
            val landing = SoCalLandings.findByName(locationMentioned)
            if (landing != null) {
                return ResolvedGeo(
                    landing.lat,
                    landing.lon,
                    landing.radiusKm * 1000,
                    GeoType.PLACE_MENTION
                )
            }
            val place = SoCalGazetteer.PLACES.firstOrNull { place ->
                place.name.equals(locationMentioned, ignoreCase = true) ||
                place.aliases.any { locationMentioned.equals(it, ignoreCase = true) }
            }
            if (place != null) {
                return ResolvedGeo(
                    place.lat,
                    place.lon,
                    place.radiusKm * 1000,
                    GeoType.PLACE_MENTION
                )
            }
            // Loose match: any gazetteer place whose name or alias appears in the string
            val lower = locationMentioned.lowercase()
            val matched = SoCalGazetteer.PLACES.firstOrNull { p ->
                lower.contains(p.name.lowercase()) || p.aliases.any { lower.contains(it) }
            }
            if (matched != null) {
                return ResolvedGeo(
                    matched.lat,
                    matched.lon,
                    matched.radiusKm * 1000,
                    GeoType.PLACE_MENTION
                )
            }
        }
        // 2) Zone default
        if (!threadZone.isNullOrBlank()) {
            val key = threadZone.trim().lowercase()
            SOCAL_ZONE_DEFAULTS[key]?.let { return it }
        }
        // 3) Fallback
        return SOCAL_FALLBACK
    }
}
