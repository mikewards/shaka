package com.shaka.config

import org.slf4j.LoggerFactory

/**
 * Startup environment validation.
 *
 * Logs one loud, greppable summary of which expected variables are set.
 * Several outages went unnoticed partly because missing/renamed env vars
 * degrade features silently (e.g. Copernicus creds, AI keys).
 */
object EnvValidation {

    private val logger = LoggerFactory.getLogger(EnvValidation::class.java)

    private val required = listOf(
        "DATABASE_URL" to "PostgreSQL persistence (in-memory fallback without it)",
    )

    private val optional = listOf(
        "COPERNICUS_CLIENT_ID" to "Copernicus CDSE OAuth (realtime clarity)",
        "COPERNICUS_CLIENT_SECRET" to "Copernicus CDSE OAuth (realtime clarity)",
        "COPERNICUSMARINE_SERVICE_USERNAME" to "CMEMS weather tile pipeline",
        "COPERNICUSMARINE_SERVICE_PASSWORD" to "CMEMS weather tile pipeline",
        "TIDE_SOURCE" to "Tide provider selection (noaa|fes2022)",
        "TIDE_SERVICE_URL" to "FES2022 tide microservice (required if TIDE_SOURCE=fes2022)",
        "FISHING_INTEL_AI_ENABLED" to "AI-generated region insights",
        "FISHING_INTEL_AI_API_KEY" to "Groq API key for AI insights",
        "GFW_API_TOKEN" to "Global Fishing Watch vessel data",
        "SENTRY_DSN" to "Error tracking",
        "BETTERSTACK_SOURCE_URL" to "Log shipping",
        "BETTERSTACK_SOURCE_TOKEN" to "Log shipping",
        "HEARTBEAT_URLS" to "Job heartbeat pings",
        "DISABLE_SCHEDULED_JOBS" to "CI/local mode: skip all background jobs (never set in prod)",
    )

    fun validateAndReport() {
        val missingRequired = required.filter { System.getenv(it.first).isNullOrBlank() }
        val missingOptional = optional.filter { System.getenv(it.first).isNullOrBlank() }

        for ((name, purpose) in missingRequired) {
            logger.error("ENV MISSING (required): $name -- $purpose")
        }
        for ((name, purpose) in missingOptional) {
            logger.warn("ENV missing (optional): $name -- $purpose; feature degraded")
        }
        val setCount = (required + optional).size - missingRequired.size - missingOptional.size
        logger.info(
            "Env validation: $setCount/${(required + optional).size} expected vars set, " +
            "${missingRequired.size} required missing, ${missingOptional.size} optional missing"
        )

        // TIDE_SOURCE=fes2022 without a service URL means tides silently die
        if (System.getenv("TIDE_SOURCE")?.lowercase() == "fes2022" &&
            System.getenv("TIDE_SERVICE_URL").isNullOrBlank()
        ) {
            logger.error("ENV INCONSISTENT: TIDE_SOURCE=fes2022 but TIDE_SERVICE_URL is not set")
        }
    }
}
