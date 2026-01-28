package com.shaka

import com.shaka.api.routes.configureRouting
import com.shaka.data.db.DatabaseFactory
import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.server.plugins.cors.routing.*
import io.ktor.server.plugins.statuspages.*
import io.ktor.http.*
import io.ktor.server.response.*
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory

private val logger = LoggerFactory.getLogger("Application")

fun main() {
    val port = System.getenv("PORT")?.toIntOrNull() ?: 8080
    logger.info("Starting Shaka API on port $port")
    
    embeddedServer(Netty, port = port, host = "0.0.0.0", module = Application::module)
        .start(wait = true)
}

fun Application.module() {
    // Initialize database connection
    initDatabase()
    
    install(CORS) {
        anyHost()
        allowMethod(HttpMethod.Get)
        allowMethod(HttpMethod.Post)
        allowMethod(HttpMethod.Options)
        allowHeader(HttpHeaders.ContentType)
        allowHeader(HttpHeaders.Authorization)
    }

    install(ContentNegotiation) {
        json(Json {
            prettyPrint = true
            isLenient = true
            ignoreUnknownKeys = true
        })
    }

    install(StatusPages) {
        exception<Throwable> { call, cause ->
            logger.error("Request failed: ${cause.message}", cause)
            call.respond(
                HttpStatusCode.InternalServerError,
                mapOf("error" to (cause.message ?: "Unknown error"))
            )
        }
    }

    configureRouting()
    
    logger.info("Shaka API initialized successfully")
}

private fun Application.initDatabase() {
    val dbUrl = System.getenv("DATABASE_URL")
    
    if (dbUrl.isNullOrBlank()) {
        logger.warn("DATABASE_URL not set - using in-memory database")
        return
    }
    
    try {
        val dbUser = System.getenv("DATABASE_USER") ?: "shaka"
        val dbPassword = System.getenv("DATABASE_PASSWORD") ?: ""
        
        logger.info("Connecting to PostgreSQL database...")
        DatabaseFactory.init(dbUrl, dbUser, dbPassword)
        logger.info("Database connection established successfully")
    } catch (e: Exception) {
        logger.error("Failed to connect to database: ${e.message}")
        logger.warn("Falling back to in-memory database")
    }
}
