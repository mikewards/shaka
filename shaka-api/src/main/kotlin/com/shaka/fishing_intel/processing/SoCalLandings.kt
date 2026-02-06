package com.shaka.fishing_intel.processing

import com.shaka.fishing_intel.models.Landing

/**
 * SoCal fishing landings with coordinates.
 * Used for geotagging reports to spot locations.
 */
object SoCalLandings {
    val ALL = listOf(
        // San Diego Region
        Landing("Fisherman's Landing", "fishermans", "San Diego", 32.7231, -117.2341, 35),
        Landing("H&M Landing", "hm_landing", "San Diego", 32.7231, -117.2331, 35),
        Landing("Point Loma Sportfishing", "point_loma", "San Diego", 32.7201, -117.2361, 35),
        Landing("Seaforth Landing", "seaforth", "San Diego", 32.7572, -117.2381, 35),
        
        // North San Diego County
        Landing("Oceanside Sea Center", "oceanside", "Oceanside", 33.1959, -117.3814, 25),
        
        // Orange County
        Landing("Dana Wharf Sportfishing", "dana_wharf", "Dana Point", 33.4594, -117.6981, 25),
        Landing("Newport Landing", "newport", "Newport Beach", 33.6054, -117.9301, 25),
        Landing("Davey's Locker", "daveys_locker", "Newport Beach", 33.6046, -117.9303, 25),
        
        // LA County - South Bay
        Landing("22nd Street Landing", "22nd_street", "San Pedro", 33.7219, -118.2732, 30),
        Landing("Long Beach Sportfishing", "long_beach", "Long Beach", 33.7601, -118.2001, 25),
        Landing("Redondo Sportfishing", "redondo", "Redondo Beach", 33.8461, -118.3969, 25),
        Landing("Marina Del Rey Sportfishing", "marina_del_rey", "Marina Del Rey", 33.9716, -118.4445, 25),
        
        // Ventura County
        Landing("Channel Islands Sportfishing", "channel_islands", "Oxnard", 34.1592, -119.2241, 30),
        Landing("Cisco's Sportfishing", "cisco", "Oxnard", 34.1589, -119.2238, 30),
        
        // Santa Barbara / Central Coast
        Landing("Santa Barbara Landing", "santa_barbara", "Santa Barbara", 34.4041, -119.6858, 30),
        Landing("Morro Bay Landing", "morro_bay", "Morro Bay", 35.3658, -120.8541, 30)
    )
    
    private val BY_NORMALIZED = ALL.associateBy { it.normalizedName }
    private val NAME_VARIATIONS = mapOf(
        "fishermans landing" to "fishermans",
        "fisherman's landing" to "fishermans",
        "fisherman's" to "fishermans",
        "fishermans" to "fishermans",
        "h&m landing" to "hm_landing",
        "h & m landing" to "hm_landing",
        "h&m" to "hm_landing",
        "point loma sportfishing" to "point_loma",
        "point loma" to "point_loma",
        "seaforth landing" to "seaforth",
        "seaforth" to "seaforth",
        "oceanside sea center" to "oceanside",
        "oceanside" to "oceanside",
        "dana wharf sportfishing" to "dana_wharf",
        "dana wharf" to "dana_wharf",
        "newport landing" to "newport",
        "newport" to "newport",
        "davey's locker" to "daveys_locker",
        "daveys locker" to "daveys_locker",
        "22nd street landing" to "22nd_street",
        "22nd street" to "22nd_street",
        "san pedro 22nd street sportfishing" to "22nd_street",
        "long beach sportfishing" to "long_beach",
        "long beach" to "long_beach",
        "redondo sportfishing" to "redondo",
        "redondo sport fishing" to "redondo",
        "redondo" to "redondo",
        "marina del rey sportfishing" to "marina_del_rey",
        "marina del rey" to "marina_del_rey",
        "channel islands sportfishing" to "channel_islands",
        "channel islands" to "channel_islands",
        "santa barbara landing" to "santa_barbara",
        "santa barbara" to "santa_barbara",
        "morro bay landing" to "morro_bay",
        "morro bay" to "morro_bay"
    )
    
    fun findByName(name: String): Landing? {
        val normalized = name.lowercase().trim()
        val key = NAME_VARIATIONS[normalized] ?: normalized.replace(" ", "_")
        return BY_NORMALIZED[key]
    }
}
