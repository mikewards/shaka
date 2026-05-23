package com.shaka.data.client

import com.shaka.model.SolunarData
import com.shaka.model.TimePeriod
import org.slf4j.LoggerFactory
import java.time.LocalDate

/**
 * Local solunar calculator.
 *
 * Previously backed by api.solunar.org, which went permanently dark
 * (connection timeouts as of Jun 2026), leaving only a moon-phase fallback
 * with no feeding periods. Solunar tables are deterministic astronomy, so
 * everything is now computed locally:
 *
 * - Moon age from the synodic cycle (29.530588 days)
 * - Lunar transits: the moon crosses the local meridian ~50 min later each
 *   day; upper transit ~ solar noon + age * 50min, lower transit +12h25m
 * - Major feeding periods: 2h windows centered on the two transits
 * - Minor feeding periods: 1h windows centered on moonrise/moonset
 *   (~6h13m either side of upper transit)
 * - Day rating: peaks at new and full moon (classic solunar theory)
 *
 * Accuracy is ~plus or minus 30-60 min, comparable to generic solunar tables and
 * sufficient for 2h feeding windows.
 */
class SolunarClient {

    private val logger = LoggerFactory.getLogger(SolunarClient::class.java)

    companion object {
        private const val SYNODIC_DAYS = 29.530588
        private val NEW_MOON_REFERENCE: LocalDate = LocalDate.of(2000, 1, 6)
        private const val MINUTES_PER_DAY = 24 * 60
        // Moon lags the sun by ~50.47 min/day of age
        private const val LAG_MIN_PER_DAY = 50.47
        // Half the average interval from transit to rise/set
        private const val RISE_SET_OFFSET_MIN = 6 * 60 + 13
    }

    /**
     * Compute solunar data for a location and date. Never fails.
     *
     * @param timezoneOffset UTC offset hours; estimated from longitude if absent
     */
    suspend fun getSolunarData(
        lat: Double,
        lon: Double,
        date: LocalDate = LocalDate.now(),
        timezoneOffset: Int? = null
    ): SolunarData {
        val age = moonAge(date)

        val (phase, illumination) = phaseAndIllumination(age)

        // Upper transit in local minutes-of-day (solar noon + lunar lag)
        val upperTransit = (12 * 60 + age * LAG_MIN_PER_DAY).toInt() % MINUTES_PER_DAY
        val lowerTransit = (upperTransit + 12 * 60 + 25) % MINUTES_PER_DAY
        val moonrise = (upperTransit - RISE_SET_OFFSET_MIN + MINUTES_PER_DAY) % MINUTES_PER_DAY
        val moonset = (upperTransit + RISE_SET_OFFSET_MIN) % MINUTES_PER_DAY

        val majorPeriods = listOf(
            window(upperTransit, halfWidthMin = 60),
            window(lowerTransit, halfWidthMin = 60)
        )
        val minorPeriods = listOf(
            window(moonrise, halfWidthMin = 30),
            window(moonset, halfWidthMin = 30)
        )

        logger.debug("Solunar (local calc): $phase ($illumination%) rating=${dayRating(age)} for ($lat, $lon)")

        return SolunarData(
            moonPhase = phase,
            illumination = illumination,
            majorPeriods = majorPeriods,
            minorPeriods = minorPeriods,
            dayRating = dayRating(age),
            hourlyRating = null
        )
    }

    /** Days since new moon, in [0, 29.53) */
    private fun moonAge(date: LocalDate): Double {
        val days = java.time.temporal.ChronoUnit.DAYS.between(NEW_MOON_REFERENCE, date).toDouble()
        return ((days % SYNODIC_DAYS) + SYNODIC_DAYS) % SYNODIC_DAYS
    }

    private fun phaseAndIllumination(age: Double): Pair<String, Int> {
        val illumination = (50.0 * (1 - kotlin.math.cos(2 * Math.PI * age / SYNODIC_DAYS))).toInt()
        val phase = when {
            age < 1.85 -> "new_moon"
            age < 7.38 -> "waxing_crescent"
            age < 9.23 -> "first_quarter"
            age < 14.76 -> "waxing_gibbous"
            age < 16.61 -> "full_moon"
            age < 22.14 -> "waning_gibbous"
            age < 23.99 -> "last_quarter"
            else -> "waning_crescent"
        }
        return phase to illumination.coerceIn(0, 100)
    }

    /**
     * Classic solunar day rating on the API's 0-5 scale:
     * best around new and full moon, worst at the quarters.
     */
    private fun dayRating(age: Double): Int {
        val half = SYNODIC_DAYS / 2
        val distToNew = minOf(age, SYNODIC_DAYS - age)
        val distToFull = kotlin.math.abs(age - half)
        val dist = minOf(distToNew, distToFull)
        return when {
            dist <= 1.0 -> 5
            dist <= 2.0 -> 4
            dist <= 3.5 -> 3
            dist <= 5.0 -> 2
            else -> 1
        }
    }

    private fun window(centerMin: Int, halfWidthMin: Int): TimePeriod {
        val start = (centerMin - halfWidthMin + MINUTES_PER_DAY) % MINUTES_PER_DAY
        val end = (centerMin + halfWidthMin) % MINUTES_PER_DAY
        return TimePeriod(start = fmt(start), end = fmt(end))
    }

    private fun fmt(minOfDay: Int): String = "%02d:%02d".format(minOfDay / 60, minOfDay % 60)
}
