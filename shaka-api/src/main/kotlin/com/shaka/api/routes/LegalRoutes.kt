package com.shaka.api.routes

import com.shaka.data.db.LegalAcceptanceRepository
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.serialization.Serializable

/**
 * Public legal pages, served as static HTML from classpath resources
 * (src/main/resources/legal/). Registered at the root level (outside the
 * "/v1" API prefix) so the App Store Privacy Policy URL is a clean public
 * link: https://<host>/legal/privacy
 */
private fun loadLegalHtml(name: String): String? =
    object {}.javaClass.classLoader
        .getResourceAsStream("legal/$name")
        ?.bufferedReader()
        ?.use { it.readText() }

private suspend fun ApplicationCall.respondLegal(resourceName: String) {
    val html = loadLegalHtml(resourceName)
    if (html == null) {
        respondText("Not found", ContentType.Text.Plain, HttpStatusCode.NotFound)
    } else {
        response.header(HttpHeaders.CacheControl, "public, max-age=3600")
        respondText(html, ContentType.Text.Html)
    }
}

fun Route.legalRoutes() {
    route("/legal") {
        get { call.respondLegal("index.html") }
        get("/privacy") { call.respondLegal("privacy.html") }
        get("/terms") { call.respondLegal("terms.html") }
    }
}

@Serializable
data class RecordAcceptanceRequest(
    val legalVersion: String,
    val appVersion: String? = null,
    val platform: String? = null
)

@Serializable
data class AcceptanceResponse(
    val id: String,
    val legalVersion: String,
    val acceptedAt: String,
    val appVersion: String? = null,
    val platform: String? = null
)

/**
 * Server-side legal acceptance records. Registered under /v1. Identified by
 * the anonymous X-Device-ID header (same model as /v1/user-spots).
 */
fun Route.legalAcceptanceRoutes(repo: LegalAcceptanceRepository) {
    route("/legal/acceptances") {
        post {
            val deviceId = call.request.header("X-Device-ID")
                ?: return@post call.respond(
                    HttpStatusCode.BadRequest,
                    mapOf("error" to "X-Device-ID header required")
                )
            val req = try {
                call.receive<RecordAcceptanceRequest>()
            } catch (e: Exception) {
                return@post call.respond(
                    HttpStatusCode.BadRequest,
                    mapOf("error" to "Invalid request body")
                )
            }
            if (req.legalVersion.isBlank()) {
                return@post call.respond(
                    HttpStatusCode.BadRequest,
                    mapOf("error" to "legalVersion required")
                )
            }
            val rec = repo.record(deviceId, req.legalVersion, req.appVersion, req.platform)
                ?: return@post call.respond(
                    HttpStatusCode.InternalServerError,
                    mapOf("error" to "Failed to record acceptance")
                )
            call.respond(
                AcceptanceResponse(
                    id = rec.id.toString(),
                    legalVersion = rec.legalVersion,
                    acceptedAt = rec.acceptedAt.toString(),
                    appVersion = rec.appVersion,
                    platform = rec.platform
                )
            )
        }

        get("/latest") {
            val deviceId = call.request.header("X-Device-ID")
                ?: return@get call.respond(
                    HttpStatusCode.BadRequest,
                    mapOf("error" to "X-Device-ID header required")
                )
            val rec = repo.latestForDevice(deviceId)
                ?: return@get call.respond(
                    HttpStatusCode.NotFound,
                    mapOf("error" to "No acceptance found")
                )
            call.respond(
                AcceptanceResponse(
                    id = rec.id.toString(),
                    legalVersion = rec.legalVersion,
                    acceptedAt = rec.acceptedAt.toString(),
                    appVersion = rec.appVersion,
                    platform = rec.platform
                )
            )
        }
    }
}
