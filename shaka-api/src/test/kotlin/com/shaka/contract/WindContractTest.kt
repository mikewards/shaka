package com.shaka.contract

import com.shaka.data.cache.SpotDataCache
import com.shaka.model.WindHourlyPoint
import com.shaka.monitoring.MonitoringConfig
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Contract tests for the wind data path (Phase 4 of the wind-data audit).
 * These encode the invariants that let clients trust the numeric wind fields:
 *
 *  1. direction is always a FROM bearing in [0, 360) and maps to a valid
 *     16-point cardinal;
 *  2. the snapshot's validAt is the model hour nearest "now" — never in the
 *     distant past/future when the series covers now — and the staleness
 *     budget is DERIVED from the 6-hourly refetch cadence, so changing the
 *     cadence without revisiting the budget fails here;
 *  3. no fabricated zeros: a derived snapshot reflects the series values, and
 *     the old failure shape (0° direction + default speed on missing data)
 *     cannot come out of a series that never contained it;
 *  4. gust < speed is a data-quality WARNING, not a failure — models
 *     occasionally emit it and it must not break payloads.
 */
class WindContractTest {

    private fun hourlySeries(
        startMs: Long,
        hours: Int,
        speedKts: (Int) -> Double = { 8.0 + it * 0.5 },
        directionDeg: (Int) -> Int = { (270 + it) % 360 },
        gustKts: (Int) -> Double? = { 10.0 + it * 0.5 }
    ): List<WindHourlyPoint> = (0 until hours).map { h ->
        WindHourlyPoint(
            epochMs = startMs + h * 3_600_000L,
            speedKts = speedKts(h),
            directionDeg = directionDeg(h),
            gustKts = gustKts(h)
        )
    }

    private fun deriveSnapshot(
        spotId: String,
        points: List<WindHourlyPoint>,
        fetchedAt: Instant = Instant.now()
    ): SpotDataCache.CachedValue<SpotDataCache.WindInfo> {
        SpotDataCache.updateWindSeries(spotId, points, "Pacific/Honolulu", fetchedAt)
        SpotDataCache.deriveCurrentHourSnapshot(spotId)
        val wind = SpotDataCache.get(spotId)?.wind
        assertNotNull(wind, "snapshot should derive when the series covers now")
        return wind
    }

    // ---------- 1. direction domain ----------

    @Test
    fun `derived direction is in 0-360 and yields a valid cardinal`() {
        val now = Instant.now().toEpochMilli()
        val start = now - 6 * 3_600_000L
        // Sweep directions across the wrap point (350..369 -> wraps to 0..9).
        val snapshot = deriveSnapshot(
            "contract-dir-wrap",
            hourlySeries(start, 13, directionDeg = { (350 + it) % 360 })
        )
        val deg = snapshot.value.directionDeg
        assertNotNull(deg, "numeric FROM bearing must be populated")
        assertTrue(deg in 0..359, "direction $deg out of [0, 360)")
        assertTrue(
            snapshot.value.direction in CARDINALS,
            "cardinal '${snapshot.value.direction}' not a 16-point label"
        )
    }

    @Test
    fun `degreesToCardinal covers the wrap and every sector`() {
        assertEquals("N", SpotDataCache.degreesToCardinal(0.0))
        assertEquals("N", SpotDataCache.degreesToCardinal(359.9))
        assertEquals("N", SpotDataCache.degreesToCardinal(11.24))
        assertEquals("NNE", SpotDataCache.degreesToCardinal(11.25))
        assertEquals("E", SpotDataCache.degreesToCardinal(90.0))
        assertEquals("S", SpotDataCache.degreesToCardinal(180.0))
        assertEquals("W", SpotDataCache.degreesToCardinal(270.0))
        for (deg in 0 until 360) {
            assertTrue(
                SpotDataCache.degreesToCardinal(deg.toDouble()) in CARDINALS,
                "degree $deg produced an invalid cardinal"
            )
        }
    }

    // ---------- 2. validAt + staleness budget ----------

    @Test
    fun `validAt is the model hour nearest now`() {
        val now = Instant.now().toEpochMilli()
        val start = now - 6 * 3_600_000L
        val snapshot = deriveSnapshot("contract-validat", hourlySeries(start, 13))
        val validAt = snapshot.dataValidAt!!.toEpochMilli()
        val driftMs = kotlin.math.abs(validAt - now)
        assertTrue(
            driftMs <= 3_600_000L,
            "validAt drifted ${driftMs / 60000} min from now; nearest-hour selection is broken"
        )
    }

    @Test
    fun `staleness budget derives from the 6-hourly refetch cadence`() {
        // interval (6h) + maxRun (2h) + 1h grace. If someone changes the
        // cadence in MonitoringConfig without reconsidering the budget, this
        // fails and forces the conversation.
        val spec = MonitoringConfig.jobByName("hourly_swell_wind")!!
        assertEquals(6 * 3_600_000L, spec.intervalMs, "refetch cadence changed")
        val budgetMinutes = MonitoringConfig.freshnessThresholdMinutes("swell")
        assertEquals(
            (spec.intervalMs + spec.maxRunMs) / 60000 + 60,
            budgetMinutes,
            "freshness budget no longer derives from interval + maxRun + 1h"
        )
    }

    @Test
    fun `snapshot fetched within budget is fresh, beyond is stale`() {
        val budgetMinutes = MonitoringConfig.freshnessThresholdMinutes("swell")!!
        val now = Instant.now().toEpochMilli()
        val start = now - 6 * 3_600_000L

        val fresh = deriveSnapshot(
            "contract-fresh", hourlySeries(start, 13),
            fetchedAt = Instant.now().minusSeconds(60)
        )
        assertTrue(fresh.minutesSinceFetch() < budgetMinutes)

        val stale = deriveSnapshot(
            "contract-stale", hourlySeries(start, 13),
            fetchedAt = Instant.now().minusSeconds((budgetMinutes + 30) * 60)
        )
        assertTrue(
            stale.minutesSinceFetch() >= budgetMinutes,
            "a fetch older than the budget must classify as stale"
        )
    }

    // ---------- 3. no fabricated zeros ----------

    @Test
    fun `snapshot reflects series values - no zero-direction default speed pair`() {
        val now = Instant.now().toEpochMilli()
        val start = now - 6 * 3_600_000L
        // Series with realistic non-zero data everywhere.
        val snapshot = deriveSnapshot(
            "contract-nozeros",
            hourlySeries(start, 13, speedKts = { 12.0 }, directionDeg = { 275 })
        )
        assertEquals(275, snapshot.value.directionDeg)
        assertTrue(snapshot.value.speedKnots > 0.0)
        // The Jun 2026 outage shape: 10 km/h default (5.39 kts) + 0°. A series
        // that never contained that pair must never produce it.
        val isOutageShape =
            snapshot.value.directionDeg == 0 &&
                kotlin.math.abs(snapshot.value.speedKnots - 5.39957) < 0.01
        assertTrue(!isOutageShape, "fabricated default wind reappeared")
    }

    @Test
    fun `preformatted label rounds instead of truncating`() {
        assertEquals("6 kts W", SpotDataCache.formatWindLabel(5.7, "W"))
        assertEquals("6 kts W", SpotDataCache.formatWindLabel(6.4, "W"))
        assertEquals("7 kts W", SpotDataCache.formatWindLabel(6.5, "W"))
        assertEquals("0 kts N", SpotDataCache.formatWindLabel(0.4, "N"))
    }

    // ---------- 4. gust >= speed is a warning, not a failure ----------

    @Test
    fun `gust below speed does not fail the payload`() {
        val now = Instant.now().toEpochMilli()
        val start = now - 6 * 3_600_000L
        // Model quirk: gust below sustained speed. Must still derive.
        val snapshot = deriveSnapshot(
            "contract-gust",
            hourlySeries(start, 13, speedKts = { 15.0 }, gustKts = { 12.0 })
        )
        val gust = snapshot.value.gustKnots
        assertNotNull(gust)
        if (gust < snapshot.value.speedKnots) {
            // WARNING by design — surfaced for humans, never a hard failure.
            println(
                "WARNING: gust ($gust kts) < speed (${snapshot.value.speedKnots} kts) " +
                    "— tolerated model quirk, monitor if frequent"
            )
        }
        assertTrue(snapshot.value.speedKnots > 0)
    }

    private companion object {
        val CARDINALS = setOf(
            "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"
        )
    }
}
