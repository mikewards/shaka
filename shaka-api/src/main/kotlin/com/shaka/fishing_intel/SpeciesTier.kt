package com.shaka.fishing_intel

/**
 * Species tier for fishing intel: trophy (headline-worthy) vs baseline (dock filler).
 * Normalized names matching SpeciesNormalizer / claim species strings.
 */
object SpeciesTier {
    val TROPHY_SPECIES = setOf(
        "yellowtail",
        "bluefin_tuna",
        "yellowfin_tuna",
        "white_seabass",
        "halibut",
        "dorado",
        "wahoo",
        "lingcod",
        "sheephead",
        "barracuda",
        "albacore"
    )

    val BASELINE_SPECIES = setOf(
        "calico_bass",
        "sculpin",
        "sand_bass",
        "rockfish",
        "red_rockfish",
        "copper_rockfish",
        "vermilion_rockfish",
        "bocaccio",
        "whitefish",
        "bonito",
        "perch",
        "sargo",
        "sand_dab",
        "lobster",
        "squid",
        "spotted_bay_bass",
        "cabezon",
        "skipjack",
        "mackerel"
    )
}
