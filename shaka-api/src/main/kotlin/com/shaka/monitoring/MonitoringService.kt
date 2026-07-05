package com.shaka.monitoring

import io.sentry.Sentry
import io.sentry.SentryEvent
import io.sentry.SentryLevel
import io.sentry.protocol.Message
import org.slf4j.LoggerFactory
import org.slf4j.MDC
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.Duration
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap

data class ItemFailure(
    val itemId: String,
    val itemName: String,
    val error: String,
    val errorClass: String
)

data class JobRunResult(
    val jobName: String,
    val startedAt: Instant,
    val finishedAt: Instant,
    val total: Int,
    val succeeded: Int,
    val failures: List<ItemFailure>
) {
    val failed: Int get() = failures.size
    val durationMs: Long get() = finishedAt.toEpochMilli() - startedAt.toEpochMilli()
    val successRate: Double get() = if (total == 0) 1.0 else succeeded.toDouble() / total

    /** Per-job severity from MonitoringConfig (unknown jobs fall back to the old 0.99 rule). */
    val severity: Severity
        get() {
            val spec = MonitoringConfig.jobByName(jobName)
                ?: return if (successRate >= 0.99) Severity.OK else Severity.DEGRADED
            return HealthSummaryLogic.jobSuccessSeverity(spec, successRate)
        }

    /** Kept for backward compatibility with existing /health/jobs consumers. */
    val status: String get() = if (severity == Severity.OK) "OK" else "BREACH"
}

object MonitoringService {
    private val logger = LoggerFactory.getLogger(MonitoringService::class.java)

    private val latestRuns = ConcurrentHashMap<String, JobRunResult>()
    private val processStartMs: Long = System.currentTimeMillis()

    fun uptimeMs(): Long = System.currentTimeMillis() - processStartMs

    fun getLatestRun(jobName: String): JobRunResult? = latestRuns[jobName]
    fun getAllLatestRuns(): Map<String, JobRunResult> = latestRuns.toMap()

    // ---------- Postgres persistence (survives redeploys) ----------

    /** Create job_runs_latest and hydrate the in-memory map. Call once at boot. */
    fun initPersistence() {
        if (!com.shaka.data.db.DatabaseFactory.isConnected()) return
        try {
            org.jetbrains.exposed.sql.transactions.transaction {
                val conn = this.connection.connection as java.sql.Connection
                conn.createStatement().use { stmt ->
                    stmt.execute(
                        """
                        CREATE TABLE IF NOT EXISTS job_runs_latest (
                            job_name VARCHAR(60) PRIMARY KEY,
                            started_at TIMESTAMP NOT NULL,
                            finished_at TIMESTAMP NOT NULL,
                            total INT NOT NULL,
                            succeeded INT NOT NULL,
                            failed INT NOT NULL,
                            duration_ms BIGINT NOT NULL
                        )
                        """.trimIndent()
                    )
                }
                conn.prepareStatement("SELECT job_name, started_at, finished_at, total, succeeded, failed FROM job_runs_latest").use { stmt ->
                    val rs = stmt.executeQuery()
                    while (rs.next()) {
                        val name = rs.getString("job_name")
                        val result = JobRunResult(
                            jobName = name,
                            startedAt = rs.getTimestamp("started_at").toInstant(),
                            finishedAt = rs.getTimestamp("finished_at").toInstant(),
                            total = rs.getInt("total"),
                            succeeded = rs.getInt("succeeded"),
                            // Failure details are not persisted; synthesize placeholders so counts survive.
                            failures = List(rs.getInt("failed")) {
                                ItemFailure("persisted", "persisted", "details not persisted across deploys", "persisted")
                            },
                        )
                        latestRuns.putIfAbsent(name, result)
                    }
                }
            }
            logger.info("job_runs_latest hydrated: ${latestRuns.size} jobs")
        } catch (e: Exception) {
            logger.warn("job_runs_latest init failed (non-fatal): ${e.message}")
        }
    }

    private fun persistRun(result: JobRunResult) {
        if (!com.shaka.data.db.DatabaseFactory.isConnected()) return
        try {
            org.jetbrains.exposed.sql.transactions.transaction {
                val conn = this.connection.connection as java.sql.Connection
                conn.prepareStatement(
                    """
                    INSERT INTO job_runs_latest (job_name, started_at, finished_at, total, succeeded, failed, duration_ms)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT (job_name) DO UPDATE SET
                        started_at = EXCLUDED.started_at, finished_at = EXCLUDED.finished_at,
                        total = EXCLUDED.total, succeeded = EXCLUDED.succeeded,
                        failed = EXCLUDED.failed, duration_ms = EXCLUDED.duration_ms
                    """.trimIndent()
                ).use { stmt ->
                    stmt.setString(1, result.jobName)
                    stmt.setTimestamp(2, java.sql.Timestamp.from(result.startedAt))
                    stmt.setTimestamp(3, java.sql.Timestamp.from(result.finishedAt))
                    stmt.setInt(4, result.total)
                    stmt.setInt(5, result.succeeded)
                    stmt.setInt(6, result.failed)
                    stmt.setLong(7, result.durationMs)
                    stmt.executeUpdate()
                }
            }
        } catch (e: Exception) {
            logger.warn("job_runs_latest persist failed for ${result.jobName}: ${e.message}")
        }
    }

    private val betterStackUrl: String? = System.getenv("BETTERSTACK_SOURCE_URL")
    private val betterStackToken: String? = System.getenv("BETTERSTACK_SOURCE_TOKEN")

    private val heartbeatUrls: Map<String, String> by lazy {
        System.getenv("HEARTBEAT_URLS")?.split(",")
            ?.mapNotNull { entry ->
                val parts = entry.split("=", limit = 2)
                if (parts.size == 2) parts[0].trim() to parts[1].trim() else null
            }?.toMap() ?: emptyMap()
    }

    private val httpClient = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(5))
        .build()

    suspend fun <T> trackJob(
        jobName: String,
        items: List<T>,
        itemId: (T) -> String,
        itemName: (T) -> String = itemId,
        process: suspend (T) -> Unit
    ): JobRunResult {
        val startedAt = Instant.now()
        val failures = mutableListOf<ItemFailure>()
        var succeeded = 0

        for (item in items) {
            try {
                process(item)
                succeeded++
            } catch (e: Exception) {
                val id = itemId(item)
                val name = itemName(item)
                val errClass = classifyError(e)
                failures.add(ItemFailure(id, name, e.message ?: "unknown", errClass))

                Sentry.withScope { scope ->
                    scope.setTag("job", jobName)
                    scope.setTag("item_id", id)
                    scope.setTag("item_name", name)
                    scope.setTag("error_class", errClass)
                    scope.fingerprint = listOf(jobName, errClass)
                    Sentry.captureException(e)
                }
            }
        }

        val result = JobRunResult(
            jobName = jobName,
            startedAt = startedAt,
            finishedAt = Instant.now(),
            total = items.size,
            succeeded = succeeded,
            failures = failures
        )

        MDC.put("job", jobName)
        logger.info(
            "job_run event={} job={} total={} succeeded={} failed={} success_rate={} duration_ms={} status={}",
            "job_run", jobName, result.total, result.succeeded, result.failed,
            String.format("%.4f", result.successRate), result.durationMs, result.status
        )
        MDC.remove("job")

        latestRuns[jobName] = result
        persistRun(result)

        if (result.severity != Severity.OK) {
            reportBreach(result)
        }

        sendToBetterStack(result)
        pingHeartbeat(jobName)

        return result
    }

    private fun reportBreach(result: JobRunResult) {
        val topFailures = result.failures.take(10)
            .joinToString("\n  ") { "${it.itemName} (${it.itemId}): ${it.errorClass} — ${it.error.take(80)}" }

        val dominant = result.failures.groupBy { it.errorClass }
            .maxByOrNull { it.value.size }

        val pattern = if (dominant != null && dominant.value.size > result.failures.size / 2) {
            "Pattern: ${dominant.value.size}/${result.failures.size} failures are ${dominant.key}"
        } else {
            "Pattern: mixed failure types"
        }

        val msg = """
            |BREACH: ${result.jobName}  ${String.format("%.1f", result.successRate * 100)}%%  (${result.succeeded}/${result.total})
            |  $topFailures
            |$pattern
        """.trimMargin()

        logger.error(msg)

        Sentry.withScope { scope ->
            scope.setTag("job", result.jobName)
            scope.setTag("status", "BREACH")
            scope.setTag("success_rate", String.format("%.4f", result.successRate))
            scope.fingerprint = listOf("job_breach", result.jobName)
            val sentryEvent = SentryEvent().apply {
                message = Message().apply { this.message = "Job breach: ${result.jobName} at ${String.format("%.1f", result.successRate * 100)}%" }
                level = SentryLevel.ERROR
            }
            Sentry.captureEvent(sentryEvent)
        }
    }

    fun reportRun(jobName: String, total: Int, succeeded: Int, failures: List<ItemFailure>, durationMs: Long): JobRunResult {
        val now = Instant.now()
        val result = JobRunResult(
            jobName = jobName,
            startedAt = now.minusMillis(durationMs),
            finishedAt = now,
            total = total,
            succeeded = succeeded,
            failures = failures
        )

        MDC.put("job", jobName)
        logger.info(
            "job_run event={} job={} total={} succeeded={} failed={} success_rate={} duration_ms={} status={}",
            "job_run", jobName, result.total, result.succeeded, result.failed,
            String.format("%.4f", result.successRate), result.durationMs, result.status
        )
        MDC.remove("job")

        latestRuns[jobName] = result
        persistRun(result)

        if (result.severity != Severity.OK) {
            reportBreach(result)
        }

        sendToBetterStack(result)
        pingHeartbeat(jobName)

        return result
    }

    private fun sendToBetterStack(result: JobRunResult) {
        val url = betterStackUrl ?: return
        val token = betterStackToken ?: return
        try {
            val topErrors = result.failures.take(5).joinToString("; ") { "${it.itemName}: ${it.errorClass}" }
            val body = """{"dt":"${result.finishedAt}","message":"job_run ${result.jobName}: ${result.status}","job":"${result.jobName}","total":${result.total},"succeeded":${result.succeeded},"failed":${result.failed},"success_rate":${String.format("%.4f", result.successRate)},"duration_ms":${result.durationMs},"status":"${result.status}","top_errors":"${topErrors.replace("\"", "'")}"}"""
            val req = HttpRequest.newBuilder(URI.create(url))
                .POST(HttpRequest.BodyPublishers.ofString(body))
                .header("Content-Type", "application/json")
                .header("Authorization", "Bearer $token")
                .timeout(Duration.ofSeconds(5))
                .build()
            httpClient.sendAsync(req, HttpResponse.BodyHandlers.discarding())
        } catch (e: Exception) {
            logger.warn("Better Stack log send failed: ${e.message}")
        }
    }

    private fun pingHeartbeat(jobName: String) {
        val url = heartbeatUrls[jobName] ?: return
        try {
            val req = HttpRequest.newBuilder(URI.create(url))
                .GET()
                .timeout(Duration.ofSeconds(5))
                .build()
            httpClient.sendAsync(req, HttpResponse.BodyHandlers.discarding())
            logger.debug("Heartbeat pinged for $jobName")
        } catch (e: Exception) {
            logger.warn("Heartbeat ping failed for $jobName: ${e.message}")
        }
    }

    fun captureItemFailure(jobName: String, itemId: String, itemName: String, exception: Exception) {
        Sentry.withScope { scope ->
            scope.setTag("job", jobName)
            scope.setTag("item_id", itemId)
            scope.setTag("item_name", itemName)
            scope.setTag("error_class", classifyError(exception))
            scope.fingerprint = listOf(jobName, classifyError(exception))
            Sentry.captureException(exception)
        }
    }

    fun classifyError(e: Exception): String = when {
        e is java.net.SocketTimeoutException -> "timeout"
        e is java.net.ConnectException -> "connection_refused"
        e.message?.contains("429") == true -> "rate_limited"
        e.message?.contains("503") == true -> "http_503"
        e.message?.contains("500") == true -> "http_500"
        e.message?.contains("404") == true -> "http_404"
        e.message?.contains("timed out", ignoreCase = true) == true -> "timeout"
        else -> e.javaClass.simpleName.lowercase()
    }
}
