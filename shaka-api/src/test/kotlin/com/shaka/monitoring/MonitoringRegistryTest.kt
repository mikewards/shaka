package com.shaka.monitoring

import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * Mechanical enforcement of the monitoring registry (the sync-with-code teeth
 * from docs/synthetic-monitor-design.md):
 *
 * Every job name passed to scheduleJob/scheduleRegisteredJob and every name
 * reported to MonitoringService.reportRun/captureItemFailure/trackJob must
 * have a JobSpec in MonitoringConfig or be listed in registryExempt.
 *
 * The scheduled-name vs reporting-name mismatches (e.g. solunar_vessel_prefetch
 * reports as fishing_intel_prefetch) are exactly the drift trap this catches:
 * add or rename a job without updating the registry and this test fails the PR.
 */
class MonitoringRegistryTest {

    private fun mainSources(): Sequence<File> {
        // Gradle runs tests with the module dir as working directory.
        val root = File("src/main/kotlin")
        assertTrue(root.isDirectory, "expected to run from the shaka-api module dir (cwd=${File(".").absolutePath})")
        return root.walkTopDown().filter { it.isFile && it.extension == "kt" }
    }

    private fun findNames(pattern: Regex): Set<String> =
        mainSources().flatMap { f -> pattern.findAll(f.readText()).map { it.groupValues[1] } }.toSet()

    private val known: Set<String> =
        MonitoringConfig.jobs.map { it.name }.toSet() +
        MonitoringConfig.jobs.mapNotNull { it.scheduledName }.toSet() +
        MonitoringConfig.registryExempt

    @Test
    fun `every scheduled job is registered or exempt`() {
        val scheduled = findNames(Regex("""scheduleJob\(\s*(?:name\s*=\s*)?"([a-z0-9_]+)"""")) +
            findNames(Regex("""scheduleRegisteredJob\(\s*"([a-z0-9_]+)""""))
        val unknown = scheduled - known
        assertTrue(
            unknown.isEmpty(),
            "Scheduled jobs missing from MonitoringConfig (add a JobSpec or registryExempt entry " +
                "AND update monitoring/probe.py + docs/synthetic-monitor-design.md): $unknown"
        )
    }

    @Test
    fun `every reported job name is registered or exempt`() {
        val reported = findNames(Regex("""reportRun\(\s*"([a-z0-9_]+)"""")) +
            findNames(Regex("""captureItemFailure\(\s*"([a-z0-9_]+)"""")) +
            findNames(Regex("""trackJob\(\s*(?:jobName\s*=\s*)?"([a-z0-9_]+)""""))
        val unknown = reported - known
        assertTrue(
            unknown.isEmpty(),
            "Job names reported to MonitoringService but missing from MonitoringConfig " +
                "(add a JobSpec or registryExempt entry): $unknown"
        )
    }

    @Test
    fun `registry entries with a scheduledName are actually scheduled`() {
        val text = mainSources().joinToString("\n") { it.readText() }
        val missing = MonitoringConfig.jobs.mapNotNull { it.scheduledName }.filter { name ->
            !text.contains("scheduleRegisteredJob(\"$name\"") && !text.contains("scheduleJob(\"$name\"")
        }
        assertTrue(
            missing.isEmpty(),
            "JobSpecs whose scheduledName is never scheduled in Application.kt (stale registry?): $missing"
        )
    }

    @Test
    fun `exempt list does not overlap the registry`() {
        val overlap = MonitoringConfig.registryExempt.intersect(MonitoringConfig.jobs.map { it.name }.toSet())
        assertTrue(overlap.isEmpty(), "Names both registered and exempt: $overlap")
    }
}
