package com.shaka.data.client

import kotlinx.serialization.Serializable
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

/**
 * Per-host request metrics for the shared HTTP client.
 *
 * Motivation (Jul 2026 outage): the shared client's per-route connection pool
 * wedged permanently for some hosts — every request failed with a connect
 * timeout for 12 days while egress was fine. Nothing surfaced it because there
 * were no per-host call metrics. This records every attempt through the shared
 * client so a recurrence is visible within one job cycle via /health/http.
 *
 * Observation only: never alters request behavior.
 */
object HttpClientMetrics {

    class HostStats {
        val attempts = AtomicLong()
        val successes = AtomicLong()
        val failures = AtomicLong()
        val totalLatencyMs = AtomicLong()
        val maxLatencyMs = AtomicLong()

        /** Consecutive connect-timeout-class failures with no intervening success. */
        val consecutiveConnectFailures = AtomicLong()

        val lastSuccessAt = AtomicReference<Instant?>(null)
        val lastFailureAt = AtomicReference<Instant?>(null)
        val lastError = AtomicReference<String?>(null)
        val failuresByClass = ConcurrentHashMap<String, AtomicLong>()
    }

    private val hosts = ConcurrentHashMap<String, HostStats>()

    private fun stats(host: String): HostStats = hosts.computeIfAbsent(host) { HostStats() }

    fun recordSuccess(host: String, latencyMs: Long) {
        val s = stats(host)
        s.attempts.incrementAndGet()
        s.successes.incrementAndGet()
        s.totalLatencyMs.addAndGet(latencyMs)
        s.maxLatencyMs.updateAndGet { maxOf(it, latencyMs) }
        s.consecutiveConnectFailures.set(0)
        s.lastSuccessAt.set(Instant.now())
    }

    fun recordFailure(host: String, latencyMs: Long, error: Throwable) {
        val s = stats(host)
        s.attempts.incrementAndGet()
        s.failures.incrementAndGet()
        s.totalLatencyMs.addAndGet(latencyMs)
        s.maxLatencyMs.updateAndGet { maxOf(it, latencyMs) }
        val errClass = classify(error)
        s.failuresByClass.computeIfAbsent(errClass) { AtomicLong() }.incrementAndGet()
        if (isConnectClass(errClass)) {
            s.consecutiveConnectFailures.incrementAndGet()
        } else {
            s.consecutiveConnectFailures.set(0)
        }
        s.lastFailureAt.set(Instant.now())
        s.lastError.set("$errClass: ${error.message?.take(160) ?: "no message"}")
    }

    /** Hosts whose consecutive connect-class failures reached [threshold]. */
    fun hostsWithConsecutiveConnectFailures(threshold: Long): Map<String, Long> =
        hosts.entries
            .filter { it.value.consecutiveConnectFailures.get() >= threshold }
            .associate { it.key to it.value.consecutiveConnectFailures.get() }

    private fun classify(e: Throwable): String = when {
        e is io.ktor.client.network.sockets.ConnectTimeoutException -> "connect_timeout"
        e is io.ktor.client.network.sockets.SocketTimeoutException -> "socket_timeout"
        e is java.net.ConnectException -> "connection_refused"
        e is java.net.UnknownHostException -> "unknown_host"
        e is io.ktor.client.plugins.HttpRequestTimeoutException -> "request_timeout"
        e.message?.contains("Connect timeout", ignoreCase = true) == true -> "connect_timeout"
        e.message?.contains("timed out", ignoreCase = true) == true -> "timeout"
        else -> e.javaClass.simpleName.lowercase()
    }

    private fun isConnectClass(errClass: String): Boolean =
        errClass == "connect_timeout" || errClass == "connection_refused"

    @Serializable
    data class HostMetricsSnapshot(
        val host: String,
        val attempts: Long,
        val successes: Long,
        val failures: Long,
        val consecutiveConnectFailures: Long,
        val avgLatencyMs: Long,
        val maxLatencyMs: Long,
        val failuresByClass: Map<String, Long>,
        val lastSuccessAt: String?,
        val lastFailureAt: String?,
        val lastError: String?,
    )

    @Serializable
    data class MetricsSnapshot(
        val generatedAt: String,
        val clientRecreations: Long,
        val hosts: List<HostMetricsSnapshot>,
    )

    /** Incremented by HttpClientFactory when the shared client is rebuilt. */
    val clientRecreations = AtomicLong()

    fun snapshot(): MetricsSnapshot = MetricsSnapshot(
        generatedAt = Instant.now().toString(),
        clientRecreations = clientRecreations.get(),
        hosts = hosts.entries.sortedBy { it.key }.map { (host, s) ->
            val attempts = s.attempts.get()
            HostMetricsSnapshot(
                host = host,
                attempts = attempts,
                successes = s.successes.get(),
                failures = s.failures.get(),
                consecutiveConnectFailures = s.consecutiveConnectFailures.get(),
                avgLatencyMs = if (attempts > 0) s.totalLatencyMs.get() / attempts else 0,
                maxLatencyMs = s.maxLatencyMs.get(),
                failuresByClass = s.failuresByClass.mapValues { it.value.get() },
                lastSuccessAt = s.lastSuccessAt.get()?.toString(),
                lastFailureAt = s.lastFailureAt.get()?.toString(),
                lastError = s.lastError.get(),
            )
        },
    )
}
