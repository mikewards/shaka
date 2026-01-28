package com.shaka.data.client

import com.shaka.model.Coordinates
import kotlin.math.*

/**
 * Comprehensive spearfishing spot database.
 * In production, this would be replaced with PostgreSQL + PostGIS.
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

    private val spots = listOf(
        // ==========================================
        // HAWAII - OAHU (Comprehensive)
        // ==========================================
        
        // North Shore
        SpotRecord(
            id = "oahu-sharks-cove",
            name = "Shark's Cove",
            description = "Premier North Shore spot with protected cove, lava rock formations, and excellent reef structure. Summer only - dangerous in winter swells.",
            coordinates = Coordinates(21.6494, -158.0628),
            access = "shore",
            depth = 12,
            commonFish = listOf("Uhu (Parrotfish)", "Kole", "Manini", "Menpachi", "He'e (Octopus)"),
            directions = "Kamehameha Highway between Waimea Bay and Sunset Beach. Park across the street.",
            parking = "Free lot across highway, gets crowded by 9am"
        ),
        SpotRecord(
            id = "oahu-three-tables",
            name = "Three Tables",
            description = "Named for three flat reef sections visible at low tide. Excellent visibility, diverse marine life. Summer only.",
            coordinates = Coordinates(21.6456, -158.0631),
            access = "shore",
            depth = 10,
            commonFish = listOf("Kole", "Manini", "Uhu", "Moana (Goatfish)", "Tako"),
            directions = "Just south of Shark's Cove on Kamehameha Highway",
            parking = "Street parking or Shark's Cove lot"
        ),
        SpotRecord(
            id = "oahu-waimea-bay",
            name = "Waimea Bay",
            description = "World-famous big wave spot. Calm and clear in summer with excellent snorkeling and spearfishing on the reef edges.",
            coordinates = Coordinates(21.6422, -158.0667),
            access = "shore",
            depth = 8,
            commonFish = listOf("Uhu", "Kole", "Aweoweo", "Manini"),
            directions = "North Shore, Kamehameha Highway. Can't miss the bay.",
            parking = "Beach parking lot, fills early on weekends"
        ),
        SpotRecord(
            id = "oahu-sunset-point",
            name = "Sunset Point",
            description = "Rocky reef with good structure. Less crowded than Shark's Cove. Watch for strong currents.",
            coordinates = Coordinates(21.6678, -158.0442),
            access = "shore",
            depth = 10,
            commonFish = listOf("Omilu (Bluefin Trevally)", "Papio", "Uhu", "Kole"),
            directions = "North of Sunset Beach on Kamehameha Highway",
            parking = "Limited street parking"
        ),
        SpotRecord(
            id = "oahu-haleiwa-harbor",
            name = "Haleiwa Harbor Reef",
            description = "Reef structure near the harbor entrance. Good for papio and ulua. Watch for boat traffic.",
            coordinates = Coordinates(21.5958, -158.1056),
            access = "shore",
            depth = 8,
            commonFish = listOf("Papio", "Omilu", "Moi", "Oio (Bonefish)"),
            directions = "Haleiwa Harbor area, enter from Haleiwa Beach Park",
            parking = "Haleiwa Beach Park lot"
        ),
        SpotRecord(
            id = "oahu-puaena-point",
            name = "Puaena Point",
            description = "Point break area with good reef. Local spot, respect the regulars.",
            coordinates = Coordinates(21.5972, -158.1014),
            access = "shore",
            depth = 6,
            commonFish = listOf("Papio", "Oio", "Moana", "Kumu"),
            directions = "Near Haleiwa, take the small road past the harbor",
            parking = "Very limited, be respectful"
        ),

        // West Side (Leeward)
        SpotRecord(
            id = "oahu-electric-beach",
            name = "Electric Beach (Kahe Point)",
            description = "Warm water outflow from power plant attracts incredible marine life including dolphins, turtles, and schools of fish. One of Oahu's best spots.",
            coordinates = Coordinates(21.3544, -158.1311),
            access = "shore",
            depth = 15,
            commonFish = listOf("Mu (Bigeye Emperor)", "Uku (Gray Snapper)", "Omilu", "Tako", "Uhu"),
            directions = "West side past Ko Olina. Power plant is visible. Park along highway.",
            parking = "Roadside parking - DON'T leave valuables, break-ins common"
        ),
        SpotRecord(
            id = "oahu-makaha",
            name = "Makaha",
            description = "Deep water access, bigger fish, more challenging conditions. For experienced divers. Can see ulua, ono, and occasionally ahi.",
            coordinates = Coordinates(21.4728, -158.2219),
            access = "shore",
            depth = 20,
            commonFish = listOf("Ulua (Giant Trevally)", "Ono (Wahoo)", "Omilu", "Mu", "Uku"),
            directions = "Farrington Highway to Makaha Beach Park",
            parking = "Beach park lot"
        ),
        SpotRecord(
            id = "oahu-makua",
            name = "Makua Beach",
            description = "Remote west side beach with clear water and less pressure. Dolphins often present. Military area nearby - check access.",
            coordinates = Coordinates(21.5267, -158.2339),
            access = "shore",
            depth = 12,
            commonFish = listOf("Uhu", "Kole", "Mu", "Tako"),
            directions = "End of Farrington Highway, north of Makaha",
            parking = "Roadside, limited"
        ),
        SpotRecord(
            id = "oahu-koolina-lagoons",
            name = "Ko Olina Lagoons",
            description = "Man-made lagoons with reef structure. Easy access, good for beginners. Can be crowded with tourists.",
            coordinates = Coordinates(21.3389, -158.1244),
            access = "shore",
            depth = 6,
            commonFish = listOf("Manini", "Kole", "Moana", "Small Papio"),
            directions = "Ko Olina Resort area, multiple lagoon access points",
            parking = "Resort parking, can be limited"
        ),
        SpotRecord(
            id = "oahu-nanakuli",
            name = "Nanakuli Beach",
            description = "Local beach with good reef. Respect the community. Less touristy than other spots.",
            coordinates = Coordinates(21.3922, -158.1564),
            access = "shore",
            depth = 8,
            commonFish = listOf("Uhu", "Kole", "Manini", "Papio"),
            directions = "Farrington Highway, Nanakuli Beach Park",
            parking = "Beach park lot"
        ),
        SpotRecord(
            id = "oahu-maili",
            name = "Maili Point",
            description = "Point with good structure and current that brings fish. Can be rough.",
            coordinates = Coordinates(21.4194, -158.1772),
            access = "shore",
            depth = 10,
            commonFish = listOf("Omilu", "Papio", "Uhu", "Mu"),
            directions = "Farrington Highway, Maili Beach Park",
            parking = "Street and beach park"
        ),
        SpotRecord(
            id = "oahu-yokohama",
            name = "Yokohama Bay",
            description = "End of the road on west side. Remote, beautiful, clear water. Can have big swell.",
            coordinates = Coordinates(21.5544, -158.2478),
            access = "shore",
            depth = 10,
            commonFish = listOf("Uhu", "Kole", "Ulua", "Tako"),
            directions = "Very end of Farrington Highway",
            parking = "Small lot at end of road"
        ),

        // South Shore
        SpotRecord(
            id = "oahu-ala-moana",
            name = "Ala Moana Bowls",
            description = "Reef near the famous surf break. Urban location but surprisingly good marine life.",
            coordinates = Coordinates(21.2886, -157.8478),
            access = "shore",
            depth = 8,
            commonFish = listOf("Papio", "Omilu", "Manini", "Kole"),
            directions = "Ala Moana Beach Park, swim out to the reef",
            parking = "Large beach park lot"
        ),
        SpotRecord(
            id = "oahu-diamond-head",
            name = "Diamond Head Reef",
            description = "Reef system off Diamond Head. Good visibility, diverse species. Boat access recommended for outer areas.",
            coordinates = Coordinates(21.2558, -157.8067),
            access = "boat",
            depth = 18,
            commonFish = listOf("Uku", "Mu", "Omilu", "Uhu", "Kahala"),
            directions = "Boat from Kewalo Basin or Hawaii Kai",
            parking = "Marina parking"
        ),
        SpotRecord(
            id = "oahu-portlock",
            name = "Portlock (Spitting Caves)",
            description = "Dramatic cliffs and caves. Advanced spot with strong currents. Big fish potential.",
            coordinates = Coordinates(21.2633, -157.7089),
            access = "shore",
            depth = 15,
            commonFish = listOf("Ulua", "Mu", "Uku", "Omilu"),
            directions = "Portlock Road in Hawaii Kai, hike down cliffs",
            parking = "Street parking, respect residents"
        ),
        SpotRecord(
            id = "oahu-hanauma-outside",
            name = "Outside Hanauma Bay",
            description = "Outside the protected bay. The bay itself is no-take. Good structure on the outer reef.",
            coordinates = Coordinates(21.2569, -157.6933),
            access = "boat",
            depth = 20,
            commonFish = listOf("Mu", "Uku", "Ulua", "Uhu"),
            directions = "Boat access only - outside the marine preserve boundary",
            parking = "N/A - boat access"
        ),

        // East Side (Windward)
        SpotRecord(
            id = "oahu-lanikai",
            name = "Lanikai Reef",
            description = "Beautiful turquoise water with good reef structure. Paddle out from beach or use boat.",
            coordinates = Coordinates(21.3922, -157.7133),
            access = "shore",
            depth = 10,
            commonFish = listOf("Papio", "Uhu", "Kole", "Tako"),
            directions = "Lanikai Beach, paddle or swim to outer reef",
            parking = "Very limited street parking"
        ),
        SpotRecord(
            id = "oahu-kailua-bay",
            name = "Kailua Bay",
            description = "Large bay with scattered reef patches. Good for paddling out. Watch for wind.",
            coordinates = Coordinates(21.4022, -157.7244),
            access = "shore",
            depth = 8,
            commonFish = listOf("Papio", "Oio", "Omilu", "Uhu"),
            directions = "Kailua Beach Park",
            parking = "Beach park lot"
        ),
        SpotRecord(
            id = "oahu-kaneohe-bay",
            name = "Kaneohe Bay Patch Reefs",
            description = "Largest bay in Hawaii with numerous patch reefs. Boat access best. Some areas restricted (military).",
            coordinates = Coordinates(21.4567, -157.7889),
            access = "boat",
            depth = 12,
            commonFish = listOf("Papio", "Uhu", "Moana", "Kumu"),
            directions = "Boat from Heeia Kea Harbor",
            parking = "Marina parking"
        ),
        SpotRecord(
            id = "oahu-makapuu",
            name = "Makapuu Point",
            description = "Dramatic point with strong currents. Expert only. Pelagics come close to shore here.",
            coordinates = Coordinates(21.3108, -157.6517),
            access = "shore",
            depth = 15,
            commonFish = listOf("Ulua", "Omilu", "Ono", "Ahi"),
            directions = "Near Makapuu Beach, hike to fishing spots",
            parking = "Makapuu lookout lot"
        ),
        SpotRecord(
            id = "oahu-waimanalo",
            name = "Waimanalo Beach Reef",
            description = "Long beach with fringing reef. Good for beginners. Local community beach.",
            coordinates = Coordinates(21.3344, -157.6961),
            access = "shore",
            depth = 6,
            commonFish = listOf("Papio", "Uhu", "Moana", "Manini"),
            directions = "Waimanalo Beach Park",
            parking = "Beach park lot"
        ),
        SpotRecord(
            id = "oahu-kahana-bay",
            name = "Kahana Bay",
            description = "North windward coast, beautiful bay with reef. Can be murky after rain.",
            coordinates = Coordinates(21.5528, -157.8756),
            access = "shore",
            depth = 8,
            commonFish = listOf("Papio", "Uhu", "Oio", "Moi"),
            directions = "Kamehameha Highway, Kahana Bay Beach Park",
            parking = "Beach park lot"
        ),
        SpotRecord(
            id = "oahu-laie-point",
            name = "Laie Point",
            description = "Rocky point with good fish. Strong currents. Can see bigger species.",
            coordinates = Coordinates(21.6467, -157.9178),
            access = "shore",
            depth = 12,
            commonFish = listOf("Ulua", "Omilu", "Mu", "Uhu"),
            directions = "Laie, take Naupaka Street to the point",
            parking = "Small lot at point"
        ),

        // ==========================================
        // HAWAII - BIG ISLAND (Kona Side)
        // ==========================================
        SpotRecord(
            id = "kona-honokohau",
            name = "Honokohau Harbor Reef",
            description = "Harbor area with excellent reef structure. Easy access, good fish population. Watch for boat traffic.",
            coordinates = Coordinates(19.6703, -156.0258),
            access = "shore",
            depth = 12,
            commonFish = listOf("Uhu", "Uku", "Mu", "Omilu", "Tako"),
            directions = "Honokohau Harbor, south of Kona airport",
            parking = "Harbor parking"
        ),
        SpotRecord(
            id = "kona-pine-trees",
            name = "Pine Trees",
            description = "Local surf spot with good reef. North of Kona. Consistent conditions.",
            coordinates = Coordinates(19.7089, -156.0417),
            access = "shore",
            depth = 10,
            commonFish = listOf("Uhu", "Kole", "Omilu", "Papio"),
            directions = "North of Kona airport off Highway 19",
            parking = "Roadside"
        ),
        SpotRecord(
            id = "kona-kohanaiki",
            name = "Kohanaiki",
            description = "Rocky coastline with clear water. Less accessible means less pressure.",
            coordinates = Coordinates(19.7267, -156.0500),
            access = "shore",
            depth = 15,
            commonFish = listOf("Mu", "Uku", "Ulua", "Uhu"),
            directions = "North of Kona, access from Highway 19",
            parking = "Limited roadside"
        ),
        SpotRecord(
            id = "kona-kua-bay",
            name = "Kua Bay (Manini'owali)",
            description = "Beautiful white sand beach with clear water. Good snorkeling, decent spearfishing on edges.",
            coordinates = Coordinates(19.7861, -156.0528),
            access = "shore",
            depth = 8,
            commonFish = listOf("Uhu", "Manini", "Kole", "Moana"),
            directions = "Off Highway 19, follow signs to Kekaha Kai State Park",
            parking = "State park lot, can fill up"
        ),
        SpotRecord(
            id = "kona-makalawena",
            name = "Makalawena Beach",
            description = "Remote beach requiring hike. Worth the effort - less pressure, clear water.",
            coordinates = Coordinates(19.8033, -156.0444),
            access = "shore",
            depth = 10,
            commonFish = listOf("Uhu", "Mu", "Tako", "Omilu"),
            directions = "Hike from Kekaha Kai State Park, about 30 min",
            parking = "State park lot"
        ),
        SpotRecord(
            id = "kona-keahole-point",
            name = "Keahole Point",
            description = "Deep water access, big fish potential. Strong currents, advanced divers.",
            coordinates = Coordinates(19.7289, -156.0589),
            access = "shore",
            depth = 25,
            commonFish = listOf("Ulua", "Ono", "Ahi", "Uku"),
            directions = "Near NELHA facility, north of airport",
            parking = "Limited"
        ),
        SpotRecord(
            id = "kona-puako",
            name = "Puako",
            description = "Series of reef channels with excellent diving. Community of houses, be respectful.",
            coordinates = Coordinates(19.9667, -155.8417),
            access = "shore",
            depth = 15,
            commonFish = listOf("Uhu", "Mu", "Kumu", "Tako", "Lobster"),
            directions = "Puako Beach Drive, multiple access points",
            parking = "Street parking, limited"
        ),
        SpotRecord(
            id = "kona-anaehoomalu",
            name = "A-Bay (Anaehoomalu)",
            description = "Resort area bay with good reef on outer edges. Calm conditions.",
            coordinates = Coordinates(19.9256, -155.8689),
            access = "shore",
            depth = 10,
            commonFish = listOf("Papio", "Uhu", "Kole", "Moana"),
            directions = "Waikoloa Resort area",
            parking = "Resort parking"
        ),
        SpotRecord(
            id = "kona-hapuna",
            name = "Hapuna Beach",
            description = "Beautiful big beach with reef on south end. Popular but fishable.",
            coordinates = Coordinates(19.9906, -155.8233),
            access = "shore",
            depth = 8,
            commonFish = listOf("Uhu", "Kole", "Manini", "Papio"),
            directions = "Hapuna Beach State Park",
            parking = "State park lot, $5 fee"
        ),
        SpotRecord(
            id = "kona-spencer",
            name = "Spencer Beach",
            description = "Calm protected beach near Kawaihae. Good for beginners.",
            coordinates = Coordinates(20.0211, -155.8167),
            access = "shore",
            depth = 6,
            commonFish = listOf("Manini", "Kole", "Uhu", "Moana"),
            directions = "Near Kawaihae Harbor",
            parking = "Beach park lot"
        ),
        SpotRecord(
            id = "kona-two-step",
            name = "Two Step (Honaunau)",
            description = "Famous dive spot south of Kona. Incredible visibility, easy entry. Near Place of Refuge.",
            coordinates = Coordinates(19.4228, -155.9094),
            access = "shore",
            depth = 20,
            commonFish = listOf("Uhu", "Lau (Surgeonfish)", "Kole", "Moana", "Tako"),
            directions = "South of Kona, Honaunau Bay",
            parking = "Small lot, gets crowded"
        ),
        SpotRecord(
            id = "kona-hookena",
            name = "Hookena Beach",
            description = "South Kona beach with good reef. Less crowded than north side.",
            coordinates = Coordinates(19.3689, -155.8989),
            access = "shore",
            depth = 12,
            commonFish = listOf("Uhu", "Mu", "Papio", "Tako"),
            directions = "South Kona, off Highway 11",
            parking = "Beach park lot"
        ),
        SpotRecord(
            id = "kona-milolii",
            name = "Milolii",
            description = "Remote fishing village. Traditional Hawaiian community. Excellent diving, respectful access.",
            coordinates = Coordinates(19.2917, -155.9056),
            access = "shore",
            depth = 15,
            commonFish = listOf("Mu", "Uku", "Uhu", "Ulua"),
            directions = "Far south Kona, winding road down",
            parking = "Very limited"
        ),

        // ==========================================
        // HAWAII - MAUI
        // ==========================================
        SpotRecord(
            id = "maui-honolua",
            name = "Honolua Bay",
            description = "Marine preserve for part of bay, excellent diving around edges. Summer best.",
            coordinates = Coordinates(21.0139, -156.6381),
            access = "shore",
            depth = 15,
            commonFish = listOf("Uhu", "Palani", "Manini", "Kole"),
            directions = "North Maui past Kapalua",
            parking = "Roadside, walk down"
        ),
        SpotRecord(
            id = "maui-kapalua",
            name = "Kapalua Bay",
            description = "Protected bay with good reef. Resort area, can be crowded but good fish.",
            coordinates = Coordinates(20.9978, -156.6656),
            access = "shore",
            depth = 8,
            commonFish = listOf("Manini", "Kole", "Uhu", "Papio"),
            directions = "Kapalua Resort area",
            parking = "Public parking available"
        ),
        SpotRecord(
            id = "maui-olowalu",
            name = "Olowalu",
            description = "Mile marker 14 reef, excellent coral and fish. One of Maui's best shore dives.",
            coordinates = Coordinates(20.8078, -156.6033),
            access = "shore",
            depth = 12,
            commonFish = listOf("Uhu", "Moana", "Manini", "Tako"),
            directions = "Highway 30, mile marker 14",
            parking = "Roadside"
        ),
        SpotRecord(
            id = "maui-black-rock",
            name = "Black Rock (Kaanapali)",
            description = "Famous dive spot at Sheraton. Cliff jumping, turtles, reef fish.",
            coordinates = Coordinates(20.9267, -156.6933),
            access = "shore",
            depth = 10,
            commonFish = listOf("Manini", "Kole", "Humuhumunukunukuapua'a", "Uhu"),
            directions = "Kaanapali Beach, north end by Sheraton",
            parking = "Resort parking or public access"
        ),
        SpotRecord(
            id = "maui-ahihi-kinau",
            name = "Ahihi-Kinau (Outside Reserve)",
            description = "Natural area reserve - check boundaries carefully. Amazing lava formations outside protected zone.",
            coordinates = Coordinates(20.6167, -156.4333),
            access = "shore",
            depth = 15,
            commonFish = listOf("Uhu", "Palani", "Manini", "Tako"),
            directions = "South Maui past Makena, end of road",
            parking = "Limited, check reserve rules"
        ),
        SpotRecord(
            id = "maui-makena",
            name = "Makena (Big Beach)",
            description = "Large beach with reef at south end. Strong currents possible.",
            coordinates = Coordinates(20.6289, -156.4456),
            access = "shore",
            depth = 10,
            commonFish = listOf("Papio", "Uhu", "Omilu", "Kole"),
            directions = "South Maui, Makena State Park",
            parking = "State park lot"
        ),
        SpotRecord(
            id = "maui-five-caves",
            name = "Five Caves (Makena)",
            description = "Dramatic underwater lava tube system. Advanced diving.",
            coordinates = Coordinates(20.6389, -156.4433),
            access = "shore",
            depth = 18,
            commonFish = listOf("Mu", "Uku", "Lobster", "Uhu"),
            directions = "South Makena, near Maui Prince",
            parking = "Street parking"
        ),
        SpotRecord(
            id = "maui-molokini",
            name = "Molokini Crater",
            description = "Volcanic crater with pristine reef. Boat access only. One of Hawaii's best dives.",
            coordinates = Coordinates(20.6308, -156.4958),
            access = "boat",
            depth = 25,
            commonFish = listOf("Ulua", "Mu", "Uku", "Kahala", "Moana"),
            directions = "Boat from Maalaea Harbor",
            parking = "Harbor parking"
        ),

        // ==========================================
        // FLORIDA KEYS
        // ==========================================
        SpotRecord(
            id = "keys-sombrero-reef",
            name = "Sombrero Reef",
            description = "Popular Middle Keys reef with lighthouse. Good fish population, watch for dive boats.",
            coordinates = Coordinates(24.6261, -81.1106),
            access = "boat",
            depth = 12,
            commonFish = listOf("Hogfish", "Yellowtail Snapper", "Mutton Snapper", "Grouper"),
            directions = "Boat from Marathon",
            parking = "Boot Key Harbor marina"
        ),
        SpotRecord(
            id = "keys-looe-key",
            name = "Looe Key",
            description = "Outstanding reef in Lower Keys. Sanctuary zone - check where spearfishing is allowed.",
            coordinates = Coordinates(24.5456, -81.4067),
            access = "boat",
            depth = 10,
            commonFish = listOf("Hogfish", "Yellowtail", "Grouper", "Lobster"),
            directions = "Boat from Big Pine Key",
            parking = "Bahia Honda or local marinas"
        ),
        SpotRecord(
            id = "keys-american-shoal",
            name = "American Shoal",
            description = "Offshore reef structure with pelagic action. Deeper water means bigger fish.",
            coordinates = Coordinates(24.5167, -81.5333),
            access = "boat",
            depth = 20,
            commonFish = listOf("Cobia", "Amberjack", "Permit", "Hogfish", "Grouper"),
            directions = "Boat from Big Pine Key or Sugarloaf",
            parking = "Marina"
        ),
        SpotRecord(
            id = "keys-marquesas",
            name = "Marquesas Keys",
            description = "Remote keys west of Key West. Pristine, less pressure, big fish.",
            coordinates = Coordinates(24.5583, -82.1083),
            access = "boat",
            depth = 15,
            commonFish = listOf("Permit", "Hogfish", "Mutton Snapper", "Grouper", "Lobster"),
            directions = "Long boat ride from Key West",
            parking = "Key West marinas"
        ),
        SpotRecord(
            id = "keys-dry-tortugas",
            name = "Dry Tortugas",
            description = "Remote national park with exceptional diving. Some areas protected, some open.",
            coordinates = Coordinates(24.6289, -82.8733),
            access = "boat",
            depth = 20,
            commonFish = listOf("Hogfish", "Mutton Snapper", "Grouper", "Permit", "Cubera Snapper"),
            directions = "Ferry or private boat from Key West, 70 miles",
            parking = "Key West"
        ),
        SpotRecord(
            id = "keys-coffins-patch",
            name = "Coffins Patch",
            description = "Middle Keys reef system with multiple dive sites.",
            coordinates = Coordinates(24.6833, -80.9667),
            access = "boat",
            depth = 8,
            commonFish = listOf("Hogfish", "Yellowtail", "Lane Snapper", "Grunts"),
            directions = "Boat from Marathon",
            parking = "Marathon marinas"
        ),
        SpotRecord(
            id = "keys-newfound-harbor",
            name = "Newfound Harbor Keys",
            description = "Lower Keys patch reefs with good hogfish and lobster.",
            coordinates = Coordinates(24.6167, -81.4000),
            access = "boat",
            depth = 6,
            commonFish = listOf("Hogfish", "Lobster", "Yellowtail", "Mangrove Snapper"),
            directions = "Boat from Big Pine Key",
            parking = "Big Pine marinas"
        ),
        SpotRecord(
            id = "keys-bahia-honda",
            name = "Bahia Honda Bridge",
            description = "Old bridge pilings create reef structure. Shore accessible from state park.",
            coordinates = Coordinates(24.6644, -81.2833),
            access = "shore",
            depth = 8,
            commonFish = listOf("Snapper", "Sheepshead", "Permit", "Snook"),
            directions = "Bahia Honda State Park",
            parking = "State park lot"
        ),

        // ==========================================
        // CALIFORNIA
        // ==========================================
        SpotRecord(
            id = "cali-la-jolla-cove",
            name = "La Jolla Cove",
            description = "Protected area - check regulations. Outside the protected zone has excellent kelp forest diving.",
            coordinates = Coordinates(32.8506, -117.2728),
            access = "shore",
            depth = 15,
            commonFish = listOf("Calico Bass", "Sheephead", "Yellowtail", "White Seabass"),
            directions = "La Jolla, walk down to cove",
            parking = "Street parking, competitive"
        ),
        SpotRecord(
            id = "cali-bird-rock",
            name = "Bird Rock",
            description = "Rocky reef with kelp. Good calico bass and sheephead.",
            coordinates = Coordinates(32.8133, -117.2722),
            access = "shore",
            depth = 12,
            commonFish = listOf("Calico Bass", "Sheephead", "Rockfish", "Lobster"),
            directions = "South La Jolla, access from beach",
            parking = "Street parking"
        ),
        SpotRecord(
            id = "cali-catalina-isthmus",
            name = "Catalina Isthmus (Two Harbors)",
            description = "Island diving with incredible visibility. Kelp forests, big fish.",
            coordinates = Coordinates(33.4439, -118.4897),
            access = "boat",
            depth = 20,
            commonFish = listOf("White Seabass", "Yellowtail", "Calico Bass", "Sheephead"),
            directions = "Boat from Long Beach or San Pedro",
            parking = "Harbor parking"
        ),
        SpotRecord(
            id = "cali-catalina-backside",
            name = "Catalina Backside",
            description = "Less visited side of island. Big fish, pelagic action.",
            coordinates = Coordinates(33.3667, -118.5333),
            access = "boat",
            depth = 25,
            commonFish = listOf("Yellowtail", "White Seabass", "Bonito", "Calico Bass"),
            directions = "Boat from mainland",
            parking = "Marina"
        ),
        SpotRecord(
            id = "cali-san-clemente",
            name = "San Clemente Island",
            description = "Navy island with limited access but incredible diving when available.",
            coordinates = Coordinates(32.9000, -118.4833),
            access = "boat",
            depth = 25,
            commonFish = listOf("Yellowtail", "White Seabass", "Lingcod", "Halibut"),
            directions = "Boat from San Diego area",
            parking = "Marina"
        ),
        SpotRecord(
            id = "cali-point-loma-kelp",
            name = "Point Loma Kelp Beds",
            description = "Extensive kelp forest with good structure. Boat recommended.",
            coordinates = Coordinates(32.6667, -117.2667),
            access = "boat",
            depth = 18,
            commonFish = listOf("Calico Bass", "Yellowtail", "Sheephead", "Rockfish"),
            directions = "Boat from San Diego Bay",
            parking = "Marina"
        ),
        SpotRecord(
            id = "cali-channel-islands",
            name = "Channel Islands - Anacapa",
            description = "National park island with pristine diving. Cold water, great vis.",
            coordinates = Coordinates(34.0167, -119.4000),
            access = "boat",
            depth = 20,
            commonFish = listOf("Calico Bass", "Sheephead", "Lingcod", "Rockfish"),
            directions = "Boat from Ventura or Oxnard",
            parking = "Harbor parking"
        ),

        // ==========================================
        // BAHAMAS - Specific Sites
        // ==========================================
        
        // Andros Island
        SpotRecord(
            id = "bahamas-andros-the-wall",
            name = "The Wall (Andros)",
            description = "Famous wall dive where barrier reef drops into Tongue of the Ocean. Prime grouper territory.",
            coordinates = Coordinates(24.7167, -77.7667),
            access = "boat",
            depth = 30,
            commonFish = listOf("Nassau Grouper", "Black Grouper", "Hogfish", "Mutton Snapper", "Yellowtail"),
            directions = "Boat from Fresh Creek, South Andros",
            parking = "Andros Beach Club marina"
        ),
        SpotRecord(
            id = "bahamas-andros-great-blue-hole",
            name = "Great Blue Hole (Andros)",
            description = "Second deepest blue hole in Bahamas. Unique structure attracts snappers and jacks.",
            coordinates = Coordinates(24.4500, -77.9000),
            access = "boat",
            depth = 40,
            commonFish = listOf("Snapper", "Horse-eye Jack", "Bar Jack", "Grouper"),
            directions = "Boat from South Andros with local guide",
            parking = "Lodge"
        ),
        SpotRecord(
            id = "bahamas-andros-north-reef",
            name = "North Andros Reef",
            description = "Shallower section of barrier reef. Easier conditions, excellent hogfish.",
            coordinates = Coordinates(25.0500, -78.0000),
            access = "boat",
            depth = 15,
            commonFish = listOf("Hogfish", "Mutton Snapper", "Nassau Grouper", "Lionfish"),
            directions = "Boat from Nicholl's Town or Morgan's Bluff",
            parking = "Local marina"
        ),

        // Exuma Cays
        SpotRecord(
            id = "bahamas-exuma-thunderball",
            name = "Thunderball Grotto",
            description = "Famous James Bond cave system near Staniel Cay. Shallow, clear, abundant reef fish.",
            coordinates = Coordinates(24.1708, -76.4389),
            access = "boat",
            depth = 8,
            commonFish = listOf("Sergeant Major", "Yellowtail Snapper", "Angelfish", "Parrotfish"),
            directions = "Boat from Staniel Cay",
            parking = "Staniel Cay Yacht Club"
        ),
        SpotRecord(
            id = "bahamas-exuma-land-sea-park",
            name = "Exuma Cays Land & Sea Park",
            description = "283 sq km marine reserve. Second largest barrier reef in Western Hemisphere. Some areas no-take.",
            coordinates = Coordinates(24.5833, -76.6333),
            access = "boat",
            depth = 25,
            commonFish = listOf("Nassau Grouper", "Hogfish", "Reef Shark", "Eagle Ray", "Turtle"),
            directions = "Boat from Staniel Cay or Georgetown",
            parking = "Marina"
        ),
        SpotRecord(
            id = "bahamas-exuma-stocking-island",
            name = "Stocking Island Blue Holes",
            description = "Multiple blue holes formed by collapsed sinkholes near Georgetown.",
            coordinates = Coordinates(23.5333, -75.7667),
            access = "boat",
            depth = 30,
            commonFish = listOf("Grouper", "Snapper", "Jacks", "Bull Shark"),
            directions = "Boat from Georgetown",
            parking = "Georgetown marina"
        ),

        // Bimini
        SpotRecord(
            id = "bahamas-bimini-north",
            name = "North Bimini Reef",
            description = "Clear Gulf Stream waters, easy Florida access. Hammerheads in winter.",
            coordinates = Coordinates(25.7500, -79.2500),
            access = "boat",
            depth = 20,
            commonFish = listOf("Hogfish", "Grouper", "Wahoo", "Hammerhead Shark"),
            directions = "50 miles from Miami",
            parking = "Bimini Big Game Club"
        ),
        SpotRecord(
            id = "bahamas-bimini-road",
            name = "Bimini Road",
            description = "Mysterious underwater rock formation. Reef fish and occasional pelagics.",
            coordinates = Coordinates(25.7667, -79.2833),
            access = "boat",
            depth = 8,
            commonFish = listOf("Grouper", "Snapper", "Barracuda", "Nurse Shark"),
            directions = "Boat from North Bimini",
            parking = "Bimini marina"
        ),

        // Abaco
        SpotRecord(
            id = "bahamas-abaco-fowl-cay",
            name = "Fowl Cay Reef (Abaco)",
            description = "Protected reef near Marsh Harbour. Excellent visibility and reef diversity.",
            coordinates = Coordinates(26.5833, -77.0667),
            access = "boat",
            depth = 15,
            commonFish = listOf("Hogfish", "Grouper", "Snapper", "Spiny Lobster"),
            directions = "Boat from Marsh Harbour",
            parking = "Marsh Harbour marina"
        ),
        SpotRecord(
            id = "bahamas-abaco-pelican-cay",
            name = "Pelican Cays Land & Sea Park",
            description = "National park with pristine reef. Limited spearfishing - check zones.",
            coordinates = Coordinates(26.3667, -77.0333),
            access = "boat",
            depth = 20,
            commonFish = listOf("Grouper", "Snapper", "Hogfish", "Spadefish"),
            directions = "Boat from Marsh Harbour",
            parking = "Marina"
        ),
        SpotRecord(
            id = "bahamas-grand-cay",
            name = "Grand Cay (Abaco)",
            description = "Remote northern Abaco. Legendary multi-day spearfishing trips. Big grouper.",
            coordinates = Coordinates(27.2167, -78.3167),
            access = "boat",
            depth = 25,
            commonFish = listOf("Black Grouper", "Nassau Grouper", "Hogfish", "Mutton Snapper", "Yellowfin Grouper"),
            directions = "Boat from West End, Grand Bahama (long run)",
            parking = "West End marina"
        ),

        // Nassau / New Providence
        SpotRecord(
            id = "bahamas-nassau-tongue",
            name = "Tongue of the Ocean Drop-off",
            description = "6,000ft drop-off. Big pelagics, serious bluewater hunting.",
            coordinates = Coordinates(24.2500, -77.5000),
            access = "boat",
            depth = 40,
            commonFish = listOf("Wahoo", "Mahi Mahi", "Yellowfin Tuna", "Blue Marlin"),
            directions = "Long boat run from Nassau",
            parking = "Nassau marinas"
        ),
        SpotRecord(
            id = "bahamas-nassau-clifton-wall",
            name = "Clifton Wall",
            description = "Western New Providence wall dive. Easier access from Nassau.",
            coordinates = Coordinates(25.0000, -77.5333),
            access = "boat",
            depth = 25,
            commonFish = listOf("Grouper", "Hogfish", "Snapper", "Barracuda"),
            directions = "Boat from Nassau",
            parking = "Nassau marina"
        ),

        // ==========================================
        // FRENCH POLYNESIA - Specific Sites
        // ==========================================
        
        // Fakarava
        SpotRecord(
            id = "fakarava-south-pass-tetamanu",
            name = "Tetamanu Pass (South Pass)",
            description = "200m wide pass, famous wall of sharks. Grey reef sharks rest in grotto during day. Grouper spawning June.",
            coordinates = Coordinates(-16.6872, -145.2511),
            access = "boat",
            depth = 18,
            commonFish = listOf("Grey Reef Shark", "Marbled Grouper", "Napoleon Wrasse", "Giant Trevally", "Barracuda"),
            directions = "1.5hr boat from Rotoava, or stay at Tetamanu Village",
            parking = "Pension/lodge"
        ),
        SpotRecord(
            id = "fakarava-north-pass-garuae",
            name = "Garuae Pass (North Pass)",
            description = "Largest pass in French Polynesia - 1.6km wide. Strong currents, wall of sharks on incoming tide.",
            coordinates = Coordinates(-16.0556, -145.6556),
            access = "boat",
            depth = 30,
            commonFish = listOf("Grey Reef Shark", "Manta Ray", "Dogtooth Tuna", "Giant Trevally", "Barracuda"),
            directions = "Boat from Rotoava village",
            parking = "Dive operator"
        ),
        SpotRecord(
            id = "fakarava-shark-grotto",
            name = "Shark Grotto (Fakarava)",
            description = "Specific site where grey reef sharks rest during daytime. Inside south pass.",
            coordinates = Coordinates(-16.6900, -145.2500),
            access = "boat",
            depth = 15,
            commonFish = listOf("Grey Reef Shark", "Whitetip Reef Shark", "Grouper"),
            directions = "South pass, local guide required",
            parking = "Tetamanu"
        ),

        // Rangiroa
        SpotRecord(
            id = "rangiroa-tiputa-pass",
            name = "Tiputa Pass",
            description = "Premier drift dive. Dolphins, mantas, hammerheads Jan-Mar. Strong currents.",
            coordinates = Coordinates(-14.9683, -147.6333),
            access = "boat",
            depth = 35,
            commonFish = listOf("Dolphin", "Manta Ray", "Hammerhead Shark", "Grey Reef Shark", "Giant Trevally"),
            directions = "Boat from Avatoru or Tiputa village",
            parking = "Dive center"
        ),
        SpotRecord(
            id = "rangiroa-sharks-cavern",
            name = "Sharks Cavern (Rangiroa)",
            description = "115ft site where divers wait stationary while grey reef sharks investigate.",
            coordinates = Coordinates(-14.9700, -147.6350),
            access = "boat",
            depth = 35,
            commonFish = listOf("Grey Reef Shark", "Whitetip Shark", "Napoleon Wrasse"),
            directions = "Inside Tiputa Pass",
            parking = "Dive center"
        ),
        SpotRecord(
            id = "rangiroa-the-canyons",
            name = "The Canyons (Rangiroa)",
            description = "Natural canyons mid-pass. Grey reef sharks abundant June-July. Hammerheads possible.",
            coordinates = Coordinates(-14.9650, -147.6300),
            access = "boat",
            depth = 25,
            commonFish = listOf("Grey Reef Shark", "Hammerhead Shark", "Eagle Ray", "Barracuda"),
            directions = "Mid Tiputa Pass",
            parking = "Dive center"
        ),
        SpotRecord(
            id = "rangiroa-avatoru-pass",
            name = "Avatoru Pass",
            description = "Two channels - eastern for beginners, western for advanced with mantas.",
            coordinates = Coordinates(-14.9500, -147.7000),
            access = "boat",
            depth = 25,
            commonFish = listOf("Manta Ray", "Whitetip Shark", "Horse-eye Jack", "Barracuda"),
            directions = "Boat from Avatoru",
            parking = "Village"
        ),

        // Moorea
        SpotRecord(
            id = "moorea-opunohu-pass",
            name = "Opunohu Pass",
            description = "Deep pass with Jardin des Roses at 40m. Canyons, drop-offs, caves. All levels.",
            coordinates = Coordinates(-17.4833, -149.8500),
            access = "boat",
            depth = 40,
            commonFish = listOf("Lemon Shark", "Blacktip Shark", "Napoleon Wrasse", "Barracuda", "Trevally"),
            directions = "Boat from Cook's Bay",
            parking = "Marina"
        ),
        SpotRecord(
            id = "moorea-tiki",
            name = "Tiki (Moorea)",
            description = "Northwest tip with rapid currents and shark school. Advanced divers.",
            coordinates = Coordinates(-17.4667, -149.9333),
            access = "boat",
            depth = 30,
            commonFish = listOf("Grey Reef Shark", "Blacktip Shark", "Trevally", "Tuna"),
            directions = "Boat from northwest Moorea",
            parking = "Resort"
        ),
        SpotRecord(
            id = "moorea-vaiare",
            name = "Vaiare (Moorea)",
            description = "Near ferry docks. Stingrays, lemon sharks, turtles in shallow water.",
            coordinates = Coordinates(-17.5167, -149.7667),
            access = "shore",
            depth = 15,
            commonFish = listOf("Stingray", "Lemon Shark", "Turtle", "Barracuda", "Parrotfish"),
            directions = "Vaiare ferry terminal area",
            parking = "Ferry parking"
        ),

        // Bora Bora
        SpotRecord(
            id = "bora-bora-lagoon-south",
            name = "Bora Bora South Lagoon",
            description = "Shallow lagoon hunting. Giant trevally, bluefin trevally around motu edges.",
            coordinates = Coordinates(-16.5333, -151.7333),
            access = "boat",
            depth = 10,
            commonFish = listOf("Giant Trevally", "Bluefin Trevally", "Emperor Fish", "Grey Snapper"),
            directions = "Boat from Vaitape",
            parking = "Vaitape dock"
        ),
        SpotRecord(
            id = "bora-bora-outer-reef",
            name = "Bora Bora Outer Reef",
            description = "Outside the lagoon for pelagics. Wahoo, tuna, mahi in blue water.",
            coordinates = Coordinates(-16.4833, -151.7833),
            access = "boat",
            depth = 30,
            commonFish = listOf("Yellowfin Tuna", "Wahoo", "Mahi Mahi", "Dogtooth Tuna"),
            directions = "Boat through Teavanui Pass",
            parking = "Marina"
        ),
        SpotRecord(
            id = "bora-bora-tapu",
            name = "Tapu (Bora Bora)",
            description = "Manta cleaning station outside reef. Advanced site with currents.",
            coordinates = Coordinates(-16.4500, -151.7500),
            access = "boat",
            depth = 25,
            commonFish = listOf("Manta Ray", "Grey Reef Shark", "Barracuda", "Trevally"),
            directions = "North side of island",
            parking = "Dive operator"
        ),

        // Tikehau
        SpotRecord(
            id = "tikehau-tuheiava-pass",
            name = "Tuheiava Pass (Tikehau)",
            description = "Only pass into Tikehau. Manta rays year-round, less crowded than Rangiroa.",
            coordinates = Coordinates(-15.0000, -148.2333),
            access = "boat",
            depth = 25,
            commonFish = listOf("Manta Ray", "Grey Reef Shark", "Barracuda", "Tuna", "Eagle Ray"),
            directions = "Boat from Tikehau village",
            parking = "Pension"
        ),

        // Manihi
        SpotRecord(
            id = "manihi-tairapa-pass",
            name = "Tairapa Pass (Manihi)",
            description = "Historic black pearl farming atoll. Excellent shark and ray encounters.",
            coordinates = Coordinates(-14.4333, -146.0667),
            access = "boat",
            depth = 25,
            commonFish = listOf("Grey Reef Shark", "Manta Ray", "Napoleon Wrasse", "Grouper"),
            directions = "Boat from Manihi village",
            parking = "Pension"
        ),

        // ==========================================
        // MEXICO - Sea of Cortez Specific Sites
        // ==========================================
        SpotRecord(
            id = "mexico-espiritu-santo",
            name = "Espiritu Santo Island",
            description = "Primary La Paz hunting ground. Sea lions, reef structure, multiple dive sites.",
            coordinates = Coordinates(24.4833, -110.3333),
            access = "boat",
            depth = 25,
            commonFish = listOf("Yellowtail", "Leopard Grouper", "Cabrilla", "Pargo", "Roosterfish"),
            directions = "Boat from La Paz, 1hr",
            parking = "La Paz marina"
        ),
        SpotRecord(
            id = "mexico-cerralvo",
            name = "Isla Cerralvo (Jacques Cousteau Island)",
            description = "Remote island with pristine conditions. Wahoo and dorado in season.",
            coordinates = Coordinates(24.1667, -109.8500),
            access = "boat",
            depth = 30,
            commonFish = listOf("Wahoo", "Dorado", "Yellowtail", "Pargo", "Cabrilla"),
            directions = "Boat from La Paz, 2hrs",
            parking = "La Paz marina"
        ),
        SpotRecord(
            id = "mexico-el-bajo",
            name = "El Bajo Seamount",
            description = "Underwater seamount with hammerhead sharks and big pelagics. Advanced.",
            coordinates = Coordinates(24.5833, -110.2833),
            access = "boat",
            depth = 20,
            commonFish = listOf("Hammerhead Shark", "Manta Ray", "Wahoo", "Tuna", "Jacks"),
            directions = "Boat from La Paz",
            parking = "Marina"
        ),
        SpotRecord(
            id = "mexico-la-reina",
            name = "La Reina",
            description = "Pinnacle with sea lions and schooling fish. Yellowtail aggregations.",
            coordinates = Coordinates(24.5500, -110.3167),
            access = "boat",
            depth = 25,
            commonFish = listOf("Yellowtail", "Sea Lion", "Cabrilla", "Pargo"),
            directions = "Near Espiritu Santo",
            parking = "La Paz marina"
        ),
        SpotRecord(
            id = "mexico-cabo-pulmo",
            name = "Cabo Pulmo National Park",
            description = "Oldest marine park on west coast. No-take zone - check boundaries.",
            coordinates = Coordinates(23.4333, -109.4167),
            access = "boat",
            depth = 20,
            commonFish = listOf("Mobula Ray", "Bull Shark", "Giant Grouper", "Jacks"),
            directions = "Boat from Cabo or La Ribera",
            parking = "Beach access"
        ),
        SpotRecord(
            id = "mexico-gordo-banks",
            name = "Gordo Banks",
            description = "Two seamounts off San Jose del Cabo. Big pelagics, hammerheads.",
            coordinates = Coordinates(23.0500, -109.4167),
            access = "boat",
            depth = 35,
            commonFish = listOf("Hammerhead Shark", "Yellowfin Tuna", "Wahoo", "Marlin"),
            directions = "Boat from San Jose del Cabo",
            parking = "Marina"
        ),

        // ==========================================
        // INDONESIA - Raja Ampat Specific Sites
        // ==========================================
        SpotRecord(
            id = "raja-ampat-cape-kri",
            name = "Cape Kri",
            description = "World record: 374 fish species on single dive. Pristine reef diversity.",
            coordinates = Coordinates(-0.5500, 130.6667),
            access = "boat",
            depth = 25,
            commonFish = listOf("Giant Trevally", "Dogtooth Tuna", "Barracuda", "Napoleon Wrasse", "Reef Shark"),
            directions = "1 min boat from Kri Eco Resort",
            parking = "Resort"
        ),
        SpotRecord(
            id = "raja-ampat-blue-magic",
            name = "Blue Magic",
            description = "Oceanic mantas, schools of fish, multiple shark species. Advanced drift dive.",
            coordinates = Coordinates(-0.5333, 130.6833),
            access = "boat",
            depth = 30,
            commonFish = listOf("Oceanic Manta", "Grey Reef Shark", "Blacktip Shark", "Trevally", "Tuna"),
            directions = "15 min boat from Mansuar Island",
            parking = "Resort"
        ),
        SpotRecord(
            id = "raja-ampat-sardines",
            name = "Sardines Reef",
            description = "Second most biodiverse site. Whitetips, hunting trevally, pygmy seahorses.",
            coordinates = Coordinates(-0.5600, 130.6500),
            access = "boat",
            depth = 20,
            commonFish = listOf("Whitetip Shark", "Giant Trevally", "Sardine Ball", "Barracuda"),
            directions = "10 min boat from Kri",
            parking = "Resort"
        ),
        SpotRecord(
            id = "raja-ampat-passage",
            name = "The Passage",
            description = "Narrow channel between Gam and Waigeo. Strong tidal flow, filter feeders.",
            coordinates = Coordinates(-0.4333, 130.5500),
            access = "boat",
            depth = 15,
            commonFish = listOf("Batfish", "Barracuda", "Soft Coral", "Wobbegong Shark"),
            directions = "Boat from Waisai or resort",
            parking = "Marina"
        ),
        SpotRecord(
            id = "raja-ampat-misool",
            name = "Misool (South Raja Ampat)",
            description = "Remote southern area with dramatic pinnacles and manta rays.",
            coordinates = Coordinates(-1.8833, 129.9833),
            access = "boat",
            depth = 30,
            commonFish = listOf("Manta Ray", "Giant Trevally", "Dogtooth Tuna", "Grouper", "Barracuda"),
            directions = "Liveaboard or Misool Eco Resort",
            parking = "Resort"
        ),

        // ==========================================
        // AUSTRALIA - Great Barrier Reef Specific Sites
        // ==========================================
        SpotRecord(
            id = "gbr-cairns-outer-reef",
            name = "Cairns Outer Reef",
            description = "Day trip distance outer reef. Coral trout, mackerel, trevally.",
            coordinates = Coordinates(-16.7500, 146.0000),
            access = "boat",
            depth = 20,
            commonFish = listOf("Coral Trout", "Spanish Mackerel", "Giant Trevally", "Red Emperor"),
            directions = "Boat from Cairns, 1.5hrs",
            parking = "Cairns marina"
        ),
        SpotRecord(
            id = "gbr-cooktown-ribbon-reefs",
            name = "Ribbon Reefs (Cooktown)",
            description = "Pristine ribbon reef system. Less pressure, bigger fish. Liveaboard recommended.",
            coordinates = Coordinates(-14.7500, 145.6500),
            access = "boat",
            depth = 25,
            commonFish = listOf("Dogtooth Tuna", "Coral Trout", "Giant Trevally", "Mackerel", "Wahoo"),
            directions = "Liveaboard from Cairns or Cooktown boat",
            parking = "Marina"
        ),
        SpotRecord(
            id = "australia-ningaloo-coral-bay",
            name = "Coral Bay (Ningaloo)",
            description = "Southern Ningaloo access. Whale sharks March-July. Shore diving possible.",
            coordinates = Coordinates(-23.1500, 113.7667),
            access = "shore",
            depth = 15,
            commonFish = listOf("Coral Trout", "Spanish Mackerel", "Giant Trevally", "Cobia"),
            directions = "Coral Bay township",
            parking = "Beach access"
        ),
        SpotRecord(
            id = "australia-ningaloo-exmouth",
            name = "Exmouth (Ningaloo North)",
            description = "Northern Ningaloo. Navy Pier is legendary dive - permit required.",
            coordinates = Coordinates(-21.9333, 114.1333),
            access = "boat",
            depth = 20,
            commonFish = listOf("Giant Trevally", "Coral Trout", "Potato Cod", "Spanish Mackerel"),
            directions = "Boat from Exmouth",
            parking = "Exmouth marina"
        ),
        SpotRecord(
            id = "australia-montague",
            name = "Montague Island (NSW)",
            description = "Temperate water, huge kingfish and jewfish. Seal colony.",
            coordinates = Coordinates(-36.2500, 150.2333),
            access = "boat",
            depth = 25,
            commonFish = listOf("Kingfish", "Jewfish", "Blue Groper", "Snapper"),
            directions = "Boat from Narooma",
            parking = "Narooma boat ramp"
        ),

        // ==========================================
        // MEDITERRANEAN - ITALY
        // ==========================================
        
        // Sardinia
        SpotRecord(
            id = "sardinia-capo-caccia",
            name = "Capo Caccia",
            description = "Dramatic cliffs and underwater caves. One of Sardinia's premier spearfishing destinations.",
            coordinates = Coordinates(40.5667, 8.1667),
            access = "boat",
            depth = 30,
            commonFish = listOf("Grouper", "Dentex", "Amberjack", "Sea Bream", "Barracuda"),
            directions = "Boat from Alghero",
            parking = "Alghero marina"
        ),
        SpotRecord(
            id = "sardinia-castelsardo",
            name = "Castelsardo",
            description = "Rocky coastline with caves, seagrass beds, and sandy patches. Excellent dentex.",
            coordinates = Coordinates(40.9133, 8.7133),
            access = "shore",
            depth = 20,
            commonFish = listOf("Dentex", "Sea Bass", "Grouper", "Leerfish", "Amberjack"),
            directions = "North Sardinia coast",
            parking = "Town parking"
        ),
        SpotRecord(
            id = "sardinia-stintino",
            name = "Stintino",
            description = "Rocky bottom with sand strips. Famous for sea bass and mullet.",
            coordinates = Coordinates(40.9400, 8.2267),
            access = "shore",
            depth = 15,
            commonFish = listOf("Sea Bass", "Mullet", "Dentex", "Bream"),
            directions = "Northwest tip of Sardinia",
            parking = "Beach parking"
        ),
        SpotRecord(
            id = "sardinia-porto-ferro",
            name = "Porto Ferro",
            description = "Rocky seabed with cracks and ravines. Sea bass in winter, snapper in summer.",
            coordinates = Coordinates(40.6833, 8.1833),
            access = "shore",
            depth = 18,
            commonFish = listOf("Sea Bass", "Snapper", "Sea Bream", "Octopus"),
            directions = "West coast near Alghero",
            parking = "Beach access"
        ),
        SpotRecord(
            id = "sardinia-sant-antioco",
            name = "Sant'Antioco Island",
            description = "Southern Sardinia island with crystal clear waters and diverse reef.",
            coordinates = Coordinates(39.0667, 8.4500),
            access = "boat",
            depth = 25,
            commonFish = listOf("Grouper", "Dentex", "Amberjack", "Barracuda"),
            directions = "Bridge from mainland or boat",
            parking = "Town marina"
        ),
        SpotRecord(
            id = "sardinia-carloforte",
            name = "Carloforte (San Pietro Island)",
            description = "Pristine island waters known for bluefin tuna migration route.",
            coordinates = Coordinates(39.1500, 8.3167),
            access = "boat",
            depth = 30,
            commonFish = listOf("Bluefin Tuna", "Amberjack", "Dentex", "Grouper"),
            directions = "Ferry from Portovesme",
            parking = "Ferry terminal"
        ),
        SpotRecord(
            id = "sardinia-gallura",
            name = "Costa Smeralda (Gallura)",
            description = "Wind-carved granite rocks, white sand, turquoise water. Luxury coast diving.",
            coordinates = Coordinates(41.1000, 9.5000),
            access = "boat",
            depth = 20,
            commonFish = listOf("Dentex", "Sea Bream", "Grouper", "Barracuda"),
            directions = "Northeast Sardinia, boat from Porto Cervo",
            parking = "Marina"
        ),
        SpotRecord(
            id = "sardinia-maddalena",
            name = "La Maddalena Archipelago",
            description = "National park with stunning islands and marine reserve. Check regulations.",
            coordinates = Coordinates(41.2167, 9.4000),
            access = "boat",
            depth = 25,
            commonFish = listOf("Grouper", "Dentex", "Sea Bass", "Bream"),
            directions = "Ferry from Palau",
            parking = "Palau ferry terminal"
        ),

        // Sicily
        SpotRecord(
            id = "sicily-pantelleria",
            name = "Pantelleria - Spadillo Point",
            description = "Volcanic island between Sicily and Tunisia. Black rock formations, big grouper.",
            coordinates = Coordinates(36.7833, 11.9833),
            access = "boat",
            depth = 35,
            commonFish = listOf("Brown Grouper", "Amberjack", "Dentex", "Parrotfish", "Barracuda"),
            directions = "Ferry or flight from Trapani",
            parking = "Marina"
        ),
        SpotRecord(
            id = "sicily-ustica",
            name = "Ustica Island",
            description = "Marine protected area with exceptional visibility and Mediterranean pelagics.",
            coordinates = Coordinates(38.7000, 13.1833),
            access = "boat",
            depth = 35,
            commonFish = listOf("Amberjack", "Dentex", "Grouper", "Barracuda", "Tuna"),
            directions = "Ferry from Palermo",
            parking = "Palermo port"
        ),
        SpotRecord(
            id = "sicily-favignana",
            name = "Favignana (Egadi Islands)",
            description = "Historic tuna fishing grounds. Clear waters, underwater caves.",
            coordinates = Coordinates(37.9333, 12.3333),
            access = "boat",
            depth = 25,
            commonFish = listOf("Bluefin Tuna", "Amberjack", "Grouper", "Dentex"),
            directions = "Ferry from Trapani",
            parking = "Trapani port"
        ),
        SpotRecord(
            id = "sicily-taormina",
            name = "Taormina Coast",
            description = "East Sicily coast with dramatic underwater cliffs and Ionian Sea species.",
            coordinates = Coordinates(37.8500, 15.2833),
            access = "boat",
            depth = 30,
            commonFish = listOf("Grouper", "Dentex", "Swordfish", "Amberjack"),
            directions = "Boat from Taormina or Giardini Naxos",
            parking = "Marina"
        ),
        SpotRecord(
            id = "sicily-siracusa",
            name = "Siracusa Coast",
            description = "Ancient Greek waters with rocky reefs and sea caves.",
            coordinates = Coordinates(37.0667, 15.2833),
            access = "shore",
            depth = 20,
            commonFish = listOf("Sea Bass", "Bream", "Grouper", "Octopus"),
            directions = "Southeast Sicily coast",
            parking = "Various beach access"
        ),

        // Mainland Italy
        SpotRecord(
            id = "italy-portofino",
            name = "Portofino Marine Reserve",
            description = "Liguria's premier dive site. Check MPA zones for spearfishing rules.",
            coordinates = Coordinates(44.3000, 9.2167),
            access = "boat",
            depth = 30,
            commonFish = listOf("Grouper", "Dentex", "Sea Bass", "Bream", "Barracuda"),
            directions = "Boat from Santa Margherita or Rapallo",
            parking = "Marina"
        ),
        SpotRecord(
            id = "italy-elba",
            name = "Elba Island",
            description = "Tuscan archipelago with varied diving. Napoleon's exile island.",
            coordinates = Coordinates(42.7667, 10.2667),
            access = "boat",
            depth = 30,
            commonFish = listOf("Grouper", "Dentex", "Amberjack", "Sea Bream"),
            directions = "Ferry from Piombino",
            parking = "Ferry terminal"
        ),
        SpotRecord(
            id = "italy-ponza",
            name = "Ponza Island",
            description = "Pontine Islands with volcanic formations and exceptional clarity.",
            coordinates = Coordinates(40.9000, 12.9667),
            access = "boat",
            depth = 35,
            commonFish = listOf("Grouper", "Dentex", "Amberjack", "Barracuda"),
            directions = "Ferry from Anzio or Formia",
            parking = "Ferry terminal"
        ),
        SpotRecord(
            id = "italy-amalfi",
            name = "Amalfi Coast",
            description = "Dramatic cliffs diving along the famous coastline.",
            coordinates = Coordinates(40.6333, 14.6000),
            access = "boat",
            depth = 25,
            commonFish = listOf("Sea Bass", "Bream", "Grouper", "Octopus"),
            directions = "Boat from Amalfi or Positano",
            parking = "Marina"
        ),

        // ==========================================
        // MEDITERRANEAN - FRANCE
        // ==========================================
        SpotRecord(
            id = "corsica-scandola",
            name = "Scandola Reserve (Corsica)",
            description = "UNESCO World Heritage site with pristine Mediterranean waters and red cliffs.",
            coordinates = Coordinates(42.3667, 8.5500),
            access = "boat",
            depth = 30,
            commonFish = listOf("Dentex", "Grouper", "Sea Bass", "Bream", "Barracuda"),
            directions = "Boat from Porto or Calvi",
            parking = "Porto marina"
        ),
        SpotRecord(
            id = "corsica-bonifacio",
            name = "Bonifacio",
            description = "Southern Corsica with limestone cliffs and crystal waters. Near Lavezzi.",
            coordinates = Coordinates(41.3872, 9.1594),
            access = "boat",
            depth = 25,
            commonFish = listOf("Dentex", "Grouper", "Sea Bream", "Barracuda"),
            directions = "Boat from Bonifacio marina",
            parking = "Town marina"
        ),
        SpotRecord(
            id = "corsica-porto-vecchio",
            name = "Porto-Vecchio",
            description = "Southeast Corsica with beautiful bays and reef systems.",
            coordinates = Coordinates(41.5917, 9.2794),
            access = "boat",
            depth = 20,
            commonFish = listOf("Sea Bass", "Dentex", "Bream", "Grouper"),
            directions = "Boat from Porto-Vecchio marina",
            parking = "Marina"
        ),
        SpotRecord(
            id = "corsica-cap-corse",
            name = "Cap Corse",
            description = "Northern tip of Corsica. Rugged coastline with strong currents and big fish.",
            coordinates = Coordinates(42.9667, 9.3500),
            access = "boat",
            depth = 30,
            commonFish = listOf("Dentex", "Amberjack", "Grouper", "Tuna"),
            directions = "Boat from Bastia or Macinaggio",
            parking = "Bastia marina"
        ),
        SpotRecord(
            id = "france-marseille-riou",
            name = "Riou Island (Marseille)",
            description = "Offshore island with dramatic caves and walls. Heart of Cousteau country.",
            coordinates = Coordinates(43.1833, 5.3833),
            access = "boat",
            depth = 35,
            commonFish = listOf("Grouper", "Dentex", "Sea Bass", "Bream", "Barracuda"),
            directions = "Boat from Marseille Vieux-Port",
            parking = "Marseille marina"
        ),
        SpotRecord(
            id = "france-marseille-frioul",
            name = "Frioul Islands",
            description = "Archipelago off Marseille with varied diving and good spearfishing.",
            coordinates = Coordinates(43.2800, 5.3100),
            access = "boat",
            depth = 25,
            commonFish = listOf("Sea Bass", "Bream", "Grouper", "Dentex"),
            directions = "Ferry from Vieux-Port Marseille",
            parking = "Marseille port"
        ),
        SpotRecord(
            id = "france-cassis",
            name = "Cassis Calanques",
            description = "Dramatic limestone calanques with excellent diving and protected areas.",
            coordinates = Coordinates(43.2167, 5.5333),
            access = "boat",
            depth = 30,
            commonFish = listOf("Grouper", "Dentex", "Sea Bass", "Bream"),
            directions = "Boat from Cassis",
            parking = "Cassis port"
        ),
        SpotRecord(
            id = "france-hyeres",
            name = "Hyeres Islands (Port-Cros)",
            description = "National park islands off Var coast. Some areas protected.",
            coordinates = Coordinates(43.0000, 6.4000),
            access = "boat",
            depth = 30,
            commonFish = listOf("Grouper", "Dentex", "Barracuda", "Amberjack"),
            directions = "Ferry from Hyeres or Toulon",
            parking = "Hyeres port"
        ),
        SpotRecord(
            id = "france-nice",
            name = "Nice - Cap Ferrat",
            description = "French Riviera diving with deep drop-offs and Mediterranean species.",
            coordinates = Coordinates(43.6833, 7.3333),
            access = "boat",
            depth = 35,
            commonFish = listOf("Dentex", "Grouper", "Sea Bream", "Barracuda"),
            directions = "Boat from Nice or Villefranche",
            parking = "Nice port"
        ),

        // ==========================================
        // MEDITERRANEAN - SPAIN
        // ==========================================
        SpotRecord(
            id = "spain-costa-brava-medes",
            name = "Medes Islands (Costa Brava)",
            description = "Protected marine reserve with exceptional grouper population.",
            coordinates = Coordinates(42.0500, 3.2167),
            access = "boat",
            depth = 30,
            commonFish = listOf("Grouper", "Sea Bass", "Dentex", "Bream", "Barracuda"),
            directions = "Boat from L'Estartit",
            parking = "L'Estartit marina"
        ),
        SpotRecord(
            id = "spain-costa-brava-tossa",
            name = "Tossa de Mar",
            description = "Rocky Costa Brava coastline with medieval castle backdrop.",
            coordinates = Coordinates(41.7200, 2.9333),
            access = "shore",
            depth = 20,
            commonFish = listOf("Sea Bass", "Bream", "Grouper", "Octopus"),
            directions = "Costa Brava, north of Barcelona",
            parking = "Town parking"
        ),
        SpotRecord(
            id = "spain-cabo-palos",
            name = "Cabo de Palos",
            description = "Marine reserve south of Murcia. Some of Spain's best diving.",
            coordinates = Coordinates(37.6333, -0.7000),
            access = "boat",
            depth = 35,
            commonFish = listOf("Grouper", "Dentex", "Amberjack", "Barracuda", "Tuna"),
            directions = "Boat from Cabo de Palos harbor",
            parking = "Harbor parking"
        ),
        SpotRecord(
            id = "spain-formentera",
            name = "Formentera",
            description = "Balearic island with crystal clear water and Posidonia seagrass.",
            coordinates = Coordinates(38.7000, 1.4333),
            access = "boat",
            depth = 25,
            commonFish = listOf("Grouper", "Dentex", "Sea Bream", "Barracuda"),
            directions = "Ferry from Ibiza",
            parking = "Ibiza port"
        ),
        SpotRecord(
            id = "spain-mallorca-cabrera",
            name = "Cabrera Island (Mallorca)",
            description = "National park island with pristine waters. Permit required.",
            coordinates = Coordinates(39.1500, 2.9500),
            access = "boat",
            depth = 35,
            commonFish = listOf("Grouper", "Dentex", "Amberjack", "Barracuda"),
            directions = "Boat from Colonia Sant Jordi, Mallorca",
            parking = "Marina"
        ),
        SpotRecord(
            id = "spain-menorca-fornells",
            name = "Fornells (Menorca)",
            description = "North Menorca bay with excellent reef diving.",
            coordinates = Coordinates(40.0500, 4.1333),
            access = "boat",
            depth = 25,
            commonFish = listOf("Grouper", "Dentex", "Sea Bass", "Bream"),
            directions = "Boat from Fornells harbor",
            parking = "Fornells"
        ),

        // Canary Islands (Spain)
        SpotRecord(
            id = "canary-tenerife",
            name = "Tenerife South",
            description = "Volcanic underwater landscape with Atlantic species.",
            coordinates = Coordinates(28.0500, -16.7167),
            access = "boat",
            depth = 30,
            commonFish = listOf("Amberjack", "Barracuda", "Grouper", "Wahoo"),
            directions = "Boat from Las Galletas or Los Cristianos",
            parking = "Marina"
        ),
        SpotRecord(
            id = "canary-lanzarote",
            name = "Lanzarote - Museo Atlantico",
            description = "Volcanic island with underwater sculpture museum and excellent diving.",
            coordinates = Coordinates(28.9167, -13.6500),
            access = "boat",
            depth = 15,
            commonFish = listOf("Angel Shark", "Grouper", "Bream", "Barracuda"),
            directions = "Boat from Playa Blanca",
            parking = "Marina"
        ),
        SpotRecord(
            id = "canary-fuerteventura",
            name = "Fuerteventura - El Canon",
            description = "Rocky-sandy seabeds with angel sharks and rays.",
            coordinates = Coordinates(28.0500, -14.3500),
            access = "boat",
            depth = 14,
            commonFish = listOf("Angel Shark", "Stingray", "Grouper", "Bream"),
            directions = "Boat from Morro Jable",
            parking = "Harbor"
        ),
        SpotRecord(
            id = "canary-el-hierro",
            name = "El Hierro - Mar de las Calmas",
            description = "Pristine volcanic island with hammerhead sharks and exceptional vis.",
            coordinates = Coordinates(27.7500, -18.0000),
            access = "boat",
            depth = 40,
            commonFish = listOf("Hammerhead Shark", "Manta Ray", "Amberjack", "Grouper"),
            directions = "Boat from La Restinga",
            parking = "La Restinga"
        ),

        // ==========================================
        // MEDITERRANEAN - GREECE
        // ==========================================
        SpotRecord(
            id = "greece-crete-chania",
            name = "Chania Coast (Crete)",
            description = "Northwest Crete with beautiful bays and reef systems.",
            coordinates = Coordinates(35.5167, 24.0167),
            access = "boat",
            depth = 25,
            commonFish = listOf("Grouper", "Dentex", "Amberjack", "Sea Bream"),
            directions = "Boat from Chania harbor",
            parking = "Chania port"
        ),
        SpotRecord(
            id = "greece-crete-elounda",
            name = "Elounda (Crete)",
            description = "East Crete with Spinalonga island and clear Aegean waters.",
            coordinates = Coordinates(35.2667, 25.7333),
            access = "boat",
            depth = 30,
            commonFish = listOf("Grouper", "Dentex", "Sea Bass", "Bream"),
            directions = "Boat from Elounda or Agios Nikolaos",
            parking = "Marina"
        ),
        SpotRecord(
            id = "greece-antikythera",
            name = "Antikythera Island",
            description = "Remote island between Crete and Peloponnese. Pristine diving.",
            coordinates = Coordinates(35.8667, 23.3000),
            access = "boat",
            depth = 35,
            commonFish = listOf("Grouper", "Amberjack", "Dentex", "Tuna"),
            directions = "Charter from Chania",
            parking = "Chania port"
        ),
        SpotRecord(
            id = "greece-gavdos",
            name = "Gavdos Island",
            description = "Europe's southernmost point. Remote and pristine waters.",
            coordinates = Coordinates(34.8417, 24.0833),
            access = "boat",
            depth = 30,
            commonFish = listOf("Grouper", "Dentex", "Amberjack", "Barracuda"),
            directions = "Ferry from Paleochora, Crete",
            parking = "Paleochora"
        ),
        SpotRecord(
            id = "greece-cyclades-mykonos",
            name = "Mykonos",
            description = "Cycladic island with Aegean diving and cosmopolitan scene.",
            coordinates = Coordinates(37.4467, 25.3289),
            access = "boat",
            depth = 25,
            commonFish = listOf("Grouper", "Sea Bream", "Dentex", "Barracuda"),
            directions = "Boat from Mykonos town",
            parking = "Marina"
        ),
        SpotRecord(
            id = "greece-cyclades-santorini",
            name = "Santorini Caldera",
            description = "Volcanic caldera with unique underwater formations.",
            coordinates = Coordinates(36.4000, 25.4333),
            access = "boat",
            depth = 30,
            commonFish = listOf("Grouper", "Sea Bass", "Bream", "Octopus"),
            directions = "Boat from Vlychada or Ammoudi",
            parking = "Marina"
        ),
        SpotRecord(
            id = "greece-dodecanese-rhodes",
            name = "Rhodes",
            description = "Large Dodecanese island with varied coastline and Turkish proximity.",
            coordinates = Coordinates(36.4333, 28.2167),
            access = "boat",
            depth = 30,
            commonFish = listOf("Grouper", "Dentex", "Amberjack", "Sea Bream"),
            directions = "Boat from Rhodes town or Lindos",
            parking = "Marina"
        ),
        SpotRecord(
            id = "greece-ionian-zakynthos",
            name = "Zakynthos (Zante)",
            description = "Ionian island famous for Navagio beach and sea caves.",
            coordinates = Coordinates(37.7833, 20.8833),
            access = "boat",
            depth = 25,
            commonFish = listOf("Sea Bass", "Grouper", "Bream", "Dentex"),
            directions = "Boat from Zakynthos town",
            parking = "Town port"
        ),

        // ==========================================
        // MEDITERRANEAN - CROATIA & ADRIATIC
        // ==========================================
        SpotRecord(
            id = "croatia-kornati",
            name = "Kornati Islands",
            description = "National park archipelago with 89 islands and crystal Adriatic.",
            coordinates = Coordinates(43.8000, 15.3000),
            access = "boat",
            depth = 30,
            commonFish = listOf("Dentex", "Sea Bass", "Grouper", "Bream", "Amberjack"),
            directions = "Boat from Zadar or Sibenik",
            parking = "Marina"
        ),
        SpotRecord(
            id = "croatia-vis",
            name = "Vis Island",
            description = "Remote Croatian island with WWII wrecks and pristine diving.",
            coordinates = Coordinates(43.0500, 16.1833),
            access = "boat",
            depth = 35,
            commonFish = listOf("Dentex", "Grouper", "Amberjack", "Sea Bass"),
            directions = "Ferry from Split",
            parking = "Split ferry"
        ),
        SpotRecord(
            id = "croatia-hvar",
            name = "Hvar Island",
            description = "Lavender island with clear waters and diverse marine life.",
            coordinates = Coordinates(43.1667, 16.6500),
            access = "boat",
            depth = 25,
            commonFish = listOf("Sea Bass", "Dentex", "Bream", "Grouper"),
            directions = "Ferry from Split or catamaran from Dubrovnik",
            parking = "Split port"
        ),
        SpotRecord(
            id = "croatia-dubrovnik",
            name = "Dubrovnik Coast",
            description = "South Croatian coast near old town with clear Adriatic waters.",
            coordinates = Coordinates(42.6500, 18.0833),
            access = "boat",
            depth = 30,
            commonFish = listOf("Dentex", "Grouper", "Sea Bass", "Bream"),
            directions = "Boat from Dubrovnik",
            parking = "Gruz port"
        ),

        // ==========================================
        // MEDITERRANEAN - TURKEY
        // ==========================================
        SpotRecord(
            id = "turkey-kas",
            name = "Kas",
            description = "Turkish Riviera with ancient Lycian ruins underwater.",
            coordinates = Coordinates(36.2000, 29.6333),
            access = "boat",
            depth = 30,
            commonFish = listOf("Grouper", "Dentex", "Amberjack", "Sea Bream"),
            directions = "Boat from Kas harbor",
            parking = "Town harbor"
        ),
        SpotRecord(
            id = "turkey-bodrum",
            name = "Bodrum Peninsula",
            description = "Aegean coast with Greek island views and diverse diving.",
            coordinates = Coordinates(37.0333, 27.4333),
            access = "boat",
            depth = 25,
            commonFish = listOf("Grouper", "Sea Bass", "Bream", "Octopus"),
            directions = "Boat from Bodrum marina",
            parking = "Marina"
        ),

        // ==========================================
        // AUSTRALIA
        // ==========================================
        SpotRecord(
            id = "australia-ningaloo",
            name = "Ningaloo Reef",
            description = "World Heritage fringing reef. Coral trout and Spanish mackerel heaven.",
            coordinates = Coordinates(-22.6833, 113.6667),
            access = "shore",
            depth = 15,
            commonFish = listOf("Coral Trout", "Spanish Mackerel", "Giant Trevally", "Red Emperor"),
            directions = "Access from Exmouth or Coral Bay",
            parking = "Beach access points"
        ),
        SpotRecord(
            id = "australia-montague",
            name = "Montague Island",
            description = "NSW south coast with kingfish, jewfish, and seal colonies.",
            coordinates = Coordinates(-36.2500, 150.2333),
            access = "boat",
            depth = 25,
            commonFish = listOf("Kingfish", "Jewfish", "Blue Groper", "Snapper"),
            directions = "Boat from Narooma",
            parking = "Boat ramp"
        ),
        SpotRecord(
            id = "nz-poor-knights",
            name = "Poor Knights Islands",
            description = "New Zealand's best dive site with subtropical species.",
            coordinates = Coordinates(-35.4667, 174.7333),
            access = "boat",
            depth = 30,
            commonFish = listOf("Kingfish", "Snapper", "Blue Maomao", "Trevally"),
            directions = "Boat from Tutukaka",
            parking = "Marina"
        )
    )

    /**
     * Get spots within radius of coordinates using Haversine formula.
     */
    fun getSpotsNear(lat: Double, lon: Double, radiusKm: Int): List<SpotRecord> {
        return spots.filter { spot ->
            val distance = haversineDistance(lat, lon, spot.coordinates.lat, spot.coordinates.lon)
            distance <= radiusKm
        }.sortedBy { spot ->
            haversineDistance(lat, lon, spot.coordinates.lat, spot.coordinates.lon)
        }
    }

    /**
     * Get spot by ID.
     */
    fun getSpot(id: String): SpotRecord? {
        return spots.find { it.id == id }
    }

    /**
     * Get all spots.
     */
    fun getAllSpots(): List<SpotRecord> = spots

    /**
     * Haversine formula for distance between two coordinates.
     */
    private fun haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val r = 6371.0 // Earth's radius in km
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = sin(dLat / 2).pow(2) + cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) * sin(dLon / 2).pow(2)
        val c = 2 * asin(sqrt(a))
        return r * c
    }
}
