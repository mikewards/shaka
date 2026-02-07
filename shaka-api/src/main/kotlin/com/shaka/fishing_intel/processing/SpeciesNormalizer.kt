package com.shaka.fishing_intel.processing

/**
 * Normalizes species names to canonical forms.
 * Handles common variants, misspellings, and bad punctuation (e.g. "Halibut." → "halibut").
 */
object SpeciesNormalizer {
    /** Strip leading/trailing punctuation so "Halibut." and "Halibut" collapse to same canonical form. */
    private val PUNCT_TRIMMER = Regex("^[\\s.,;:]+|[\\s.,;:]+$")

    private val SPECIES_MAP = mapOf(
        // Rockfish variants
        "rockfish" to "rockfish",
        "rock fish" to "rockfish",
        "reds" to "rockfish",
        "red rockfish" to "red_rockfish",
        "copper rockfish" to "copper_rockfish",
        "vermilion rockfish" to "vermilion_rockfish",
        "bocaccio" to "bocaccio",
        
        // Bass variants
        "calico bass" to "calico_bass",
        "calico" to "calico_bass",
        "kelp bass" to "calico_bass",
        "sand bass" to "sand_bass",
        "spotted bay bass" to "spotted_bay_bass",
        "barred sand bass" to "sand_bass",
        
        // Tuna variants
        "bluefin tuna" to "bluefin_tuna",
        "bluefin" to "bluefin_tuna",
        "yellowfin tuna" to "yellowfin_tuna",
        "yellowfin" to "yellowfin_tuna",
        "albacore" to "albacore",
        "albacore tuna" to "albacore",
        "skipjack" to "skipjack",
        
        // Other pelagics
        "yellowtail" to "yellowtail",
        "yellowtail amberjack" to "yellowtail",
        "dorado" to "dorado",
        "mahi mahi" to "dorado",
        "mahi" to "dorado",
        "wahoo" to "wahoo",
        "bonito" to "bonito",
        "barracuda" to "barracuda",
        
        // Bottom fish
        "halibut" to "halibut",
        "california halibut" to "halibut",
        "lingcod" to "lingcod",
        "ling cod" to "lingcod",
        "ling" to "lingcod",
        "sheephead" to "sheephead",
        "california sheephead" to "sheephead",
        "sculpin" to "sculpin",
        "scorpionfish" to "sculpin",
        "cabezon" to "cabezon",
        "whitefish" to "whitefish",
        "white fish" to "whitefish",
        "white seabass" to "white_seabass",
        "seabass" to "white_seabass",
        "sea bass" to "white_seabass",
        
        // Other
        "lobster" to "lobster",
        "squid" to "squid",
        "perch" to "perch",
        "sargo" to "sargo",
        "sand dab" to "sand_dab",
        "sanddab" to "sand_dab"
    )
    
    fun normalize(species: String): String {
        val cleaned = PUNCT_TRIMMER.replace(species.trim(), "").lowercase()
        if (cleaned.isBlank()) return species.lowercase().trim().replace(" ", "_")
        return SPECIES_MAP[cleaned] ?: cleaned.replace(" ", "_")
    }
}
