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
                FishingIntelReportGeosTable,
                FishingIntelRegionInsightsTable
            )
            val conn = this.connection.connection as java.sql.Connection
            addReportColumnsIfMissing(conn)
            addSourceColumnsIfMissing(conn)
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

    private fun addSourceColumnsIfMissing(conn: Connection) {
        try {
            conn.createStatement().execute("ALTER TABLE fishing_intel_sources ADD COLUMN IF NOT EXISTS regional_report VARCHAR(50) DEFAULT 'so_cal'")
            conn.createStatement().execute("UPDATE fishing_intel_sources SET regional_report = 'so_cal' WHERE regional_report IS NULL OR regional_report = ''")
        } catch (e: Exception) {
            logger.warn("Fishing intel sources regional_report migration: ${e.message}")
        }
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
     * Active sources: only bd-outdoors (ingested via external scraper POST endpoint).
     * All per-boat aggregator sources (socal-fish-reports, san-diego-fish-reports,
     * 22nd-street, fishermans-landing, seaforth) are disabled to prevent double-counting.
     */
    private val ACTIVE_SOURCES = setOf("bd-outdoors")

    /**
     * Seed initial data sources (upsert — safe to call on every startup).
     * Data is NOT wiped; the replace-on-scrape logic in the scraper handles freshness.
     */
    fun seedSources() {
        transaction {
            val sources = listOf(
                SourceConfig("bd-outdoors", "BD Outdoors Forums", "https://www.bdoutdoors.com/forums/", TrustTier.B, 0.5, "so_cal")
            )
            
            sources.forEach { source ->
                FishingIntelSourcesTable.insertIgnore {
                    it[sourceId] = source.id
                    it[name] = source.name
                    it[baseUrl] = source.baseUrl
                    it[trustTier] = source.trustTier.name[0]
                    it[rateLimitRps] = source.rateLimitRps.toBigDecimal()
                    it[enabled] = true
                    it[regionalReport] = source.regionalReport
                }
            }
            logger.info("Seeded ${sources.size} active sources")

            // Disable retired sources so their existing data is excluded from queries
            val disabled = FishingIntelSourcesTable.update(
                where = { FishingIntelSourcesTable.sourceId notInList ACTIVE_SOURCES }
            ) {
                it[enabled] = false
            }
            if (disabled > 0) {
                logger.info("Disabled $disabled retired sources")
            }
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
     * Wipe ALL fishing intel data. Clean slate.
     * Deletes claims, report_geos, reports, raw_pages, and region_insights.
     * Sources table is preserved (just the config, not data).
     */
    fun deleteAllIntelData() {
        transaction {
            val conn = this.connection.connection as java.sql.Connection
            val tables = listOf(
                "fishing_intel_claims",
                "fishing_intel_report_geos",
                "fishing_intel_reports",
                "fishing_intel_raw_pages",
                "fishing_intel_region_insights"
            )
            for (table in tables) {
                try {
                    val count = conn.createStatement().executeUpdate("DELETE FROM $table")
                    logger.info("Wiped $count rows from $table")
                } catch (e: Exception) {
                    logger.warn("Failed to wipe $table: ${e.message}")
                }
            }
            logger.info("All fishing intel data wiped — clean slate")
        }
    }

    /**
     * Delete DOCK_TOTAL reports for a specific source and published_at date.
     * Used by the scraper for replace-on-scrape: delete old report, then insert fresh one.
     * Deletes child rows (claims, report_geos) first.
     */
    fun deleteReportsForSourceAndDate(sourceId: String, publishedAt: LocalDateTime, reportType: String = "DOCK_TOTAL") {
        transaction {
            val conn = this.connection.connection as java.sql.Connection
            // Find matching report IDs
            val reportIds = FishingIntelReportsTable
                .slice(FishingIntelReportsTable.id)
                .select {
                    (FishingIntelReportsTable.sourceId eq sourceId) and
                    (FishingIntelReportsTable.publishedAt eq publishedAt) and
                    (FishingIntelReportsTable.reportType eq reportType)
                }
                .map { it[FishingIntelReportsTable.id].value }

            if (reportIds.isEmpty()) return@transaction

            // Delete child rows then reports
            for (id in reportIds) {
                conn.prepareStatement("DELETE FROM fishing_intel_claims WHERE report_id = ?").use { it.setInt(1, id); it.executeUpdate() }
                conn.prepareStatement("DELETE FROM fishing_intel_report_geos WHERE report_id = ?").use { it.setInt(1, id); it.executeUpdate() }
                conn.prepareStatement("DELETE FROM fishing_intel_reports WHERE report_id = ?").use { it.setInt(1, id); it.executeUpdate() }
            }
            logger.debug("Replaced ${reportIds.size} $reportType report(s) for $sourceId @ $publishedAt")
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
     * Backfill REGION_FALLBACK geo for every report that has no row in fishing_intel_report_geos.
     * Ensures all reports (any source) are visible to getReportsNearby. Call at startup or after bulk ingest.
     */
    fun backfillAllMissingGeos(defaultLat: Double = 32.7157, defaultLon: Double = -117.1611, radiusM: Int = 150_000): Int {
        return transaction {
            val allReportIds = FishingIntelReportsTable
                .slice(FishingIntelReportsTable.id)
                .selectAll()
                .map { it[FishingIntelReportsTable.id].value }
            val reportIdsWithGeo = FishingIntelReportGeosTable
                .slice(FishingIntelReportGeosTable.reportId)
                .selectAll()
                .map { it[FishingIntelReportGeosTable.reportId] }
                .toSet()
            val missing = allReportIds.filter { it !in reportIdsWithGeo }
            missing.forEach { reportId ->
                FishingIntelReportGeosTable.insert {
                    it[FishingIntelReportGeosTable.reportId] = reportId
                    it[FishingIntelReportGeosTable.latitude] = defaultLat
                    it[FishingIntelReportGeosTable.longitude] = defaultLon
                    it[FishingIntelReportGeosTable.geoType] = GeoType.REGION_FALLBACK.name
                    it[FishingIntelReportGeosTable.radiusM] = radiusM
                }
            }
            if (missing.isNotEmpty()) {
                logger.info("Backfilled geo for ${missing.size} reports (all sources)")
            }
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
            
            // Get full reports with claims (only from enabled/active sources)
            val enabledSourceIds = FishingIntelSourcesTable
                .slice(FishingIntelSourcesTable.sourceId)
                .select { FishingIntelSourcesTable.enabled eq true }
                .map { it[FishingIntelSourcesTable.sourceId] }

            FishingIntelReportsTable
                .select { 
                    (FishingIntelReportsTable.id inList reportIds) and
                    (FishingIntelReportsTable.publishedAt greaterEq cutoff) and
                    (FishingIntelReportsTable.sourceId inList enabledSourceIds)
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
                        observedAt = row[FishingIntelReportsTable.observedAt]?.toInstant(ZoneOffset.UTC),
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
     * Get reports for a region (filter by sources.regional_report). No geo/lat/lon.
     * Used for the Reports tab; when adding other geos, set regional_report per source.
     */
    fun getReportsForRegion(regionId: String, hoursBack: Int): List<ReportWithClaims> {
        return transaction {
            val cutoff = LocalDateTime.now().minusHours(hoursBack.toLong())
            val reportIds = FishingIntelReportsTable
                .innerJoin(FishingIntelSourcesTable)
                .slice(FishingIntelReportsTable.id)
                .select {
                    (FishingIntelReportsTable.sourceId eq FishingIntelSourcesTable.sourceId) and
                    (FishingIntelSourcesTable.regionalReport eq regionId) and
                    (FishingIntelSourcesTable.enabled eq true) and
                    (FishingIntelReportsTable.publishedAt greaterEq cutoff)
                }
                .map { it[FishingIntelReportsTable.id].value }
                .distinct()

            if (reportIds.isEmpty()) return@transaction emptyList()

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
                        observedAt = row[FishingIntelReportsTable.observedAt]?.toInstant(ZoneOffset.UTC),
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
                        rateLimitRps = row[FishingIntelSourcesTable.rateLimitRps].toDouble(),
                        regionalReport = row[FishingIntelSourcesTable.regionalReport]
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

    /**
     * Get persisted key insights for a region and time slot (e.g. "2025-02-08_morning").
     * Returns null if not found.
     */
    fun getRegionInsights(regionId: String, slotKey: String): List<String>? {
        return transaction {
            val rid = regionId
            val sk = slotKey
            val row = FishingIntelRegionInsightsTable.select {
                (FishingIntelRegionInsightsTable.regionId eq rid) and
                (FishingIntelRegionInsightsTable.slotKey eq sk)
            }.singleOrNull() ?: return@transaction null
            val raw = row[FishingIntelRegionInsightsTable.insightsJson]
            raw.split("\n").map { it.trim() }.filter { it.isNotEmpty() }
        }
    }

    /**
     * Persist key insights for a region and time slot so they stay the same until the next slot.
     */
    fun setRegionInsights(regionId: String, slotKey: String, insights: List<String>) {
        transaction {
            val conn = this.connection.connection as java.sql.Connection
            conn.prepareStatement("DELETE FROM fishing_intel_region_insights WHERE region_id = ? AND slot_key = ?").use { stmt ->
                stmt.setString(1, regionId)
                stmt.setString(2, slotKey)
                stmt.executeUpdate()
            }
            FishingIntelRegionInsightsTable.insert {
                it[FishingIntelRegionInsightsTable.regionId] = regionId
                it[FishingIntelRegionInsightsTable.slotKey] = slotKey
                it[FishingIntelRegionInsightsTable.insightsJson] = insights.joinToString("\n")
            }
        }
    }
}
