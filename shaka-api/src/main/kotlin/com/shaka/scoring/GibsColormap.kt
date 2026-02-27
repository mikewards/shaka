package com.shaka.scoring

import com.shaka.data.cache.SpotDataCache
import kotlin.math.*

/**
 * NASA GIBS VIIRS_Chlorophyll colormap (255 entries).
 * Source: https://gibs.earthdata.nasa.gov/colormaps/v1.3/VIIRS_Chlorophyll.xml
 *
 * Maps (R, G, B) to the geometric midpoint of its chlorophyll-a range (mg/m³).
 * Used by all 5 GIBS chlorophyll layers: PACE OCI, NOAA-20 VIIRS, NOAA-21 VIIRS,
 * Sentinel-3A OLCI, Sentinel-3B OLCI.
 *
 * Port of the Dart gibs_colormap.dart — identical table and matching algorithm.
 */
object GibsColormap {

    private data class ColormapEntry(val r: Int, val g: Int, val b: Int, val chl: Double)

    private val colormap = listOf(
        ColormapEntry(147, 0, 108, 0.0071),
        ColormapEntry(144, 0, 111, 0.0101),
        ColormapEntry(141, 0, 114, 0.0104),
        ColormapEntry(138, 0, 117, 0.0107),
        ColormapEntry(135, 0, 120, 0.0111),
        ColormapEntry(132, 0, 123, 0.0114),
        ColormapEntry(129, 0, 126, 0.0118),
        ColormapEntry(126, 0, 129, 0.0121),
        ColormapEntry(123, 0, 132, 0.0125),
        ColormapEntry(120, 0, 135, 0.0129),
        ColormapEntry(117, 0, 138, 0.0133),
        ColormapEntry(114, 0, 141, 0.0137),
        ColormapEntry(111, 0, 144, 0.0141),
        ColormapEntry(108, 0, 147, 0.0145),
        ColormapEntry(105, 0, 150, 0.0150),
        ColormapEntry(102, 0, 153, 0.0154),
        ColormapEntry(99, 0, 156, 0.0159),
        ColormapEntry(96, 0, 159, 0.0164),
        ColormapEntry(93, 0, 162, 0.0169),
        ColormapEntry(90, 0, 165, 0.0174),
        ColormapEntry(87, 0, 168, 0.0179),
        ColormapEntry(84, 0, 171, 0.0185),
        ColormapEntry(81, 0, 174, 0.0191),
        ColormapEntry(78, 0, 177, 0.0197),
        ColormapEntry(75, 0, 180, 0.0203),
        ColormapEntry(72, 0, 183, 0.0209),
        ColormapEntry(69, 0, 186, 0.0215),
        ColormapEntry(66, 0, 189, 0.0221),
        ColormapEntry(63, 0, 192, 0.0228),
        ColormapEntry(60, 0, 195, 0.0235),
        ColormapEntry(57, 0, 198, 0.0242),
        ColormapEntry(54, 0, 201, 0.0250),
        ColormapEntry(51, 0, 204, 0.0258),
        ColormapEntry(48, 0, 207, 0.0266),
        ColormapEntry(45, 0, 210, 0.0274),
        ColormapEntry(42, 0, 213, 0.0282),
        ColormapEntry(39, 0, 216, 0.0290),
        ColormapEntry(36, 0, 219, 0.0299),
        ColormapEntry(33, 0, 222, 0.0308),
        ColormapEntry(30, 0, 225, 0.0318),
        ColormapEntry(27, 0, 228, 0.0328),
        ColormapEntry(24, 0, 231, 0.0338),
        ColormapEntry(21, 0, 234, 0.0348),
        ColormapEntry(18, 0, 237, 0.0358),
        ColormapEntry(15, 0, 240, 0.0369),
        ColormapEntry(12, 0, 243, 0.0380),
        ColormapEntry(9, 0, 246, 0.0392),
        ColormapEntry(6, 0, 249, 0.0404),
        ColormapEntry(0, 0, 252, 0.0416),
        ColormapEntry(0, 0, 255, 0.0429),
        ColormapEntry(0, 5, 255, 0.0442),
        ColormapEntry(0, 10, 255, 0.0456),
        ColormapEntry(0, 16, 255, 0.0470),
        ColormapEntry(0, 21, 255, 0.0484),
        ColormapEntry(0, 26, 255, 0.0498),
        ColormapEntry(0, 32, 255, 0.0514),
        ColormapEntry(0, 37, 255, 0.0530),
        ColormapEntry(0, 42, 255, 0.0546),
        ColormapEntry(0, 48, 255, 0.0562),
        ColormapEntry(0, 53, 255, 0.0580),
        ColormapEntry(0, 58, 255, 0.0598),
        ColormapEntry(0, 64, 255, 0.0616),
        ColormapEntry(0, 69, 255, 0.0634),
        ColormapEntry(0, 74, 255, 0.0654),
        ColormapEntry(0, 80, 255, 0.0674),
        ColormapEntry(0, 85, 255, 0.0694),
        ColormapEntry(0, 90, 255, 0.0715),
        ColormapEntry(0, 96, 255, 0.0737),
        ColormapEntry(0, 101, 255, 0.0759),
        ColormapEntry(0, 106, 255, 0.0783),
        ColormapEntry(0, 112, 255, 0.0807),
        ColormapEntry(0, 117, 255, 0.0831),
        ColormapEntry(0, 122, 255, 0.0857),
        ColormapEntry(0, 128, 255, 0.0883),
        ColormapEntry(0, 133, 255, 0.0910),
        ColormapEntry(0, 138, 255, 0.0938),
        ColormapEntry(0, 144, 255, 0.0966),
        ColormapEntry(0, 149, 255, 0.0995),
        ColormapEntry(0, 154, 255, 0.1025),
        ColormapEntry(0, 160, 255, 0.1055),
        ColormapEntry(0, 165, 255, 0.1090),
        ColormapEntry(0, 170, 255, 0.1125),
        ColormapEntry(0, 176, 255, 0.1155),
        ColormapEntry(0, 181, 255, 0.1190),
        ColormapEntry(0, 186, 255, 0.1230),
        ColormapEntry(0, 192, 255, 0.1270),
        ColormapEntry(0, 197, 255, 0.1305),
        ColormapEntry(0, 202, 255, 0.1345),
        ColormapEntry(0, 208, 255, 0.1390),
        ColormapEntry(0, 213, 255, 0.1430),
        ColormapEntry(0, 218, 255, 0.1470),
        ColormapEntry(0, 224, 255, 0.1515),
        ColormapEntry(0, 229, 255, 0.1565),
        ColormapEntry(0, 234, 255, 0.1610),
        ColormapEntry(0, 240, 255, 0.1655),
        ColormapEntry(0, 245, 255, 0.1710),
        ColormapEntry(0, 250, 255, 0.1765),
        ColormapEntry(0, 255, 255, 0.1815),
        ColormapEntry(0, 255, 247, 0.1870),
        ColormapEntry(0, 255, 239, 0.1930),
        ColormapEntry(0, 255, 231, 0.1990),
        ColormapEntry(0, 255, 223, 0.2050),
        ColormapEntry(0, 255, 215, 0.2110),
        ColormapEntry(0, 255, 207, 0.2175),
        ColormapEntry(0, 255, 199, 0.2240),
        ColormapEntry(0, 255, 191, 0.2305),
        ColormapEntry(0, 255, 183, 0.2380),
        ColormapEntry(0, 255, 175, 0.2455),
        ColormapEntry(0, 255, 167, 0.2530),
        ColormapEntry(0, 255, 159, 0.2605),
        ColormapEntry(0, 255, 151, 0.2680),
        ColormapEntry(0, 255, 143, 0.2765),
        ColormapEntry(0, 255, 135, 0.2850),
        ColormapEntry(0, 255, 127, 0.2935),
        ColormapEntry(0, 255, 119, 0.3025),
        ColormapEntry(0, 255, 111, 0.3120),
        ColormapEntry(0, 255, 103, 0.3215),
        ColormapEntry(0, 255, 95, 0.3310),
        ColormapEntry(0, 255, 87, 0.3410),
        ColormapEntry(0, 255, 79, 0.3515),
        ColormapEntry(0, 255, 71, 0.3625),
        ColormapEntry(0, 255, 63, 0.3735),
        ColormapEntry(0, 255, 55, 0.3850),
        ColormapEntry(0, 255, 47, 0.3970),
        ColormapEntry(0, 255, 39, 0.4090),
        ColormapEntry(0, 255, 31, 0.4214),
        ColormapEntry(0, 255, 23, 0.4345),
        ColormapEntry(0, 255, 15, 0.4475),
        ColormapEntry(0, 255, 0, 0.4609),
        ColormapEntry(8, 255, 0, 0.4749),
        ColormapEntry(16, 255, 0, 0.4894),
        ColormapEntry(24, 255, 0, 0.5044),
        ColormapEntry(32, 255, 0, 0.5199),
        ColormapEntry(40, 255, 0, 0.5359),
        ColormapEntry(48, 255, 0, 0.5519),
        ColormapEntry(56, 255, 0, 0.5684),
        ColormapEntry(64, 255, 0, 0.5859),
        ColormapEntry(72, 255, 0, 0.6039),
        ColormapEntry(80, 255, 0, 0.6224),
        ColormapEntry(88, 255, 0, 0.6414),
        ColormapEntry(96, 255, 0, 0.6609),
        ColormapEntry(104, 255, 0, 0.6809),
        ColormapEntry(112, 255, 0, 0.7014),
        ColormapEntry(120, 255, 0, 0.7229),
        ColormapEntry(128, 255, 0, 0.7454),
        ColormapEntry(136, 255, 0, 0.7684),
        ColormapEntry(144, 255, 0, 0.7914),
        ColormapEntry(152, 255, 0, 0.8154),
        ColormapEntry(160, 255, 0, 0.8404),
        ColormapEntry(168, 255, 0, 0.8659),
        ColormapEntry(176, 255, 0, 0.8924),
        ColormapEntry(184, 255, 0, 0.9199),
        ColormapEntry(192, 255, 0, 0.9479),
        ColormapEntry(200, 255, 0, 0.9764),
        ColormapEntry(208, 255, 0, 1.0064),
        ColormapEntry(216, 255, 0, 1.0374),
        ColormapEntry(224, 255, 0, 1.0689),
        ColormapEntry(232, 255, 0, 1.1014),
        ColormapEntry(240, 255, 0, 1.1349),
        ColormapEntry(248, 255, 0, 1.1694),
        ColormapEntry(255, 255, 0, 1.2054),
        ColormapEntry(255, 251, 0, 1.2424),
        ColormapEntry(255, 247, 0, 1.2799),
        ColormapEntry(255, 243, 0, 1.3188),
        ColormapEntry(255, 239, 0, 1.3593),
        ColormapEntry(255, 235, 0, 1.4008),
        ColormapEntry(255, 231, 0, 1.4433),
        ColormapEntry(255, 227, 0, 1.4873),
        ColormapEntry(255, 223, 0, 1.5328),
        ColormapEntry(255, 219, 0, 1.5793),
        ColormapEntry(255, 215, 0, 1.6273),
        ColormapEntry(255, 211, 0, 1.6773),
        ColormapEntry(255, 207, 0, 1.7288),
        ColormapEntry(255, 203, 0, 1.7813),
        ColormapEntry(255, 199, 0, 1.8353),
        ColormapEntry(255, 195, 0, 1.8913),
        ColormapEntry(255, 191, 0, 1.9493),
        ColormapEntry(255, 187, 0, 2.0088),
        ColormapEntry(255, 183, 0, 2.0698),
        ColormapEntry(255, 179, 0, 2.1328),
        ColormapEntry(255, 175, 0, 2.1978),
        ColormapEntry(255, 171, 0, 2.2647),
        ColormapEntry(255, 167, 0, 2.3337),
        ColormapEntry(255, 163, 0, 2.4052),
        ColormapEntry(255, 159, 0, 2.4787),
        ColormapEntry(255, 155, 0, 2.5542),
        ColormapEntry(255, 151, 0, 2.6322),
        ColormapEntry(255, 147, 0, 2.7127),
        ColormapEntry(255, 143, 0, 2.7957),
        ColormapEntry(255, 139, 0, 2.8807),
        ColormapEntry(255, 135, 0, 2.9682),
        ColormapEntry(255, 131, 0, 3.0587),
        ColormapEntry(255, 127, 0, 3.1521),
        ColormapEntry(255, 123, 0, 3.2481),
        ColormapEntry(255, 119, 0, 3.3471),
        ColormapEntry(255, 115, 0, 3.4496),
        ColormapEntry(255, 111, 0, 3.5546),
        ColormapEntry(255, 107, 0, 3.6626),
        ColormapEntry(255, 103, 0, 3.7746),
        ColormapEntry(255, 99, 0, 3.8901),
        ColormapEntry(255, 95, 0, 4.0086),
        ColormapEntry(255, 91, 0, 4.1305),
        ColormapEntry(255, 87, 0, 4.2565),
        ColormapEntry(255, 83, 0, 4.3865),
        ColormapEntry(255, 79, 0, 4.5205),
        ColormapEntry(255, 75, 0, 4.6585),
        ColormapEntry(255, 71, 0, 4.8005),
        ColormapEntry(255, 67, 0, 4.9469),
        ColormapEntry(255, 63, 0, 5.0979),
        ColormapEntry(255, 59, 0, 5.2534),
        ColormapEntry(255, 55, 0, 5.4134),
        ColormapEntry(255, 51, 0, 5.5784),
        ColormapEntry(255, 47, 0, 5.7488),
        ColormapEntry(255, 43, 0, 5.9243),
        ColormapEntry(255, 39, 0, 6.1048),
        ColormapEntry(255, 35, 0, 6.2908),
        ColormapEntry(255, 31, 0, 6.4828),
        ColormapEntry(255, 27, 0, 6.6803),
        ColormapEntry(255, 23, 0, 6.8837),
        ColormapEntry(255, 19, 0, 7.0937),
        ColormapEntry(255, 15, 0, 7.3102),
        ColormapEntry(255, 11, 0, 7.5332),
        ColormapEntry(255, 7, 0, 7.7631),
        ColormapEntry(255, 3, 0, 8.0001),
        ColormapEntry(255, 0, 0, 8.2441),
        ColormapEntry(250, 0, 0, 8.4955),
        ColormapEntry(245, 0, 0, 8.7545),
        ColormapEntry(240, 0, 0, 9.0215),
        ColormapEntry(235, 0, 0, 9.2965),
        ColormapEntry(230, 0, 0, 9.5799),
        ColormapEntry(225, 0, 0, 9.8724),
        ColormapEntry(220, 0, 0, 10.1734),
        ColormapEntry(215, 0, 0, 10.4833),
        ColormapEntry(210, 0, 0, 10.8033),
        ColormapEntry(205, 0, 0, 11.1327),
        ColormapEntry(200, 0, 0, 11.4722),
        ColormapEntry(195, 0, 0, 11.8222),
        ColormapEntry(190, 0, 0, 12.1826),
        ColormapEntry(185, 0, 0, 12.5541),
        ColormapEntry(180, 0, 0, 12.9370),
        ColormapEntry(175, 0, 0, 13.3320),
        ColormapEntry(170, 0, 0, 13.7385),
        ColormapEntry(165, 0, 0, 14.1574),
        ColormapEntry(160, 0, 0, 14.5894),
        ColormapEntry(155, 0, 0, 15.0343),
        ColormapEntry(150, 0, 0, 15.4928),
        ColormapEntry(145, 0, 0, 15.9652),
        ColormapEntry(140, 0, 0, 16.4521),
        ColormapEntry(135, 0, 0, 16.9536),
        ColormapEntry(130, 0, 0, 17.4705),
        ColormapEntry(125, 0, 0, 18.0035),
        ColormapEntry(120, 0, 0, 18.5529),
        ColormapEntry(115, 0, 0, 19.1188),
        ColormapEntry(110, 0, 0, 19.7018),
        ColormapEntry(105, 0, 0, 20.0000),
    )

    private const val MAX_DISTANCE = 30.0

    /**
     * Estimate chlorophyll-a (mg/m³) from a GIBS satellite hex color string.
     * Returns null if the color doesn't match any GIBS chlorophyll color
     * (e.g. land, cloud artifact, or non-chlorophyll layer).
     */
    fun estimateChlorophyllFromHex(hexColor: String): Double? {
        val (r, g, b) = parseHex(hexColor) ?: return null

        var bestDist = Double.MAX_VALUE
        var bestChl = 0.0

        for (entry in colormap) {
            val dr = (r - entry.r).toDouble()
            val dg = (g - entry.g).toDouble()
            val db = (b - entry.b).toDouble()
            val dist = sqrt(dr * dr + dg * dg + db * db)
            if (dist < bestDist) {
                bestDist = dist
                bestChl = entry.chl
                if (dist == 0.0) break
            }
        }

        return if (bestDist > MAX_DISTANCE) null else bestChl
    }

    /**
     * Compute geometric mean of satellite-derived chlorophyll estimates.
     * Mirrors the Flutter _estimateFromSatelliteColors logic exactly:
     * picks yesterday's color (preferred) or today's for each satellite,
     * maps each to chlorophyll via the colormap, then returns the geometric mean.
     */
    fun estimateFromGibsColors(gibs: SpotDataCache.GIBSSatelliteData?): Double? {
        if (gibs == null) return null

        val hexColors = listOfNotNull(
            gibs.paceYesterdayColor ?: gibs.paceTodayColor,
            gibs.noaa20YesterdayColor ?: gibs.noaa20TodayColor,
            gibs.noaa21YesterdayColor ?: gibs.noaa21TodayColor,
            gibs.sentinel3aYesterdayColor ?: gibs.sentinel3aTodayColor,
            gibs.sentinel3bYesterdayColor ?: gibs.sentinel3bTodayColor,
        )
        if (hexColors.isEmpty()) return null

        val estimates = hexColors.mapNotNull { estimateChlorophyllFromHex(it) }
        if (estimates.isEmpty()) return null

        val logSum = estimates.sumOf { ln(it) }
        return exp(logSum / estimates.size)
    }

    private fun parseHex(hex: String): Triple<Int, Int, Int>? {
        return try {
            val h = hex.removePrefix("#")
            if (h.length != 6) return null
            val v = h.toInt(16)
            Triple((v shr 16) and 0xFF, (v shr 8) and 0xFF, v and 0xFF)
        } catch (_: Exception) {
            null
        }
    }
}
