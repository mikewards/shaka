package com.shaka.monitoring

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Unit tests for the /health/summary severity policy. Pure logic — no I/O.
 * These encode the design decisions in docs/synthetic-monitor-design.md;
 * if you change a threshold or rule, change the doc and these together.
 */
class HealthSummaryTest {

    private val hourly = MonitoringConfig.jobByName("hourly_swell_wind")!!
    private val satellite = MonitoringConfig.jobByName("satellite_prefetch")!!

    // ---------- aggregation ----------

    @Test
    fun `overall severity is the worst cause`() {
        val causes = listOf(
            HealthSummaryLogic.dbCause(true),
            HealthSummaryLogic.upstreamCause("noaa", "error"),
        )
        assertEquals("degraded", HealthSummaryLogic.aggregate(causes, "t").severity)

        val withCritical = causes + HealthSummaryLogic.dbCause(false)
        assertEquals("critical", HealthSummaryLogic.aggregate(withCritical, "t").severity)
    }

    @Test
    fun `all ok aggregates to ok`() {
        val causes = listOf(HealthSummaryLogic.dbCause(true))
        assertEquals("ok", HealthSummaryLogic.aggregate(causes, "t").severity)
    }

    // ---------- job success-rate severity ----------

    @Test
    fun `hourly_swell_wind at 95 percent is degraded not critical`() {
        assertEquals(Severity.DEGRADED, HealthSummaryLogic.jobSuccessSeverity(hourly, 0.9503))
    }

    @Test
    fun `hourly_swell_wind total outage is critical`() {
        assertEquals(Severity.CRITICAL, HealthSummaryLogic.jobSuccessSeverity(hourly, 0.0))
    }

    @Test
    fun `hourly_swell_wind at 100 percent is ok`() {
        assertEquals(Severity.OK, HealthSummaryLogic.jobSuccessSeverity(hourly, 1.0))
    }

    // ---------- missed-run detection ----------

    @Test
    fun `satellite lastRun age of 30h is lawful (6h interval + 24h maxRun)`() {
        // Reviewer finding: 2x-interval detection would false-positive here.
        val thirtyHoursMs = 30L * 3_600_000
        val (sev, _) = HealthSummaryLogic.jobCause(
            spec = satellite, successRate = 1.0, succeeded = 100, total = 100,
            lastRunAgeMs = thirtyHoursMs, uptimeMs = Long.MAX_VALUE / 2, schedulersDisabled = false,
        )
        assertEquals(Severity.OK, sev)
    }

    @Test
    fun `satellite lastRun age past interval+maxRun+1h is degraded`() {
        val ageMs = MonitoringConfig.missedRunDegradedAfterMs(satellite) + 60_000
        val (sev, cause) = HealthSummaryLogic.jobCause(
            spec = satellite, successRate = 1.0, succeeded = 100, total = 100,
            lastRunAgeMs = ageMs, uptimeMs = Long.MAX_VALUE / 2, schedulersDisabled = false,
        )
        assertEquals(Severity.DEGRADED, sev)
        assertTrue(cause.observed.startsWith("lastRunAge="))
    }

    @Test
    fun `satellite lastRun age past 2x is critical even when last run succeeded`() {
        val ageMs = MonitoringConfig.missedRunCriticalAfterMs(satellite) + 60_000
        val (sev, _) = HealthSummaryLogic.jobCause(
            spec = satellite, successRate = 1.0, succeeded = 100, total = 100,
            lastRunAgeMs = ageMs, uptimeMs = Long.MAX_VALUE / 2, schedulersDisabled = false,
        )
        assertEquals(Severity.CRITICAL, sev)
    }

    @Test
    fun `never-reported job is ok during deploy grace, critical after`() {
        val grace = MonitoringConfig.deployGraceMs(satellite)
        val (during, _) = HealthSummaryLogic.jobCause(
            satellite, null, null, null, lastRunAgeMs = null,
            uptimeMs = grace - 1, schedulersDisabled = false,
        )
        assertEquals(Severity.OK, during)
        val (after, _) = HealthSummaryLogic.jobCause(
            satellite, null, null, null, lastRunAgeMs = null,
            uptimeMs = grace + 1, schedulersDisabled = false,
        )
        assertEquals(Severity.CRITICAL, after)
    }

    @Test
    fun `schedulers disabled reports ok regardless of state`() {
        val (sev, cause) = HealthSummaryLogic.jobCause(
            hourly, 0.0, 0, 825, lastRunAgeMs = null, uptimeMs = 0, schedulersDisabled = true,
        )
        assertEquals(Severity.OK, sev)
        assertEquals("schedulers disabled", cause.observed)
    }

    // ---------- freshness thresholds (lawful-max derivation) ----------

    @Test
    fun `freshness thresholds follow gate+interval+maxRun+1h`() {
        // swell: 0 + 24h + 24h + 1h = 49h
        assertEquals(49 * 60, MonitoringConfig.freshnessThresholdMinutes("swell"))
        // sst: 12 + 6 + 24 + 1 = 43h
        assertEquals(43 * 60, MonitoringConfig.freshnessThresholdMinutes("sst"))
        // vessel: 24h gate + 12h interval + 48h maxRun + 1h = 85h
        assertEquals(85 * 60, MonitoringConfig.freshnessThresholdMinutes("vessel"))
        // solunar shares the job but has a 12h gate: 12 + 12 + 48 + 1 = 73h
        assertEquals(73 * 60, MonitoringConfig.freshnessThresholdMinutes("solunar"))
        // mpa: 168 + 168 + 24 + 1 = 361h
        assertEquals(361 * 60, MonitoringConfig.freshnessThresholdMinutes("mpa"))
    }

    @Test
    fun `tide is never age-based`() {
        assertNull(MonitoringConfig.freshnessThresholdMinutes("tide"))
        assertTrue(!MonitoringConfig.isAgeBasedType("tide"))
    }

    @Test
    fun `vessel at lawful 36h age is not stale (old 25h threshold false-positived)`() {
        val cause = HealthSummaryLogic.freshnessCause("vessel", 36 * 60)
        assertNotNull(cause)
        assertEquals(Severity.OK, cause.first)
    }

    // ---------- tide horizon ----------

    @Test
    fun `tide horizon severity tiers`() {
        assertEquals(Severity.OK, HealthSummaryLogic.tideHorizonCause(300, 0.96).first)
        assertEquals(Severity.DEGRADED, HealthSummaryLogic.tideHorizonCause(29, 0.96).first)
        assertEquals(Severity.CRITICAL, HealthSummaryLogic.tideHorizonCause(6, 0.96).first)
        assertEquals(Severity.DEGRADED, HealthSummaryLogic.tideHorizonCause(300, 0.90).first)
        assertEquals(Severity.DEGRADED, HealthSummaryLogic.tideHorizonCause(null, null).first)
    }

    // ---------- AI insights ----------

    @Test
    fun `ai insights degraded only past grace with reports available`() {
        // populated slot -> ok
        assertEquals(Severity.OK, HealthSummaryLogic.aiInsightsCause(true, 23, true, true).first)
        // empty early in the day -> ok (generation attempts still coming)
        assertEquals(Severity.OK, HealthSummaryLogic.aiInsightsCause(false, 3, true, true).first)
        // empty past grace -> degraded
        assertEquals(Severity.DEGRADED, HealthSummaryLogic.aiInsightsCause(false, 9, true, true).first)
        // nothing to summarize -> ok
        assertEquals(Severity.OK, HealthSummaryLogic.aiInsightsCause(false, 23, false, true).first)
        // deliberately disabled -> ok, never an incident
        assertEquals(Severity.OK, HealthSummaryLogic.aiInsightsCause(false, 23, true, false).first)
    }

    @Test
    fun `ai insights never critical`() {
        for (hasToday in listOf(true, false)) for (h in listOf(0, 12, 23))
            for (reports in listOf(true, false)) for (enabled in listOf(true, false)) {
                val sev = HealthSummaryLogic.aiInsightsCause(hasToday, h, reports, enabled).first
                assertTrue(sev != Severity.CRITICAL)
            }
    }

    // ---------- upstreams ----------

    @Test
    fun `upstream failures are capped at degraded`() {
        assertEquals(Severity.DEGRADED, HealthSummaryLogic.upstreamCause("noaa", "error").first)
        assertEquals(Severity.OK, HealthSummaryLogic.upstreamCause("noaa", "ok").first)
    }
}
