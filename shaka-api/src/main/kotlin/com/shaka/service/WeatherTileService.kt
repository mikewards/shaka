package com.shaka.service

import com.shaka.monitoring.MonitoringService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory
import java.io.File
import java.time.Duration
import java.time.Instant

@Serializable
data class VariableInfo(
    val timestamps: List<String> = emptyList(),
    val bounds: List<Double> = emptyList(),
)

@Serializable
data class WeatherCatalog(
    val generatedAt: String = "",
    val variables: Map<String, VariableInfo> = emptyMap(),
)

object WeatherTileService {
    private val logger = LoggerFactory.getLogger("WeatherTileService")
    private val dataDir = File(System.getenv("WEATHER_DATA_DIR") ?: "/data/weather")
    private val pipelineScript = System.getenv("WEATHER_PIPELINE_SCRIPT") ?: "/app/scripts/weather_pipeline.py"
    private val json = Json { ignoreUnknownKeys = true }
    
    @Volatile
    private var cachedCatalog: WeatherCatalog? = null
    
    @Volatile
    private var lastRun: Instant? = null

    fun getCatalog(): WeatherCatalog {
        cachedCatalog?.let { return it }
        return reloadCatalog()
    }

    fun getTileFile(variable: String, timestamp: String): File? {
        if (!variable.matches(Regex("[a-z_]+"))) return null
        if (!timestamp.matches(Regex("[0-9T\\-Z]+"))) return null
        val webp = File(dataDir, "$variable/$timestamp.webp")
        if (webp.exists() && webp.isFile) return webp
        val png = File(dataDir, "$variable/$timestamp.png")
        return if (png.exists() && png.isFile) png else null
    }

    suspend fun runPipeline() {
        if (!shouldRun()) {
            logger.info("Weather pipeline skipped (last run was recent)")
            return
        }
        
        logger.info("Starting weather data pipeline...")
        val startTime = System.currentTimeMillis()
        
        withContext(Dispatchers.IO) {
            try {
                dataDir.mkdirs()
                val process = ProcessBuilder(
                    "python3", pipelineScript,
                    "--output-dir", dataDir.absolutePath,
                    "--days", "5"
                )
                    .redirectErrorStream(true)
                    .start()

                val output = process.inputStream.bufferedReader().readText()
                val exitCode = process.waitFor()
                val elapsedMs = System.currentTimeMillis() - startTime

                if (exitCode == 0) {
                    logger.info("Weather pipeline completed in ${elapsedMs / 1000}s:\n$output")
                    lastRun = Instant.now()
                    reloadCatalog()
                    MonitoringService.reportRun("weather_tile_pipeline", 1, 1, emptyList(), elapsedMs)
                } else {
                    logger.error("Weather pipeline failed (exit=$exitCode, ${elapsedMs / 1000}s):\n$output")
                    val ex = Exception("Weather pipeline exit code $exitCode")
                    MonitoringService.captureItemFailure("weather_tile_pipeline", "pipeline", "weather_pipeline.py", ex)
                    MonitoringService.reportRun("weather_tile_pipeline", 1, 0, listOf(
                        com.shaka.monitoring.ItemFailure("pipeline", "weather_pipeline.py", "exit_code=$exitCode", "process_failed")
                    ), elapsedMs)
                }
            } catch (e: Exception) {
                logger.error("Weather pipeline exception: ${e.message}", e)
                MonitoringService.captureItemFailure("weather_tile_pipeline", "pipeline", "weather_pipeline.py", e)
            }
        }
    }

    private fun reloadCatalog(): WeatherCatalog {
        val catalogFile = File(dataDir, "catalog.json")
        if (!catalogFile.exists()) {
            logger.debug("No catalog.json found at ${catalogFile.absolutePath}")
            return WeatherCatalog()
        }
        return try {
            val raw = catalogFile.readText()
            val fileGeneratedAt = Instant.ofEpochMilli(catalogFile.lastModified()).toString()
            // Current shape: {"generatedAt": ..., "variables": {...}}. Older
            // flat shapes (var -> info, or var -> [timestamps]) still parse.
            val root = json.parseToJsonElement(raw)
            val catalog = if (root is kotlinx.serialization.json.JsonObject && root.containsKey("variables")) {
                val wrapped = json.decodeFromString<WeatherCatalog>(raw)
                if (wrapped.generatedAt.isNotBlank()) wrapped else wrapped.copy(generatedAt = fileGeneratedAt)
            } else {
                val variables = try {
                    json.decodeFromString<Map<String, VariableInfo>>(raw)
                } catch (_: Exception) {
                    val legacy = json.decodeFromString<Map<String, List<String>>>(raw)
                    legacy.mapValues { VariableInfo(timestamps = it.value) }
                }
                WeatherCatalog(generatedAt = fileGeneratedAt, variables = variables)
            }
            cachedCatalog = catalog
            catalog
        } catch (e: Exception) {
            logger.error("Failed to parse catalog.json: ${e.message}")
            WeatherCatalog()
        }
    }

    suspend fun forcePipeline() {
        lastRun = null
        runPipeline()
    }

    private fun shouldRun(): Boolean {
        val last = lastRun ?: return true
        return Duration.between(last, Instant.now()).toHours() >= 6
    }
}
