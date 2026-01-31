package com.shaka.data.client

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.slf4j.LoggerFactory
import java.time.Instant
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/**
 * Circuit breaker pattern implementation for external API calls.
 * 
 * Prevents cascade failures by failing fast when an API is down.
 * 
 * States:
 * - CLOSED: Normal operation, requests pass through
 * - OPEN: API is down, requests fail immediately (no network call)
 * - HALF_OPEN: Testing if API recovered, allows one request through
 * 
 * Usage:
 * ```
 * val breaker = CircuitBreaker("copernicus")
 * 
 * val result = breaker.execute {
 *     httpClient.get(url)  // Only called if circuit is closed
 * }
 * ```
 */
class CircuitBreaker(
    private val name: String,
    private val failureThreshold: Int = 5,        // Failures before opening
    private val successThreshold: Int = 2,        // Successes to close from half-open
    private val resetTimeoutMs: Long = 60_000     // Time before trying again (1 minute)
) {
    private val logger = LoggerFactory.getLogger("CircuitBreaker.$name")
    
    enum class State { CLOSED, OPEN, HALF_OPEN }
    
    private val state = AtomicReference(State.CLOSED)
    private val failureCount = AtomicInteger(0)
    private val successCount = AtomicInteger(0)
    private val lastFailureTime = AtomicReference<Instant?>(null)
    private val mutex = Mutex()
    
    /**
     * Execute a block with circuit breaker protection.
     * 
     * @param block The suspending function to execute (e.g., HTTP request)
     * @return The result of the block, or null if circuit is open
     * @throws CircuitBreakerOpenException if circuit is open
     */
    suspend fun <T> execute(block: suspend () -> T): T {
        // Check if we should allow the request
        when (state.get()) {
            State.OPEN -> {
                // Check if we should transition to half-open
                val lastFailure = lastFailureTime.get()
                if (lastFailure != null && 
                    Instant.now().toEpochMilli() - lastFailure.toEpochMilli() > resetTimeoutMs) {
                    
                    mutex.withLock {
                        if (state.get() == State.OPEN) {
                            logger.info("Circuit transitioning to HALF_OPEN after timeout")
                            state.set(State.HALF_OPEN)
                            successCount.set(0)
                        }
                    }
                } else {
                    logger.debug("Circuit OPEN - failing fast")
                    throw CircuitBreakerOpenException(name)
                }
            }
            State.HALF_OPEN -> {
                logger.debug("Circuit HALF_OPEN - allowing test request")
            }
            State.CLOSED -> {
                // Normal operation
            }
        }
        
        // Execute the block
        return try {
            val result = block()
            onSuccess()
            result
        } catch (e: Exception) {
            onFailure(e)
            throw e
        }
    }
    
    /**
     * Execute with fallback when circuit is open.
     * 
     * @param block The suspending function to execute
     * @param fallback Value to return if circuit is open
     * @return The result of the block, or fallback if circuit is open
     */
    suspend fun <T> executeWithFallback(fallback: T, block: suspend () -> T): T {
        return try {
            execute(block)
        } catch (e: CircuitBreakerOpenException) {
            fallback
        }
    }
    
    /**
     * Check if requests can pass through (circuit is not fully open).
     */
    fun allowsRequests(): Boolean {
        val currentState = state.get()
        if (currentState == State.OPEN) {
            val lastFailure = lastFailureTime.get()
            if (lastFailure != null && 
                Instant.now().toEpochMilli() - lastFailure.toEpochMilli() > resetTimeoutMs) {
                return true  // Would transition to half-open
            }
            return false
        }
        return true
    }
    
    /**
     * Get current circuit state.
     */
    fun getState(): State = state.get()
    
    /**
     * Get statistics about the circuit breaker.
     */
    fun getStats(): Map<String, Any> = mapOf(
        "name" to name,
        "state" to state.get().name,
        "failureCount" to failureCount.get(),
        "successCount" to successCount.get(),
        "failureThreshold" to failureThreshold,
        "lastFailure" to (lastFailureTime.get()?.toString() ?: "none")
    )
    
    /**
     * Manually reset the circuit breaker to closed state.
     */
    fun reset() {
        logger.info("Circuit manually reset to CLOSED")
        state.set(State.CLOSED)
        failureCount.set(0)
        successCount.set(0)
        lastFailureTime.set(null)
    }
    
    private suspend fun onSuccess() {
        when (state.get()) {
            State.HALF_OPEN -> {
                val count = successCount.incrementAndGet()
                if (count >= successThreshold) {
                    mutex.withLock {
                        if (state.get() == State.HALF_OPEN) {
                            logger.info("Circuit transitioning to CLOSED after $count successes")
                            state.set(State.CLOSED)
                            failureCount.set(0)
                            successCount.set(0)
                        }
                    }
                }
            }
            State.CLOSED -> {
                // Reset failure count on success
                failureCount.set(0)
            }
            else -> {}
        }
    }
    
    private suspend fun onFailure(e: Exception) {
        lastFailureTime.set(Instant.now())
        
        when (state.get()) {
            State.HALF_OPEN -> {
                mutex.withLock {
                    if (state.get() == State.HALF_OPEN) {
                        logger.warn("Circuit transitioning to OPEN after failure in HALF_OPEN: ${e.message}")
                        state.set(State.OPEN)
                    }
                }
            }
            State.CLOSED -> {
                val count = failureCount.incrementAndGet()
                if (count >= failureThreshold) {
                    mutex.withLock {
                        if (state.get() == State.CLOSED) {
                            logger.warn("Circuit transitioning to OPEN after $count failures")
                            state.set(State.OPEN)
                        }
                    }
                }
            }
            else -> {}
        }
    }
}

/**
 * Exception thrown when circuit breaker is open and not allowing requests.
 */
class CircuitBreakerOpenException(val circuitName: String) : 
    Exception("Circuit breaker '$circuitName' is OPEN - failing fast")
