package com.shaka.fishing_intel.db

import com.shaka.fishing_intel.models.*
import com.shaka.fishing_intel.processing.SoCalLandings
import org.jetbrains.exposed.sql.*
import org.jetbrains.exposed.sql.transactions.transaction
import java.sql.Connection
import org.slf4j.LoggerFactory
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneOffset

/**
 * Database operations for Fishing Intel feature.
 * Uses the existing database connection (DatabaseFactory must be initialized).
 */
object FishingIntelDb {
    private val logger = LoggerFactory.getLogger(FishingIntelDb::class.java)
    
    /**
     * Create all fishing intel tables if they don't exist.
     * Safe to call multiple times.
     */
    fun createTablesIfNotExists() {
        transaction {
            SchemaUtils.create(
                FishingIntelSourcesTable,
                FishingIntelRawPagesTable,
                FishingIntelReportsTable,
                FishingIntelClaimsTable,
                FishingIntelLandingsTable,
                FishingIntelReportGeosTable
            )
            val conn = this.connection.connection as java.sql.Connection
            addReportColumnsIfMissing(conn)
            logger.info("Fishing intel tables created/verified")
        }
    }

    private fun addReportColumnsIfMissing(conn: Connection) {
        // Use IF NOT EXISTS for all so one "already exists" doesn't abort the transaction and block later columns (e.g. tldr).
        val alters = listOf(
            "ALTER TABLE fishing_intel_reports ADD COLUMN IF NOT EXISTS thread_zone VARCHAR(50)",
            "ALTER TABLE fishing_intel_reports ADD COLUMN IF NOT EXISTS content_type VARCHAR(30)",
            "ALTER TABLE fishing_intel_reports ADD COLUMN IF NOT EXISTS last_activity_at TIMESTAMP",
            "ALTER TABLE fishing_intel_reports ADD COLUMN IF NOT EXISTS thread_url VARCHAR(512)",
            "ALTER TABLE fishing_intel_reports ADD COLUMN IF NOT EXISTS tldr TEXT",
            "ALTER TABLE fishing_intel_reports ADD COLUMN IF NOT EXISTS is_catch_intel BOOLEAN"
        )
        alters.forEach { sql ->
            try {
                conn.createStatement().execute(sql)
            } catch (e: Exception) {
                logger.warn("Fishing intel report column migration: ${e.message}")
            }
        }
        try {
            conn.createStatement().execute("CREATE INDEX IF NOT EXISTS fishing_intel_reports_thread_url_idx ON fishing_intel_reports(thread_url)")
        } catch (e: Exception) {
            logger.warn("thread_url index: ${e.message}")
        }
        logger.info("Fishing intel reports columns verified")
    }
    
    /**
     * Seed landings gazetteer with SoCal landings.
     */
    fun seedLandings() {
        transaction {
            SoCalLandings.ALL.forEach { landing ->
                FishingIntelLandingsTable.insertIgnore {
                    it[name] = landing.name
                    it[normalizedName] = landing.normalizedName
                    it[city] = landing.city
                    it[latitude] = landing.lat
                    it[longitude] = landing.lon
                    it[defaultRadiusKm] = landing.radiusKm
                }
            }
            logger.info("Seeded ${SoCalLandings.ALL.size} landings")
        }
    }
    
    /**
     * Seed initial data sources.
     */
    fun seedSources() {
        transaction {
            val sources = listOf(
                SourceConfig("socal-fish-reports", "SoCalFishReports", "https://www.socalfishreports.com", TrustTier.B, 1.0),
                SourceConfig("san-diego-fish-reports", "SanDiegoFishReports", "https://www.sandiegofishreports.com", TrustTier.B, 1.0),
                SourceConfig("976-tuna", "976-TUNA", "https://www.976-tuna.com", TrustTier.B, 1.0),
                SourceConfig("976-tuna-longrange", "976-TUNA Long Range", "https://www.976-tuna.com", TrustTier.B, 1.0),
                SourceConfig("22nd-street", "22nd Street Landing", "https://www.22ndstreet.com", TrustTier.A, 0.5),
                SourceConfig("fishermans-landing", "Fisherman's Landing", "https://www.fishermanslanding.com", TrustTier.A, 0.5),
                SourceConfig("seaforth", "Seaforth Sportfishing", "https://www.seaforthlanding.com", TrustTier.A, 0.5),
                SourceConfig("bd-outdoors", "BD Outdoors Forums", "https://www.bdoutdoors.com/forums/", TrustTier.B, 0.5)
            )
            
            sources.forEach { source ->
                FishingIntelSourcesTable.insertIgnore {
                    it[sourceId] = source.id
                    it[name] = source.name
                    it[baseUrl] = source.baseUrl
                    it[trustTier] = source.trustTier.name[0]
                    it[rateLimitRps] = source.rateLimitRps.toBigDecimal()
                    it[enabled] = true
                }
            }
            logger.info("Seeded ${sources.size} sources")
        }
    }
    
    /**
     * Save a raw HTML page snapshot.
     */
    fun saveRawPage(sourceId: String, url: String, html: String, httpStatus: Int, etag: String?, lastModified: String?): Int {
        return transaction {
            val sha256 = java.security.MessageDigest.getInstance("SHA-256")
                .digest(html.toByteArray())
                .joinToString("") { "%02x".format(it) }
            
            FishingIntelRawPagesTable.insertAndGetId {
                it[FishingIntelRawPagesTable.sourceId] = sourceId
                it[FishingIntelRawPagesTable.url] = url
                it[FishingIntelRawPagesTable.httpStatus] = httpStatus
                it[FishingIntelRawPagesTable.etag] = etag
                it[FishingIntelRawPagesTable.lastModified] = lastModified
                it[FishingIntelRawPagesTable.htmlBlob] = html
                it[FishingIntelRawPagesTable.sha256] = sha256
            }.value
        }
    }
    
    /**
     * Save a parsed report.
     */
    fun saveReport(report: FishingReport): Int {
        return transaction {
            FishingIntelReportsTable.insertAndGetId {
                it[sourceId] = report.sourceId
                it[url] = report.url
                it[publishedAt] = report.publishedAt?.let { ts -> LocalDateTime.ofInstant(ts, ZoneOffset.UTC) }
                it[observedAt] = report.observedAt?.let { ts -> LocalDateTime.ofInstant(ts, ZoneOffset.UTC) }
                it[reportType] = report.reportType.name
                it[title] = report.title
                it[rawExcerpt] = report.rawExcerpt
                it[canonicalFingerprint] = report.fingerprint
                it[confidence] = report.confidence.toBigDecimal()
                report.threadZone?.let { v -> it[threadZone] = v }
                report.contentType?.let { v -> it[contentType] = v }
                report.lastActivityAt?.let { ts -> it[lastActivityAt] = LocalDateTime.ofInstant(ts, ZoneOffset.UTC) }
                report.threadUrl?.let { v -> it[threadUrl] = v.take(512) }
                report.tldr?.let { v -> it[tldr] = v }
                report.isCatchIntel?.let { v -> it[isCatchIntel] = v }
            }.value
        }
    }
    
    /**
     * Save a claim extracted from a report.
     */
    fun saveClaim(reportId: Int, claim: FishingClaim) {
        transaction {
            FishingIntelClaimsTable.insert {
                it[FishingIntelClaimsTable.reportId] = reportId
                it[claimType] = claim.claimType.name
                it[species] = claim.species
                it[countKept] = claim.countKept
                it[countReleased] = claim.countReleased
                it[baitType] = claim.baitType
                it[baitStatus] = claim.baitStatus
                it[tripType] = claim.tripType
                it[anglerCount] = claim.anglerCount
                it[boatName] = claim.boatName
                it[landingName] = claim.landingName
                it[landingCity] = claim.landingCity
                it[notes] = claim.notes
            }
        }
    }
    
    /**
     * Save a geotag for a report.
     */
    fun saveReportGeo(reportId: Int, lat: Double, lon: Double, geoType: GeoType, radiusM: Int) {
        transaction {
            FishingIntelReportGeosTable.insert {
                it[FishingIntelReportGeosTable.reportId] = reportId
                it[latitude] = lat
                it[longitude] = lon
                it[FishingIntelReportGeosTable.geoType] = geoType.name
                it[FishingIntelReportGeosTable.radiusM] = radiusM
            }
        }
    }
    
    /**
     * Delete all reports for a source (e.g. bd-outdoors). Use to clear bad/old data before re-ingest.
     * Deletes child rows (claims, report_geos) first so it works even without ON DELETE CASCADE.
     */
    fun deleteReportsBySource(source: String): Int {
        return transaction {
            val conn = this.connection.connection as java.sql.Connection
            conn.prepareStatement("DELETE FROM fishing_intel_claims WHERE report_id IN (SELECT report_id FROM fishing_intel_reports WHERE source_id = ?)").use { stmt ->
                stmt.setString(1, source)
                stmt.executeUpdate()
            }
            conn.prepareStatement("DELETE FROM fishing_intel_report_geos WHERE report_id IN (SELECT report_id FROM fishing_intel_reports WHERE source_id = ?)").use { stmt ->
                stmt.setString(1, source)
                stmt.executeUpdate()
            }
            conn.prepareStatement("DELETE FROM fishing_intel_reports WHERE source_id = ?").use { stmt ->
                stmt.setString(1, source)
                stmt.executeUpdate()
            }
        }
    }

    /**
     * Backfill default SoCal geo for any BD Outdoors report that has no row in fishing_intel_report_geos.
     * Call once (e.g. on startup or migration) so all BD reports are eligible for getReportsNearby.
     */
    fun backfillBdOutdoorsGeos(): Int {
        return transaction {
            val bdReportIds = FishingIntelReportsTable
                .slice(FishingIntelReportsTable.id)
                .select { FishingIntelReportsTable.sourceId eq "bd-outdoors" }
                .map { it[FishingIntelReportsTable.id].value }
            val reportIdsWithGeo = FishingIntelReportGeosTable
                .slice(FishingIntelReportGeosTable.reportId)
                .selectAll()
                .map { it[FishingIntelReportGeosTable.reportId] }
                .toSet()
            val missing = bdReportIds.filter { it !in reportIdsWithGeo }
            missing.forEach { reportId ->
                FishingIntelReportGeosTable.insert {
                    it[FishingIntelReportGeosTable.reportId] = reportId
                    it[FishingIntelReportGeosTable.latitude] = 32.7157
                    it[FishingIntelReportGeosTable.longitude] = -117.1611
                    it[FishingIntelReportGeosTable.geoType] = GeoType.REGION_FALLBACK.name
                    it[FishingIntelReportGeosTable.radiusM] = 150000
                }
            }
            logger.info("Backfilled geo for ${missing.size} BD Outdoors reports")
            missing.size
        }
    }

    /**
     * Check if a report fingerprint already exists.
     */
    fun fingerprintExists(fingerprint: String): Boolean {
        return transaction {
            FishingIntelReportsTable.select { FishingIntelReportsTable.canonicalFingerprint eq fingerprint }
                .count() > 0
        }
    }
    
    /**
     * Get reports near a location within a time window.
     * Note: Uses simple bounding box instead of PostGIS for compatibility.
     */
    fun getReportsNearby(lat: Double, lon: Double, radiusKm: Int, hoursBack: Int): List<ReportWithClaims> {
        return transaction {
            val cutoff = LocalDateTime.now().minusHours(hoursBack.toLong())
            
            // Convert radius to approximate degrees (1 degree ~ 111km at equator)
            val latDelta = radiusKm / 111.0
            val lonDelta = radiusKm / (111.0 * kotlin.math.cos(Math.toRadians(lat)))
            
            // Find reports with geos in bounding box
            val reportIds = FishingIntelReportGeosTable
                .slice(FishingIntelReportGeosTable.reportId)
                .select {
                    (FishingIntelReportGeosTable.latitude greaterEq (lat - latDelta)) and
                    (FishingIntelReportGeosTable.latitude lessEq (lat + latDelta)) and
                    (FishingIntelReportGeosTable.longitude greaterEq (lon - lonDelta)) and
                    (FishingIntelReportGeosTable.longitude lessEq (lon + lonDelta))
                }
                .map { it[FishingIntelReportGeosTable.reportId] }
                .distinct()
            
            if (reportIds.isEmpty()) return@transaction emptyList()
            
            // Get full reports with claims
            FishingIntelReportsTable
                .select { 
                    (FishingIntelReportsTable.id inList reportIds) and
                    (FishingIntelReportsTable.publishedAt greaterEq cutoff)
                }
                .orderBy(FishingIntelReportsTable.publishedAt, SortOrder.DESC)
                .map { row ->
                    val reportId = row[FishingIntelReportsTable.id].value
                    val claims = FishingIntelClaimsTable
                        .select { FishingIntelClaimsTable.reportId eq reportId }
                        .map { claimRow ->
                            FishingClaim(
                                claimType = ClaimType.valueOf(claimRow[FishingIntelClaimsTable.claimType]),
                                species = claimRow[FishingIntelClaimsTable.species],
                                countKept = claimRow[FishingIntelClaimsTable.countKept],
                                countReleased = claimRow[FishingIntelClaimsTable.countReleased],
                                baitType = claimRow[FishingIntelClaimsTable.baitType],
                                baitStatus = claimRow[FishingIntelClaimsTable.baitStatus],
                                tripType = claimRow[FishingIntelClaimsTable.tripType],
                                anglerCount = claimRow[FishingIntelClaimsTable.anglerCount],
                                boatName = claimRow[FishingIntelClaimsTable.boatName],
                                landingName = claimRow[FishingIntelClaimsTable.landingName],
                                landingCity = claimRow[FishingIntelClaimsTable.landingCity],
                                notes = claimRow[FishingIntelClaimsTable.notes]
                            )
                        }
                    
                    ReportWithClaims(
                        reportId = reportId,
                        sourceId = row[FishingIntelReportsTable.sourceId],
                        url = row[FishingIntelReportsTable.url],
                        publishedAt = row[FishingIntelReportsTable.publishedAt]?.toInstant(ZoneOffset.UTC),
                        reportType = ReportType.valueOf(row[FishingIntelReportsTable.reportType]),
                        title = row[FishingIntelReportsTable.title],
                        rawExcerpt = row[FishingIntelReportsTable.rawExcerpt],
                        confidence = row[FishingIntelReportsTable.confidence].toDouble(),
                        threadUrl = row[FishingIntelReportsTable.threadUrl],
                        threadZone = row[FishingIntelReportsTable.threadZone],
                        canonicalFingerprint = row[FishingIntelReportsTable.canonicalFingerprint],
                        tldr = row[FishingIntelReportsTable.tldr],
                        isCatchIntel = row[FishingIntelReportsTable.isCatchIntel],
                        lastActivityAt = row[FishingIntelReportsTable.lastActivityAt]?.toInstant(ZoneOffset.UTC),
                        claims = claims
                    )
                }
        }
    }
    
    /**
     * Get enabled sources.
     */
    fun getEnabledSources(): List<SourceConfig> {
        return transaction {
            FishingIntelSourcesTable.select { FishingIntelSourcesTable.enabled eq true }
                .map { row ->
                    val tierChar = row[FishingIntelSourcesTable.trustTier]
                    SourceConfig(
                        id = row[FishingIntelSourcesTable.sourceId],
                        name = row[FishingIntelSourcesTable.name],
                        baseUrl = row[FishingIntelSourcesTable.baseUrl],
                        trustTier = when (tierChar) {
                            'A' -> TrustTier.A
                            'B' -> TrustTier.B
                            else -> TrustTier.C
                        },
                        rateLimitRps = row[FishingIntelSourcesTable.rateLimitRps].toDouble()
                    )
                }
        }
    }
    
    /**
     * Update source last successful fetch timestamp.
     */
    fun updateSourceLastFetch(sourceId: String) {
        transaction {
            FishingIntelSourcesTable.update({ FishingIntelSourcesTable.sourceId eq sourceId }) {
                it[lastSuccessfulFetch] = LocalDateTime.now()
            }
        }
    }
    
    /**
     * Toggle source enabled status.
     */
    fun toggleSource(sourceId: String, enabled: Boolean) {
        transaction {
            FishingIntelSourcesTable.update({ FishingIntelSourcesTable.sourceId eq sourceId }) {
                it[FishingIntelSourcesTable.enabled] = enabled
            }
        }
    }
    
    /**
     * Get source health stats with report and claim counts.
     */
    fun getSourceStats(): List<Map<String, Any?>> {
        return transaction {
            FishingIntelSourcesTable.selectAll().map { row ->
                val sourceId = row[FishingIntelSourcesTable.sourceId]
                
                // Count reports for this source
                val reportCount = FishingIntelReportsTable
                    .select { FishingIntelReportsTable.sourceId eq sourceId }
                    .count()
                    .toInt()
                
                // Count claims for this source (via reports)
                val claimCount = FishingIntelClaimsTable
                    .innerJoin(FishingIntelReportsTable)
                    .select { FishingIntelReportsTable.sourceId eq sourceId }
                    .count()
                    .toInt()
                
                mapOf<String, Any?>(
                    "sourceId" to sourceId,
                    "name" to row[FishingIntelSourcesTable.name],
                    "enabled" to row[FishingIntelSourcesTable.enabled],
                    "lastSuccessfulFetch" to row[FishingIntelSourcesTable.lastSuccessfulFetch]?.toString(),
                    "reportCount" to reportCount,
                    "claimCount" to claimCount
                )
            }
        }
    }
}
