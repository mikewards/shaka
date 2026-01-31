package com.shaka.data.client

import io.ktor.client.*
import io.ktor.client.engine.cio.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.plugins.logging.*
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
    val shared: HttpClient by lazy {
        logger.info("Initializing shared HTTP client with connection pooling")
        
        HttpClient(CIO) {
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
    }
    
    /**
     * Gracefully close the HTTP client.
     * Call this on application shutdown.
     */
    fun close() {
        logger.info("Closing shared HTTP client")
        shared.close()
    }
    
}
