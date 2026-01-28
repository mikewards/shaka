package com.shaka.data.client

import com.shaka.model.Coordinates
import kotlin.math.*

/**
 * In-memory spot database.
 * In production, this would be replaced with PostgreSQL.
 */
object SpotDatabase {

    data class SpotRecord(
        val id: String,
        val name: String,
        val description: String,
        val coordinates: Coordinates,
        val access: String, // "shore" or "boat"
        val depth: Int, // meters
        val commonFish: List<String>,
        val directions: String,
        val parking: String,
        val imageUrl: String? = null
    )

    // Sample spots - would come from database in production
    private val spots = listOf(
        // Hawaii - Oahu
        SpotRecord(
            id = "oahu-sharks-cove",
            name = "Shark's Cove",
            description = "Famous north shore snorkeling and spearfishing spot with protected cove and reef system.",
            coordinates = Coordinates(21.6494, -158.0628),
            access = "shore",
            depth = 8,
            commonFish = listOf("Uhu (Parrotfish)", "Kole", "Manini", "Menpachi"),
            directions = "Located on Kamehameha Highway between Waimea Bay and Sunset Beach",
            parking = "Free parking lot across the street"
        ),
        SpotRecord(
            id = "oahu-electric-beach",
            name = "Electric Beach (Kahe Point)",
            description = "Warm water outflow from power plant attracts diverse marine life including dolphins and turtles.",
            coordinates = Coordinates(21.3544, -158.1311),
            access = "shore",
            depth = 15,
            commonFish = listOf("Mu (Bigeye Emperor)", "Uku", "Omilu", "Tako (Octopus)"),
            directions = "West side of Oahu, past Ko Olina resort",
            parking = "Small parking area along highway"
        ),
        SpotRecord(
            id = "oahu-three-tables",
            name = "Three Tables",
            description = "Named for three flat reef formations. Clear water and abundant reef fish.",
            coordinates = Coordinates(21.6458, -158.0575),
            access = "shore",
            depth = 10,
            commonFish = listOf("Kole", "Palani", "Toau", "Weke"),
            directions = "North Shore, between Shark's Cove and Waimea Bay",
            parking = "Beach parking lot"
        ),

        // Hawaii - Big Island
        SpotRecord(
            id = "kona-honaunau-bay",
            name = "Honaunau Bay (Two Step)",
            description = "Crystal clear waters with easy entry. Excellent for all skill levels.",
            coordinates = Coordinates(19.4219, -155.9128),
            access = "shore",
            depth = 20,
            commonFish = listOf("Uku", "Mu", "Uhu", "Kole"),
            directions = "South Kona, near Pu'uhonua o Honaunau National Park",
            parking = "Paid parking at nearby lot"
        ),
        SpotRecord(
            id = "kona-keauhou-bay",
            name = "Keauhou Bay",
            description = "Deep bay with pelagic fish opportunities. Manta ray cleaning station nearby.",
            coordinates = Coordinates(19.5547, -155.9669),
            access = "shore",
            depth = 25,
            commonFish = listOf("Ono (Wahoo)", "Ahi (Yellowfin)", "Ulua (Giant Trevally)"),
            directions = "South of Kailua-Kona town",
            parking = "Small lot at boat ramp"
        ),

        // California
        SpotRecord(
            id = "socal-catalina-blue-cavern",
            name = "Blue Cavern Point",
            description = "Catalina Island's premier spearfishing destination with kelp forests and abundant game fish.",
            coordinates = Coordinates(33.4469, -118.4875),
            access = "boat",
            depth = 30,
            commonFish = listOf("White Seabass", "Yellowtail", "Calico Bass", "Sheephead"),
            directions = "Boat access from Long Beach or San Pedro",
            parking = "Marina parking at departure point"
        ),
        SpotRecord(
            id = "socal-la-jolla-cove",
            name = "La Jolla Cove",
            description = "Marine protected area with exceptional visibility. Some areas open to spearfishing.",
            coordinates = Coordinates(32.8508, -117.2711),
            access = "shore",
            depth = 15,
            commonFish = listOf("Sheephead", "Calico Bass", "Opaleye", "Halibut"),
            directions = "Downtown La Jolla, San Diego",
            parking = "Street parking and paid lots"
        ),

        // Florida
        SpotRecord(
            id = "florida-keys-sombrero",
            name = "Sombrero Reef",
            description = "Large reef system in the Florida Keys with diverse tropical species.",
            coordinates = Coordinates(24.6258, -81.1097),
            access = "boat",
            depth = 18,
            commonFish = listOf("Hogfish", "Mutton Snapper", "Black Grouper", "Cobia"),
            directions = "Boat from Marathon Key",
            parking = "Marina parking"
        ),

        // Mexico - Baja
        SpotRecord(
            id = "baja-cabo-pulmo",
            name = "Cabo Pulmo",
            description = "One of the most successful marine reserves. Incredible biodiversity after 20+ years of protection.",
            coordinates = Coordinates(23.4414, -109.4264),
            access = "shore",
            depth = 20,
            commonFish = listOf("Pargo (Snapper)", "Cabrilla", "Roosterfish", "Jack Crevalle"),
            directions = "East Cape of Baja California Sur",
            parking = "Village parking"
        ),

        // Caribbean
        SpotRecord(
            id = "bahamas-tongue-ocean",
            name = "Tongue of the Ocean",
            description = "Deep water drop-off attracting large pelagics. World-class bluewater hunting.",
            coordinates = Coordinates(24.2500, -77.5000),
            access = "boat",
            depth = 40,
            commonFish = listOf("Wahoo", "Mahi Mahi", "Yellowfin Tuna", "Marlin"),
            directions = "Boat from Nassau or Andros",
            parking = "Marina facilities"
        )
    )

    fun getSpotsNear(lat: Double, lon: Double, radiusKm: Int): List<SpotRecord> {
        return spots.filter { spot ->
            haversineDistance(lat, lon, spot.coordinates.lat, spot.coordinates.lon) <= radiusKm
        }
    }

    fun getSpot(id: String): SpotRecord? {
        return spots.find { it.id == id }
    }

    fun getAllSpots(): List<SpotRecord> = spots

    /**
     * Calculate distance between two points using Haversine formula.
     */
    private fun haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val r = 6371.0 // Earth's radius in km

        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)

        val a = sin(dLat / 2).pow(2) +
                cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) *
                sin(dLon / 2).pow(2)

        val c = 2 * asin(sqrt(a))

        return r * c
    }
}
