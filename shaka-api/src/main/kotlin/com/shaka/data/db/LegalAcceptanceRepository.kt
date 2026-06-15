package com.shaka.data.db

import org.jetbrains.exposed.dao.id.UUIDTable
import org.jetbrains.exposed.sql.*
import org.jetbrains.exposed.sql.SqlExpressionBuilder.eq
import org.jetbrains.exposed.sql.javatime.datetime
import org.slf4j.LoggerFactory
import java.time.LocalDateTime
import java.util.UUID

/**
 * Append-only record that an install accepted the Terms/Privacy. This is the
 * authoritative (court-grade) proof of assent; the app keeps a local mirror
 * only for the first-launch gate. Keyed to the anonymous device id — no
 * name/email/account, and intentionally NO IP or user-agent.
 */
object LegalAcceptancesTable : UUIDTable("legal_acceptances") {
    val deviceId: Column<String> = varchar("device_id", 64)
    val legalVersion: Column<String> = varchar("legal_version", 32)
    val document: Column<String> = varchar("document", 32).default("tos_privacy")
    val acceptedAt: Column<LocalDateTime> = datetime("accepted_at").default(LocalDateTime.now())
    val appVersion: Column<String?> = varchar("app_version", 32).nullable()
    val platform: Column<String?> = varchar("platform", 16).nullable()
}

class LegalAcceptanceRepository {

    private val logger = LoggerFactory.getLogger(LegalAcceptanceRepository::class.java)

    data class AcceptanceRecord(
        val id: UUID,
        val deviceId: String,
        val legalVersion: String,
        val document: String,
        val acceptedAt: LocalDateTime,
        val appVersion: String?,
        val platform: String?
    )

    /** Create the table if it doesn't exist (idempotent). */
    suspend fun createTableIfNotExists() {
        if (!DatabaseFactory.isConnected()) return
        try {
            DatabaseFactory.dbQuery {
                SchemaUtils.create(LegalAcceptancesTable)
            }
        } catch (e: Exception) {
            logger.warn("Failed to create legal_acceptances table: ${e.message}")
        }
    }

    /** Append a new acceptance row. Returns the created record, or null on failure. */
    suspend fun record(
        deviceId: String,
        legalVersion: String,
        appVersion: String?,
        platform: String?
    ): AcceptanceRecord? {
        return try {
            if (!DatabaseFactory.isConnected()) {
                logger.warn("Database not connected, cannot record legal acceptance")
                return null
            }
            DatabaseFactory.dbQuery {
                val now = LocalDateTime.now()
                val id = LegalAcceptancesTable.insertAndGetId {
                    it[LegalAcceptancesTable.deviceId] = deviceId
                    it[LegalAcceptancesTable.legalVersion] = legalVersion
                    it[LegalAcceptancesTable.acceptedAt] = now
                    it[LegalAcceptancesTable.appVersion] = appVersion
                    it[LegalAcceptancesTable.platform] = platform
                }.value
                AcceptanceRecord(id, deviceId, legalVersion, "tos_privacy", now, appVersion, platform)
            }
        } catch (e: Exception) {
            logger.error("Failed to record legal acceptance: ${e.message}")
            null
        }
    }

    /** The device's most recent acceptance, if any. */
    suspend fun latestForDevice(deviceId: String): AcceptanceRecord? {
        return try {
            if (!DatabaseFactory.isConnected()) return null
            DatabaseFactory.dbQuery {
                LegalAcceptancesTable.selectAll()
                    .where { LegalAcceptancesTable.deviceId eq deviceId }
                    .orderBy(LegalAcceptancesTable.acceptedAt, SortOrder.DESC)
                    .limit(1)
                    .map { row ->
                        AcceptanceRecord(
                            id = row[LegalAcceptancesTable.id].value,
                            deviceId = row[LegalAcceptancesTable.deviceId],
                            legalVersion = row[LegalAcceptancesTable.legalVersion],
                            document = row[LegalAcceptancesTable.document],
                            acceptedAt = row[LegalAcceptancesTable.acceptedAt],
                            appVersion = row[LegalAcceptancesTable.appVersion],
                            platform = row[LegalAcceptancesTable.platform]
                        )
                    }
                    .firstOrNull()
            }
        } catch (e: Exception) {
            logger.warn("Failed to read latest legal acceptance: ${e.message}")
            null
        }
    }
}
