package com.shaka.fishing_intel.parsing

import com.shaka.fishing_intel.models.FishCount
import com.shaka.fishing_intel.processing.SpeciesNormalizer

/**
 * Parses fish count strings from dock totals.
 * Examples:
 *   - "57 Whitefish, 14 Sculpin, 4 Halibut, 3 Released Halibut"
 *   - "838 calico bass released, 548 rockfish"
 */
object CountsParser {
    // Pattern: "57 Whitefish" or "3 Released Halibut" or "838 calico bass released"
    private val COUNT_PATTERN = Regex(
        """(\d+)\s+(Released\s+)?([A-Za-z\s]+?)(\s+released)?(?:,|$)""",
        RegexOption.IGNORE_CASE
    )
    
    fun parse(countsString: String): List<FishCount> {
        val results = mutableListOf<FishCount>()
        
        COUNT_PATTERN.findAll(countsString).forEach { match ->
            val count = match.groupValues[1].toIntOrNull() ?: return@forEach
            val releasedPrefix = match.groupValues[2].isNotBlank()
            val species = match.groupValues[3].trim()
            val releasedSuffix = match.groupValues[4].isNotBlank()
            
            if (species.isNotBlank() && count > 0) {
                val isReleased = releasedPrefix || releasedSuffix
                results.add(FishCount(
                    species = SpeciesNormalizer.normalize(species),
                    kept = if (isReleased) 0 else count,
                    released = if (isReleased) count else 0
                ))
            }
        }
        
        return results
    }
}
