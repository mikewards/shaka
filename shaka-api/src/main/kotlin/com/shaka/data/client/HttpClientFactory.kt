package com.shaka.data.client

import io.ktor.client.*
import io.ktor.client.engine.cio.*
import io.ktor.client.plugins.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.plugins.logging.*
import io.ktor.client.request.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory

/**
 * Singleton HTTP client factory with enterprise-grade connection pooling.
 * 
 * All API clients MUST use this shared client instead of creating their own.
 * This prevents:
 * - Connection pool exhaustion
 * - Socket/file descriptor exhaustion  
 * - Memory bloat from duplicate client instances
 * - Thread pool proliferation
 * 
 * Configuration tuned for external API calls with proper timeouts and limits.
 */
object HttpClientFactory {
    
    private val logger = LoggerFactory.getLogger(HttpClientFactory::class.java)
    
    /**
     * Shared HTTP client instance.
     * 
     * Connection limits:
     * - 100 total connections max (prevents resource exhaustion)
     * - 10 connections per route (prevents hammering single API)
     * - 5s connect timeout (fail fast on unreachable hosts)
     * - 30s request timeout (allows for slow responses)
     * - 30s socket timeout (prevents hung connections)
     * 
     * All API clients should use this client.
     */
    @Volatile
    private var current: HttpClient? = null
    private val lock = Any()

    @Volatile
    private var lastRebuildMs = 0L

    /** Consecutive connect-class failures to one host before the watchdog suspects a wedged pool. */
    private const val WEDGE_THRESHOLD = 5L

    /** Minimum time between shared-client rebuilds. */
    private const val REBUILD_COOLDOWN_MS = 10 * 60_000L

    /**
     * The shared client. Consumers must read this per-request (property getter,
     * not a captured val) so a watchdog rebuild takes effect everywhere.
     */
    val shared: HttpClient
        get() = current ?: synchronized(lock) {
            current ?: buildClient().also {
                logger.info("Initializing shared HTTP client with connection pooling")
                current = it
            }
        }

    /**
     * Replace the shared client with a fresh instance.
     *
     * The old client is deliberately NOT closed: in-flight requests still hold
     * it, and closing would cancel them mid-call. Rebuilds are rare (wedge
     * detection only, cooldown-limited), so leaking one engine is the safe
     * trade-off.
     */
    fun rebuild(reason: String) {
        synchronized(lock) {
            logger.error("Recreating shared HTTP client: $reason")
            current = buildClient()
            lastRebuildMs = System.currentTimeMillis()
            HttpClientMetrics.clientRecreations.incrementAndGet()
            HttpClientMetrics.resetConsecutiveConnectFailures()
        }
    }

    /**
     * Pool-wedge watchdog (Jul 2026 outage hardening). If some host has
     * accumulated WEDGE_THRESHOLD consecutive connect-class failures through
     * the shared client, probe it with a fresh single-use client. If the
     * canary connects fine, the shared client's per-route pool is wedged
     * (slots leaked, connects time out forever) — rebuild the shared client.
     * If the canary also fails, it is a genuine upstream/network outage and
     * rebuilding would not help.
     */
    suspend fun watchdogTick() {
        val suspects = HttpClientMetrics.hostsWithConsecutiveConnectFailures(WEDGE_THRESHOLD)
        if (suspects.isEmpty()) return
        if (System.currentTimeMillis() - lastRebuildMs < REBUILD_COOLDOWN_MS) {
            logger.warn("HTTP pool watchdog: suspect hosts $suspects but rebuild cooldown active")
            return
        }
        val (host, streak) = suspects.entries.first()
        if (canaryProbe(host)) {
            rebuild("suspected wedged pool for $host ($streak consecutive connect failures on shared client, fresh canary connection succeeded)")
        } else {
            logger.warn("HTTP pool watchdog: $host has $streak consecutive connect failures and the canary also failed — genuine upstream/network issue, not rebuilding")
        }
    }

    /** True if a fresh single-use client can reach the host (any HTTP response counts). */
    private suspend fun canaryProbe(host: String): Boolean {
        val canary = HttpClient(CIO) {
            engine {
                endpoint {
                    connectTimeout = 5_000
                    socketTimeout = 5_000
                    requestTimeout = 8_000
                }
            }
        }
        return try {
            // expectSuccess is off: any HTTP status (even 4xx/5xx) proves
            // TCP/TLS connectivity, which is all the canary needs.
            canary.head("https://$host/")
            true
        } catch (e: Throwable) {
            false
        } finally {
            canary.close()
        }
    }

    private fun buildClient(): HttpClient {
        val client = HttpClient(CIO) {
            engine {
                // Total connection pool size
                maxConnectionsCount = 100
                
                // Per-host limits and timeouts
                endpoint {
                    maxConnectionsPerRoute = 10
                    keepAliveTime = 10_000        // 10s keep-alive
                    connectTimeout = 5_000         // 5s connect timeout
                    requestTimeout = 30_000        // 30s request timeout
                    socketTimeout = 30_000         // 30s socket timeout
                }
                
                // Connection retries on network failures
                requestTimeout = 30_000
            }
            
            // JSON serialization
            install(ContentNegotiation) {
                json(Json {
                    ignoreUnknownKeys = true
                    isLenient = true
                    prettyPrint = false  // Reduce memory in production
                })
            }
            
            // Minimal logging in production
            install(Logging) {
                logger = Logger.DEFAULT
                level = LogLevel.NONE  // Change to INFO/HEADERS for debugging
            }
        }

        // Per-host call metrics (observation only): records every attempt,
        // success, failure and latency by host so a wedged connection pool
        // (Jul 2026 outage: connect timeouts forever on some hosts) is visible
        // via /v1/health/http instead of being swallowed at debug level.
        client.plugin(HttpSend).intercept { request ->
            val host = request.url.host
            val startNs = System.nanoTime()
            try {
                val call = execute(request)
                HttpClientMetrics.recordSuccess(host, (System.nanoTime() - startNs) / 1_000_000)
                call
            } catch (e: Throwable) {
                HttpClientMetrics.recordFailure(host, (System.nanoTime() - startNs) / 1_000_000, e)
                throw e
            }
        }

        return client
    }
    
    /**
     * Gracefully close the HTTP client.
     * Call this on application shutdown.
     */
    fun close() {
        logger.info("Closing shared HTTP client")
        current?.close()
    }
    
}
