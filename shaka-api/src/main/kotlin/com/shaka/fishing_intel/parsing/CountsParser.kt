package com.shaka.fishing_intel.parsing

import com.shaka.fishing_intel.models.FishCount
import com.shaka.fishing_intel.processing.SpeciesNormalizer

/**
 * Parses fish count strings from dock totals.
 * Examples:
 *   - "57 Whitefish, 14 Sculpin, 4 Halibut, 3 Released Halibut"
 *   - "838 calico bass released, 548 rockfish"
 *   - "40 rockfish, 34 red snapper, 14 calico bass, and 1 trigger fish"
 *   - "12 Sand Bass, 1 Halibut, 90 Whitefish"
 */
object CountsParser {
    
    /**
     * Parse a fish counts string and return a list of FishCount objects.
     * Handles various formats from different fishing report sites.
     */
    fun parse(countsString: String): List<FishCount> {
        val results = mutableListOf<FishCount>()
        
        // Clean up the input - remove "and" conjunctions, normalize separators
        val cleaned = countsString
            .replace(Regex("""\s+and\s+""", RegexOption.IGNORE_CASE), ", ")
            .replace(Regex("""\s*,\s*"""), ", ")
            .trim()
        
        // Split by comma and process each item
        val items = cleaned.split(Regex("""\s*,\s*"""))
        
        for (item in items) {
            val trimmed = item.trim()
            if (trimmed.isBlank()) continue
            
            // Try different patterns
            val fishCount = parseItem(trimmed)
            if (fishCount != null) {
                results.add(fishCount)
            }
        }
        
        return results
    }
    
    /**
     * Parse a single item like "57 Whitefish" or "3 Released Halibut"
     */
    private fun parseItem(item: String): FishCount? {
        // Pattern 1: "X released SPECIES" (released prefix)
        val releasedPrefixPattern = Regex(
            """^(\d+)\s+released\s+(.+)$""",
            RegexOption.IGNORE_CASE
        )
        
        // Pattern 2: "X SPECIES released" (released suffix)
        val releasedSuffixPattern = Regex(
            """^(\d+)\s+(.+?)\s+released$""",
            RegexOption.IGNORE_CASE
        )
        
        // Pattern 3: "X SPECIES" (standard - no released)
        val standardPattern = Regex(
            """^(\d+)\s+(.+)$""",
            RegexOption.IGNORE_CASE
        )
        
        // Try released prefix pattern first
        releasedPrefixPattern.find(item)?.let { match ->
            val count = match.groupValues[1].toIntOrNull() ?: return null
            val species = match.groupValues[2].trim()
            if (species.isNotBlank() && count > 0) {
                return FishCount(
                    species = SpeciesNormalizer.normalize(species),
                    kept = 0,
                    released = count
                )
            }
        }
        
        // Try released suffix pattern
        releasedSuffixPattern.find(item)?.let { match ->
            val count = match.groupValues[1].toIntOrNull() ?: return null
            val species = match.groupValues[2].trim()
            if (species.isNotBlank() && count > 0) {
                return FishCount(
                    species = SpeciesNormalizer.normalize(species),
                    kept = 0,
                    released = count
                )
            }
        }
        
        // Try standard pattern (no released)
        standardPattern.find(item)?.let { match ->
            val count = match.groupValues[1].toIntOrNull() ?: return null
            var species = match.groupValues[2].trim()
            
            // Skip items that don't look like species names
            if (species.isBlank() || 
                species.equals("fish", ignoreCase = true) ||
                species.equals("total fish", ignoreCase = true) ||
                species.matches(Regex("""^\d+$"""))) {
                return null
            }
            
            // Clean up common suffixes that aren't part of the species name
            species = species
                .replace(Regex("""\s*\(.*\)\s*$"""), "")  // Remove parenthetical
                .trim()
            
            if (species.isNotBlank() && count > 0) {
                return FishCount(
                    species = SpeciesNormalizer.normalize(species),
                    kept = count,
                    released = 0
                )
            }
        }
        
        return null
    }
}
