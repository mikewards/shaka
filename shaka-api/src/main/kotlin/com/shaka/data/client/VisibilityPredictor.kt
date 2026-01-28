package com.shaka.data.client

import org.slf4j.LoggerFactory
import java.time.LocalDateTime
import java.time.ZoneId

/**
 * Real-time underwater visibility predictor.
 * 
 * Predicts current visibility based on real-time oceanographic conditions,
 * similar to how VizFinder and DiveViz work.
 * 
 * Key factors affecting visibility (all available in real-time):
 * - Tide stage: Outgoing tide = runoff/sediment transport = worse visibility
 * - Wind speed: High wind = wave action = churns sediment = worse visibility  
 * - Swell height: Large swell = stirs bottom = worse visibility
 * - Recent rainfall: Runoff brings sediment = worse visibility
 * - Current strength: Strong currents = sediment transport = variable visibility
 * - Chlorophyll: High chlorophyll = plankton blooms = reduced clarity
 * 
 * This gives CURRENT conditions, not 2-day-old satellite data.
 */
class VisibilityPredictor {

    private val logger = LoggerFactory.getLogger(VisibilityPredictor::class.java)

    data class VisibilityInput(
        // Tide conditions (from NOAA real-time)
        val tideStage: TideStage,           // Incoming, Outgoing, High, Low
        val tideHeightM: Double,            // Current tide height
        
        // Wave conditions (from Open-Meteo real-time)
        val swellHeightM: Double,           // Swell height in meters
        val windSpeedKmh: Double,           // Wind speed km/h
        
        // Recent weather (from Open-Meteo)
        val recentRainfallMm: Double,       // Rainfall in last 24h
        
        // Ocean conditions (from Open-Meteo/NOAA)
        val currentVelocityMs: Double,      // Current strength m/s
        
        // Water quality (from latest satellite)
        val chlorophyllMgM3: Double?,       // Chlorophyll concentration
        
        // Location context
        val isNearRiver: Boolean = false,   // Near river mouth = more runoff impact
        val bottomType: BottomType = BottomType.ROCKY,  // Sandy bottoms stir more easily
        val depthM: Double = 15.0           // Shallow = more stirring
    )

    enum class TideStage {
        INCOMING,   // Cleaner ocean water flowing in
        OUTGOING,   // Runoff/sediment flowing out
        HIGH,       // Stable, typically better visibility
        LOW         // Stable but may expose sediment
    }

    enum class BottomType {
        ROCKY,      // Less sediment suspension
        SANDY,      // Moderate sediment
        MUDDY       // High sediment suspension potential
    }

    data class VisibilityPrediction(
        val visibilityM: Double,            // Predicted visibility in meters
        val confidence: Double,             // 0-1 confidence score
        val category: VisibilityCategory,   // Quick reference
        val factors: Map<String, String>,   // Explanation of each factor's impact
        val recommendation: String,         // Go/No-go recommendation
        val dataSource: String              // "Real-time prediction model"
    )

    enum class VisibilityCategory(val label: String, val emoji: String) {
        EXCELLENT("Excellent (30m+)", "🔵"),
        GOOD("Good (15-30m)", "🟢"),
        MODERATE("Moderate (8-15m)", "🟡"),
        POOR("Poor (3-8m)", "🟠"),
        VERY_POOR("Very Poor (<3m)", "🔴")
    }

    /**
     * Predict current underwater visibility based on real-time conditions.
     * 
     * Returns visibility in METERS with confidence score and factors breakdown.
     */
    fun predictVisibility(input: VisibilityInput): VisibilityPrediction {
        val factors = mutableMapOf<String, String>()
        
        // Start with baseline visibility based on chlorophyll (if available)
        val baselineVis = calculateBaselineFromChlorophyll(input.chlorophyllMgM3)
        factors["Baseline (chlorophyll)"] = "${String.format("%.0f", baselineVis)}m"
        
        // TIDE IMPACT: Outgoing tide reduces visibility significantly
        val tideFactor = when (input.tideStage) {
            TideStage.INCOMING -> 1.15  // Ocean water = cleaner, +15%
            TideStage.HIGH -> 1.1       // Stable high = good, +10%
            TideStage.LOW -> 0.9        // Exposed sediment possible, -10%
            TideStage.OUTGOING -> 0.7   // Runoff/sediment, -30%
        }
        factors["Tide (${input.tideStage.name.lowercase()})"] = 
            if (tideFactor >= 1.0) "+${((tideFactor - 1) * 100).toInt()}%" else "${((tideFactor - 1) * 100).toInt()}%"
        
        // SWELL IMPACT: Large swell stirs up bottom
        val swellFactor = when {
            input.swellHeightM < 0.5 -> 1.1   // Calm = excellent, +10%
            input.swellHeightM < 1.0 -> 1.0   // Moderate = neutral
            input.swellHeightM < 2.0 -> 0.85  // Moderate-large = -15%
            input.swellHeightM < 3.0 -> 0.7   // Large = -30%
            else -> 0.5                        // Very large = -50%
        }
        factors["Swell (${String.format("%.1f", input.swellHeightM)}m)"] = 
            if (swellFactor >= 1.0) "+${((swellFactor - 1) * 100).toInt()}%" else "${((swellFactor - 1) * 100).toInt()}%"
        
        // WIND IMPACT: High wind churns surface and creates turbulence
        val windFactor = when {
            input.windSpeedKmh < 15 -> 1.05   // Light wind = +5%
            input.windSpeedKmh < 25 -> 1.0    // Moderate = neutral
            input.windSpeedKmh < 35 -> 0.9    // Fresh = -10%
            input.windSpeedKmh < 50 -> 0.75   // Strong = -25%
            else -> 0.6                        // Very strong = -40%
        }
        factors["Wind (${input.windSpeedKmh.toInt()}km/h)"] = 
            if (windFactor >= 1.0) "+${((windFactor - 1) * 100).toInt()}%" else "${((windFactor - 1) * 100).toInt()}%"
        
        // RAINFALL IMPACT: Recent rain = runoff = sediment
        val rainFactor = when {
            input.recentRainfallMm < 1 -> 1.0    // No rain = neutral
            input.recentRainfallMm < 5 -> 0.95   // Light rain = -5%
            input.recentRainfallMm < 15 -> 0.85  // Moderate rain = -15%
            input.recentRainfallMm < 30 -> 0.7   // Heavy rain = -30%
            else -> 0.5                           // Very heavy = -50%
        }
        // Near rivers are more affected by rainfall
        val adjustedRainFactor = if (input.isNearRiver && input.recentRainfallMm > 5) {
            rainFactor * 0.8  // Extra 20% penalty near rivers
        } else {
            rainFactor
        }
        factors["Rainfall (${String.format("%.0f", input.recentRainfallMm)}mm/24h)"] = 
            if (adjustedRainFactor >= 1.0) "neutral" else "${((adjustedRainFactor - 1) * 100).toInt()}%"
        
        // CURRENT IMPACT: Strong currents = sediment transport
        val currentFactor = when {
            input.currentVelocityMs < 0.1 -> 1.0   // Slack = neutral
            input.currentVelocityMs < 0.3 -> 0.95  // Light = -5%
            input.currentVelocityMs < 0.5 -> 0.85  // Moderate = -15%
            else -> 0.7                             // Strong = -30%
        }
        factors["Current (${String.format("%.1f", input.currentVelocityMs)}m/s)"] = 
            if (currentFactor >= 1.0) "neutral" else "${((currentFactor - 1) * 100).toInt()}%"
        
        // BOTTOM TYPE ADJUSTMENT
        val bottomFactor = when (input.bottomType) {
            BottomType.ROCKY -> 1.1     // Rocky = less suspension
            BottomType.SANDY -> 1.0     // Sandy = moderate
            BottomType.MUDDY -> 0.8     // Muddy = more suspension
        }
        factors["Bottom (${input.bottomType.name.lowercase()})"] = 
            if (bottomFactor >= 1.0) "+${((bottomFactor - 1) * 100).toInt()}%" else "${((bottomFactor - 1) * 100).toInt()}%"
        
        // DEPTH ADJUSTMENT: Shallow water stirs more easily
        val depthFactor = when {
            input.depthM > 30 -> 1.1    // Deep = less stirring
            input.depthM > 15 -> 1.0    // Moderate = neutral
            input.depthM > 8 -> 0.9     // Shallow = -10%
            else -> 0.8                  // Very shallow = -20%
        }
        factors["Depth (${input.depthM.toInt()}m)"] = 
            if (depthFactor >= 1.0) "+${((depthFactor - 1) * 100).toInt()}%" else "${((depthFactor - 1) * 100).toInt()}%"
        
        // CALCULATE FINAL VISIBILITY
        val combinedFactor = tideFactor * swellFactor * windFactor * 
                            adjustedRainFactor * currentFactor * bottomFactor * depthFactor
        
        val predictedVis = (baselineVis * combinedFactor).coerceIn(1.0, 50.0)
        
        // DETERMINE CATEGORY
        val category = when {
            predictedVis >= 30 -> VisibilityCategory.EXCELLENT
            predictedVis >= 15 -> VisibilityCategory.GOOD
            predictedVis >= 8 -> VisibilityCategory.MODERATE
            predictedVis >= 3 -> VisibilityCategory.POOR
            else -> VisibilityCategory.VERY_POOR
        }
        
        // CALCULATE CONFIDENCE (based on data completeness and conditions)
        val confidence = calculateConfidence(input)
        
        // GENERATE RECOMMENDATION
        val recommendation = generateRecommendation(category, input, predictedVis)
        
        logger.info("Visibility prediction: ${String.format("%.1f", predictedVis)}m (${category.label}) - " +
                   "tide=${input.tideStage}, swell=${input.swellHeightM}m, wind=${input.windSpeedKmh}km/h")
        
        return VisibilityPrediction(
            visibilityM = predictedVis,
            confidence = confidence,
            category = category,
            factors = factors,
            recommendation = recommendation,
            dataSource = "Real-time prediction (tide/swell/wind/current/rainfall)"
        )
    }

    /**
     * Calculate baseline visibility from chlorophyll.
     * Lower chlorophyll = clearer water.
     */
    private fun calculateBaselineFromChlorophyll(chlorophyll: Double?): Double {
        return when {
            chlorophyll == null -> 20.0  // Unknown = assume moderate
            chlorophyll < 0.1 -> 40.0    // Very clear (open ocean)
            chlorophyll < 0.3 -> 30.0    // Clear
            chlorophyll < 0.8 -> 22.0    // Moderate
            chlorophyll < 1.5 -> 15.0    // Productive
            chlorophyll < 3.0 -> 10.0    // High productivity
            else -> 5.0                   // Bloom conditions
        }
    }

    private fun calculateConfidence(input: VisibilityInput): Double {
        var confidence = 0.9  // High base confidence for real-time data
        
        // Reduce confidence for extreme conditions (harder to predict)
        if (input.swellHeightM > 3.0) confidence -= 0.1
        if (input.windSpeedKmh > 50) confidence -= 0.1
        if (input.recentRainfallMm > 30) confidence -= 0.1
        
        // Reduce if no chlorophyll data
        if (input.chlorophyllMgM3 == null) confidence -= 0.1
        
        return confidence.coerceIn(0.5, 0.95)
    }

    private fun generateRecommendation(
        category: VisibilityCategory, 
        input: VisibilityInput,
        visM: Double
    ): String {
        return when (category) {
            VisibilityCategory.EXCELLENT -> 
                "Excellent conditions for spearfishing! ${String.format("%.0f", visM)}m+ visibility."
            
            VisibilityCategory.GOOD -> 
                "Good conditions. Visibility around ${String.format("%.0f", visM)}m."
            
            VisibilityCategory.MODERATE -> {
                val warnings = mutableListOf<String>()
                if (input.tideStage == TideStage.OUTGOING) warnings.add("outgoing tide")
                if (input.swellHeightM > 1.5) warnings.add("moderate swell")
                if (input.recentRainfallMm > 10) warnings.add("recent rain")
                
                if (warnings.isNotEmpty()) {
                    "Moderate visibility (~${String.format("%.0f", visM)}m). Watch for: ${warnings.joinToString(", ")}."
                } else {
                    "Moderate visibility (~${String.format("%.0f", visM)}m). Decent conditions."
                }
            }
            
            VisibilityCategory.POOR -> {
                val causes = mutableListOf<String>()
                if (input.tideStage == TideStage.OUTGOING) causes.add("outgoing tide")
                if (input.swellHeightM > 2.0) causes.add("large swell")
                if (input.windSpeedKmh > 35) causes.add("strong wind")
                if (input.recentRainfallMm > 15) causes.add("recent rainfall")
                
                "Poor visibility (~${String.format("%.0f", visM)}m). " +
                "Consider waiting for: ${if (causes.isNotEmpty()) causes.joinToString(", ") + " to pass" else "conditions to improve"}."
            }
            
            VisibilityCategory.VERY_POOR -> 
                "Very poor visibility (<3m). Not recommended for spearfishing. Wait for conditions to improve."
        }
    }

    companion object {
        /**
         * Determine tide stage from current height and trend.
         */
        fun determineTideStage(
            currentHeight: Double,
            previousHeight: Double,
            highTide: Double,
            lowTide: Double
        ): TideStage {
            val range = highTide - lowTide
            val relativeHeight = (currentHeight - lowTide) / range
            val rising = currentHeight > previousHeight
            
            return when {
                relativeHeight > 0.9 -> TideStage.HIGH
                relativeHeight < 0.1 -> TideStage.LOW
                rising -> TideStage.INCOMING
                else -> TideStage.OUTGOING
            }
        }
    }
}
