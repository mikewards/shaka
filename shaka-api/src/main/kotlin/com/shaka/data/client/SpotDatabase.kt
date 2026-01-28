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
        ),
        SpotRecord(
            id = "bahamas-grand-cay",
            name = "Grand Cay",
            description = "Remote Bahamas destination known for hogfish, grouper, and pristine reef systems.",
            coordinates = Coordinates(27.2167, -78.3167),
            access = "boat",
            depth = 25,
            commonFish = listOf("Hogfish", "Nassau Grouper", "Mutton Snapper", "Black Grouper"),
            directions = "Boat from West End, Grand Bahama",
            parking = "Marina at departure point"
        ),

        // French Polynesia
        SpotRecord(
            id = "tahiti-fakarava",
            name = "Fakarava South Pass",
            description = "UNESCO biosphere reserve with incredible shark aggregations and pelagic action.",
            coordinates = Coordinates(-16.4500, -145.4500),
            access = "boat",
            depth = 35,
            commonFish = listOf("Dogtooth Tuna", "Bluefin Trevally", "Napoleon Wrasse", "Wahoo"),
            directions = "Boat from Fakarava village",
            parking = "Dive operator pickup"
        ),
        SpotRecord(
            id = "tahiti-rangiroa",
            name = "Rangiroa Tiputa Pass",
            description = "World-famous pass dive with dolphins, sharks, and massive fish schools.",
            coordinates = Coordinates(-14.9500, -147.6167),
            access = "boat",
            depth = 40,
            commonFish = listOf("Mahi Mahi", "Yellowfin Tuna", "Giant Trevally", "Barracuda"),
            directions = "Boat from Avatoru village",
            parking = "Dive operator facilities"
        ),
        SpotRecord(
            id = "tahiti-moorea",
            name = "Moorea Outer Reef",
            description = "Beautiful reef system with excellent visibility and diverse species.",
            coordinates = Coordinates(-17.5333, -149.8333),
            access = "boat",
            depth = 20,
            commonFish = listOf("Parrotfish", "Surgeonfish", "Unicornfish", "Grouper"),
            directions = "Boat from Moorea ferry terminal",
            parking = "Resort or marina"
        ),

        // Mediterranean - Italy
        SpotRecord(
            id = "italy-sardinia-capo-caccia",
            name = "Capo Caccia",
            description = "Dramatic cliffs and caves with excellent grouper and dentex hunting.",
            coordinates = Coordinates(40.5667, 8.1667),
            access = "boat",
            depth = 30,
            commonFish = listOf("Grouper", "Dentex", "Amberjack", "Sea Bream"),
            directions = "Boat from Alghero",
            parking = "Alghero marina"
        ),
        SpotRecord(
            id = "italy-sicily-ustica",
            name = "Ustica Island",
            description = "Marine protected area with exceptional visibility and Mediterranean species.",
            coordinates = Coordinates(38.7000, 13.1833),
            access = "boat",
            depth = 35,
            commonFish = listOf("Amberjack", "Dentex", "Grouper", "Barracuda"),
            directions = "Ferry from Palermo",
            parking = "Ustica port"
        ),

        // Mediterranean - France
        SpotRecord(
            id = "france-corsica-scandola",
            name = "Scandola Reserve",
            description = "UNESCO World Heritage site with pristine Mediterranean waters.",
            coordinates = Coordinates(42.3667, 8.5500),
            access = "boat",
            depth = 25,
            commonFish = listOf("Dentex", "Grouper", "Sea Bass", "Bream"),
            directions = "Boat from Porto or Calvi",
            parking = "Marina facilities"
        ),
        SpotRecord(
            id = "france-marseille-riou",
            name = "Riou Island",
            description = "Offshore island with caves, walls, and excellent spearfishing.",
            coordinates = Coordinates(43.1833, 5.3833),
            access = "boat",
            depth = 30,
            commonFish = listOf("Sea Bass", "Dentex", "Grouper", "Bream"),
            directions = "Boat from Marseille Vieux-Port",
            parking = "Marseille marina"
        ),

        // UK
        SpotRecord(
            id = "uk-plymouth-breakwater",
            name = "Plymouth Breakwater",
            description = "Historic structure creating reef habitat with bass and pollock.",
            coordinates = Coordinates(50.3333, -4.1500),
            access = "boat",
            depth = 15,
            commonFish = listOf("Bass", "Pollock", "Wrasse", "Mackerel"),
            directions = "Boat from Plymouth marina",
            parking = "Queen Anne's Battery"
        ),
        SpotRecord(
            id = "uk-cornwall-manacles",
            name = "The Manacles",
            description = "Notorious reef system with excellent marine life and challenging conditions.",
            coordinates = Coordinates(50.0500, -5.0333),
            access = "boat",
            depth = 20,
            commonFish = listOf("Bass", "Pollock", "Bream", "Wrasse"),
            directions = "Boat from Falmouth or Helford",
            parking = "Falmouth marina"
        ),

        // Australia
        SpotRecord(
            id = "australia-ningaloo",
            name = "Ningaloo Reef",
            description = "World Heritage fringing reef with incredible coral trout and Spanish mackerel.",
            coordinates = Coordinates(-22.6833, 113.6667),
            access = "shore",
            depth = 15,
            commonFish = listOf("Coral Trout", "Spanish Mackerel", "Giant Trevally", "Red Emperor"),
            directions = "Access from Exmouth or Coral Bay",
            parking = "Beach access points"
        ),
        SpotRecord(
            id = "australia-montague-island",
            name = "Montague Island",
            description = "NSW south coast island with kingfish, jewfish, and seal colonies.",
            coordinates = Coordinates(-36.2500, 150.2333),
            access = "boat",
            depth = 25,
            commonFish = listOf("Kingfish", "Jewfish", "Blue Groper", "Snapper"),
            directions = "Boat from Narooma",
            parking = "Narooma boat ramp"
        ),

        // New Zealand
        SpotRecord(
            id = "nz-poor-knights",
            name = "Poor Knights Islands",
            description = "Marine reserve with subtropical fish at world's best temperate dive site.",
            coordinates = Coordinates(-35.4667, 174.7333),
            access = "boat",
            depth = 30,
            commonFish = listOf("Kingfish", "Snapper", "Blue Maomao", "Trevally"),
            directions = "Boat from Tutukaka",
            parking = "Tutukaka marina"
        ),

        // Mozambique
        SpotRecord(
            id = "mozambique-bazaruto",
            name = "Bazaruto Archipelago",
            description = "Remote African paradise with giant kingfish and pristine reefs.",
            coordinates = Coordinates(-21.6500, 35.4667),
            access = "boat",
            depth = 30,
            commonFish = listOf("Giant Kingfish", "Dogtooth Tuna", "Wahoo", "Sailfish"),
            directions = "Boat from Vilankulo",
            parking = "Resort facilities"
        ),

        // Indonesia
        SpotRecord(
            id = "indonesia-raja-ampat",
            name = "Raja Ampat",
            description = "Epicenter of marine biodiversity with exceptional diving and spearfishing.",
            coordinates = Coordinates(-0.5000, 130.5000),
            access = "boat",
            depth = 25,
            commonFish = listOf("Giant Trevally", "Dogtooth Tuna", "Spanish Mackerel", "Barramundi Cod"),
            directions = "Boat from Sorong",
            parking = "Liveaboard or resort"
        ),

        // Portugal - Azores
        SpotRecord(
            id = "azores-pico",
            name = "Pico Island",
            description = "Atlantic volcanic island with blue water pelagics and excellent visibility.",
            coordinates = Coordinates(38.4667, -28.2500),
            access = "boat",
            depth = 35,
            commonFish = listOf("Yellowfin Tuna", "Wahoo", "Amberjack", "Almaco Jack"),
            directions = "Boat from Madalena harbor",
            parking = "Madalena marina"
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
