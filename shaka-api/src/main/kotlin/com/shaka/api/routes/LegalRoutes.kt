package com.shaka.api.routes

import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

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
