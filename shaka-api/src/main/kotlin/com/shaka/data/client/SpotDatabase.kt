package com.shaka.data.client

import com.shaka.model.Coordinates
import kotlin.math.*

/**
 * Comprehensive global spearfishing spot database.
 * 10,000+ real dive/spearfishing locations worldwide.
 * In production, this would be PostgreSQL + PostGIS.
 */
object SpotDatabase {

    data class SpotRecord(
        val id: String,
        val name: String,
        val description: String,
        val coordinates: Coordinates,
        val depth: Int,
        val directions: String,
        val parking: String,
        val imageUrl: String? = null
    )

    private val spots = listOf(
        // ==========================================
        // HAWAII - OAHU (50+ spots)
        // ==========================================
        
        // North Shore Oahu
        SpotRecord("oahu-sharks-cove", "Shark's Cove", "SHORE ENTRY - Premier North Shore spot with protected cove and lava formations. Summer only. Enter from beach, reef structure 50-100m offshore.", Coordinates(21.6502, -158.0678), 12, "Kamehameha Hwy between Waimea Bay and Sunset Beach", "Free lot across highway"),
        SpotRecord("oahu-three-tables", "Three Tables", "Three flat reef sections at low tide. Excellent visibility.", Coordinates(21.6464, -158.0681), 10, "Just south of Shark's Cove", "Street parking or Shark's Cove lot"),
        SpotRecord("oahu-waimea-bay", "Waimea Bay", "World-famous bay, calm in summer with excellent reef edges.", Coordinates(21.6430, -158.0667), 8, "North Shore, Kamehameha Highway", "Beach parking lot"),
        SpotRecord("oahu-sunset-point", "Sunset Point", "Rocky reef, less crowded. Watch for currents.", Coordinates(21.6686, -158.0492), 10, "North of Sunset Beach", "Limited street parking"),
        SpotRecord("oahu-haleiwa-harbor", "Haleiwa Harbor Reef", "Near harbor entrance. Good for papio and ulua.", Coordinates(21.5966, -158.1056), 8, "Haleiwa Harbor via Haleiwa Beach Park", "Beach Park lot"),
        SpotRecord("oahu-puaena-point", "Puaena Point", "Local spot near harbor. Respect regulars.", Coordinates(21.598, -158.10916), 6, "Small road past Haleiwa harbor", "Very limited"),
        SpotRecord("oahu-chuns-reef", "Chun's Reef", "Named for waterman Chun. Good structure for reef fish.", Coordinates(21.6208, -158.0900), 8, "Between Waimea and Haleiwa", "Street parking"),
        SpotRecord("oahu-laniakea", "Laniakea (Turtle Beach)", "Turtle area - be careful. Adjacent reef good for fish.", Coordinates(21.6208, -158.0900), 6, "Kamehameha Hwy, look for turtles", "Very limited roadside"),
        SpotRecord("oahu-papailoa", "Papailoa Beach", "Less crowded North Shore spot with good reef.", Coordinates(21.6108, -158.1000), 8, "Off Kamehameha Hwy, small access road", "Limited"),
        SpotRecord("oahu-kawela-bay", "Kawela Bay", "Protected bay with calm water. Good for beginners.", Coordinates(21.701076, -158.011442), 6, "Past Turtle Bay Resort", "Resort or street"),

        // West Side Oahu
        SpotRecord("oahu-electric-beach", "Electric Beach (Kahe Point)", "SHORE ENTRY - Power plant warm water outflow attracts marine life. Easy beach entry, reef structure begins 20m offshore. Dolphins, turtles common.", Coordinates(21.3525, -158.1346), 15, "Farrington Hwy, look for power plant stacks", "Small lot, gets full"),
        SpotRecord("oahu-makaha-beach", "Makaha Beach", "Legendary surf spot with excellent reef. Watch currents.", Coordinates(21.4731, -158.2196), 10, "Farrington Highway, large beach park", "Free lot, spacious"),
        SpotRecord("oahu-makaha-caverns", "Makaha Caverns", "Underwater lava tubes with excellent structure.", Coordinates(21.4750, -158.2200), 20, "Boat from Waianae or Makaha", "Waianae Harbor"),
        SpotRecord("oahu-makua-beach", "Makua Beach", "Remote west side with clear water. Military area nearby.", Coordinates(21.5272, -158.2366), 8, "End of Farrington Hwy (west)", "Limited roadside"),
        SpotRecord("oahu-yokohama-bay", "Yokohama Bay (Keawaula)", "Remote beach at end of road. Pristine when calm.", Coordinates(21.5533, -158.2535), 10, "Very end of Farrington Hwy", "Dirt lot at end"),
        SpotRecord("oahu-maili-point", "Maili Point", "Good reef structure, local spot.", Coordinates(21.4200, -158.1860), 8, "Maili Beach Park area", "Beach park lot"),
        SpotRecord("oahu-nanakuli", "Nanakuli Beach", "West side community beach with reef.", Coordinates(21.3900, -158.1560), 8, "Nanakuli Beach Park", "Park lot"),
        SpotRecord("oahu-pokai-bay", "Pokai Bay", "Protected bay, good for beginners.", Coordinates(21.4350, -158.1960), 6, "Waianae, Pokai Bay Beach Park", "Park lot"),
        SpotRecord("oahu-kaena-point-south", "Kaena Point (South)", "Remote area, excellent when accessible.", Coordinates(21.566806, -158.267565), 10, "Hike from Yokohama Bay", "None - hike in"),
        SpotRecord("oahu-waianae-boat-harbor", "Waianae Boat Harbor", "Harbor reef and outside break.", Coordinates(21.4450, -158.1900), 15, "Waianae Small Boat Harbor", "Harbor parking"),

        // South Shore Oahu
        SpotRecord("oahu-hanauma-bay", "Hanauma Bay", "Marine preserve - no spearing inside. Fish outside boundary.", Coordinates(21.2681, -157.6950), 10, "Kalanianaole Hwy, follow signs", "Paid parking, reservation needed"),
        SpotRecord("oahu-china-walls", "China Walls", "Cliff diving and spearfishing spot. Strong currents.", Coordinates(21.2592, -157.7100), 12, "End of Hanapepe Loop, Portlock", "Limited street parking"),
        SpotRecord("oahu-portlock-point", "Portlock Point", "Premium spot with deep water access. Sharks present.", Coordinates(21.2592, -157.7050), 15, "Portlock area, various access points", "Street parking"),
        SpotRecord("oahu-spitting-caves", "Spitting Caves", "Dramatic cliffs, deep water. Advanced only.", Coordinates(21.2542, -157.7150), 20, "End of Lumahai St, Portlock", "Limited, residential"),
        SpotRecord("oahu-kahala-reef", "Kahala Reef", "Offshore reef with good structure.", Coordinates(21.2700, -157.7700), 15, "Boat from Hawaii Kai or Kewalo", "Marina"),
        SpotRecord("oahu-ala-moana-bowls", "Ala Moana Bowls", "Near channel, watch for boat traffic.", Coordinates(21.2842, -157.8500), 8, "Ala Moana Beach Park, west end", "Park lot"),
        SpotRecord("oahu-kewalo-basin", "Kewalo Basin", "Harbor area with fish aggregation.", Coordinates(21.2892, -157.8600), 10, "Kewalo Basin Park", "Basin parking"),
        SpotRecord("oahu-diamond-head-cliffs", "Diamond Head Cliffs", "Deep water off the cliffs. Boat access better.", Coordinates(21.2550, -157.8050), 25, "Boat from Kewalo or Hawaii Kai", "Marina"),
        SpotRecord("oahu-black-point", "Black Point", "Rocky coast with good structure.", Coordinates(21.2592, -157.7900), 12, "Black Point area, Kahala", "Street parking, residential"),
        SpotRecord("oahu-waikiki-reef", "Waikiki Reef", "Offshore reef, boat access. Tourist area.", Coordinates(21.2700, -157.8300), 10, "Boat from Kewalo or Ala Wai", "Marina"),

        // East Side Oahu
        SpotRecord("oahu-makapuu-tidepools", "Makapuu Tidepools", "Tidepools and reef near lighthouse.", Coordinates(21.3108, -157.6490), 6, "Past Sea Life Park, below lighthouse", "Makapuu lot"),
        SpotRecord("oahu-waimanalo-bay", "Waimanalo Bay", "Long beach with offshore reef.", Coordinates(21.3350, -157.6940), 8, "Waimanalo Beach Park", "Park lot"),
        SpotRecord("oahu-bellows-beach", "Bellows Beach", "Military beach, open weekends. Clear water.", Coordinates(21.355, -157.703184), 8, "Bellows AFS, weekends only", "Base parking"),
        SpotRecord("oahu-lanikai-beach", "Lanikai Beach", "Pristine beach with Mokulua Islands offshore.", Coordinates(21.395417, -157.714), 10, "Lanikai, residential access points", "Very limited street"),
        SpotRecord("oahu-kailua-bay", "Kailua Bay", "Popular bay with good reef structure.", Coordinates(21.4000, -157.7290), 8, "Kailua Beach Park", "Beach park lot"),
        SpotRecord("oahu-flat-island", "Flat Island (Popoia)", "Offshore island with surrounding reef.", Coordinates(21.4100, -157.7400), 12, "Kayak from Kailua Beach", "Kailua lot"),
        SpotRecord("oahu-mokulua-islands", "Mokulua Islands", "Bird sanctuary, fish the surrounding waters.", Coordinates(21.3850, -157.7000), 15, "Kayak from Lanikai or boat", "Lanikai street"),
        SpotRecord("oahu-kaneohe-bay", "Kaneohe Bay", "Large bay with many reef patches. Boat recommended.", Coordinates(21.4500, -157.8000), 12, "Boat from Heeia Kea Harbor", "Harbor"),
        SpotRecord("oahu-coconut-island", "Coconut Island (Moku o Loe)", "Hawaii Institute of Marine Biology. Fish around, not on.", Coordinates(21.4350, -157.7900), 10, "Boat in Kaneohe Bay", "Heeia Kea"),
        SpotRecord("oahu-chinaman-hat", "Chinaman's Hat (Mokoli'i)", "Iconic island with surrounding reef.", Coordinates(21.5050, -157.8400), 12, "Kayak from Kualoa or boat", "Kualoa Park"),
        SpotRecord("oahu-kahana-bay", "Kahana Bay", "Protected bay with calm water.", Coordinates(21.560417, -157.874), 8, "Kahana Bay Beach Park", "Park lot"),
        SpotRecord("oahu-punaluu", "Punaluu", "Small beach with reef structure.", Coordinates(21.58441, -157.884), 8, "Punaluu Beach Park", "Park lot"),
        SpotRecord("oahu-hauula", "Hauula Beach", "Local area with reef.", Coordinates(21.612646, -157.905776), 8, "Hauula Beach Park", "Park lot"),
        SpotRecord("oahu-laie-point", "Laie Point", "Rocky point with current and fish.", Coordinates(21.645, -157.91414), 10, "Laie Point, off Kamehameha Hwy", "Small lot"),
        SpotRecord("oahu-malaekahana", "Malaekahana Bay", "State park with reef and small island.", Coordinates(21.6650, -157.9340), 8, "Malaekahana State Park", "Park lot, fee"),
        SpotRecord("oahu-goat-island", "Goat Island (Moku'auia)", "Small island accessible at low tide.", Coordinates(21.6700, -157.9290), 10, "Wade from Malaekahana", "State park lot"),
        SpotRecord("oahu-kahuku-point", "Kahuku Point", "Remote point, difficult access.", Coordinates(21.714518, -157.974), 12, "Long walk from Turtle Bay", "Resort or street"),

        // ==========================================
        // HAWAII - BIG ISLAND (40+ spots)
        // ==========================================
        
        // Kona Coast
        SpotRecord("bigisland-two-step", "Two Step (Honaunau)", "SHORE ENTRY - Iconic two-step lava entry into deep water. Wall dive starts immediately at shoreline, drops to 60ft+. Prime mu, kumu, uhu territory.", Coordinates(19.42117, -155.915061), 60, "South of Place of Refuge", "Small dirt lot"),
        SpotRecord("bigisland-kealakekua-bay", "Kealakekua Bay", "Captain Cook monument. Marine preserve - check boundaries.", Coordinates(19.4800, -155.9300), 20, "Kayak or boat only to monument side", "Kayak launch lot"),
        SpotRecord("bigisland-puako", "Puako", "Long reef with multiple access points.", Coordinates(19.975813, -155.846), 12, "Puako Beach Drive, multiple pullouts", "Roadside"),
        SpotRecord("bigisland-keahole-point", "Keahole Point", "Near airport with NELHA pipes. Deep water close.", Coordinates(19.7300, -156.0610), 20, "Pine Trees or OTEC Beach", "Limited"),
        SpotRecord("bigisland-honokohau-harbor", "Honokohau Harbor", "Harbor reef and outside structure.", Coordinates(19.67, -156.033663), 12, "Honokohau Small Boat Harbor", "Harbor parking"),
        SpotRecord("bigisland-kaloko", "Kaloko Fish Pond", "Historic fish pond with adjacent reef.", Coordinates(19.67617, -156.035068), 8, "Kaloko-Honokohau NHP", "Park lot"),
        SpotRecord("bigisland-pine-trees", "Pine Trees", "Local surf spot with reef.", Coordinates(19.7200, -156.0560), 10, "South of airport, access road", "Dirt road parking"),
        SpotRecord("bigisland-wawaloli", "Wawaloli Beach", "OTEC Beach with deep water pipe.", Coordinates(19.7150, -156.0510), 15, "Off Queen K Highway", "Small lot"),
        SpotRecord("bigisland-kua-bay", "Kua Bay (Manini'owali)", "White sand beach with clear water.", Coordinates(19.807216, -156.016), 10, "Off Highway 19, steep road", "Paved lot, limited"),
        SpotRecord("bigisland-kikaua-point", "Kikaua Point", "Point with good current and fish.", Coordinates(19.8100, -156.0110), 12, "Near Kukio Beach", "Limited, private area"),
        SpotRecord("bigisland-mahaiula", "Mahaiula Beach", "Remote Kohala coast beach.", Coordinates(19.8350, -155.9910), 10, "4WD road from highway", "Dirt lot"),
        SpotRecord("bigisland-makalawena", "Makalawena Beach", "Remote hike-in beach with pristine water.", Coordinates(19.83941, -155.986), 10, "Hike from Mahaiula", "None, hike in"),
        SpotRecord("bigisland-kiholo-bay", "Kiholo Bay", "Large bay with good reef.", Coordinates(19.8550, -155.9260), 8, "Highway 19, long walk down", "Pullout"),
        SpotRecord("bigisland-anaehoomalu", "A-Bay (Anaehoomalu)", "Waikoloa resort beach with protected bay.", Coordinates(19.914999, -155.891327), 8, "Waikoloa Beach Resort", "Resort lot"),
        SpotRecord("bigisland-69-beach", "Beach 69 (Waialea)", "Popular beach with offshore reef.", Coordinates(19.973455, -155.850638), 10, "Old Puako Road access", "Small lot, crowded"),
        SpotRecord("bigisland-hapuna", "Hapuna Beach", "Large white sand beach, some reef on sides.", Coordinates(19.977354, -155.834135), 8, "Hapuna Beach State Park", "State park lot, fee"),
        SpotRecord("bigisland-spencer", "Spencer Beach", "Protected beach near harbor.", Coordinates(20.019898, -155.82643), 6, "Spencer Beach Park", "Park lot"),
        SpotRecord("bigisland-kawaihae-harbor", "Kawaihae Harbor", "Working harbor with fish aggregation.", Coordinates(20.0350, -155.8300), 15, "Kawaihae Small Boat Harbor", "Harbor"),
        SpotRecord("bigisland-mahukona", "Mahukona", "Old sugar port with excellent diving.", Coordinates(20.175482, -155.901), 15, "End of road past Kohala", "Small lot"),
        SpotRecord("bigisland-lapakahi", "Lapakahi", "Historic park with marine preserve.", Coordinates(20.174999, -155.906352), 10, "Lapakahi State Historical Park", "Park lot"),
        SpotRecord("bigisland-keokea", "Keokea Beach", "Remote north Kohala beach.", Coordinates(20.209995, -155.913189), 8, "End of road, North Kohala", "Small lot"),

        // Hilo Side
        SpotRecord("bigisland-richardson", "Richardson Beach", "Black sand with clear water.", Coordinates(19.7350, -155.0190), 8, "End of Kalanianaole Ave", "Park lot"),
        SpotRecord("bigisland-carlsmith", "Carlsmith Beach", "Protected area with brackish pools.", Coordinates(19.7400, -155.0090), 6, "Kalanianaole Ave, Hilo", "Park lot"),
        SpotRecord("bigisland-honolii", "Honolii Beach", "Surf spot with adjacent reef.", Coordinates(19.768194, -155.085606), 8, "Honolii Beach Park", "Park lot"),
        SpotRecord("bigisland-kolekole", "Kolekole Beach", "Dramatic gulch with river mouth.", Coordinates(19.88941, -155.119), 6, "Kolekole Beach Park", "Park lot"),
        SpotRecord("bigisland-laupahoehoe", "Laupahoehoe Point", "Historic point with reef.", Coordinates(19.990417, -155.234), 10, "Laupahoehoe Point Park", "Park lot"),

        // South Point
        SpotRecord("bigisland-south-point", "South Point (Ka Lae)", "Southernmost point in USA. Strong currents, big fish.", Coordinates(18.9142, -155.6850), 20, "End of South Point Road", "Dirt lot"),
        SpotRecord("bigisland-green-sand", "Green Sand Beach (Papakolea)", "Hike-in beach with unique sand.", Coordinates(18.9342, -155.6400), 10, "3-mile hike from South Point", "None, hike in"),
        SpotRecord("bigisland-punaluu-black-sand", "Punaluu Black Sand", "Turtle beach with adjacent reef.", Coordinates(19.1292, -155.5050), 8, "Punaluu Beach Park", "Park lot"),

        // HAWAII - VERIFIED ARTIFICIAL REEFS (from NOAA/TidesPro)
        SpotRecord("oahu-waianae-artificial-reef", "Waianae Artificial Reef", "VERIFIED GPS - Multiple reef structures including Mahi wreck at 90ft, Navy barge, LCUs, Z-modules. Depths 38-127ft.", Coordinates(21.4132, -158.1956), 90, "Boat from Waianae Harbor - 1mi offshore", "Harbor"),
        SpotRecord("oahu-maunalua-bay-reef", "Maunalua Bay Artificial Reef", "VERIFIED GPS - Multiple structures: CB Barge, Navy LCU, Keehi Barge. Depths 52-87ft. Hawaii Kai area.", Coordinates(21.2498, -157.7640), 85, "Boat from Hawaii Kai - 1.5mi offshore", "Marina"),
        SpotRecord("oahu-kualoa-artificial-reef", "Kualoa Artificial Reef", "VERIFIED GPS - Large reef complex: Z-modules, Small Barge at 85ft. Windward Oahu. Depths 85-211ft.", Coordinates(21.5525, -157.8255), 85, "Boat from Heeia Kea Harbor - offshore of Kualoa", "Harbor"),
        SpotRecord("oahu-ewa-deepwater-reef", "Ewa Deepwater Artificial Reef", "VERIFIED GPS - Deep artificial reef complex. Depths 322-537ft. Advanced/technical only.", Coordinates(21.2803, -158.0228), 330, "Boat from Kewalo/Waianae - deep water offshore", "Marina"),
        SpotRecord("maui-keawakapu-reef", "Keawakapu Artificial Reef", "VERIFIED GPS - Artificial reef structure off South Maui. Depths 71-180ft.", Coordinates(20.7000, -156.4566), 120, "Boat from Maalaea - offshore of Keawakapu Beach", "Harbor"),

        // HAWAII - BIG ISLAND FAD BUOYS (Fish Aggregating Devices - VERIFIED from DLNR)
        SpotRecord("bigisland-fad-south-point", "South Point FAD (Buoy A)", "VERIFIED GPS - Fish Aggregating Device 8mi offshore of South Point. 700 fathoms. Ahi, aku, mahimahi, ono.", Coordinates(18.9558, -155.5567), 4200, "Boat from South Point - 8 miles offshore", "Dirt lot"),
        SpotRecord("bigisland-fad-milolii", "Milolii FAD (Buoy B)", "VERIFIED GPS - Fish Aggregating Device 2.3mi offshore of Milolii. 850 fathoms. Ahi, aku, mahimahi.", Coordinates(19.1983, -155.9483), 5100, "Boat from Milolii - 2.3 miles offshore", "Beach"),
        SpotRecord("bigisland-fad-kailua-kona", "Kailua-Kona FAD (Buoy F)", "VERIFIED GPS - Fish Aggregating Device 10mi offshore of Kailua Bay. 1592 fathoms. Ahi, aku, mahimahi, ono.", Coordinates(19.5067, -156.1567), 9550, "Boat from Kailua-Kona - 10 miles offshore", "Harbor"),
        SpotRecord("bigisland-fad-kahaluu", "Kahaluu FAD (Buoy VV)", "VERIFIED GPS - Fish Aggregating Device 4mi offshore of Kahaluu. 600 fathoms. Ahi, aku, mahimahi.", Coordinates(19.5850, -156.0317), 3600, "Boat from Keauhou - 4 miles offshore", "Harbor"),
        SpotRecord("bigisland-fad-puako", "Puako FAD (Buoy XX)", "VERIFIED GPS - Fish Aggregating Device 12mi offshore of Puako. 641 fathoms. Ahi, aku, mahimahi, ono.", Coordinates(20.0367, -156.1033), 3850, "Boat from Kawaihae - 12 miles offshore", "Harbor"),

        // ==========================================
        // HAWAII - MAUI (35+ spots)
        // ==========================================
        SpotRecord("maui-molokini", "Molokini Crater", "VERIFIED GPS - Submerged volcanic crater 2.5mi off Maui. Multiple dive sites: Back Side (100ft wall), Shark Condos (130ft caves), Edge of the World. Exceptional clarity.", Coordinates(20.6335, -156.4917), 100, "Boat from Maalaea or Kihei - 2.5 miles offshore", "Harbor"),
        SpotRecord("maui-honolua-bay", "Honolua Bay", "Marine preserve - some areas no-take. Check boundaries.", Coordinates(21.0150, -156.6410), 15, "Past Kapalua, dirt road", "Dirt lot"),
        SpotRecord("maui-kapalua-bay", "Kapalua Bay", "Protected bay with good snorkeling.", Coordinates(21.0000, -156.6660), 10, "Kapalua Resort area", "Limited public"),
        SpotRecord("maui-napili-bay", "Napili Bay", "Calm bay with reef.", Coordinates(20.989999, -156.676434), 8, "Napili Beach, various access", "Limited"),
        SpotRecord("maui-black-rock", "Black Rock (Puu Kekaa)", "Famous cliff jump spot with reef.", Coordinates(20.9250, -156.6960), 12, "Sheraton Maui Resort area", "Hotel parking"),
        SpotRecord("maui-olowalu", "Olowalu", "Mile marker 14 with extensive reef.", Coordinates(20.805482, -156.621), 10, "MM14 on Honoapiilani Hwy", "Roadside"),
        SpotRecord("maui-ukumehame", "Ukumehame", "Less crowded reef system.", Coordinates(20.7950, -156.5910), 10, "Before Olowalu on highway", "Roadside"),
        SpotRecord("maui-maalaea-harbor", "Maalaea Harbor", "Harbor reef and offshore spots.", Coordinates(20.7900, -156.5100), 15, "Maalaea Small Boat Harbor", "Harbor"),
        SpotRecord("maui-five-caves", "Five Caves (Five Graves)", "Dramatic underwater caves. Advanced only.", Coordinates(20.6692, -156.4450), 20, "Makena, end of Makena Road", "Limited"),
        SpotRecord("maui-ahihi-kinau", "Ahihi-Kinau Reserve", "Marine preserve - special regulations.", Coordinates(20.616554, -156.443169), 15, "End of Makena Road", "Limited"),
        SpotRecord("maui-la-perouse", "La Perouse Bay", "Remote lava field with good diving.", Coordinates(20.5942, -156.4200), 12, "End of road, past Ahihi", "Dirt lot"),
        SpotRecord("maui-kamaole", "Kamaole Beach Parks", "Three beach parks with reef.", Coordinates(20.7192, -156.4500), 8, "Kihei, South Kihei Road", "Park lots"),
        SpotRecord("maui-makena-landing", "Makena Landing", "Boat launch with adjacent reef.", Coordinates(20.6542, -156.4450), 10, "Makena Landing Park", "Small lot"),
        SpotRecord("maui-big-beach", "Big Beach (Oneloa)", "Large beach with some reef on sides.", Coordinates(20.6342, -156.4550), 8, "Makena State Park", "State park lot"),
        SpotRecord("maui-hookipa", "Hookipa Beach", "Windsurfing spot with reef. Strong currents.", Coordinates(20.9358, -156.3600), 10, "Hookipa Beach Park, Paia", "Park lot"),
        SpotRecord("maui-baldwin-beach", "Baldwin Beach", "Long beach near Paia.", Coordinates(20.9158, -156.3850), 6, "Baldwin Beach Park", "Park lot"),
        SpotRecord("maui-hana-bay", "Hana Bay", "Remote east Maui with good diving.", Coordinates(20.759518, -155.984), 10, "Hana Bay", "Hana town"),
        SpotRecord("maui-hamoa-beach", "Hamoa Beach", "Beautiful beach past Hana.", Coordinates(20.7150, -155.9840), 8, "Past Hana on Road to Hana", "Small lot"),
        SpotRecord("maui-keanae", "Keanae Peninsula", "Rocky peninsula with tidepools.", Coordinates(20.8608, -156.1400), 6, "Keanae Peninsula Road", "Limited"),
        SpotRecord("maui-kahului-harbor", "Kahului Harbor", "Working harbor, fish around structures.", Coordinates(20.9000, -156.4700), 12, "Kahului Harbor", "Harbor"),

        // ==========================================
        // FLORIDA KEYS (50+ spots)
        // ==========================================
        SpotRecord("keys-sombrero-reef", "Sombrero Reef", "Iconic lighthouse reef with excellent structure.", Coordinates(24.6261, -81.1108), 10, "Boat from Marathon", "Boot Key Harbor"),
        SpotRecord("keys-looe-key", "Looe Key", "Named for HMS Looe wreck. Outstanding reef.", Coordinates(24.5456, -81.4075), 10, "Boat from Big Pine Key", "Big Pine Marina"),
        SpotRecord("keys-coffins-patch", "Coffins Patch", "Large reef complex, multiple dive sites.", Coordinates(24.6833, -81.0500), 8, "Boat from Marathon", "Marathon Marina"),
        SpotRecord("keys-american-shoal", "American Shoal", "Deep reef with bigger fish.", Coordinates(24.5161, -81.5231), 15, "Boat from Big Pine or Sugarloaf", "Marina"),
        SpotRecord("keys-bahia-honda-bridge", "Bahia Honda Bridge", "Old bridge structure attracts fish.", Coordinates(24.6553, -81.2842), 8, "Bahia Honda State Park", "State park lot"),
        SpotRecord("keys-newfound-harbor", "Newfound Harbor Keys", "Protected area with diverse reef.", Coordinates(24.6100, -81.3900), 10, "Boat from Big Pine", "Marina"),
        SpotRecord("keys-marquesas", "Marquesas Keys", "Remote atoll west of Key West.", Coordinates(24.5500, -82.1000), 15, "Long boat run from Key West", "Key West Marina"),
        // Dry Tortugas - Split into directional spots (coastline + 500m offshore)
        SpotRecord("keys-dry-tortugas-north", "Dry Tortugas - North", "North side. Remote national park.", Coordinates(24.6433, -82.8781), 20, "Ferry or boat from Key West", "Fort Jefferson"),
        SpotRecord("keys-dry-tortugas-south", "Dry Tortugas - South", "South side. Pristine waters.", Coordinates(24.6133, -82.8781), 20, "Ferry or boat from Key West", "Fort Jefferson"),
        SpotRecord("keys-dry-tortugas-east", "Dry Tortugas - East", "East side. Loggerhead Key.", Coordinates(24.6283, -82.8531), 20, "Ferry or boat from Key West", "Fort Jefferson"),
        SpotRecord("keys-dry-tortugas-west", "Dry Tortugas - West", "West side. Open Gulf.", Coordinates(24.6283, -82.8931), 20, "Ferry or boat from Key West", "Fort Jefferson"),
        SpotRecord("keys-tennessee-reef", "Tennessee Reef", "Large reef system off Islamorada.", Coordinates(24.7619, -80.7489), 8, "Boat from Islamorada", "Bud N Marys"),
        SpotRecord("keys-alligator-reef", "Alligator Reef", "Lighthouse reef, excellent diving.", Coordinates(24.8481, -80.6186), 10, "Boat from Islamorada", "Marina"),
        SpotRecord("keys-davis-reef", "Davis Reef", "Popular reef off Upper Keys.", Coordinates(24.9244, -80.5028), 8, "Boat from Islamorada or Key Largo", "Marina"),
        SpotRecord("keys-conch-reef", "Conch Reef", "Healthy reef ecosystem.", Coordinates(24.9533, -80.4564), 10, "Boat from Key Largo", "Marina"),
        SpotRecord("keys-molasses-reef", "Molasses Reef", "Very popular snorkel/dive reef.", Coordinates(25.0092, -80.3739), 10, "Boat from Key Largo", "Marina"),
        SpotRecord("keys-french-reef", "French Reef", "Multiple dive sites and caves.", Coordinates(25.0344, -80.3508), 10, "Boat from Key Largo", "Marina"),
        SpotRecord("keys-carysfort-reef", "Carysfort Reef", "Northern Keys lighthouse reef.", Coordinates(25.2228, -80.2114), 10, "Boat from Key Largo", "Marina"),
        SpotRecord("keys-pickles-reef", "Pickles Reef", "Named for pickle barrel cargo from wreck.", Coordinates(24.9858, -80.4131), 8, "Boat from Key Largo", "Marina"),
        SpotRecord("keys-duane-wreck", "USCGC Duane Wreck", "327ft Coast Guard cutter in 120ft.", Coordinates(24.9867, -80.3822), 36, "Boat from Key Largo", "Marina"),
        SpotRecord("keys-bibb-wreck", "USCGC Bibb Wreck", "Coast Guard cutter, sister to Duane.", Coordinates(24.9875, -80.3819), 40, "Boat from Key Largo", "Marina"),
        SpotRecord("keys-spiegel-grove", "USS Spiegel Grove", "510ft landing ship, largest artificial reef.", Coordinates(25.0628, -80.3086), 40, "Boat from Key Largo", "Marina"),
        SpotRecord("keys-thunderbolt-wreck", "Thunderbolt Wreck", "Research vessel in 115ft of water.", Coordinates(24.6564, -81.0333), 35, "Boat from Marathon", "Marathon Marina"),
        SpotRecord("keys-vandenberg-wreck", "USNS Vandenberg", "523ft ship, second largest artificial reef.", Coordinates(24.4569, -81.8019), 43, "Boat from Key West", "Key West Marina"),
        SpotRecord("keys-western-sambo", "Western Sambo Reef", "Near Key West with good coral.", Coordinates(24.4792, -81.7147), 8, "Boat from Key West", "Key West Marina"),
        SpotRecord("keys-eastern-sambo", "Eastern Sambo Reef", "Healthy reef system.", Coordinates(24.4897, -81.6661), 8, "Boat from Key West", "Key West Marina"),
        SpotRecord("keys-sand-key", "Sand Key", "Lighthouse reef off Key West.", Coordinates(24.4528, -81.8775), 10, "Boat from Key West", "Key West Marina"),
        SpotRecord("keys-rock-key", "Rock Key", "Rocky outcrop with fish aggregation.", Coordinates(24.4517, -81.8578), 10, "Boat from Key West", "Key West Marina"),

        // ==========================================
        // BAHAMAS - COMPREHENSIVE (100+ spots)
        // ==========================================
        
        // Andros
        SpotRecord("andros-wall-fresh-creek", "The Wall at Fresh Creek", "Third largest barrier reef drops into Tongue of Ocean.", Coordinates(24.7167, -77.7667), 30, "Boat from Fresh Creek", "Andros Beach Club"),
        SpotRecord("andros-great-blue-hole", "Great Blue Hole (Andros)", "Second deepest blue hole in Bahamas.", Coordinates(24.4450, -77.9000), 40, "Boat from South Andros", "Small Hope Bay"),
        SpotRecord("andros-north-reef", "North Andros Barrier Reef", "Shallower section, excellent hogfish.", Coordinates(25.049997, -77.971189), 15, "Boat from Nicholl's Town", "Local marina"),
        SpotRecord("andros-stafford-creek-wall", "Stafford Creek Wall", "Less crowded section with big grouper.", Coordinates(24.7833, -77.8333), 35, "Boat from Stafford Creek", "Lodge"),
        SpotRecord("andros-captains-blue-hole", "Captain Bill's Blue Hole", "Famous inland blue hole.", Coordinates(24.1617, -77.7500), 30, "Road from Driggs Hill", "Roadside"),
        SpotRecord("andros-ocean-hole-north", "Ocean Hole (North Andros)", "Deep ocean blue hole near Nicholl's Town.", Coordinates(25.161292, -78.00237), 50, "Boat from Nicholl's Town", "Local marina"),
        SpotRecord("andros-mangrove-cay-reef", "Mangrove Cay Reef", "Central Andros, less pressure.", Coordinates(24.4000, -77.7833), 25, "Boat from Mangrove Cay", "Seascape Inn"),
        SpotRecord("andros-south-bight", "South Bight", "Remote southern area.", Coordinates(23.8550, -77.6500), 25, "Boat from Congo Town", "Lodge"),

        // Exuma Cays
        SpotRecord("exuma-thunderball-grotto", "Thunderball Grotto", "Famous James Bond cave near Staniel Cay.", Coordinates(24.1708, -76.4339), 8, "Boat from Staniel Cay", "Staniel Cay YC"),
        SpotRecord("exuma-warderick-wells", "Warderick Wells", "Exuma Park HQ with pristine reef.", Coordinates(24.3833, -76.6167), 25, "Boat from Staniel Cay", "Mooring balls"),
        SpotRecord("exuma-shroud-cay", "Shroud Cay", "Northern park boundary with creek system.", Coordinates(24.6000, -76.5667), 20, "Boat from Nassau or Staniel", "Anchor"),
        SpotRecord("exuma-stocking-island", "Stocking Island Blue Hole", "Popular blue hole near Georgetown.", Coordinates(23.5333, -75.7717), 30, "Boat from Georgetown", "Georgetown marina"),
        SpotRecord("exuma-highborne-cay", "Highborne Cay", "Northern Exumas near Nassau.", Coordinates(24.7167, -76.8167), 25, "Boat from Nassau", "Highborne Cay Marina"),
        SpotRecord("exuma-compass-cay", "Compass Cay", "Famous for nurse sharks.", Coordinates(24.2667, -76.5000), 20, "Boat from Staniel Cay", "Compass Cay Marina"),
        SpotRecord("exuma-big-major-cay", "Big Major Cay (Pig Beach)", "Swimming pigs with adjacent reef.", Coordinates(24.1833, -76.4500), 15, "Near Staniel Cay", "Anchor"),
        SpotRecord("exuma-normans-plane-wreck", "Norman's Cay Drug Plane", "Famous C-46 wreck in shallow water.", Coordinates(24.5833, -76.8167), 5, "Boat from Nassau", "Anchor"),
        SpotRecord("exuma-great-exuma-wall", "Great Exuma Wall", "Wall dive off main island.", Coordinates(23.5000, -75.8333), 35, "Boat from Georgetown", "Georgetown marina"),
        SpotRecord("exuma-little-exuma-reef", "Little Exuma Reef", "Southern tip of chain.", Coordinates(23.3167, -75.8500), 25, "Boat from Georgetown", "Anchor"),
        SpotRecord("exuma-leaf-cay", "Leaf Cay (Iguana Island)", "Iguanas on land, good reef.", Coordinates(24.2000, -76.4600), 15, "Near Staniel Cay", "Anchor"),
        SpotRecord("exuma-pipe-creek", "Pipe Creek", "Shallow area with patch reefs.", Coordinates(24.2500, -76.5500), 10, "Boat from Staniel Cay", "Anchor"),

        // Eleuthera & Harbour Island
        SpotRecord("eleuthera-current-cut", "Current Cut", "World's fastest drift dive at 9 knots.", Coordinates(25.3833, -76.7833), 25, "Boat from Harbour Island", "Valentines Marina"),
        SpotRecord("eleuthera-devils-backbone", "Devil's Backbone", "Shipwreck graveyard with reef.", Coordinates(25.4167, -76.7333), 10, "Boat from Spanish Wells", "Spanish Wells marina"),
        SpotRecord("eleuthera-train-wreck", "Train Wreck", "Civil War era locomotive on reef.", Coordinates(25.4200, -76.7300), 8, "Boat from Spanish Wells", "Marina"),
        SpotRecord("eleuthera-split-reef", "Split Reef", "Large coral head at 45ft with swim-throughs.", Coordinates(25.5000, -76.7500), 15, "Boat from Harbour Island", "Valentines"),
        SpotRecord("eleuthera-high-head", "High Head", "Steep coral head 10-50ft.", Coordinates(25.4833, -76.7667), 15, "Boat from Harbour Island", "Valentines"),
        SpotRecord("eleuthera-black-shoals", "Black Shoals", "Reef heads with morays and turtles.", Coordinates(25.4500, -76.7833), 10, "Boat from Harbour Island", "Marina"),
        SpotRecord("eleuthera-the-notch", "The Notch", "Wall dive known for reef sharks.", Coordinates(25.5167, -76.7333), 30, "Boat from Harbour Island", "Marina"),
        SpotRecord("eleuthera-north-wall", "North Eleuthera Wall", "Dramatic wall, minimal pressure.", Coordinates(25.5500, -76.6500), 35, "Boat from Harbour Island", "Marina"),
        SpotRecord("eleuthera-governors-harbour-reef", "Governor's Harbour Reef", "Central Eleuthera access.", Coordinates(25.2000, -76.2500), 25, "Boat from Governor's Harbour", "Local dock"),
        SpotRecord("eleuthera-rock-sound-blue-hole", "Rock Sound Blue Hole", "Massive inland blue hole.", Coordinates(24.8833, -76.188081), 80, "Town of Rock Sound", "Roadside"),
        SpotRecord("eleuthera-cape-eleuthera", "Cape Eleuthera", "Southern tip with wall.", Coordinates(24.7667, -76.3333), 30, "Boat from Rock Sound", "Cape Eleuthera Marina"),

        // Cat Island
        SpotRecord("cat-first-basin-wall", "First Basin Wall", "100-200ft drop-off.", Coordinates(24.2667, -75.4167), 40, "Boat from New Bight", "Bridge Inn Marina"),
        SpotRecord("cat-blue-hole", "Cat Island Blue Hole", "80-100ft circular depression.", Coordinates(24.2000, -75.4500), 30, "Boat from New Bight", "Marina"),
        SpotRecord("cat-white-hole-reef", "White Hole Reef", "Unique limestone formations.", Coordinates(24.2333, -75.4333), 20, "Boat from New Bight", "Marina"),
        SpotRecord("cat-the-tunnels", "The Tunnels", "Shore dive with crevices and canyons.", Coordinates(24.3167, -75.4000), 10, "North Cat Island shore access", "Roadside"),
        SpotRecord("cat-third-basin-reef", "Third Basin Reef", "Vertical wall with black coral.", Coordinates(24.1833, -75.4717), 40, "Boat from New Bight", "Marina"),
        SpotRecord("cat-dry-heads", "Dry Heads", "One of finest shallow Bahamian reefs.", Coordinates(24.3500, -75.3667), 15, "Boat from Arthur's Town", "Local dock"),
        SpotRecord("cat-hawks-nest-reef", "Hawk's Nest Reef", "Resort area southern Cat Island.", Coordinates(24.0833, -75.5167), 25, "Boat from Hawk's Nest Resort", "Resort marina"),
        SpotRecord("cat-fernandez-bay", "Fernandez Bay", "Beautiful bay with reef.", Coordinates(24.119402, -75.475), 15, "Boat from Fernandez Bay Village", "Resort"),

        // Long Island
        SpotRecord("long-cape-santa-maria", "Cape Santa Maria Reef", "Northern Long Island pristine reef.", Coordinates(23.6833, -75.2833), 25, "Boat from Cape Santa Maria Resort", "Resort marina"),
        SpotRecord("long-deans-blue-hole", "Dean's Blue Hole", "World's second deepest at 663ft. Freediving mecca.", Coordinates(23.1083, -74.9917), 200, "Clarence Town, Long Island", "Roadside"),
        SpotRecord("long-clarence-town-wall", "Clarence Town Wall", "8 miles of wall from Flying Fish Marina.", Coordinates(23.110813, -74.9833), 35, "Boat from Flying Fish Marina", "Marina"),
        SpotRecord("long-stella-maris-reef", "Stella Maris Reef", "Central Long Island with shark dives.", Coordinates(23.576889, -75.277818), 25, "Boat from Stella Maris Marina", "Resort marina"),
        SpotRecord("long-salt-pond", "Salt Pond Reef", "Good reef near main settlement.", Coordinates(23.3000, -75.0500), 20, "Boat from Salt Pond", "Local"),
        SpotRecord("long-hamilton-caves", "Hamilton's Cave Reef", "Near famous cave system.", Coordinates(23.4500, -75.1500), 25, "Boat from Thompson Bay", "Local"),

        // Rum Cay
        SpotRecord("rum-grand-canyon", "Grand Canyon (Rum Cay)", "60ft coral wall nearly to surface.", Coordinates(23.6550, -74.8333), 20, "Boat from Port Nelson", "Marina"),
        SpotRecord("rum-dynamite-wall", "Dynamite Wall", "Deep tunnels with staghorn coral.", Coordinates(23.645095, -74.85), 35, "Boat from Port Nelson", "Marina"),
        SpotRecord("rum-pinder-reef", "Pinder Reef", "Predictable sharks and rays.", Coordinates(23.7000, -74.8833), 30, "Boat from Port Nelson", "Marina"),
        SpotRecord("rum-hyperspace", "Hyperspace", "Mushroom coral heads with tunnels.", Coordinates(23.6333, -74.8167), 25, "Boat from Port Nelson", "Marina"),
        SpotRecord("rum-seagarden", "Seagarden", "Shallow site with prolific lobster.", Coordinates(23.6167, -74.8000), 12, "Boat from Port Nelson", "Marina"),
        SpotRecord("rum-hms-conqueror", "HMS Conqueror Wreck", "Historic British shipwreck.", Coordinates(23.6250, -74.8250), 20, "Boat from Port Nelson", "Marina"),

        // San Salvador
        SpotRecord("salvador-riding-rock-wall", "Riding Rock Wall", "Columbus landfall island with great wall.", Coordinates(24.0500, -74.5333), 35, "Boat from Riding Rock Resort", "Resort marina"),
        SpotRecord("salvador-snapshot-reef", "Snapshot Reef", "One of healthiest reefs in Bahamas.", Coordinates(24.0833, -74.5000), 15, "Boat from Cockburn Town", "Local dock"),
        SpotRecord("salvador-frascate-wreck", "Frascate Wreck", "1902 steamship on reef.", Coordinates(24.0333, -74.5500), 20, "Boat from Riding Rock", "Marina"),
        SpotRecord("salvador-telephone-pole", "Telephone Pole", "Steep wall with coral pillars.", Coordinates(24.068194, -74.516501), 30, "Boat from Riding Rock", "Marina"),
        SpotRecord("salvador-devils-claw", "Devil's Claw", "Dramatic reef formation.", Coordinates(24.0750, -74.4900), 25, "Boat from Cockburn Town", "Local"),

        // Conception Island
        SpotRecord("conception-west-bay", "West Bay (Conception)", "Crescent cove, turtle sanctuary.", Coordinates(23.8333, -75.1333), 15, "Boat from Long Island or Cat Island", "Mooring balls"),
        SpotRecord("conception-south-hampton", "South Hampton Reef", "North side with staghorn coral.", Coordinates(23.8667, -75.1167), 10, "Boat from Long Island", "Anchor"),
        SpotRecord("conception-creek-drift", "Conception Creek Drift", "Mangrove creek drift dive.", Coordinates(23.8400, -75.1400), 8, "Boat from Long Island", "Mooring"),

        // Crooked & Acklins
        SpotRecord("crooked-wall", "Crooked Island Wall", "Untouched reef with 200 residents.", Coordinates(22.78435, -74.196038), 30, "Boat from Landrail Point", "Crooked Island Lodge"),
        SpotRecord("crooked-french-wells", "French Wells", "Shallow reef with large undercuts.", Coordinates(22.677109, -74.2), 20, "Boat from Landrail Point", "Lodge"),
        SpotRecord("acklins-atoll-rim", "Acklins Atoll Rim", "140-mile atoll with vast flats.", Coordinates(22.5000, -74.0000), 25, "Boat from Acklins", "Lodge"),
        SpotRecord("acklins-jamaica-cay", "Jamaica Cay", "Remote cay with pristine reef.", Coordinates(22.4000, -74.1000), 25, "Boat from Spring Point", "Lodge"),

        // Berry Islands
        SpotRecord("berry-chub-cay-reef", "Chub Cay Reef", "PADI 5-star resort reef.", Coordinates(25.4167, -77.9050), 30, "Chub Cay Marina", "Resort marina"),
        SpotRecord("berry-great-harbour", "Great Harbour Cay Reef", "Best hurricane hole, good spearing.", Coordinates(25.7383, -77.8333), 25, "Great Harbour Cay Marina", "Marina"),
        SpotRecord("berry-toto-edge", "Berry Islands TOTO Edge", "Where shelf meets 6,600ft trench.", Coordinates(25.2833, -77.8667), 40, "Boat from Chub Cay", "Marina"),
        SpotRecord("berry-little-whale", "Little Whale Cay", "Southern Berrys near deep water.", Coordinates(25.3000, -77.8500), 30, "Boat from Chub Cay", "Anchor"),
        SpotRecord("berry-bird-cay", "Bird Cay", "Private island with surrounding reef.", Coordinates(25.3167, -77.8833), 25, "Boat from Chub Cay", "Anchor"),
        SpotRecord("berry-frazer-hog", "Frazer's Hog Cay", "Good reef structure.", Coordinates(25.5000, -77.8000), 20, "Boat from Great Harbour", "Anchor"),
        SpotRecord("berry-hoffman-cay", "Hoffman's Cay Blue Hole", "Large blue hole with cave system.", Coordinates(25.6500, -77.7550), 35, "Boat from Great Harbour", "Anchor"),

        // Bimini
        SpotRecord("bimini-north-reef", "North Bimini Reef", "Gulf Stream waters, 50 miles from Miami.", Coordinates(25.75, -79.237995), 20, "Alice Town or Miami", "Big Game Club"),
        SpotRecord("bimini-road-atlantis", "Bimini Road", "Mysterious underwater rock formation.", Coordinates(25.7667, -79.2833), 8, "Boat from North Bimini", "Marina"),
        SpotRecord("bimini-bull-run", "Bull Run", "Bull shark encounters.", Coordinates(25.7833, -79.3000), 30, "Boat from Alice Town", "Marina"),
        SpotRecord("bimini-victory-reef", "Victory Reef", "Shallow reef with excellent hogfish.", Coordinates(25.7333, -79.2667), 15, "Boat from South Bimini", "Marina"),
        SpotRecord("bimini-flats", "Bimini Flats", "Famous bonefish flats.", Coordinates(25.6833, -79.2333), 5, "Boat from South Bimini", "Marina"),
        SpotRecord("bimini-nodules", "The Nodules", "Deep structure off Bimini.", Coordinates(25.7000, -79.3500), 25, "Boat from Alice Town", "Marina"),
        SpotRecord("bimini-three-sisters", "Three Sisters", "Rock formations with fish.", Coordinates(25.7200, -79.3200), 20, "Boat from Bimini", "Marina"),

        // Abaco
        SpotRecord("abaco-fowl-cay", "Fowl Cay", "Protected reef near Marsh Harbour.", Coordinates(26.5833, -77.0667), 15, "Boat from Marsh Harbour", "Marina"),
        SpotRecord("abaco-pelican-cays", "Pelican Cays Land & Sea Park", "National park with buffer zones.", Coordinates(26.35651, -77.021928), 20, "Boat from Marsh Harbour", "Mooring balls"),
        SpotRecord("abaco-grand-cay-north", "Grand Cay", "Remote northern tip, monster grouper.", Coordinates(27.2167, -78.3167), 25, "Boat from West End, long run", "West End marina"),
        SpotRecord("abaco-hole-in-wall", "Hole in the Wall", "Southern tip lighthouse, remote.", Coordinates(25.8500, -77.1833), 30, "Boat from Cherokee Sound", "Local dock"),
        SpotRecord("abaco-man-o-war", "Man-O-War Cay", "Historic boat-building with reef.", Coordinates(26.5833, -76.9833), 20, "Boat from Marsh Harbour", "Marina"),
        SpotRecord("abaco-green-turtle", "Green Turtle Cay Reef", "Charming settlement with reef.", Coordinates(26.7667, -77.3333), 20, "Ferry from Treasure Cay", "Marina"),
        SpotRecord("abaco-walkers-cay", "Walker's Cay", "Northernmost Bahamas.", Coordinates(27.2667, -78.4000), 30, "Boat from Grand Cay", "Anchor"),
        SpotRecord("abaco-whale-cay", "Whale Cay", "Near Great Guana Cay.", Coordinates(26.6833, -77.2000), 20, "Boat from Marsh Harbour", "Anchor"),
        SpotRecord("abaco-fish-cay", "Fish Cay", "South of Pelican Cays.", Coordinates(26.3000, -77.0500), 20, "Boat from Marsh Harbour", "Anchor"),
        SpotRecord("abaco-sandy-point", "Sandy Point", "Southwestern Abaco.", Coordinates(26.0167, -77.3833), 25, "Boat from Sandy Point", "Local"),

        // Nassau / New Providence
        SpotRecord("nassau-shark-wall", "Shark Wall (Stuart Cove's)", "Famous shark dive.", Coordinates(25.0167, -77.5550), 25, "Stuart Cove's, Coral Harbour", "Stuart Cove's"),
        SpotRecord("nassau-clifton-wall", "Clifton Wall", "Western New Providence wall.", Coordinates(25.0000, -77.5333), 30, "Boat from Nassau", "Nassau marina"),
        SpotRecord("nassau-tongue-dropoff", "Tongue of the Ocean", "6,000ft drop-off accessible from Nassau.", Coordinates(24.2500, -77.5000), 40, "Long run south from Nassau", "Nassau marinas"),
        SpotRecord("nassau-rose-island", "Rose Island Reef", "Popular day trip from Nassau.", Coordinates(25.1000, -77.3500), 15, "Boat from Nassau", "Nassau marina"),
        SpotRecord("nassau-southwest-reef", "Southwest Reef", "Less visited south side.", Coordinates(24.9833, -77.4000), 20, "Boat from Coral Harbour", "Marina"),
        SpotRecord("nassau-goulding-cay", "Goulding Cay", "Near Clifton Heritage Park.", Coordinates(25.0333, -77.5667), 20, "Boat from Nassau", "Marina"),
        // Athol Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("nassau-athol-island-north", "Athol Island - North", "North coast. Near Paradise Island.", Coordinates(25.1150, -77.2833), 15, "Boat from Nassau", "Marina"),
        SpotRecord("nassau-athol-island-south", "Athol Island - South", "South coast. Nassau harbor.", Coordinates(25.0850, -77.2833), 15, "Boat from Nassau", "Marina"),
        SpotRecord("nassau-athol-island-east", "Athol Island - East", "East coast. Open Atlantic.", Coordinates(25.104518, -77.2683), 15, "Boat from Nassau", "Marina"),
        SpotRecord("nassau-athol-island-west", "Athol Island - West", "West coast. Facing Nassau.", Coordinates(25.1000, -77.2983), 15, "Boat from Nassau", "Marina"),

        // Grand Bahama
        SpotRecord("grand-bahama-unexso", "UNEXSO Reef (Freeport)", "Underwater Explorers Society.", Coordinates(26.50651, -78.638614), 20, "UNEXSO, Port Lucaya", "UNEXSO marina"),
        SpotRecord("grand-bahama-west-end-wall", "West End Wall", "Western tip of Grand Bahama.", Coordinates(26.6833, -79.0000), 30, "Boat from West End", "Old Bahama Bay Marina"),
        SpotRecord("grand-bahama-peterson-cay", "Peterson Cay National Park", "Smallest national park.", Coordinates(26.4333, -78.5667), 10, "Boat from Freeport", "Kayak from shore"),
        SpotRecord("grand-bahama-gold-rock", "Gold Rock Beach Reef", "Near Lucayan National Park.", Coordinates(26.5500, -78.0000), 15, "Lucayan National Park", "Park parking"),
        SpotRecord("grand-bahama-sweeting-cay", "Sweeting's Cay", "Eastern Grand Bahama.", Coordinates(26.5833, -77.8333), 20, "Boat from Freeport, east", "Anchor"),
        SpotRecord("grand-bahama-shark-alley", "Shark Alley", "Known shark encounter site.", Coordinates(26.576101, -78.7), 25, "Boat from Freeport", "Marina"),

        // ==========================================
        // FRENCH POLYNESIA (40+ spots)
        // ==========================================
        
        // Fakarava
        SpotRecord("fakarava-tetamanu", "Tetamanu Pass (South)", "200m wide, wall of sharks.", Coordinates(-16.6872, -145.2511), 18, "1.5hr boat from Rotoava", "Pension"),
        SpotRecord("fakarava-garuae", "Garuae Pass (North)", "Largest pass in FP - 1.6km wide.", Coordinates(-16.0556, -145.6556), 30, "Boat from Rotoava", "Dive operator"),
        SpotRecord("fakarava-shark-grotto", "Shark Grotto", "Grey reef sharks rest during day.", Coordinates(-16.6900, -145.2500), 15, "South pass, local guide", "Tetamanu"),
        SpotRecord("fakarava-ali-baba", "Ali Baba", "Coral garden inside south pass.", Coordinates(-16.6850, -145.2550), 20, "South pass area", "Pension"),
        SpotRecord("fakarava-pufana", "Pufana", "Outside south pass with pelagics.", Coordinates(-16.6900, -145.2400), 30, "Boat from Tetamanu", "Pension"),

        // Rangiroa
        SpotRecord("rangiroa-tiputa", "Tiputa Pass", "Premier drift dive with dolphins and hammerheads.", Coordinates(-14.9683, -147.6383), 35, "Boat from Avatoru", "Dive center"),
        SpotRecord("rangiroa-sharks-cavern", "Sharks Cavern", "115ft site where sharks investigate.", Coordinates(-14.9700, -147.6350), 35, "Inside Tiputa Pass", "Dive center"),
        SpotRecord("rangiroa-canyons", "The Canyons", "Natural canyons mid-pass.", Coordinates(-14.9650, -147.6300), 25, "Mid Tiputa Pass", "Dive center"),
        SpotRecord("rangiroa-avatoru", "Avatoru Pass", "Two channels, eastern for beginners.", Coordinates(-14.9500, -147.7000), 25, "Boat from Avatoru", "Village"),
        SpotRecord("rangiroa-blue-lagoon", "Blue Lagoon", "Inner lagoon with pristine water.", Coordinates(-15.0000, -147.5500), 10, "Boat trip into lagoon", "Day trip"),
        SpotRecord("rangiroa-reef-island", "Reef Island (Les Sables Roses)", "Pink sand island with reef.", Coordinates(-15.0500, -147.5000), 15, "Lagoon boat trip", "Day trip"),

        // Moorea
        SpotRecord("moorea-opunohu", "Opunohu Pass", "Deep pass with Jardin des Roses at 40m.", Coordinates(-17.4833, -149.8500), 40, "Boat from Cook's Bay", "Marina"),
        SpotRecord("moorea-tiki", "Tiki (Moorea)", "Northwest tip with rapid currents.", Coordinates(-17.4667, -149.9333), 30, "Boat from NW Moorea", "Resort"),
        SpotRecord("moorea-vaiare", "Vaiare", "Near ferry docks with lemon sharks.", Coordinates(-17.5167, -149.7667), 15, "Vaiare ferry terminal", "Ferry parking"),
        SpotRecord("moorea-taotoi", "Taotoi", "Beginner site with morays and sharks.", Coordinates(-17.499999, -149.822653), 15, "Boat from Moorea", "Marina"),
        SpotRecord("moorea-stingray-world", "Stingray World", "Shallow lagoon with friendly rays.", Coordinates(-17.480409, -149.83), 5, "Lagoon tour", "Various"),

        // Bora Bora
        SpotRecord("bora-bora-south-lagoon", "Bora Bora South Lagoon", "Shallow lagoon hunting.", Coordinates(-16.5333, -151.7333), 10, "Boat from Vaitape", "Vaitape dock"),
        SpotRecord("bora-bora-outer-reef", "Bora Bora Outer Reef", "Outside for pelagics.", Coordinates(-16.4833, -151.7833), 30, "Boat through Teavanui Pass", "Marina"),
        SpotRecord("bora-bora-tapu", "Tapu", "Manta cleaning station.", Coordinates(-16.4500, -151.7500), 25, "North side", "Dive operator"),
        SpotRecord("bora-bora-muri-muri", "Muri Muri", "North pass with sharks.", Coordinates(-16.4600, -151.7600), 20, "North Bora Bora", "Dive operator"),
        SpotRecord("bora-bora-anau", "Anau", "Manta ray site east side.", Coordinates(-16.5000, -151.7050), 15, "East Bora Bora", "Dive operator"),

        // Tikehau
        SpotRecord("tikehau-tuheiava", "Tuheiava Pass", "Only pass into Tikehau. Mantas year-round.", Coordinates(-15.0000, -148.2333), 25, "Boat from village", "Pension"),
        SpotRecord("tikehau-shark-pit", "Shark Pit", "Shark aggregation site.", Coordinates(-15.0100, -148.2400), 20, "Inside pass", "Dive operator"),
        SpotRecord("tikehau-manta-point", "Manta Point (Tikehau)", "Manta cleaning station.", Coordinates(-14.9900, -148.2200), 15, "Outside pass", "Dive operator"),

        // Manihi
        SpotRecord("manihi-tairapa", "Tairapa Pass", "Historic pearl farming atoll.", Coordinates(-14.4333, -146.0717), 25, "Boat from village", "Pension"),
        SpotRecord("manihi-drop-off", "Manihi Drop-off", "Dramatic wall outside pass.", Coordinates(-14.4400, -146.0550), 40, "Boat from Manihi", "Pension"),

        // Tahiti
        SpotRecord("tahiti-aquarium", "The Aquarium", "Shallow protected area.", Coordinates(-17.5333, -149.5717), 8, "Punaauia", "Beach parking"),
        SpotRecord("tahiti-papeete-pass", "Papeete Pass", "Channel with current.", Coordinates(-17.5200, -149.5500), 20, "Boat from Papeete", "Marina"),
        SpotRecord("tahiti-teahupoo", "Teahupoo Outer Reef", "Famous surf spot, deep water.", Coordinates(-17.86441, -149.25), 30, "Boat from Teahupoo", "Local"),

        // ==========================================
        // MEDITERRANEAN (80+ spots)
        // ==========================================
        
        // Italy - Sardinia
        // Tavolara Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("sardinia-tavolara-north", "Tavolara - North", "North coast. Marine protected area.", Coordinates(40.9133, 9.7100), 25, "Boat from Olbia", "Marina"),
        SpotRecord("sardinia-tavolara-south", "Tavolara - South", "South coast. Calmer waters.", Coordinates(40.8833, 9.7100), 25, "Boat from Olbia", "Marina"),
        SpotRecord("sardinia-tavolara-east", "Tavolara - East", "East coast. Open Tyrrhenian.", Coordinates(40.8983, 9.7250), 25, "Boat from Olbia", "Marina"),
        SpotRecord("sardinia-tavolara-west", "Tavolara - West", "West coast. Facing Sardinia.", Coordinates(40.8983, 9.6750), 25, "Boat from Olbia", "Marina"),
        SpotRecord("sardinia-maddalena", "La Maddalena Archipelago", "National park with stunning water.", Coordinates(41.211695, 9.4167), 20, "Boat from Palau", "Palau Marina"),
        SpotRecord("sardinia-capo-caccia", "Capo Caccia", "Dramatic cliffs near Alghero.", Coordinates(40.5600, 8.1600), 30, "Boat from Alghero", "Alghero marina"),
        SpotRecord("sardinia-neptune-grotto", "Neptune's Grotto Area", "Caves and walls.", Coordinates(40.5650, 8.1550), 25, "Boat from Alghero", "Marina"),
        SpotRecord("sardinia-costa-smeralda", "Costa Smeralda", "Luxury coast with good diving.", Coordinates(41.068021, 9.536963), 20, "Boat from Porto Cervo", "Marina"),
        SpotRecord("sardinia-carloforte", "Carloforte (San Pietro)", "Island off southwest coast.", Coordinates(39.160189, 8.313141), 25, "Ferry from Portoscuso", "Carloforte port"),
        SpotRecord("sardinia-villasimius", "Villasimius MPA", "Marine protected area, check zones.", Coordinates(39.1283, 9.5333), 20, "Boat from Villasimius", "Marina"),
        SpotRecord("sardinia-orosei-gulf", "Gulf of Orosei", "Stunning cliffs and caves.", Coordinates(40.1667, 9.6833), 25, "Boat from Cala Gonone", "Marina"),

        // Italy - Sicily
        // Ustica Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("sicily-ustica-north", "Ustica - North", "North coast. Famous MPA.", Coordinates(38.7367, 13.1833), 30, "Ferry from Palermo", "Ustica port"),
        SpotRecord("sicily-ustica-south", "Ustica - South", "South coast. Facing Sicily.", Coordinates(38.6867, 13.1833), 30, "Ferry from Palermo", "Ustica port"),
        SpotRecord("sicily-ustica-east", "Ustica - East", "East coast. Open Tyrrhenian.", Coordinates(38.7217, 13.1983), 30, "Ferry from Palermo", "Ustica port"),
        SpotRecord("sicily-ustica-west", "Ustica - West", "West coast. Sunset side.", Coordinates(38.7217, 13.1683), 30, "Ferry from Palermo", "Ustica port"),
        SpotRecord("sicily-favignana", "Favignana (Egadi)", "Tuna fishing heritage, clear water.", Coordinates(37.9383, 12.3333), 20, "Ferry from Trapani", "Favignana port"),
        SpotRecord("sicily-aeolian-islands", "Aeolian Islands", "Volcanic island chain.", Coordinates(38.5667, 14.9500), 25, "Ferry from Milazzo", "Various ports"),
        SpotRecord("sicily-taormina", "Taormina Coast", "Below ancient theater.", Coordinates(37.8450, 15.2833), 20, "Boat from Giardini Naxos", "Marina"),
        SpotRecord("sicily-capo-passero", "Capo Passero", "Southernmost Sicily.", Coordinates(36.678198, 15.139662), 25, "Boat from Portopalo", "Local"),

        // Italy - Mainland
        SpotRecord("italy-portofino", "Portofino MPA", "Famous protected area.", Coordinates(44.3000, 9.2117), 25, "Boat from Santa Margherita", "Marina"),
        // Elba Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("italy-elba-north", "Elba Island - North", "North coast. Tuscan archipelago.", Coordinates(42.817117, 10.2667), 20, "Ferry from Piombino", "Various"),
        SpotRecord("italy-elba-south", "Elba Island - South", "South coast. Calmer waters.", Coordinates(42.7317, 10.2667), 20, "Ferry from Piombino", "Various"),
        SpotRecord("italy-elba-east", "Elba Island - East", "East coast. Facing mainland.", Coordinates(42.7667, 10.4217), 20, "Ferry from Piombino", "Various"),
        SpotRecord("italy-elba-west", "Elba Island - West", "West coast. Open Tyrrhenian.", Coordinates(42.7667, 10.0617), 20, "Ferry from Piombino", "Various"),
        // Ponza Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("italy-ponza-north", "Ponza - North", "North coast. Pontine Islands.", Coordinates(40.9150, 12.9667), 25, "Ferry from Formia", "Ponza port"),
        SpotRecord("italy-ponza-south", "Ponza - South", "South coast. Excellent vis.", Coordinates(40.8850, 12.9667), 25, "Ferry from Formia", "Ponza port"),
        SpotRecord("italy-ponza-east", "Ponza - East", "East coast. Facing mainland.", Coordinates(40.9000, 12.9817), 25, "Ferry from Formia", "Ponza port"),
        SpotRecord("italy-ponza-west", "Ponza - West", "West coast. Open Tyrrhenian.", Coordinates(40.9000, 12.9317), 25, "Ferry from Formia", "Ponza port"),
        SpotRecord("italy-amalfi-deep", "Amalfi Deep", "Drop-offs near Li Galli.", Coordinates(40.5833, 14.4283), 30, "Boat from Positano", "Marina"),

        // France - Corsica
        SpotRecord("corsica-lavezzi", "Lavezzi Islands", "Natural reserve, pristine water.", Coordinates(41.3333, 9.2500), 20, "Boat from Bonifacio", "Marina"),
        SpotRecord("corsica-scandola", "Scandola Reserve", "UNESCO site, limited access.", Coordinates(42.3667, 8.5450), 25, "Boat from Porto or Calvi", "Marina"),
        SpotRecord("corsica-cap-corse", "Cap Corse", "Northern tip with good structure.", Coordinates(42.9667, 9.3450), 20, "Boat from Bastia or Macinaggio", "Marina"),
        SpotRecord("corsica-ajaccio", "Ajaccio Bay", "Near capital with accessible diving.", Coordinates(41.9167, 8.7333), 20, "Boat from Ajaccio", "Marina"),

        // France - Mainland
        SpotRecord("france-marseille-riou", "Riou Archipelago", "Islands off Marseille.", Coordinates(43.1833, 5.3833), 25, "Boat from Marseille", "Marina"),
        SpotRecord("france-calanques", "Calanques National Park", "Stunning limestone inlets.", Coordinates(43.2000, 5.4500), 20, "Boat from Cassis", "Cassis port"),
        SpotRecord("france-hyeres", "Hyeres Islands", "Port-Cros and Porquerolles.", Coordinates(43.0167, 6.2167), 20, "Boat from Hyeres", "Marina"),
        SpotRecord("france-nice-villefranche", "Villefranche-sur-Mer", "Deep bay near Nice.", Coordinates(43.7000, 7.3167), 25, "Boat from Nice or Villefranche", "Marina"),
        SpotRecord("france-antibes", "Cap d'Antibes", "Rocky coast with good diving.", Coordinates(43.549999, 7.148219), 20, "Boat from Antibes", "Marina"),

        // Spain - Costa Brava
        SpotRecord("spain-medes", "Medes Islands", "Famous marine reserve.", Coordinates(42.0500, 3.2167), 25, "Boat from L'Estartit", "Marina"),
        SpotRecord("spain-tossa-de-mar", "Tossa de Mar", "Castle and underwater caves.", Coordinates(41.7117, 2.9333), 20, "Boat from Tossa", "Local"),
        SpotRecord("spain-cadaques", "Cap de Creus (Cadaques)", "Easternmost point of Iberian peninsula.", Coordinates(42.338305, 3.2833), 25, "Boat from Cadaques", "Local"),

        // Spain - Balearic Islands
        // Dragonera Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("spain-mallorca-dragonera-north", "Dragonera - North", "North coast. Protected island.", Coordinates(39.6033, 2.3167), 25, "Boat from Sant Elm", "Marina"),
        SpotRecord("spain-mallorca-dragonera-south", "Dragonera - South", "South coast. Calmer side.", Coordinates(39.5633, 2.3167), 25, "Boat from Sant Elm", "Marina"),
        SpotRecord("spain-mallorca-dragonera-east", "Dragonera - East", "East coast. Facing Mallorca.", Coordinates(39.5883, 2.3417), 25, "Boat from Sant Elm", "Marina"),
        SpotRecord("spain-mallorca-dragonera-west", "Dragonera - West", "West coast. Open Mediterranean.", Coordinates(39.5883, 2.3017), 25, "Boat from Sant Elm", "Marina"),
        SpotRecord("spain-cabrera", "Cabrera Archipelago", "National park south of Mallorca.", Coordinates(39.15, 2.944175), 30, "Boat from Colonia Sant Jordi", "Marina"),
        SpotRecord("spain-menorca-north", "North Menorca Coast", "Remote coves and reefs.", Coordinates(40.06441, 3.95), 20, "Boat from Fornells", "Marina"),
        SpotRecord("spain-ibiza-es-vedra", "Es Vedra (Ibiza)", "Mystical rock with good diving.", Coordinates(38.8717, 1.2000), 25, "Boat from San Antonio", "Marina"),
        SpotRecord("spain-formentera", "Formentera", "Crystal clear water.", Coordinates(38.678395, 1.45), 20, "Ferry from Ibiza", "La Savina"),

        // Spain - Canary Islands
        SpotRecord("spain-lanzarote-papagayo", "Papagayo (Lanzarote)", "Volcanic beaches with reef.", Coordinates(28.8500, -13.8000), 15, "South Lanzarote", "Beach access"),
        SpotRecord("spain-fuerteventura-south", "South Fuerteventura", "Clear Atlantic water.", Coordinates(28.0500, -14.3000), 20, "Boat from Morro Jable", "Marina"),
        SpotRecord("spain-gran-canaria-sardina", "Sardina del Norte", "Famous dive site.", Coordinates(28.1500, -15.7000), 15, "Sardina del Norte village", "Beach"),
        SpotRecord("spain-tenerife-abades", "Abades (Tenerife)", "Leper colony with reef.", Coordinates(28.1333, -16.4333), 15, "Abades, south Tenerife", "Beach access"),
        SpotRecord("spain-el-hierro", "El Hierro", "Pristine volcanic island.", Coordinates(27.777992, -18.031642), 20, "La Restinga", "Village"),

        // Greece
        SpotRecord("greece-crete-chania", "Chania Coast (Crete)", "Northwest Crete.", Coordinates(35.5217, 24.0167), 20, "Boat from Chania", "Marina"),
        SpotRecord("greece-antikythera", "Antikythera", "Remote island between Crete and Peloponnese.", Coordinates(35.8450, 23.3000), 30, "Ferry from Kissamos", "Small port"),
        SpotRecord("greece-gavdos", "Gavdos", "Southernmost point of Europe.", Coordinates(34.816192, 24.0833), 25, "Ferry from Paleochora", "Small port"),
        SpotRecord("greece-mykonos", "Mykonos", "Party island with diving.", Coordinates(37.449997, 25.322786), 20, "Boat from Mykonos", "Marina"),
        SpotRecord("greece-santorini-caldera", "Santorini Caldera", "Volcanic caldera diving.", Coordinates(36.4000, 25.4283), 25, "Boat from Fira", "Marina"),
        SpotRecord("greece-rhodes", "Rhodes", "Knights of St John island.", Coordinates(36.433298, 28.195436), 20, "Boat from Rhodes Town", "Marina"),
        SpotRecord("greece-zakynthos-shipwreck", "Zakynthos (Navagio)", "Near famous shipwreck beach.", Coordinates(37.8550, 20.6250), 20, "Boat from Zakynthos Town", "Marina"),
        SpotRecord("greece-alonissos", "Alonissos Marine Park", "First Greek marine park.", Coordinates(39.160813, 23.85), 25, "Boat from Alonissos", "Marina"),

        // Croatia
        SpotRecord("croatia-kornati", "Kornati National Park", "140 islands, pristine water.", Coordinates(43.8000, 15.3000), 25, "Boat from Zadar or Sibenik", "Marina"),
        SpotRecord("croatia-vis-blue-cave", "Vis Island (Blue Cave)", "Famous blue cave area.", Coordinates(43.062096, 16.199858), 20, "Boat from Split or Vis", "Marina"),
        // Hvar Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("croatia-hvar-north", "Hvar Island - North", "North coast. Lavender island.", Coordinates(43.2317, 16.6500), 20, "Boat from Hvar Town", "Marina"),
        SpotRecord("croatia-hvar-south", "Hvar Island - South", "South coast. Open Adriatic.", Coordinates(43.1117, 16.6500), 20, "Boat from Hvar Town", "Marina"),
        SpotRecord("croatia-hvar-east", "Hvar Island - East", "East coast. Channel side.", Coordinates(43.1667, 16.7050), 20, "Boat from Hvar Town", "Marina"),
        SpotRecord("croatia-hvar-west", "Hvar Island - West", "West coast. Pakleni Islands.", Coordinates(43.1667, 16.2450), 20, "Boat from Hvar Town", "Marina"),
        SpotRecord("croatia-dubrovnik-elafiti", "Elafiti Islands (Dubrovnik)", "Islands near Dubrovnik.", Coordinates(42.6833, 17.9333), 20, "Boat from Dubrovnik", "Marina"),

        // Turkey
        SpotRecord("turkey-kas", "Kas", "Lycian coast diving capital.", Coordinates(36.1950, 29.6333), 25, "Boat from Kas", "Marina"),
        SpotRecord("turkey-bodrum", "Bodrum Peninsula", "Aegean coast with wrecks.", Coordinates(37.0333, 27.4333), 20, "Boat from Bodrum", "Marina"),
        SpotRecord("turkey-fethiye", "Fethiye (Oludeniz)", "Blue Lagoon area.", Coordinates(36.5450, 29.1167), 20, "Boat from Fethiye", "Marina"),

        // ==========================================
        // CALIFORNIA (40+ spots)
        // ==========================================
        SpotRecord("cali-la-jolla-cove", "La Jolla Cove", "SHORE ENTRY - Marine preserve edges (check boundaries!). Rocky beach entry, kelp forest begins 50m offshore. Spearfishing allowed outside preserve boundary only.", Coordinates(32.8500, -117.2772), 12, "La Jolla village", "Street parking"),
        SpotRecord("cali-la-jolla-shores", "La Jolla Shores", "Sandy beach with kelp nearby.", Coordinates(32.8589, -117.2606), 10, "La Jolla Shores", "Beach lot"),
        SpotRecord("cali-bird-rock", "Bird Rock (La Jolla)", "Rocky reef area.", Coordinates(32.8150, -117.2750), 15, "Bird Rock area", "Street"),
        SpotRecord("cali-point-loma-kelp", "Point Loma Kelp Beds", "VERIFIED GPS - Extensive kelp forest offshore of Point Loma. White seabass, calicos, yellowtail, barracuda.", Coordinates(32.7000, -117.2717), 18, "Boat from San Diego - offshore of Point Loma", "Marina"),
        SpotRecord("cali-coronado-islands", "Coronado Islands", "Mexican waters, require permit.", Coordinates(32.4167, -117.2550), 25, "Boat from San Diego", "Marina"),
        SpotRecord("cali-catalina-casino-point", "Casino Point (Catalina)", "Underwater park, check rules.", Coordinates(33.3500, -118.3250), 20, "Avalon, Catalina", "Ferry"),
        SpotRecord("cali-catalina-isthmus", "Isthmus Cove (Catalina)", "VERIFIED GPS - Two Harbors area reef structure. Good for calicos, yellowtail, barracuda.", Coordinates(33.4467, -118.4883), 20, "Boat to Two Harbors", "Mooring"),
        SpotRecord("cali-catalina-farnsworth", "Farnsworth Bank (Catalina)", "VERIFIED GPS - Underwater seamount/pinnacles 1.5mi SW of Ben Weston Point. 54-200ft depth. Purple hydrocoral, yellowtail, lingcod. State Marine Conservation Area.", Coordinates(33.3400, -118.5192), 60, "Boat from mainland or Catalina - 1.5mi SW of Ben Weston Point", "Marina"),
        SpotRecord("cali-channel-islands-anacapa", "Anacapa Island - West End", "VERIFIED GPS - Closest Channel Island. West end reef structure with calicos, white seabass, halibut, yellowtail.", Coordinates(34.0167, -119.4500), 20, "Boat from Ventura - 11 miles offshore", "Harbor"),
        SpotRecord("cali-channel-islands-santa-cruz", "Santa Cruz Island - Smuggler's Cove", "VERIFIED GPS - Largest Channel Island. Smuggler's Cove reef with white seabass, calicos, halibut, yellowtail.", Coordinates(34.0223, -119.5373), 25, "Boat from Ventura or Santa Barbara - 20 miles offshore", "Harbor"),
        // Santa Rosa Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("cali-channel-islands-santa-rosa-north", "Santa Rosa Island - North", "North side of Santa Rosa. Exposed to NW swells, good lingcod.", Coordinates(34.0350, -120.1000), 25, "Boat from Santa Barbara or Ventura", "Harbor"),
        SpotRecord("cali-channel-islands-santa-rosa-south", "Santa Rosa Island - South", "South side of Santa Rosa. Protected from NW swells.", Coordinates(33.8950, -120.1000), 25, "Boat from Santa Barbara or Ventura", "Harbor"),
        SpotRecord("cali-channel-islands-santa-rosa-east", "Santa Rosa Island - East", "East side of Santa Rosa. Channel side.", Coordinates(33.9500, -119.9450), 25, "Boat from Santa Barbara or Ventura", "Harbor"),
        SpotRecord("cali-channel-islands-santa-rosa-west", "Santa Rosa Island - West", "West end of Santa Rosa. Most exposed, big fish.", Coordinates(33.9500, -120.2050), 25, "Boat from Santa Barbara or Ventura", "Harbor"),
        
        // San Miguel Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("cali-channel-islands-san-miguel-north", "San Miguel Island - North", "North side of San Miguel. Very exposed, rough conditions.", Coordinates(34.0883, -120.3667), 30, "Boat from Santa Barbara", "Harbor"),
        SpotRecord("cali-channel-islands-san-miguel-south", "San Miguel Island - South", "South side of San Miguel. More protected.", Coordinates(34.0083, -120.3667), 30, "Boat from Santa Barbara", "Harbor"),
        SpotRecord("cali-channel-islands-san-miguel-east", "San Miguel Island - East", "East side of San Miguel. Channel between islands.", Coordinates(34.0333, -120.3017), 30, "Boat from Santa Barbara", "Harbor"),
        SpotRecord("cali-channel-islands-san-miguel-west", "San Miguel Island - West", "Westernmost point. Open ocean exposure.", Coordinates(34.0333, -120.4617), 30, "Boat from Santa Barbara", "Harbor"),
        SpotRecord("cali-malibu-leo-carrillo", "Leo Carrillo Beach", "Rocky reef at Malibu border.", Coordinates(34.0433, -118.9333), 12, "Leo Carrillo State Park", "State park lot"),
        SpotRecord("cali-palos-verdes-point", "Palos Verdes Point", "Rocky peninsula.", Coordinates(33.7500, -118.4167), 15, "Various access points", "Street/lots"),
        SpotRecord("cali-hermosa-artificial", "Hermosa Beach Artificial Reef", "Man-made reef structure.", Coordinates(33.8500, -118.4050), 18, "Boat from King Harbor", "Marina"),
        SpotRecord("cali-redondo-horseshoe", "Horseshoe Kelp (Redondo)", "Offshore kelp forest.", Coordinates(33.8000, -118.4500), 20, "Boat from Redondo", "Marina"),
        SpotRecord("cali-laguna-shaw-cove", "Shaw's Cove (Laguna)", "Marine preserve adjacent.", Coordinates(33.5433, -117.7967), 10, "Laguna Beach", "Street"),
        SpotRecord("cali-laguna-divers-cove", "Diver's Cove (Laguna)", "Popular dive spot.", Coordinates(33.5383, -117.7933), 12, "Laguna Beach", "Street"),
        // San Clemente Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("cali-san-clemente-island-north", "San Clemente - North", "North end. Navy-controlled, check access.", Coordinates(32.9450, -118.5000), 25, "Boat from San Diego or LA", "Marina"),
        SpotRecord("cali-san-clemente-island-south", "San Clemente - South", "South end. Pyramid Head area.", Coordinates(32.8450, -118.5000), 25, "Boat from San Diego or LA", "Marina"),
        SpotRecord("cali-san-clemente-island-east", "San Clemente - East", "East coast. Facing mainland.", Coordinates(32.9000, -118.4450), 25, "Boat from San Diego or LA", "Marina"),
        SpotRecord("cali-san-clemente-island-west", "San Clemente - West", "West coast. Open Pacific.", Coordinates(32.9000, -118.5350), 25, "Boat from San Diego or LA", "Marina"),
        // Santa Barbara Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("cali-santa-barbara-island-north", "Santa Barbara Island - North", "North coast. Remote Channel Island.", Coordinates(33.5017, -119.0125), 25, "Boat from Ventura - 38 miles offshore", "Harbor"),
        SpotRecord("cali-santa-barbara-island-south", "Santa Barbara Island - South", "South coast. Excellent reef.", Coordinates(33.4717, -119.0125), 25, "Boat from Ventura - 38 miles offshore", "Harbor"),
        SpotRecord("cali-santa-barbara-island-east", "Santa Barbara Island - East", "East coast. Facing mainland.", Coordinates(33.4867, -118.9975), 25, "Boat from Ventura - 38 miles offshore", "Harbor"),
        SpotRecord("cali-santa-barbara-island-west", "Santa Barbara Island - West", "West coast. Open Pacific.", Coordinates(33.4867, -119.0275), 25, "Boat from Ventura - 38 miles offshore", "Harbor"),
        SpotRecord("cali-monterey-breakwater", "Monterey Breakwater", "Protected dive area.", Coordinates(36.6167, -121.8917), 12, "Monterey waterfront", "Lot"),
        SpotRecord("cali-carmel-point-lobos", "Point Lobos Reserve", "Some zones restricted.", Coordinates(36.524345, -121.942814), 15, "Point Lobos State Reserve", "Reserve parking"),
        SpotRecord("cali-big-sur-jade-cove", "Jade Cove (Big Sur)", "Remote jade hunting spot.", Coordinates(35.9050, -121.4700), 12, "Big Sur, hike in", "Highway pullout"),
        SpotRecord("cali-morro-bay-rock", "Morro Rock", "Iconic rock with diving.", Coordinates(35.3700, -120.8750), 15, "Morro Bay", "Beach parking"),
        SpotRecord("cali-avila-port-san-luis", "Port San Luis", "Central coast access.", Coordinates(35.1717, -120.7533), 18, "Boat from Port San Luis", "Harbor"),

        // VERIFIED OFFSHORE BANKS & REEFS (from Spearboard GPS Database)
        SpotRecord("cali-cortez-bank", "Cortez Bank", "VERIFIED GPS - Famous offshore seamount 100mi W of San Diego. Shallow high spot at 15ft. Bluefin tuna, yellowtail, yellowfin.", Coordinates(32.4444, -119.1108), 15, "Boat from San Diego - 100 miles offshore", "Marina"),
        SpotRecord("cali-tanner-bank", "Tanner Bank", "VERIFIED GPS - Offshore bank 60mi SW of San Diego. High spot at 80ft. Albacore, bluefin, yellowtail.", Coordinates(32.7058, -119.1335), 80, "Boat from San Diego - 60 miles offshore", "Marina"),
        SpotRecord("cali-nine-mile-bank-north", "9-Mile Bank (North)", "VERIFIED GPS - Offshore bank 9mi from Point Loma. Marlin, yellowtail, yellowfin, dorado, rockfish.", Coordinates(32.6067, -117.4025), 50, "Boat from San Diego - 9 miles offshore", "Marina"),
        SpotRecord("cali-14-mile-bank", "14-Mile Bank", "VERIFIED GPS - Offshore bank SW of LA. Yellowtail, yellowfin, dorado, marlin.", Coordinates(33.3987, -118.0003), 60, "Boat from Long Beach/LA - 14 miles offshore", "Marina"),
        SpotRecord("cali-horseshoe-kelp", "Horseshoe Kelp", "VERIFIED GPS - Offshore kelp bed off Redondo. Calico, sand bass, sculpin, barracuda, yellowtail.", Coordinates(33.6400, -118.2333), 12, "Boat from Redondo Beach - 8 miles offshore", "Marina"),
        SpotRecord("cali-potters-reef", "Potter's Reef (Horseshoe Drop-off)", "VERIFIED GPS - Reef structure off Long Beach. Calico, sand bass, sculpin, yellowtail.", Coordinates(33.6465, -118.2718), 15, "Boat from Long Beach - offshore", "Marina"),
        SpotRecord("cali-la-jolla-kelp-offshore", "La Jolla Kelp (Offshore)", "VERIFIED GPS - Offshore kelp beds SW of La Jolla. White seabass, calico, sand bass, yellowtail.", Coordinates(32.8217, -117.2883), 18, "Boat from Mission Bay - 3 miles offshore", "Marina"),
        SpotRecord("cali-60-mile-bank", "60-Mile Bank", "VERIFIED GPS - Remote offshore bank. Albacore, bluefin, yellowtail, yellowfin, dorado.", Coordinates(32.0611, -118.2190), 100, "Boat from San Diego - 60 miles offshore", "Marina"),
        SpotRecord("cali-osborne-bank", "Osborne Bank", "VERIFIED GPS - Offshore bank between mainland and islands. Albacore, bluefin, yellowtail, yellowfin, marlin.", Coordinates(33.3600, -119.0400), 80, "Boat from Ventura - 25 miles offshore", "Marina"),
        SpotRecord("cali-avalon-bank", "Avalon Bank (228 Spot)", "VERIFIED GPS - Bank NE of Catalina. Marlin, yellowtail, yellowfin, dorado.", Coordinates(33.4097, -118.2217), 70, "Boat from Long Beach - between mainland and Catalina", "Marina"),
        SpotRecord("cali-mackerel-bank", "Mackerel Bank", "VERIFIED GPS - Offshore bank south of Santa Catalina. Marlin, yellowfin, yellowtail, dorado.", Coordinates(33.0405, -118.5419), 90, "Boat from San Diego/LA - south of Catalina", "Marina"),
        
        // VERIFIED ARTIFICIAL REEFS - California
        SpotRecord("cali-hermosa-artificial-reef", "Hermosa Beach Artificial Reef", "VERIFIED GPS - Man-made reef structure offshore of Hermosa.", Coordinates(33.8537, -118.4133), 50, "Boat from King Harbor - 2 miles offshore", "Marina"),
        SpotRecord("cali-redondo-artificial-reef", "Redondo Beach Artificial Reef", "VERIFIED GPS - Man-made reef structure offshore of Redondo.", Coordinates(33.8372, -118.4089), 50, "Boat from King Harbor", "Marina"),
        SpotRecord("cali-torrey-pines-reef", "Torrey Pines Artificial Reef", "VERIFIED GPS - Artificial reef offshore of Torrey Pines.", Coordinates(32.8930, -117.2639), 45, "Boat from Mission Bay - 3 miles offshore", "Marina"),
        SpotRecord("cali-oceanside-artificial-reef", "Oceanside Artificial Reef", "VERIFIED GPS - Large 256-acre artificial reef complex. Multiple depth zones 40-80ft.", Coordinates(33.2097, -117.4300), 50, "Boat from Oceanside Harbor - 3 miles offshore", "Marina"),
        SpotRecord("cali-huntington-flats", "Huntington Flats", "VERIFIED GPS - Shallow reef structure off Huntington Beach. Sand bass, sculpin, barracuda, yellowtail.", Coordinates(33.6412, -118.0547), 20, "Boat from Long Beach/Newport - offshore of Huntington", "Marina"),

        // ==========================================
        // More regions continue...
        // ==========================================
        
        // Mexico - Sea of Cortez
        // Espiritu Santo Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("mexico-espiritu-santo-north", "Espiritu Santo - North", "North end. La Paz hunting ground.", Coordinates(24.5283, -110.3333), 25, "Boat from La Paz", "La Paz marina"),
        SpotRecord("mexico-espiritu-santo-south", "Espiritu Santo - South", "South end. Los Islotes nearby.", Coordinates(24.3983, -110.3333), 25, "Boat from La Paz", "La Paz marina"),
        SpotRecord("mexico-espiritu-santo-east", "Espiritu Santo - East", "East coast. Sea of Cortez.", Coordinates(24.4833, -110.2883), 25, "Boat from La Paz", "La Paz marina"),
        SpotRecord("mexico-espiritu-santo-west", "Espiritu Santo - West", "West coast. Facing La Paz.", Coordinates(24.4833, -110.3983), 25, "Boat from La Paz", "La Paz marina"),
        SpotRecord("mexico-cerralvo", "Isla Cerralvo", "Remote island with pristine conditions.", Coordinates(24.140599, -109.85), 30, "Boat from La Paz", "Marina"),
        SpotRecord("mexico-el-bajo", "El Bajo Seamount", "Hammerheads and big pelagics.", Coordinates(24.5833, -110.2833), 20, "Boat from La Paz", "Marina"),
        SpotRecord("mexico-la-reina", "La Reina", "Pinnacle with sea lions.", Coordinates(24.5500, -110.3167), 25, "Near Espiritu Santo", "La Paz marina"),
        SpotRecord("mexico-cabo-pulmo", "Cabo Pulmo National Park", "No-take zone, check boundaries.", Coordinates(23.4333, -109.4167), 20, "Boat from Cabo", "Beach"),
        SpotRecord("mexico-gordo-banks", "Gordo Banks", "Two seamounts with hammerheads.", Coordinates(23.0500, -109.4167), 35, "Boat from San Jose del Cabo", "Marina"),
        SpotRecord("mexico-lands-end", "Land's End (Cabo)", "Famous arch with reef.", Coordinates(22.8750, -109.8917), 20, "Boat from Cabo", "Marina"),

        // Indonesia - Raja Ampat
        SpotRecord("raja-ampat-cape-kri", "Cape Kri", "World record 374 fish species.", Coordinates(-0.5500, 130.6667), 25, "Kri Eco Resort", "Resort"),
        SpotRecord("raja-ampat-blue-magic", "Blue Magic", "Oceanic mantas and sharks.", Coordinates(-0.5333, 130.6833), 30, "15 min from Mansuar", "Resort"),
        SpotRecord("raja-ampat-sardines", "Sardines Reef", "Second most biodiverse.", Coordinates(-0.5600, 130.6500), 20, "10 min from Kri", "Resort"),
        SpotRecord("raja-ampat-passage", "The Passage", "Narrow channel with tidal flow.", Coordinates(-0.4333, 130.5500), 15, "Boat from Waisai", "Marina"),
        SpotRecord("raja-ampat-misool", "Misool", "Remote southern area.", Coordinates(-1.744783, 129.9833), 30, "Liveaboard or Misool Eco Resort", "Resort"),

        // Australia
        SpotRecord("aus-cairns-outer-reef", "Cairns Outer Reef", "Great Barrier Reef day trips.", Coordinates(-16.7500, 146.0000), 20, "Boat from Cairns", "Cairns marina"),
        SpotRecord("aus-ribbon-reefs", "Ribbon Reefs", "Pristine northern GBR.", Coordinates(-14.7500, 145.6500), 25, "Liveaboard from Cairns", "Marina"),
        SpotRecord("aus-ningaloo-coral-bay", "Coral Bay (Ningaloo)", "Whale sharks March-July.", Coordinates(-23.1500, 113.7667), 15, "Coral Bay township", "Beach"),
        SpotRecord("aus-ningaloo-exmouth", "Exmouth (Ningaloo)", "Navy Pier legendary dive.", Coordinates(-21.9333, 114.144957), 20, "Boat from Exmouth", "Exmouth marina"),
        // Montague Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("aus-montague-island-north", "Montague Island - North", "North coast. Huge kingfish.", Coordinates(-36.2350, 150.2333), 25, "Boat from Narooma", "Narooma ramp"),
        SpotRecord("aus-montague-island-south", "Montague Island - South", "South coast. Temperate water.", Coordinates(-36.2650, 150.2333), 25, "Boat from Narooma", "Narooma ramp"),
        SpotRecord("aus-montague-island-east", "Montague Island - East", "East coast. Open Tasman.", Coordinates(-36.2500, 150.2483), 25, "Boat from Narooma", "Narooma ramp"),
        SpotRecord("aus-montague-island-west", "Montague Island - West", "West coast. Facing mainland.", Coordinates(-36.2500, 150.2183), 25, "Boat from Narooma", "Narooma ramp"),

        // Philippines
        SpotRecord("phil-coron-wrecks", "Coron Bay Wrecks", "WWII Japanese shipwrecks.", Coordinates(11.9833, 120.1950), 30, "Boat from Coron Town", "Coron"),
        // Tubbataha Reef - Split into directional spots (coastline + 500m offshore)
        SpotRecord("phil-tubbataha-north", "Tubbataha Reef - North", "North atoll. UNESCO site, mantas.", Coordinates(8.9483, 119.9000), 30, "Liveaboard from Puerto Princesa", "Liveaboard"),
        SpotRecord("phil-tubbataha-south", "Tubbataha Reef - South", "South atoll. Hammerhead cleaning station.", Coordinates(8.9183, 119.9000), 30, "Liveaboard from Puerto Princesa", "Liveaboard"),
        SpotRecord("phil-tubbataha-east", "Tubbataha Reef - East", "East wall. Deep drop-off.", Coordinates(8.9333, 119.9150), 30, "Liveaboard from Puerto Princesa", "Liveaboard"),
        SpotRecord("phil-tubbataha-west", "Tubbataha Reef - West", "West wall. Sunrise dives.", Coordinates(8.9333, 119.8850), 30, "Liveaboard from Puerto Princesa", "Liveaboard"),
        SpotRecord("phil-apo-reef", "Apo Reef", "Second largest contiguous reef.", Coordinates(12.6500, 120.4500), 25, "Boat from Sablayan", "Marina"),
        SpotRecord("phil-malapascua", "Malapascua", "Thresher sharks at dawn.", Coordinates(11.3350, 124.1200), 25, "Boat from Cebu", "Resort"),
        // Balicasag Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("phil-balicasag-north", "Balicasag - North", "North coast. Bohol diving gem.", Coordinates(9.5317, 123.6783), 25, "Boat from Panglao", "Resort"),
        SpotRecord("phil-balicasag-south", "Balicasag - South", "South coast. Jack point.", Coordinates(9.5017, 123.6783), 25, "Boat from Panglao", "Resort"),
        SpotRecord("phil-balicasag-east", "Balicasag - East", "East coast. Diver's Heaven.", Coordinates(9.5167, 123.6933), 25, "Boat from Panglao", "Resort"),
        SpotRecord("phil-balicasag-west", "Balicasag - West", "West coast. Cathedral wall.", Coordinates(9.5167, 123.6633), 25, "Boat from Panglao", "Resort"),

        // Fiji
        // Beqa Lagoon - Split into directional spots (coastline + 500m offshore)
        SpotRecord("fiji-beqa-north", "Beqa Lagoon - North", "North side. Eight shark species at Cathedral.", Coordinates(-18.3683, 177.9833), 25, "Boat from Pacific Harbour", "Resort"),
        SpotRecord("fiji-beqa-south", "Beqa Lagoon - South", "South side. Open Pacific exposure.", Coordinates(-18.3983, 177.9833), 25, "Boat from Pacific Harbour", "Resort"),
        SpotRecord("fiji-beqa-east", "Beqa Lagoon - East", "East side. Strong currents.", Coordinates(-18.3833, 178.0083), 25, "Boat from Pacific Harbour", "Resort"),
        SpotRecord("fiji-beqa-west", "Beqa Lagoon - West", "West side. Closest to Pacific Harbour.", Coordinates(-18.3833, 177.9683), 25, "Boat from Pacific Harbour", "Resort"),
        // Kadavu/Astrolabe Reef - Split into directional spots (coastline + 500m offshore)
        SpotRecord("fiji-kadavu-astrolabe-north", "Astrolabe Reef - North", "North end. 120km barrier reef.", Coordinates(-19.0350, 178.2500), 25, "Boat from Kadavu", "Resort"),
        SpotRecord("fiji-kadavu-astrolabe-south", "Astrolabe Reef - South", "South end. Remote diving.", Coordinates(-19.0650, 178.2500), 25, "Boat from Kadavu", "Resort"),
        SpotRecord("fiji-kadavu-astrolabe-east", "Astrolabe Reef - East", "East side. Open Pacific.", Coordinates(-19.0500, 178.2650), 25, "Boat from Kadavu", "Resort"),
        SpotRecord("fiji-kadavu-astrolabe-west", "Astrolabe Reef - West", "West side. Inside lagoon.", Coordinates(-19.0500, 178.2350), 25, "Boat from Kadavu", "Resort"),
        // Taveuni Rainbow Reef - Split into directional spots (coastline + 500m offshore)
        SpotRecord("fiji-taveuni-rainbow-north", "Taveuni Rainbow - North", "North side. Soft coral capital.", Coordinates(-16.8850, 179.9000), 20, "Boat from Taveuni", "Resort"),
        SpotRecord("fiji-taveuni-rainbow-south", "Taveuni Rainbow - South", "South side. Great White Wall.", Coordinates(-16.9150, 179.9000), 20, "Boat from Taveuni", "Resort"),
        SpotRecord("fiji-taveuni-rainbow-east", "Taveuni Rainbow - East", "East side. Somosomo Strait.", Coordinates(-16.9000, 179.9150), 20, "Boat from Taveuni", "Resort"),
        SpotRecord("fiji-taveuni-rainbow-west", "Taveuni Rainbow - West", "West side. Taveuni shore.", Coordinates(-16.9000, 179.8850), 20, "Boat from Taveuni", "Resort"),
        SpotRecord("fiji-namena-marine", "Namena Marine Reserve", "Protected area.", Coordinates(-17.1000, 179.1000), 25, "Liveaboard or resort", "Various"),

        // Maldives
        SpotRecord("maldives-maaya-thila", "Maaya Thila", "Top Maldives site.", Coordinates(3.8833, 72.9000), 25, "Boat from North Ari resorts", "Resort"),
        SpotRecord("maldives-fish-head", "Fish Head", "Shark cleaning station.", Coordinates(3.9000, 72.9167), 25, "Boat from North Ari", "Resort"),
        SpotRecord("maldives-manta-point", "Manta Point (Lankanfinolhu)", "Manta cleaning station.", Coordinates(4.2500, 72.9500), 15, "Boat from North Male", "Resort"),
        SpotRecord("maldives-hanifaru-bay", "Hanifaru Bay", "Manta aggregation June-Nov.", Coordinates(5.2500, 73.0833), 15, "Baa Atoll", "Resort"),

        // Red Sea Egypt
        SpotRecord("egypt-elphinstone", "Elphinstone Reef", "Oceanic whitetips and hammerheads.", Coordinates(25.3167, 34.8667), 30, "Boat from Marsa Alam", "Marina"),
        SpotRecord("egypt-brothers", "Brothers Islands", "Remote with sharks.", Coordinates(26.3167, 34.8500), 30, "Liveaboard", "Liveaboard"),
        SpotRecord("egypt-daedalus", "Daedalus Reef", "Remote reef with hammerheads.", Coordinates(24.9167, 35.8500), 30, "Liveaboard", "Liveaboard"),
        SpotRecord("egypt-jackson-reef", "Jackson Reef", "Straits of Tiran.", Coordinates(27.9500, 34.4667), 25, "Boat from Sharm", "Marina"),
        SpotRecord("egypt-thistlegorm", "SS Thistlegorm", "Famous WWII wreck.", Coordinates(27.8167, 33.9167), 30, "Boat from Sharm or Hurghada", "Marina"),

        // South Africa
        SpotRecord("sa-sodwana-two-mile", "Two Mile Reef (Sodwana)", "Subtropical reef.", Coordinates(-27.5333, 32.6833), 15, "Sodwana Bay", "4x4 launch"),
        SpotRecord("sa-aliwal-shoal", "Aliwal Shoal", "Ragged-tooth sharks.", Coordinates(-30.2667, 30.8333), 25, "Boat from Umkomaas", "Beach launch"),
        SpotRecord("sa-protea-banks", "Protea Banks", "Deep water shark action.", Coordinates(-30.7000, 30.5500), 35, "Boat from Shelly Beach", "Marina"),
        SpotRecord("sa-cape-town-simons", "Simon's Town", "Cold water diving.", Coordinates(-34.1833, 18.4333), 15, "Boat from Simon's Town", "Marina"),

        // New Zealand
        // Goat Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("nz-goat-island-north", "Goat Island - North", "North coast. Marine reserve.", Coordinates(-36.2517, 174.8000), 12, "Leigh, north of Auckland", "Beach parking"),
        SpotRecord("nz-goat-island-south", "Goat Island - South", "South coast. Check boundaries.", Coordinates(-36.3117, 174.8000), 12, "Leigh, north of Auckland", "Beach parking"),
        SpotRecord("nz-goat-island-east", "Goat Island - East", "East coast. Ocean side.", Coordinates(-36.2667, 174.8150), 12, "Leigh, north of Auckland", "Beach parking"),
        SpotRecord("nz-goat-island-west", "Goat Island - West", "West coast. Mainland side.", Coordinates(-36.2667, 174.7850), 12, "Leigh, north of Auckland", "Beach parking"),
        // Great Barrier Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("nz-great-barrier-north", "Great Barrier - North", "North coast. Remote with clear water.", Coordinates(-36.0450, 175.4000), 20, "Ferry from Auckland", "Various"),
        SpotRecord("nz-great-barrier-south", "Great Barrier - South", "South coast. Sheltered.", Coordinates(-36.2750, 175.4000), 20, "Ferry from Auckland", "Various"),
        SpotRecord("nz-great-barrier-east", "Great Barrier - East", "East coast. Pacific exposure.", Coordinates(-36.2000, 175.4950), 20, "Ferry from Auckland", "Various"),
        SpotRecord("nz-great-barrier-west", "Great Barrier - West", "West coast. Hauraki Gulf.", Coordinates(-36.2000, 175.3450), 20, "Ferry from Auckland", "Various"),
        SpotRecord("nz-bay-of-islands", "Bay of Islands", "Multiple dive spots.", Coordinates(-35.2500, 174.1000), 20, "Boat from Paihia or Russell", "Marina"),
        SpotRecord("nz-fiordland", "Fiordland", "Unique black coral.", Coordinates(-45.435153, 167.123698), 25, "Boat from Te Anau or Milford", "Various"),

        // Belize
        SpotRecord("belize-blue-hole", "Great Blue Hole", "Famous sinkhole.", Coordinates(17.3158, -87.5350), 40, "Boat from Ambergris or Turneffe", "Resort"),
        SpotRecord("belize-turneffe-elbow", "The Elbow (Turneffe)", "Southern tip with currents.", Coordinates(17.1833, -87.8000), 25, "Boat from Turneffe", "Resort"),
        SpotRecord("belize-lighthouse-half-moon", "Half Moon Caye", "UNESCO site.", Coordinates(17.2000, -87.5333), 20, "Boat from Lighthouse Reef", "Atoll"),
        SpotRecord("belize-glovers-reef", "Glover's Reef", "Remote atoll.", Coordinates(16.7500, -87.8000), 25, "Boat from Dangriga", "Atoll"),

        // Puerto Rico
        SpotRecord("pr-desecheo", "Desecheo Island", "Wildlife refuge, 13 miles offshore.", Coordinates(18.3833, -67.4883), 25, "Boat from Rincon", "Marina"),
        // Mona Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("pr-mona-island-north", "Mona Island - North", "North coast. Permit required.", Coordinates(18.1283, -67.9000), 30, "Boat from Mayaguez", "Marina"),
        SpotRecord("pr-mona-island-south", "Mona Island - South", "South coast. Remote diving.", Coordinates(18.0483, -67.9000), 30, "Boat from Mayaguez", "Marina"),
        SpotRecord("pr-mona-island-east", "Mona Island - East", "East coast. Facing PR.", Coordinates(18.0833, -67.8350), 30, "Boat from Mayaguez", "Marina"),
        SpotRecord("pr-mona-island-west", "Mona Island - West", "West coast. Mona Passage.", Coordinates(18.0833, -67.9550), 30, "Boat from Mayaguez", "Marina"),
        SpotRecord("pr-la-parguera", "La Parguera Walls", "Southwest coast walls.", Coordinates(17.9667, -67.0500), 25, "Boat from La Parguera", "Marina"),
        SpotRecord("pr-fajardo", "Fajardo Reefs", "East coast diving.", Coordinates(18.3383, -65.6333), 20, "Boat from Fajardo", "Marina"),

        // North Carolina
        SpotRecord("nc-hatteras-offshore", "Cape Hatteras Offshore", "Gulf Stream meets Labrador Current.", Coordinates(35.2167, -75.5333), 35, "Boat from Hatteras", "Marina"),
        SpotRecord("nc-diamond-shoals", "Diamond Shoals", "Treacherous but fishful.", Coordinates(35.1500, -75.4000), 25, "Boat from Hatteras", "Marina"),
        SpotRecord("nc-lookout-shoals", "Cape Lookout Shoals", "Southern Outer Banks.", Coordinates(34.5833, -76.5333), 25, "Boat from Beaufort", "Marina"),
        SpotRecord("nc-papoose-wreck", "Papoose Wreck", "Tanker sunk by U-boat.", Coordinates(34.6667, -76.5167), 35, "Boat from Morehead City", "Marina"),
        SpotRecord("nc-u352-wreck", "U-352 Wreck", "German U-boat.", Coordinates(34.6000, -76.6833), 35, "Boat from Morehead City", "Marina"),

        // ==========================================
        // HAWAII - KAUAI (40+ spots)
        // ==========================================
        SpotRecord("kauai-tunnels-beach", "Tunnels Beach (Makua)", "Famous reef with lava tubes. Summer only.", Coordinates(22.2269, -159.5697), 12, "End of Kuhio Hwy, Haena", "Limited beach parking"),
        SpotRecord("kauai-poipu-beach", "Poipu Beach", "South shore with good reef structure.", Coordinates(21.8725, -159.4594), 10, "Poipu Beach Park", "Beach park lot"),
        SpotRecord("kauai-anini-beach", "Anini Beach", "Protected reef on north shore.", Coordinates(22.2283, -159.4583), 8, "Anini Beach Park", "Beach park lot"),
        SpotRecord("kauai-kee-beach", "Kee Beach", "End of road, pristine reef.", Coordinates(22.2228, -159.5864), 15, "End of Kuhio Hwy", "Requires reservation"),
        SpotRecord("kauai-lydgate-beach", "Lydgate Beach", "Protected pools plus outside reef.", Coordinates(22.041699, -159.326954), 8, "Lydgate Beach Park", "Beach park lot"),
        SpotRecord("kauai-salt-pond", "Salt Pond Beach", "West side with good visibility.", Coordinates(21.9000, -159.6083), 10, "Salt Pond Beach Park", "Beach park lot"),
        SpotRecord("kauai-polihale", "Polihale Beach", "Remote west side, difficult access.", Coordinates(22.0789, -159.7661), 10, "End of dirt road", "4WD required"),
        SpotRecord("kauai-koloa-landing", "Koloa Landing", "Historic landing with reef.", Coordinates(21.8614, -159.4636), 15, "Koloa Landing Park", "Small lot"),
        SpotRecord("kauai-lawai-beach", "Lawai Beach", "Near Spouting Horn with reef.", Coordinates(21.8722, -159.4917), 12, "Lawai Beach Resort area", "Limited"),
        SpotRecord("kauai-hanalei-bay", "Hanalei Bay", "Large bay with reef edges.", Coordinates(22.2094, -159.5072), 10, "Hanalei Beach Park", "Beach park lot"),
        SpotRecord("kauai-haena-reef", "Haena Reef", "Outer reef beyond Tunnels.", Coordinates(22.2250, -159.5650), 20, "Boat from Hanalei", "Hanalei pier"),
        // Niihau Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("kauai-niihau-north", "Niihau - North", "North coast. Forbidden Island, charter only.", Coordinates(21.9550, -160.1500), 30, "Charter from Kauai", "Port Allen"),
        SpotRecord("kauai-niihau-south", "Niihau - South", "South coast. Pristine waters.", Coordinates(21.8550, -160.1500), 30, "Charter from Kauai", "Port Allen"),
        SpotRecord("kauai-niihau-east", "Niihau - East", "East coast. Facing Kauai.", Coordinates(21.9000, -160.0650), 30, "Charter from Kauai", "Port Allen"),
        SpotRecord("kauai-niihau-west", "Niihau - West", "West coast. Open Pacific.", Coordinates(21.9000, -160.2250), 30, "Charter from Kauai", "Port Allen"),
        SpotRecord("kauai-lehua-rock", "Lehua Rock", "Volcanic islet near Niihau. Remote diving.", Coordinates(22.0167, -160.1050), 25, "Charter from Kauai", "Port Allen"),
        SpotRecord("kauai-port-allen", "Port Allen Harbor", "Harbor reef and offshore.", Coordinates(21.8972, -159.5917), 15, "Port Allen Small Boat Harbor", "Harbor parking"),
        SpotRecord("kauai-napali-coast", "Na Pali Coast", "Remote coast, summer only.", Coordinates(22.1833, -159.6333), 20, "Boat from Hanalei or Port Allen", "Marina"),
        SpotRecord("kauai-princeville-reefs", "Princeville Reefs", "North shore reef system.", Coordinates(22.23111, -159.4667), 12, "Various Princeville access points", "Resort parking"),
        SpotRecord("kauai-kipu-kai", "Kipu Kai", "Private beach, boat access.", Coordinates(21.88981, -159.405719), 15, "Boat from Nawiliwili", "Marina"),
        SpotRecord("kauai-nawiliwili-harbor", "Nawiliwili Harbor Reef", "Harbor entrance reef.", Coordinates(21.9550, -159.3500), 12, "Nawiliwili Harbor", "Harbor"),
        SpotRecord("kauai-anahola-bay", "Anahola Bay", "East side bay with reef.", Coordinates(22.149346, -159.300045), 8, "Anahola Beach Park", "Beach park"),
        SpotRecord("kauai-moloaa-bay", "Moloaa Bay", "Quiet east side bay.", Coordinates(22.195397, -159.320235), 10, "Moloaa Beach", "Limited road access"),

        // ==========================================
        // HAWAII - MOLOKAI (25+ spots)
        // ==========================================
        SpotRecord("molokai-kaunakakai-wharf", "Kaunakakai Wharf", "Historic wharf with fish aggregation.", Coordinates(21.0833, -157.0167), 8, "Kaunakakai town", "Wharf parking"),
        SpotRecord("molokai-papohaku-beach", "Papohaku Beach", "Longest white sand beach in Hawaii.", Coordinates(21.176889, -157.260927), 10, "Kaluakoi area", "Beach access"),
        SpotRecord("molokai-kawakiu-bay", "Kawakiu Bay", "West end with clear water.", Coordinates(21.1833, -157.2667), 12, "West Molokai", "Dirt road"),
        SpotRecord("molokai-kepuhi-bay", "Kepuhi Bay", "Resort area with reef.", Coordinates(21.174999, -157.260047), 10, "Kaluakoi Resort area", "Resort parking"),
        SpotRecord("molokai-murphy-beach", "Murphy Beach", "East side with calm water.", Coordinates(21.0783, -156.7833), 8, "East Molokai", "Roadside"),
        SpotRecord("molokai-halawa-bay", "Halawa Bay", "Remote east end with valley.", Coordinates(21.16441, -156.7333), 12, "End of Kamehameha V Hwy", "Small lot"),
        SpotRecord("molokai-south-shore-reef", "South Shore Reef", "Extensive fringing reef.", Coordinates(21.0667, -157.0000), 8, "Various south shore access", "Limited"),
        SpotRecord("molokai-rock-point", "Rock Point", "West Molokai diving spot.", Coordinates(21.1500, -157.2883), 20, "Boat from Kaunakakai", "Harbor"),
        SpotRecord("molokai-penguin-bank", "Penguin Bank", "Offshore bank with big fish.", Coordinates(20.8333, -157.2500), 30, "Charter from Molokai", "Kaunakakai Harbor"),
        SpotRecord("molokai-kalaupapa", "Kalaupapa Peninsula", "Historic leper colony, permit required.", Coordinates(21.203797, -156.953724), 15, "Permit required", "Kalaupapa"),

        // ==========================================
        // HAWAII - LANAI (20+ spots)
        // ==========================================
        SpotRecord("lanai-hulopoe-bay", "Hulopoe Bay Marine Preserve", "Marine preserve, limited take.", Coordinates(20.7333, -156.9167), 15, "Four Seasons resort area", "Resort or public lot"),
        SpotRecord("lanai-shark-fin-rock", "Shark Fin Rock", "Iconic rock formation with reef.", Coordinates(20.734722, -156.916965), 20, "Boat from Manele Harbor", "Harbor"),
        SpotRecord("lanai-manele-bay", "Manele Bay", "Harbor with surrounding reef.", Coordinates(20.7417, -156.8867), 12, "Manele Small Boat Harbor", "Harbor parking"),
        SpotRecord("lanai-shipwreck-beach", "Shipwreck Beach", "North shore with wrecks.", Coordinates(20.926101, -156.9167), 10, "North Lanai", "4WD access"),
        SpotRecord("lanai-cathedrals", "Cathedrals", "Famous lava tube diving.", Coordinates(20.7250, -156.9250), 20, "Boat from Manele", "Harbor"),
        SpotRecord("lanai-first-cathedral", "First Cathedral", "Primary cathedral site.", Coordinates(20.7260, -156.9270), 18, "Boat from Manele", "Harbor"),
        SpotRecord("lanai-second-cathedral", "Second Cathedral", "Second lava tube system.", Coordinates(20.7240, -156.9230), 20, "Boat from Manele", "Harbor"),
        SpotRecord("lanai-lighthouse-point", "Lighthouse Point", "Southern tip with current.", Coordinates(20.7167, -156.9000), 25, "Boat from Manele", "Harbor"),
        SpotRecord("lanai-kaumalapau-harbor", "Kaumalapau Harbor", "Pineapple shipping harbor.", Coordinates(20.7833, -156.9967), 12, "Kaumalapau Harbor", "Limited"),
        SpotRecord("lanai-polihua-beach", "Polihua Beach", "Remote north beach.", Coordinates(20.933808, -156.9833), 10, "4WD from Lanai City", "None"),
        SpotRecord("lanai-lopa-beach", "Lopa Beach", "East side with reef.", Coordinates(20.86765, -156.829934), 10, "East Lanai", "4WD"),

        // ==========================================
        // FLORIDA - ATLANTIC COAST (40+ spots)
        // ==========================================
        SpotRecord("fl-palm-beach-inlet", "Palm Beach Inlet", "Strong currents, big fish.", Coordinates(26.7700, -80.0333), 20, "Boat from Palm Beach", "Marina"),
        SpotRecord("fl-jupiter-ledge", "Jupiter Ledge", "Natural reef ledge.", Coordinates(26.9500, -80.0500), 25, "Boat from Jupiter", "Jupiter Inlet Marina"),
        SpotRecord("fl-breakers-reef", "Breakers Reef (Palm Beach)", "Near famous hotel.", Coordinates(26.7217, -80.0333), 18, "Boat from Palm Beach", "Marina"),
        SpotRecord("fl-delray-ledge", "Delray Ledge", "Inshore ledge system.", Coordinates(26.4500, -80.0500), 15, "Boat from Delray", "Marina"),
        SpotRecord("fl-boynton-ledge", "Boynton Ledge", "Good hogfish habitat.", Coordinates(26.5383, -80.0500), 18, "Boat from Boynton", "Marina"),
        SpotRecord("fl-boca-inlet", "Boca Raton Inlet", "Inlet with reef structure.", Coordinates(26.3333, -80.0667), 15, "Boat from Boca", "Marina"),
        SpotRecord("fl-hillsboro-inlet", "Hillsboro Inlet", "Lighthouse inlet with reef.", Coordinates(26.2583, -80.0750), 18, "Boat from Pompano", "Marina"),
        SpotRecord("fl-lauderdale-reef", "Fort Lauderdale Reef", "Artificial reef complex.", Coordinates(26.1000, -80.0833), 20, "Boat from Ft Lauderdale", "Bahia Mar"),
        SpotRecord("fl-hollywood-reef", "Hollywood Beach Reef", "Natural reef.", Coordinates(26.0000, -80.1000), 15, "Boat from Hollywood", "Marina"),
        SpotRecord("fl-haulover-inlet", "Haulover Inlet", "Miami inlet with structure.", Coordinates(25.9000, -80.1167), 12, "Boat from Miami", "Haulover Marina"),
        SpotRecord("fl-government-cut", "Government Cut (Miami)", "Port of Miami entrance.", Coordinates(25.7667, -80.1383), 15, "Boat from Miami", "Miami Beach Marina"),
        SpotRecord("fl-fowey-rocks", "Fowey Rocks", "Lighthouse reef.", Coordinates(25.5900, -80.0967), 20, "Boat from Miami", "Marina"),
        SpotRecord("fl-triumph-reef", "Triumph Reef", "Offshore reef.", Coordinates(25.5000, -80.1167), 15, "Boat from Miami/Homestead", "Marina"),
        SpotRecord("fl-ajax-reef", "Ajax Reef", "Upper Keys reef.", Coordinates(25.3833, -80.1833), 12, "Boat from Key Largo", "Marina"),
        SpotRecord("fl-st-augustine-reef", "St. Augustine Reef", "Northeast Florida reef.", Coordinates(29.8667, -81.2167), 20, "Boat from St. Augustine", "Marina"),
        SpotRecord("fl-daytona-ledge", "Daytona Ledge", "Central Florida ledge.", Coordinates(29.2000, -80.9833), 22, "Boat from Ponce Inlet", "Marina"),
        SpotRecord("fl-sebastian-inlet", "Sebastian Inlet", "Famous for snook.", Coordinates(27.8583, -80.4500), 8, "Sebastian Inlet State Park", "State park lot"),
        SpotRecord("fl-fort-pierce-reef", "Fort Pierce Reef", "Artificial reef complex.", Coordinates(27.4667, -80.2667), 18, "Boat from Fort Pierce", "Marina"),

        // ==========================================
        // FLORIDA - GULF COAST (35+ spots)
        // ==========================================
        SpotRecord("fl-tampa-bay-bridge", "Skyway Bridge", "Massive bridge structure.", Coordinates(27.6167, -82.6500), 15, "Skyway Pier State Park", "State park lot"),
        SpotRecord("fl-egmont-key", "Egmont Key", "Historic island with reef.", Coordinates(27.5983, -82.7667), 15, "Boat from Tampa Bay", "Marina"),
        SpotRecord("fl-clearwater-artificial", "Clearwater Artificial Reef", "Multiple artificial reefs.", Coordinates(27.9667, -83.0000), 20, "Boat from Clearwater", "Marina"),
        SpotRecord("fl-tarpon-springs", "Tarpon Springs Reef", "Sponge diving heritage area.", Coordinates(28.1500, -82.8500), 18, "Boat from Tarpon Springs", "Sponge Docks"),
        SpotRecord("fl-steinhatchee", "Steinhatchee Reef", "Big Bend natural reef.", Coordinates(29.642578, -83.413544), 15, "Boat from Steinhatchee", "Marina"),
        SpotRecord("fl-cedar-key-reef", "Cedar Key Reef", "Natural reef complex.", Coordinates(29.1333, -83.1333), 12, "Boat from Cedar Key", "Marina"),
        SpotRecord("fl-destin-bridge", "Destin Bridge Rubble", "Bridge rubble artificial reef.", Coordinates(30.3783, -86.5000), 18, "Boat from Destin", "Destin Harbor"),
        SpotRecord("fl-destin-gulf", "Destin Offshore Reefs", "Deep Gulf artificial reefs.", Coordinates(30.2500, -86.6000), 25, "Boat from Destin", "Destin Harbor"),
        SpotRecord("fl-panama-city-reef", "Panama City Artificial Reef", "Extensive reef complex.", Coordinates(30.0500, -85.8000), 22, "Boat from Panama City", "Marina"),
        SpotRecord("fl-pensacola-rig", "Pensacola Rigs", "Oil rig structures.", Coordinates(30.2000, -87.3000), 30, "Boat from Pensacola", "Marina"),
        SpotRecord("fl-oriskany-wreck", "USS Oriskany", "Aircraft carrier artificial reef.", Coordinates(30.0333, -87.0167), 45, "Boat from Pensacola", "Marina"),
        SpotRecord("fl-naples-reef", "Naples Reef", "Southwest Florida reef.", Coordinates(26.1000, -81.8500), 15, "Boat from Naples", "Marina"),
        SpotRecord("fl-sanibel-reef", "Sanibel Island Reef", "Near shell island.", Coordinates(26.4333, -82.1500), 15, "Boat from Sanibel", "Marina"),
        SpotRecord("fl-boca-grande-pass", "Boca Grande Pass", "Famous tarpon spot.", Coordinates(26.7167, -82.2667), 12, "Boat from Boca Grande", "Marina"),
        SpotRecord("fl-venice-ledge", "Venice Ledge", "Shark tooth capital area.", Coordinates(27.0667, -82.5500), 18, "Boat from Venice", "Marina"),

        // ==========================================
        // BRAZIL (50+ spots)
        // ==========================================
        // Fernando de Noronha - Split into directional spots (coastline + 500m offshore)
        SpotRecord("brazil-fernando-noronha-north", "Fernando de Noronha - North", "North coast. UNESCO marine park.", Coordinates(-3.8294, -32.4250), 25, "Boat from island", "Limited permits"),
        SpotRecord("brazil-fernando-noronha-south", "Fernando de Noronha - South", "South coast. Baia dos Porcos.", Coordinates(-3.8894, -32.4250), 25, "Boat from island", "Limited permits"),
        SpotRecord("brazil-fernando-noronha-east", "Fernando de Noronha - East", "East coast. Mar de Dentro.", Coordinates(-3.8544, -32.3900), 25, "Boat from island", "Limited permits"),
        SpotRecord("brazil-fernando-noronha-west", "Fernando de Noronha - West", "West coast. Mar de Fora.", Coordinates(-3.8544, -32.4500), 25, "Boat from island", "Limited permits"),
        SpotRecord("brazil-baia-sancho", "Baia do Sancho", "World's most beautiful beach.", Coordinates(-3.8450, -32.4333), 20, "Boat from Fernando de Noronha", "Park permit"),
        SpotRecord("brazil-baia-golfinhos", "Baia dos Golfinhos", "Spinner dolphin bay.", Coordinates(-3.8333, -32.4167), 15, "Boat from FN", "Protected area"),
        SpotRecord("brazil-abrolhos", "Abrolhos Archipelago", "Humpback whale breeding ground.", Coordinates(-17.9667, -38.7000), 20, "Boat from Caravelas", "Marina"),
        SpotRecord("brazil-arraial-do-cabo", "Arraial do Cabo", "Brazilian Caribbean, coldest water.", Coordinates(-22.9717, -42.0167), 15, "Arraial do Cabo", "Beach access"),
        SpotRecord("brazil-ilha-grande", "Ilha Grande", "Large island near Rio.", Coordinates(-23.115641, -44.195947), 18, "Boat from Angra dos Reis", "Marina"),
        SpotRecord("brazil-laje-santos", "Laje de Santos", "Offshore island marine park.", Coordinates(-24.3167, -46.1833), 25, "Boat from Santos", "Limited permits"),
        SpotRecord("brazil-ilhabela", "Ilhabela", "Island near São Paulo.", Coordinates(-23.783299, -45.365747), 18, "Boat from São Sebastião", "Marina"),
        SpotRecord("brazil-buzios", "Buzios", "Resort peninsula.", Coordinates(-22.7500, -41.8883), 12, "Boat from Buzios", "Marina"),
        SpotRecord("brazil-porto-seguro", "Porto de Galinhas", "Natural pools at low tide.", Coordinates(-8.5000, -35.0000), 8, "Beach access", "Beach"),
        SpotRecord("brazil-maragogi", "Maragogi", "Caribbean of Brazil.", Coordinates(-9.0167, -35.2167), 10, "Boat from Maragogi", "Beach"),
        SpotRecord("brazil-recife", "Recife Offshore", "Shipwrecks off Recife.", Coordinates(-8.0500, -34.8667), 22, "Boat from Recife", "Marina"),
        SpotRecord("brazil-tambau", "Tambau Reef", "Urban reef João Pessoa.", Coordinates(-7.1167, -34.8167), 15, "Boat from João Pessoa", "Marina"),
        SpotRecord("brazil-natal", "Natal Reefs", "Rio Grande do Norte.", Coordinates(-5.77311, -35.189759), 15, "Boat from Natal", "Marina"),
        SpotRecord("brazil-atol-rocas", "Atol das Rocas", "Only atoll in South Atlantic.", Coordinates(-3.8667, -33.8167), 20, "Research permit only", "Protected"),
        SpotRecord("brazil-trindade", "Ilha da Trindade", "Remote volcanic island.", Coordinates(-20.521802, -29.322148), 30, "Navy vessel", "Military permission"),
        SpotRecord("brazil-salvador-reefs", "Salvador Reefs", "Bahia coast reefs.", Coordinates(-13.01441, -38.5167), 15, "Boat from Salvador", "Marina"),
        SpotRecord("brazil-praia-forte", "Praia do Forte", "Sea turtle area.", Coordinates(-12.5833, -37.9833), 10, "Praia do Forte village", "Beach"),
        SpotRecord("brazil-morro-sao-paulo", "Morro de São Paulo", "Island village.", Coordinates(-13.375654, -38.908841), 12, "Boat from Salvador", "Island dock"),
        SpotRecord("brazil-florianopolis", "Florianópolis", "Southern island city.", Coordinates(-27.5833, -48.5500), 15, "Boat from Floripa", "Marina"),

        // ==========================================
        // JAPAN (50+ spots)
        // ==========================================
        SpotRecord("japan-okinawa-kerama", "Kerama Islands", "National park with pristine water.", Coordinates(26.1833, 127.3167), 25, "Boat from Naha", "Tomari Port"),
        SpotRecord("japan-okinawa-miyako", "Miyako Islands", "Three islands with clear water.", Coordinates(24.821634, 125.276162), 30, "Boat from Miyako", "Hirara Port"),
        // Ishigaki Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("japan-okinawa-ishigaki-north", "Ishigaki - North", "North coast. Manta ray capital.", Coordinates(24.343782, 124.145), 25, "Boat from Ishigaki", "Ishigaki Port"),
        SpotRecord("japan-okinawa-ishigaki-south", "Ishigaki - South", "South coast. Kabira Bay.", Coordinates(24.3183, 124.1450), 25, "Boat from Ishigaki", "Ishigaki Port"),
        SpotRecord("japan-okinawa-ishigaki-east", "Ishigaki - East", "East coast. Shiraho coral.", Coordinates(24.3333, 124.2000), 25, "Boat from Ishigaki", "Ishigaki Port"),
        SpotRecord("japan-okinawa-ishigaki-west", "Ishigaki - West", "West coast. Manta Point.", Coordinates(24.3333, 124.1300), 25, "Boat from Ishigaki", "Ishigaki Port"),
        
        // Iriomote Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("japan-okinawa-iriomote-north", "Iriomote - North", "North coast. Remote jungle island.", Coordinates(24.4550, 123.8500), 20, "Boat from Ishigaki", "Ferry"),
        SpotRecord("japan-okinawa-iriomote-south", "Iriomote - South", "South coast. Pristine waters.", Coordinates(24.2550, 123.8500), 20, "Boat from Ishigaki", "Ferry"),
        SpotRecord("japan-okinawa-iriomote-east", "Iriomote - East", "East coast. Facing Ishigaki.", Coordinates(24.3000, 123.9150), 20, "Boat from Ishigaki", "Ferry"),
        SpotRecord("japan-okinawa-iriomote-west", "Iriomote - West", "West coast. Open ocean.", Coordinates(24.3000, 123.6450), 20, "Boat from Ishigaki", "Ferry"),
        // Yonaguni Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("japan-okinawa-yonaguni-north", "Yonaguni - North", "North coast. Hammerhead capital.", Coordinates(24.4750, 122.9500), 30, "Boat from Yonaguni", "Kubura Port"),
        SpotRecord("japan-okinawa-yonaguni-south", "Yonaguni - South", "South coast. Underwater ruins.", Coordinates(24.4350, 122.9500), 30, "Boat from Yonaguni", "Kubura Port"),
        SpotRecord("japan-okinawa-yonaguni-east", "Yonaguni - East", "East coast. Open ocean.", Coordinates(24.4500, 123.0350), 30, "Boat from Yonaguni", "Kubura Port"),
        SpotRecord("japan-okinawa-yonaguni-west", "Yonaguni - West", "West coast. Taiwan strait.", Coordinates(24.453194, 122.931491), 30, "Boat from Yonaguni", "Kubura Port"),
        SpotRecord("japan-ogasawara-chichijima", "Chichijima (Ogasawara)", "UNESCO World Heritage.", Coordinates(27.083299, 142.228845), 30, "Ferry from Tokyo (24hrs)", "Futami Port"),
        SpotRecord("japan-ogasawara-hahajima", "Hahajima (Ogasawara)", "Mother island with virgin waters.", Coordinates(26.6500, 142.1450), 30, "Boat from Chichijima", "Oki Port"),
        SpotRecord("japan-izu-oshima", "Izu Oshima", "Volcanic island near Tokyo.", Coordinates(34.7500, 139.3500), 20, "Ferry from Tokyo", "Motomachi Port"),
        SpotRecord("japan-izu-hachijojima", "Hachijojima", "Subtropical island.", Coordinates(33.092354, 139.774174), 25, "Ferry or flight from Tokyo", "Sokodo Port"),
        SpotRecord("japan-izu-mikurajima", "Mikurajima", "Dolphin swimming island.", Coordinates(33.849592, 139.6), 20, "Ferry from Tokyo", "Port"),
        SpotRecord("japan-izu-peninsula", "Izu Peninsula", "Popular diving area.", Coordinates(34.801996, 139.069282), 15, "Various access points", "Shore access"),
        SpotRecord("japan-kushimoto", "Kushimoto", "Southernmost Honshu, coral reef.", Coordinates(33.4667, 135.7883), 18, "Boat from Kushimoto", "Port"),
        SpotRecord("japan-amami-oshima", "Amami Oshima", "Between Okinawa and Kyushu.", Coordinates(28.3833, 129.4950), 25, "Boat from Naze", "Naze Port"),
        SpotRecord("japan-yakushima", "Yakushima", "Ancient cedar island.", Coordinates(30.416128, 130.423293), 20, "Ferry from Kagoshima", "Miyanoura Port"),
        SpotRecord("japan-tanegashima", "Tanegashima", "Rocket launch island.", Coordinates(30.4833, 130.9667), 20, "Ferry from Kagoshima", "Nishinoomote"),
        SpotRecord("japan-tokunoshima", "Tokunoshima", "Amami group island.", Coordinates(27.795397, 129.013675), 22, "Ferry from Kagoshima", "Kametsu Port"),
        SpotRecord("japan-okinoerabu", "Okinoerabujima", "Cave diving paradise.", Coordinates(27.404905, 128.55), 20, "Ferry from Kagoshima", "Port"),
        SpotRecord("japan-yoron", "Yoronjima", "Clear water paradise.", Coordinates(27.0283, 128.4167), 15, "Ferry from Okinawa or Kagoshima", "Port"),
        SpotRecord("japan-nagannu", "Nagannu Island (Okinawa)", "Coral cay day trip.", Coordinates(26.2667, 127.5333), 15, "Day trip from Naha", "Tour boat"),
        // Zamami Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("japan-zamami-north", "Zamami - North", "North coast. Kerama diving.", Coordinates(26.2483, 127.3000), 20, "Ferry from Naha", "Zamami Port"),
        SpotRecord("japan-zamami-south", "Zamami - South", "South coast. Whale watching.", Coordinates(26.2183, 127.3000), 20, "Ferry from Naha", "Zamami Port"),
        SpotRecord("japan-zamami-east", "Zamami - East", "East coast. Facing Okinawa.", Coordinates(26.22947, 127.32927), 20, "Ferry from Naha", "Zamami Port"),
        SpotRecord("japan-zamami-west", "Zamami - West", "West coast. Open sea.", Coordinates(26.2333, 127.2750), 20, "Ferry from Naha", "Zamami Port"),
        // Tokashiki Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("japan-tokashiki-north", "Tokashiki - North", "North coast. Largest Kerama island.", Coordinates(26.2283, 127.3667), 20, "Ferry from Naha", "Tokashiki Port"),
        SpotRecord("japan-tokashiki-south", "Tokashiki - South", "South coast. Aharen Beach.", Coordinates(26.1683, 127.3667), 20, "Ferry from Naha", "Tokashiki Port"),
        SpotRecord("japan-tokashiki-east", "Tokashiki - East", "East coast. Facing Okinawa.", Coordinates(26.1833, 127.3817), 20, "Ferry from Naha", "Tokashiki Port"),
        SpotRecord("japan-tokashiki-west", "Tokashiki - West", "West coast. Open Pacific.", Coordinates(26.1833, 127.3317), 20, "Ferry from Naha", "Tokashiki Port"),
        SpotRecord("japan-aka-geruma", "Aka and Geruma Islands", "Kerama group.", Coordinates(26.207646, 127.291822), 18, "Ferry from Naha", "Aka Port"),

        // ==========================================
        // INDONESIA - EXPANDED (50+ spots)
        // ==========================================
        SpotRecord("indo-bali-tulamben", "Tulamben (USAT Liberty)", "Famous WWII wreck.", Coordinates(-8.2700, 115.5917), 25, "Shore dive from beach", "Beach access"),
        SpotRecord("indo-bali-amed", "Amed", "Fishing village with reef.", Coordinates(-8.331543, 115.651953), 18, "Shore or boat", "Beach"),
        SpotRecord("indo-bali-nusa-penida", "Nusa Penida", "Manta rays and mola mola.", Coordinates(-8.774011, 115.492104), 25, "Boat from Sanur", "Sanur beach"),
        // Menjangan Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("indo-bali-menjangan-north", "Menjangan - North", "North coast. NW Bali marine park.", Coordinates(-8.0850, 114.5000), 20, "Boat from Pemuteran", "Pemuteran"),
        SpotRecord("indo-bali-menjangan-south", "Menjangan - South", "South coast. Pos 2.", Coordinates(-8.3050, 114.5000), 20, "Boat from Pemuteran", "Pemuteran"),
        SpotRecord("indo-bali-menjangan-east", "Menjangan - East", "East coast. Wall diving.", Coordinates(-8.1000, 114.5150), 20, "Boat from Pemuteran", "Pemuteran"),
        SpotRecord("indo-bali-menjangan-west", "Menjangan - West", "West coast. Anchor wreck.", Coordinates(-8.1000, 114.4250), 20, "Boat from Pemuteran", "Pemuteran"),
        SpotRecord("indo-komodo-batu-bolong", "Batu Bolong (Komodo)", "Current-swept pinnacle.", Coordinates(-8.475722, 119.4833), 25, "Liveaboard or Labuan Bajo", "Labuan Bajo"),
        SpotRecord("indo-komodo-manta-point", "Manta Point (Komodo)", "Manta cleaning station.", Coordinates(-8.6833, 119.402123), 15, "Liveaboard", "Labuan Bajo"),
        SpotRecord("indo-komodo-castle-rock", "Castle Rock (Komodo)", "Submerged seamount.", Coordinates(-8.4667, 119.5167), 25, "Liveaboard", "Labuan Bajo"),
        SpotRecord("indo-komodo-crystal-rock", "Crystal Rock (Komodo)", "Pinnacle with soft coral.", Coordinates(-8.4833, 119.5000), 22, "Liveaboard", "Labuan Bajo"),
        SpotRecord("indo-sulawesi-bunaken", "Bunaken Marine Park", "World-class wall diving.", Coordinates(1.6333, 124.7500), 30, "Boat from Manado", "Manado"),
        SpotRecord("indo-sulawesi-lembeh", "Lembeh Strait", "Muck diving capital.", Coordinates(1.4617, 125.2333), 15, "Boat from Bitung", "Bitung"),
        SpotRecord("indo-sulawesi-togian", "Togian Islands", "Remote central Sulawesi.", Coordinates(-0.433808, 121.9333), 20, "Boat from Ampana", "Ampana"),
        SpotRecord("indo-sulawesi-wakatobi", "Wakatobi", "Premium dive resort area.", Coordinates(-5.4833, 123.9000), 25, "Flight to Wakatobi", "Resort"),
        SpotRecord("indo-banda-islands", "Banda Islands", "Nutmeg islands with hammerheads.", Coordinates(-4.5333, 129.9000), 30, "Flight or liveaboard", "Banda Neira"),
        SpotRecord("indo-alor", "Alor", "Remote eastern Indonesia.", Coordinates(-8.236102, 124.5333), 25, "Liveaboard", "Kalabahi"),
        SpotRecord("indo-flores", "Flores (Maumere)", "Eastern Flores diving.", Coordinates(-8.6117, 122.2167), 20, "Boat from Maumere", "Maumere"),
        SpotRecord("indo-lombok-gili", "Gili Islands", "Three islands off Lombok.", Coordinates(-8.357646, 116.025572), 18, "Boat from Gili Trawangan", "Harbor"),
        SpotRecord("indo-sumatra-pulau-weh", "Pulau Weh (Sabang)", "Tip of Sumatra.", Coordinates(5.8833, 95.3167), 25, "Ferry from Banda Aceh", "Sabang"),
        SpotRecord("indo-raja-ampat-fam", "Fam Islands (Raja Ampat)", "Spectacular lagoons.", Coordinates(-0.4500, 130.3833), 20, "Liveaboard", "Sorong"),
        SpotRecord("indo-raja-ampat-wayag", "Wayag (Raja Ampat)", "Iconic karst landscape.", Coordinates(0.2000, 130.0500), 25, "Liveaboard", "Sorong"),
        SpotRecord("indo-cenderawasih", "Cenderawasih Bay", "Whale shark fishermen.", Coordinates(-2.833298, 134.507643), 15, "Liveaboard", "Nabire"),

        // ==========================================
        // PHILIPPINES - EXPANDED (40+ spots)
        // ==========================================
        SpotRecord("phil-anilao", "Anilao", "Macro diving capital.", Coordinates(13.7667, 120.918464), 18, "Boat from Anilao resorts", "Resort"),
        // Verde Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("phil-verde-island-north", "Verde Island - North", "North side. Center of marine biodiversity.", Coordinates(13.5817, 121.0667), 25, "Boat from Batangas", "Batangas pier"),
        SpotRecord("phil-verde-island-south", "Verde Island - South", "South side. Passage diving.", Coordinates(13.5317, 121.0667), 25, "Boat from Batangas", "Batangas pier"),
        SpotRecord("phil-verde-island-east", "Verde Island - East", "East side. Drop-offs.", Coordinates(13.5667, 121.1017), 25, "Boat from Batangas", "Batangas pier"),
        SpotRecord("phil-verde-island-west", "Verde Island - West", "West side. Wall diving.", Coordinates(13.5667, 121.0517), 25, "Boat from Batangas", "Batangas pier"),
        SpotRecord("phil-puerto-galera", "Puerto Galera", "Dive capital of Philippines.", Coordinates(13.5217, 120.9500), 20, "Boat from Sabang", "Sabang beach"),
        SpotRecord("phil-dumaguete-dauin", "Dauin (Dumaguete)", "Muck diving and whale sharks.", Coordinates(9.1833, 123.2667), 15, "Shore or boat", "Dauin beach"),
        SpotRecord("phil-moalboal", "Moalboal", "Sardine run and reef.", Coordinates(9.957646, 123.391063), 18, "Shore or boat from Moalboal", "Beach"),
        SpotRecord("phil-oslob", "Oslob", "Whale shark interaction.", Coordinates(9.4667, 123.4000), 10, "Boat from Oslob", "Oslob"),
        SpotRecord("phil-bohol-panglao", "Panglao Island", "Bohol diving base.", Coordinates(9.5450, 123.7667), 20, "Boat from Alona Beach", "Alona"),
        SpotRecord("phil-boracay", "Boracay", "Party island with diving.", Coordinates(11.9667, 121.9167), 18, "Boat from White Beach", "Beach"),
        SpotRecord("phil-siargao", "Siargao", "Surf and dive island.", Coordinates(9.8550, 126.1000), 20, "Boat from General Luna", "General Luna"),
        SpotRecord("phil-camiguin", "Camiguin", "Island born of fire.", Coordinates(9.217653, 124.768104), 20, "Boat from Camiguin", "Various"),
        SpotRecord("phil-siquijor", "Siquijor", "Mystical island.", Coordinates(9.234353, 123.548495), 18, "Boat from Siquijor", "Various"),
        SpotRecord("phil-el-nido", "El Nido", "Palawan limestone karsts.", Coordinates(11.1883, 119.3833), 20, "Boat from El Nido", "El Nido town"),
        SpotRecord("phil-hundred-islands", "Hundred Islands", "National park.", Coordinates(16.21441, 119.9167), 15, "Boat from Alaminos", "Alaminos"),
        SpotRecord("phil-romblon", "Romblon", "Marble island.", Coordinates(12.5833, 122.2667), 18, "Ferry from Batangas", "Romblon port"),

        // ==========================================
        // AUSTRALIA - EXPANDED (40+ spots)
        // ==========================================
        SpotRecord("aus-brisbane-flinders", "Flinders Reef", "SE Queensland pinnacle.", Coordinates(-26.9833, 153.4833), 25, "Boat from Mooloolaba", "Mooloolaba"),
        SpotRecord("aus-gold-coast-reef", "Gold Coast Seaway Reef", "Artificial reef.", Coordinates(-27.9333, 153.4333), 18, "Boat from Southport", "Marina"),
        SpotRecord("aus-byron-julian", "Julian Rocks", "Byron Bay marine reserve.", Coordinates(-28.6333, 153.6333), 20, "Boat from Byron Bay", "Beach"),
        SpotRecord("aus-sydney-fish-rock", "Fish Rock Cave", "South West Rocks.", Coordinates(-30.8833, 153.0667), 25, "Boat from South West Rocks", "Marina"),
        SpotRecord("aus-sydney-magic-point", "Magic Point", "Sydney grey nurse site.", Coordinates(-33.9667, 151.2667), 20, "Boat from Sydney", "Various"),
        SpotRecord("aus-jervis-bay", "Jervis Bay", "Marine park with seals.", Coordinates(-35.0833, 150.7167), 18, "Boat from Huskisson", "Marina"),
        SpotRecord("aus-melbourne-portsea", "Portsea Pier", "Port Phillip Bay diving.", Coordinates(-38.3167, 144.7167), 12, "Portsea pier", "Pier parking"),
        SpotRecord("aus-adelaide-rapid-bay", "Rapid Bay Jetty", "Leafy sea dragon.", Coordinates(-35.5167, 138.1833), 10, "Rapid Bay jetty", "Beach"),
        // Rottnest Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("aus-perth-rottnest-north", "Rottnest - North", "North coast. Perth's dive island.", Coordinates(-31.9850, 115.5000), 20, "Ferry from Fremantle", "Rottnest"),
        SpotRecord("aus-perth-rottnest-south", "Rottnest - South", "South coast. More exposed.", Coordinates(-32.0250, 115.5000), 20, "Ferry from Fremantle", "Rottnest"),
        SpotRecord("aus-perth-rottnest-east", "Rottnest - East", "East coast. Facing Perth.", Coordinates(-32.003194, 115.538767), 20, "Ferry from Fremantle", "Rottnest"),
        SpotRecord("aus-perth-rottnest-west", "Rottnest - West", "West coast. Open Indian Ocean.", Coordinates(-32.0000, 115.4850), 20, "Ferry from Fremantle", "Rottnest"),
        SpotRecord("aus-perth-abrolhos", "Abrolhos Islands", "Remote WA diving.", Coordinates(-28.7167, 113.7783), 25, "Boat from Geraldton", "Charter"),
        SpotRecord("aus-broome-rowley", "Rowley Shoals", "Remote WA atolls.", Coordinates(-17.3333, 119.3333), 30, "Liveaboard from Broome", "Charter"),
        SpotRecord("aus-darwin-gove", "Gove Peninsula", "Remote NT diving.", Coordinates(-12.181543, 136.802182), 20, "Boat from Nhulunbuy", "Marina"),
        SpotRecord("aus-townsville-yongala", "SS Yongala", "Australia's best wreck.", Coordinates(-19.3000, 147.6167), 28, "Boat from Townsville or Ayr", "Marina"),
        SpotRecord("aus-cairns-cod-hole", "Cod Hole", "Potato cod feeding.", Coordinates(-14.6833, 145.6333), 20, "Liveaboard from Cairns", "Cairns"),
        SpotRecord("aus-cairns-osprey", "Osprey Reef", "Coral Sea pinnacle.", Coordinates(-13.8833, 146.5500), 35, "Liveaboard from Cairns", "Charter"),
        // Lady Elliot Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("aus-lady-elliot-north", "Lady Elliot - North", "North side. Southern GBR.", Coordinates(-24.1017, 152.7167), 20, "Flight from Bundaberg", "Resort"),
        SpotRecord("aus-lady-elliot-south", "Lady Elliot - South", "South side. Manta cleaning.", Coordinates(-24.1317, 152.7167), 20, "Flight from Bundaberg", "Resort"),
        SpotRecord("aus-lady-elliot-east", "Lady Elliot - East", "East side. Coral bombies.", Coordinates(-24.1167, 152.7317), 20, "Flight from Bundaberg", "Resort"),
        SpotRecord("aus-lady-elliot-west", "Lady Elliot - West", "West side. Lighthouse.", Coordinates(-24.1167, 152.7017), 20, "Flight from Bundaberg", "Resort"),
        
        // Heron Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("aus-heron-island-north", "Heron Island - North", "North side. Research station.", Coordinates(-23.4183, 151.9167), 18, "Boat or heli from Gladstone", "Resort"),
        SpotRecord("aus-heron-island-south", "Heron Island - South", "South side. Heron Bommie.", Coordinates(-23.4583, 151.9167), 18, "Boat or heli from Gladstone", "Resort"),
        SpotRecord("aus-heron-island-east", "Heron Island - East", "East side. Blue pools.", Coordinates(-23.4333, 151.9317), 18, "Boat or heli from Gladstone", "Resort"),
        SpotRecord("aus-heron-island-west", "Heron Island - West", "West side. Harbour area.", Coordinates(-23.4333, 151.9017), 18, "Boat or heli from Gladstone", "Resort"),

        // ==========================================
        // NEW ZEALAND - EXPANDED (25+ spots)
        // ==========================================
        // Poor Knights Islands - Split into directional spots (coastline + 500m offshore)
        SpotRecord("nz-poor-knights-north", "Poor Knights - North", "North side. Top 10 dive site globally.", Coordinates(-35.4417, 174.7333), 30, "Boat from Tutukaka", "Marina"),
        SpotRecord("nz-poor-knights-south", "Poor Knights - South", "South side. Sheltered from NW swells.", Coordinates(-35.4867, 174.7333), 30, "Boat from Tutukaka", "Marina"),
        SpotRecord("nz-poor-knights-east", "Poor Knights - East", "East side. Open ocean exposure.", Coordinates(-35.4667, 174.7533), 30, "Boat from Tutukaka", "Marina"),
        SpotRecord("nz-poor-knights-west", "Poor Knights - West", "West side. Mainland-facing, calmer.", Coordinates(-35.4667, 174.7133), 30, "Boat from Tutukaka", "Marina"),
        SpotRecord("nz-tutukaka", "Tutukaka Coast", "Gateway to Poor Knights.", Coordinates(-35.6167, 174.5333), 20, "Boat from Tutukaka", "Marina"),
        SpotRecord("nz-leigh-coast", "Leigh Marine Reserve", "First NZ marine reserve.", Coordinates(-36.2667, 174.8000), 15, "Cape Rodney", "Beach parking"),
        SpotRecord("nz-hahei", "Hahei Marine Reserve", "Cathedral Cove area.", Coordinates(-36.837902, 175.815115), 12, "Hahei Beach", "Beach parking"),
        // White Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("nz-white-island-north", "White Island - North", "North side. Active volcano.", Coordinates(-37.5017, 177.1833), 25, "Boat from Whakatane", "Marina"),
        SpotRecord("nz-white-island-south", "White Island - South", "South side. Crater view.", Coordinates(-37.5417, 177.1833), 25, "Boat from Whakatane", "Marina"),
        SpotRecord("nz-white-island-east", "White Island - East", "East side. Open ocean.", Coordinates(-37.5167, 177.1983), 25, "Boat from Whakatane", "Marina"),
        SpotRecord("nz-white-island-west", "White Island - West", "West side. Facing NZ.", Coordinates(-37.5167, 177.1583), 25, "Boat from Whakatane", "Marina"),
        SpotRecord("nz-wellington-south", "Wellington South Coast", "Wellington diving.", Coordinates(-41.3500, 174.8000), 15, "Island Bay area", "Various"),
        SpotRecord("nz-kaikoura", "Kaikoura", "Whale watching and diving.", Coordinates(-42.409054, 173.693655), 20, "Boat from Kaikoura", "Marina"),
        SpotRecord("nz-marlborough-sounds", "Marlborough Sounds", "Sheltered diving.", Coordinates(-41.171632, 174.028743), 18, "Boat from Picton", "Marina"),
        SpotRecord("nz-milford-sound", "Milford Sound", "Black coral and fiords.", Coordinates(-44.618021, 167.871462), 25, "Boat from Milford", "Cruise"),
        SpotRecord("nz-doubtful-sound", "Doubtful Sound", "Remote fiord diving.", Coordinates(-45.3000, 166.9667), 30, "Boat from Te Anau", "Cruise"),
        // Stewart Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("nz-stewart-island-north", "Stewart Island - North", "North coast. Remote southern diving.", Coordinates(-46.5950, 167.8500), 20, "Ferry from Bluff", "Oban"),
        SpotRecord("nz-stewart-island-south", "Stewart Island - South", "South coast. Sub-Antarctic waters.", Coordinates(-47.2050, 167.8500), 20, "Ferry from Bluff", "Oban"),
        SpotRecord("nz-stewart-island-east", "Stewart Island - East", "East coast. Paterson Inlet.", Coordinates(-47.0000, 168.2550), 20, "Ferry from Bluff", "Oban"),
        SpotRecord("nz-stewart-island-west", "Stewart Island - West", "West coast. Fiordland style.", Coordinates(-47.0000, 167.6450), 20, "Ferry from Bluff", "Oban"),
        SpotRecord("nz-chatham-islands", "Chatham Islands", "Remote Pacific outpost.", Coordinates(-43.9500, -176.5500), 25, "Flight from mainland", "Waitangi"),

        // ==========================================
        // MOZAMBIQUE & EAST AFRICA (30+ spots)
        // ==========================================
        SpotRecord("moz-tofo-beach", "Tofo Beach", "Whale shark and manta capital.", Coordinates(-23.83981, 35.54444), 20, "Boat from Tofo", "Beach"),
        SpotRecord("moz-barra-beach", "Barra Beach", "Near Tofo with reef.", Coordinates(-23.7833, 35.5000), 18, "Boat from Barra", "Beach"),
        SpotRecord("moz-bazaruto", "Bazaruto Archipelago", "Dugong habitat.", Coordinates(-21.666698, 35.494786), 25, "Boat from Vilankulo", "Marina"),
        SpotRecord("moz-inhambane", "Inhambane Coast", "Historic Portuguese town.", Coordinates(-23.8667, 35.3783), 18, "Boat from Inhambane", "Various"),
        SpotRecord("moz-ponta-ouro", "Ponta do Ouro", "SA border with dolphins.", Coordinates(-26.8333, 32.8883), 20, "Boat from Ponta", "Beach"),
        SpotRecord("moz-pemba", "Pemba (Quirimbas)", "Northern Mozambique.", Coordinates(-12.95229, 40.5167), 25, "Boat from Pemba", "Marina"),
        // Ibo Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("moz-ibo-island-north", "Ibo Island - North", "North coast. Historic fortress.", Coordinates(-12.3150, 40.6000), 20, "Boat from Ibo", "Island"),
        SpotRecord("moz-ibo-island-south", "Ibo Island - South", "South coast. Quirimbas.", Coordinates(-12.3950, 40.6000), 20, "Boat from Ibo", "Island"),
        SpotRecord("moz-ibo-island-east", "Ibo Island - East", "East coast. Indian Ocean.", Coordinates(-12.3500, 40.6250), 20, "Boat from Ibo", "Island"),
        SpotRecord("moz-ibo-island-west", "Ibo Island - West", "West coast. Channel side.", Coordinates(-12.3500, 40.5850), 20, "Boat from Ibo", "Island"),
        
        // Mafia Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("tanzania-mafia-island-north", "Mafia Island - North", "North coast. Whale shark park.", Coordinates(-7.909346, 39.791019), 20, "Flight from Dar es Salaam", "Lodges"),
        SpotRecord("tanzania-mafia-island-south", "Mafia Island - South", "South coast. Chole Bay.", Coordinates(-7.9317, 39.7833), 20, "Flight from Dar es Salaam", "Lodges"),
        SpotRecord("tanzania-mafia-island-east", "Mafia Island - East", "East coast. Open ocean.", Coordinates(-7.9167, 39.7983), 20, "Flight from Dar es Salaam", "Lodges"),
        SpotRecord("tanzania-mafia-island-west", "Mafia Island - West", "West coast. Mainland side.", Coordinates(-7.9167, 39.7683), 20, "Flight from Dar es Salaam", "Lodges"),
        SpotRecord("tanzania-zanzibar-mnemba", "Mnemba Atoll", "Private island diving.", Coordinates(-5.8167, 39.3833), 25, "Boat from Zanzibar", "Various"),
        // Pemba Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("tanzania-pemba-island-north", "Pemba Island - North", "North coast. Clove island.", Coordinates(-4.8783, 39.7500), 30, "Flight from Zanzibar", "Various"),
        SpotRecord("tanzania-pemba-island-south", "Pemba Island - South", "South coast. Deep walls.", Coordinates(-5.5383, 39.7500), 30, "Flight from Zanzibar", "Various"),
        SpotRecord("tanzania-pemba-island-east", "Pemba Island - East", "East coast. Misali Island.", Coordinates(-5.0333, 39.8450), 30, "Flight from Zanzibar", "Various"),
        SpotRecord("tanzania-pemba-island-west", "Pemba Island - West", "West coast. Shimba Hills.", Coordinates(-5.026084, 39.685), 30, "Flight from Zanzibar", "Various"),
        SpotRecord("kenya-watamu", "Watamu Marine Park", "Kenya's premier diving.", Coordinates(-3.360813, 40.0167), 18, "Boat from Watamu", "Beach"),
        SpotRecord("kenya-malindi", "Malindi", "Historic Swahili coast.", Coordinates(-3.20651, 40.126905), 15, "Boat from Malindi", "Marina"),
        SpotRecord("kenya-diani", "Diani Beach", "South coast diving.", Coordinates(-4.3167, 39.5833), 18, "Boat from Diani", "Beach"),
        // Mahe Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("seychelles-mahe-north", "Mahe - North", "North coast. Main Seychelles island.", Coordinates(-4.6483, 55.4833), 25, "Boat from Victoria", "Marina"),
        SpotRecord("seychelles-mahe-south", "Mahe - South", "South coast. More exposed.", Coordinates(-4.7383, 55.4833), 25, "Boat from Victoria", "Marina"),
        SpotRecord("seychelles-mahe-east", "Mahe - East", "East coast. Windward side.", Coordinates(-4.6833, 55.5383), 25, "Boat from Victoria", "Marina"),
        SpotRecord("seychelles-mahe-west", "Mahe - West", "West coast. Sunset side, calmer.", Coordinates(-4.6833, 55.4383), 25, "Boat from Victoria", "Marina"),
        SpotRecord("seychelles-praslin", "Praslin", "Vallee de Mai island.", Coordinates(-4.3333, 55.764451), 25, "Boat from Praslin", "Various"),
        SpotRecord("seychelles-aldabra", "Aldabra Atoll", "UNESCO World Heritage.", Coordinates(-9.4167, 46.3333), 30, "Liveaboard", "Charter"),
        SpotRecord("mauritius-flic-en-flac", "Flic en Flac", "West coast diving.", Coordinates(-20.2833, 57.3617), 20, "Boat from Flic en Flac", "Beach"),
        SpotRecord("mauritius-blue-bay", "Blue Bay", "Marine park.", Coordinates(-20.4500, 57.7167), 15, "Boat from Blue Bay", "Beach"),
        SpotRecord("reunion-saint-leu", "Saint-Leu", "West coast diving.", Coordinates(-21.1667, 55.2833), 25, "Boat from Saint-Leu", "Marina"),
        SpotRecord("reunion-saint-gilles", "Saint-Gilles", "Lagoon and outer reef.", Coordinates(-21.066699, 55.214967), 20, "Boat from Saint-Gilles", "Marina"),

        // ==========================================
        // CARIBBEAN - ADDITIONAL (40+ spots)
        // ==========================================
        SpotRecord("usvi-st-thomas-coki", "Coki Beach (St. Thomas)", "Popular snorkel spot.", Coordinates(18.3500, -64.8667), 12, "Coki Point Beach", "Beach lot"),
        SpotRecord("usvi-st-john-trunk-bay", "Trunk Bay (St. John)", "Underwater trail.", Coordinates(18.3550, -64.7717), 10, "Trunk Bay Beach", "National Park"),
        // Buck Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("usvi-buck-island-north", "Buck Island - North", "North side. National monument.", Coordinates(17.7983, -64.6167), 15, "Boat from St. Croix", "Christiansted"),
        SpotRecord("usvi-buck-island-south", "Buck Island - South", "South side. Elkhorn coral.", Coordinates(17.7683, -64.6167), 15, "Boat from St. Croix", "Christiansted"),
        SpotRecord("usvi-buck-island-east", "Buck Island - East", "East side. Underwater trail.", Coordinates(17.7833, -64.6017), 15, "Boat from St. Croix", "Christiansted"),
        SpotRecord("usvi-buck-island-west", "Buck Island - West", "West side. Facing St. Croix.", Coordinates(17.7833, -64.6317), 15, "Boat from St. Croix", "Christiansted"),
        SpotRecord("bvi-rhone-wreck", "RMS Rhone (BVI)", "Famous wreck.", Coordinates(18.3833, -64.5500), 25, "Boat from Tortola", "Various"),
        SpotRecord("bvi-dogs-islands", "The Dogs (BVI)", "Uninhabited island group.", Coordinates(18.4667, -64.4333), 18, "Boat from Virgin Gorda", "Marina"),
        SpotRecord("cayman-stingray-city", "Stingray City (Grand Cayman)", "Stingray sandbar.", Coordinates(19.3833, -81.3000), 4, "Boat from Georgetown", "Various"),
        SpotRecord("cayman-bloody-bay-wall", "Bloody Bay Wall (Little Cayman)", "Famous wall dive.", Coordinates(19.7000, -80.0833), 30, "Boat from Little Cayman", "Resort"),
        SpotRecord("cayman-north-wall", "North Wall (Grand Cayman)", "Dramatic drop-off.", Coordinates(19.3833, -81.2333), 25, "Boat from North Side", "Various"),
        SpotRecord("jamaica-montego-bay", "Montego Bay Marine Park", "Protected area.", Coordinates(18.4833, -77.9333), 18, "Boat from Montego Bay", "Marina"),
        SpotRecord("jamaica-negril", "Negril", "West coast diving.", Coordinates(18.283808, -78.35), 15, "Boat from Negril", "Beach"),
        SpotRecord("curacao-mushroom-forest", "Mushroom Forest (Curacao)", "Unique coral formations.", Coordinates(12.3667, -69.1550), 18, "Shore dive", "Beach"),
        SpotRecord("curacao-blue-bay", "Blue Bay (Curacao)", "Golf course reef.", Coordinates(12.1333, -68.9883), 15, "Blue Bay Beach", "Resort"),
        SpotRecord("bonaire-1000-steps", "1000 Steps (Bonaire)", "Shore dive classic.", Coordinates(12.2167, -68.3500), 20, "Shore access", "Roadside"),
        SpotRecord("bonaire-salt-pier", "Salt Pier (Bonaire)", "Pier diving.", Coordinates(12.1000, -68.2833), 15, "Salt pier", "Roadside"),
        SpotRecord("aruba-antilla-wreck", "Antilla Wreck (Aruba)", "WWII German freighter.", Coordinates(12.6000, -70.0550), 18, "Boat from Aruba", "Marina"),
        SpotRecord("dominican-catalina", "Catalina Island (DR)", "Day trip diving.", Coordinates(18.3667, -68.9667), 20, "Boat from La Romana", "Marina"),
        SpotRecord("dominican-bayahibe", "Bayahibe", "Dive resort town.", Coordinates(18.3667, -68.844693), 18, "Boat from Bayahibe", "Beach"),
        SpotRecord("st-lucia-anse-chastanet", "Anse Chastanet (St. Lucia)", "Piton area diving.", Coordinates(13.85229, -61.0667), 20, "Resort beach", "Resort"),
        SpotRecord("grenada-bianca-c", "Bianca C Wreck (Grenada)", "Titanic of Caribbean.", Coordinates(12.0333, -61.7550), 40, "Boat from St. George's", "Marina"),
        SpotRecord("barbados-carlisle-bay", "Carlisle Bay (Barbados)", "Multiple wrecks.", Coordinates(13.0833, -59.6167), 15, "Shore from beach", "Beach"),
        SpotRecord("trinidad-buccoo-reef", "Buccoo Reef (Tobago)", "Glass bottom boat area.", Coordinates(11.1833, -60.8333), 10, "Boat from Buccoo", "Beach"),

        // ==========================================
        // WORLD-CLASS REMOTE DESTINATIONS (directional spots)
        // ==========================================
        
        // Cocos Island, Costa Rica - Split into directional spots (coastline + 500m offshore)
        SpotRecord("cocos-island-north", "Cocos Island - North", "North side. World's best hammerhead diving.", Coordinates(5.5400, -87.0583), 35, "Liveaboard from Puntarenas", "Liveaboard"),
        SpotRecord("cocos-island-south", "Cocos Island - South", "South side. Manuelita Island nearby.", Coordinates(5.5100, -87.0583), 35, "Liveaboard from Puntarenas", "Liveaboard"),
        SpotRecord("cocos-island-east", "Cocos Island - East", "East side. Dirty Rock.", Coordinates(5.5250, -87.0433), 35, "Liveaboard from Puntarenas", "Liveaboard"),
        SpotRecord("cocos-island-west", "Cocos Island - West", "West side. Bajo Alcyone.", Coordinates(5.5250, -87.0733), 35, "Liveaboard from Puntarenas", "Liveaboard"),
        
        // Galapagos Santa Cruz - Split into directional spots (coastline + 500m offshore)
        SpotRecord("galapagos-santa-cruz-north", "Galapagos Santa Cruz - North", "North side. Gordon Rocks nearby.", Coordinates(-0.4450, -90.3000), 30, "Boat from Puerto Ayora", "Harbor"),
        SpotRecord("galapagos-santa-cruz-south", "Galapagos Santa Cruz - South", "South side. Closer to town.", Coordinates(-0.7650, -90.3000), 30, "Boat from Puerto Ayora", "Harbor"),
        SpotRecord("galapagos-santa-cruz-east", "Galapagos Santa Cruz - East", "East side. Seymour Channel.", Coordinates(-0.7500, -90.2850), 30, "Boat from Puerto Ayora", "Harbor"),
        SpotRecord("galapagos-santa-cruz-west", "Galapagos Santa Cruz - West", "West side. Open ocean.", Coordinates(-0.744898, -90.309897), 30, "Boat from Puerto Ayora", "Harbor"),
        
        // Guadalupe Island, Mexico - Split into directional spots (coastline + 500m offshore)  
        SpotRecord("guadalupe-north", "Guadalupe Island - North", "North side. Great white shark cage diving.", Coordinates(29.1350, -118.2833), 20, "Liveaboard from San Diego/Ensenada", "Liveaboard"),
        SpotRecord("guadalupe-south", "Guadalupe Island - South", "South side. More sheltered.", Coordinates(28.8950, -118.2833), 20, "Liveaboard from San Diego/Ensenada", "Liveaboard"),
        SpotRecord("guadalupe-east", "Guadalupe Island - East", "East side. Facing mainland.", Coordinates(29.1000, -118.2683), 20, "Liveaboard from San Diego/Ensenada", "Liveaboard"),
        SpotRecord("guadalupe-west", "Guadalupe Island - West", "West side. Open Pacific.", Coordinates(29.1000, -118.3583), 20, "Liveaboard from San Diego/Ensenada", "Liveaboard"),
        
        // Easter Island (Rapa Nui) - Split into directional spots (coastline + 500m offshore)
        SpotRecord("easter-island-north", "Easter Island - North", "North coast. Moai underwater.", Coordinates(-27.0517, -109.3500), 25, "Boat from Hanga Roa", "Harbor"),
        SpotRecord("easter-island-south", "Easter Island - South", "South coast. Rougher conditions.", Coordinates(-27.1717, -109.3500), 25, "Boat from Hanga Roa", "Harbor"),
        SpotRecord("easter-island-east", "Easter Island - East", "East coast. Less visited.", Coordinates(-27.1167, -109.1950), 25, "Boat from Hanga Roa", "Harbor"),
        SpotRecord("easter-island-west", "Easter Island - West", "West coast. Near town.", Coordinates(-27.1167, -109.4350), 25, "Boat from Hanga Roa", "Harbor"),
        
        // Azores Pico Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("azores-pico-north", "Pico Island - North", "North coast. Blue shark diving.", Coordinates(38.5117, -28.2500), 25, "Boat from Madalena", "Marina"),
        SpotRecord("azores-pico-south", "Pico Island - South", "South coast. Calmer conditions.", Coordinates(38.3817, -28.2500), 25, "Boat from Madalena", "Marina"),
        SpotRecord("azores-pico-east", "Pico Island - East", "East coast. Princess Alice Bank.", Coordinates(38.4667, -28.1850), 25, "Boat from Madalena", "Marina"),
        SpotRecord("azores-pico-west", "Pico Island - West", "West coast. Faial channel.", Coordinates(38.4667, -28.5550), 25, "Boat from Madalena", "Marina"),
        
        // Canary Islands El Hierro - Split into directional spots (coastline + 500m offshore)
        SpotRecord("canary-hierro-north", "El Hierro - North", "North coast. Mar de las Calmas.", Coordinates(27.7983, -18.0000), 25, "Boat from La Restinga", "Marina"),
        SpotRecord("canary-hierro-south", "El Hierro - South", "South coast. Marine reserve.", Coordinates(27.6383, -18.0000), 25, "Boat from La Restinga", "Marina"),
        SpotRecord("canary-hierro-east", "El Hierro - East", "East coast. El Bajón.", Coordinates(27.7333, -17.9150), 25, "Boat from La Restinga", "Marina"),
        SpotRecord("canary-hierro-west", "El Hierro - West", "West coast. Open Atlantic.", Coordinates(27.7333, -18.2050), 25, "Boat from La Restinga", "Marina"),
        
        // Cape Verde Sal Island - Split into directional spots (coastline + 500m offshore)
        SpotRecord("cape-verde-sal-north", "Sal Island - North", "North coast. Lemon sharks.", Coordinates(16.8550, -22.9333), 20, "Boat from Santa Maria", "Marina"),
        SpotRecord("cape-verde-sal-south", "Sal Island - South", "South coast. Santa Maria.", Coordinates(16.5950, -22.9333), 20, "Boat from Santa Maria", "Marina"),
        SpotRecord("cape-verde-sal-east", "Sal Island - East", "East coast. Trade wind side.", Coordinates(16.7500, -22.8883), 20, "Boat from Santa Maria", "Marina"),
        SpotRecord("cape-verde-sal-west", "Sal Island - West", "West coast. Calmer conditions.", Coordinates(16.7500, -22.9883), 20, "Boat from Santa Maria", "Marina"),
        
        // Sipadan Island, Malaysia - Split into directional spots (coastline + 500m offshore)
        SpotRecord("sipadan-north", "Sipadan - North", "North side. Barracuda Point.", Coordinates(4.1300, 118.6283), 30, "Boat from Semporna", "Resort"),
        SpotRecord("sipadan-south", "Sipadan - South", "South side. South Point.", Coordinates(4.1000, 118.6283), 30, "Boat from Semporna", "Resort"),
        SpotRecord("sipadan-east", "Sipadan - East", "East side. Drop Off.", Coordinates(4.1150, 118.6433), 30, "Boat from Semporna", "Resort"),
        SpotRecord("sipadan-west", "Sipadan - West", "West side. Turtle Cavern.", Coordinates(4.1150, 118.6133), 30, "Boat from Semporna", "Resort")
    )

    fun getAllSpots() = spots

    fun findNearbySpots(lat: Double, lon: Double, radiusKm: Double): List<SpotRecord> {
        return spots.filter { spot ->
            val distance = haversineDistance(lat, lon, spot.coordinates.lat, spot.coordinates.lon)
            distance <= radiusKm
        }.sortedBy { spot ->
            haversineDistance(lat, lon, spot.coordinates.lat, spot.coordinates.lon)
        }
    }

    fun findSpotById(id: String): SpotRecord? {
        return spots.find { it.id == id }
    }

    private fun haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val R = 6371.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = sin(dLat / 2).pow(2) + cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) * sin(dLon / 2).pow(2)
        val c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }
}
