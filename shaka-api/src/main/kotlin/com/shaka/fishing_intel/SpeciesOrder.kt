package com.shaka.fishing_intel

/**
 * Canonical order of species by desirability (most to least) for SoCal sportfishing.
 * Used to sort the unified "What's being caught" list. Normalized names (underscores).
 * Species not in this list sort last (e.g. by 24h count).
 */
object SpeciesOrder {
    /** Most desirable first, least desirable last. */
    val DESIRABILITY_ORDER: List<String> = listOf(
        "bluefin_tuna",
        "yellowfin_tuna",
        "white_seabass",
        "yellowtail",
        "dorado",
        "wahoo",
        "halibut",
        "lingcod",
        "albacore",
        "sheephead",
        "barracuda",
        "calico_bass",
        "bonito",
        "red_rockfish",
        "copper_rockfish",
        "vermilion_rockfish",
        "bocaccio",
        "whitefish",
        "lobster",
        "sculpin",
        "sand_bass",
        "perch",
        "sargo",
        "sand_dab",
        "spotted_bay_bass",
        "cabezon",
        "skipjack",
        "mackerel",
        "squid"
    )

    private val orderIndex: Map<String, Int> = DESIRABILITY_ORDER.withIndex().associate { (i, s) -> s to i }

    /** Sort key: lower = more desirable. Species not in list get Int.MAX so they sort last. */
    fun sortKey(normalizedSpecies: String): Int = orderIndex[normalizedSpecies] ?: Int.MAX_VALUE
}
