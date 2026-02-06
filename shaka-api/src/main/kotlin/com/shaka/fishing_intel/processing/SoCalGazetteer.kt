package com.shaka.fishing_intel.processing

import com.shaka.fishing_intel.models.FishingGround

/**
 * Gazetteer of SoCal fishing grounds and places.
 * Used for extracting place mentions from narrative reports.
 */
object SoCalGazetteer {
    val PLACES = listOf(
        // Islands
        FishingGround("Catalina Island", 33.3891, -118.4168, 12, listOf("catalina", "cat", "avalon")),
        FishingGround("San Clemente Island", 32.9000, -118.5000, 15, listOf("san clemente", "clemente", "sci")),
        FishingGround("Coronado Islands", 32.4167, -117.2500, 8, listOf("coronados", "coronado", "the rocks")),
        FishingGround("Santa Barbara Island", 33.4758, -119.0297, 8, listOf("santa barbara island", "sbi")),
        FishingGround("San Nicolas Island", 33.2500, -119.5000, 10, listOf("san nicolas", "nicolas")),
        
        // Banks and Ridges
        FishingGround("Tanner Bank", 32.7000, -119.1500, 15, listOf("tanner", "tanner bank")),
        FishingGround("Cortes Bank", 32.4667, -119.1667, 12, listOf("cortes", "cortes bank")),
        FishingGround("9 Mile Bank", 32.6167, -117.4167, 8, listOf("9 mile", "nine mile", "9-mile")),
        FishingGround("43 Fathom Spot", 32.9500, -118.0000, 5, listOf("43 fathom")),
        
        // Kelp Beds and Reefs
        FishingGround("Horseshoe Kelp", 33.7500, -118.3500, 3, listOf("horseshoe")),
        FishingGround("La Jolla Kelp", 32.8328, -117.2713, 5, listOf("la jolla")),
        FishingGround("Point Loma Kelp", 32.6833, -117.2667, 5, listOf("point loma kelp")),
        FishingGround("Huntington Flats", 33.6200, -118.0500, 5, listOf("huntington")),
        FishingGround("Rocky Point", 33.7200, -118.4300, 4, listOf("rocky point", "rocky pt")),
        
        // Coastal Areas
        FishingGround("Palos Verdes", 33.7400, -118.4100, 8, listOf("pv", "palos verdes peninsula")),
        FishingGround("Dana Point", 33.4600, -117.7000, 6, listOf("dana")),
        FishingGround("San Diego Bay", 32.6500, -117.1500, 5, listOf("sd bay", "san diego bay")),
        FishingGround("Mission Bay", 32.7700, -117.2400, 4, listOf("mission bay")),
        
        // Offshore Zones
        FishingGround("The 302", 32.5000, -117.5000, 8, listOf("302")),
        FishingGround("The 425", 31.2500, -117.5000, 10, listOf("425")),
        FishingGround("Ridge", 31.5000, -118.0000, 12, listOf("the ridge")),
        FishingGround("Hidden Bank", 32.0000, -118.2000, 8, listOf("hidden", "hidden bank"))
    )
    
    fun findInText(text: String): List<FishingGround> {
        val lower = text.lowercase()
        return PLACES.filter { place ->
            lower.contains(place.name.lowercase()) ||
            place.aliases.any { alias -> lower.contains(alias) }
        }
    }
}
