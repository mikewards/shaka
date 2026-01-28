package com.shaka.data.db

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import io.ktor.server.config.*
import kotlinx.coroutines.Dispatchers
import org.jetbrains.exposed.sql.Database
import org.jetbrains.exposed.sql.SchemaUtils
import org.jetbrains.exposed.sql.transactions.experimental.newSuspendedTransaction
import org.jetbrains.exposed.sql.transactions.transaction
import org.slf4j.LoggerFactory

/**
 * Database connection factory using HikariCP for connection pooling.
 * Configures PostgreSQL + PostGIS for spatial queries.
 */
object DatabaseFactory {

    private val logger = LoggerFactory.getLogger(DatabaseFactory::class.java)
    private var dataSource: HikariDataSource? = null

    /**
     * Initialize the database connection from application config.
     */
    fun init(config: ApplicationConfig) {
        val dbConfig = config.config("database")
        val url = dbConfig.property("url").getString()
        val driver = dbConfig.property("driver").getString()
        val user = dbConfig.property("user").getString()
        val password = dbConfig.propertyOrNull("password")?.getString() ?: ""

        logger.info("Initializing database connection to: ${url.substringBefore("?")}")

        val hikariConfig = HikariConfig().apply {
            jdbcUrl = url
            driverClassName = driver
            username = user
            this.password = password
            maximumPoolSize = 10
            minimumIdle = 2
            idleTimeout = 60000
            connectionTimeout = 30000
            maxLifetime = 1800000
            isAutoCommit = false
            transactionIsolation = "TRANSACTION_REPEATABLE_READ"
            validate()
        }

        dataSource = HikariDataSource(hikariConfig)
        Database.connect(dataSource!!)

        // Create tables if they don't exist
        transaction {
            SchemaUtils.create(SpotsTable, ReportsTable)
        }

        logger.info("Database connection initialized successfully")
    }

    /**
     * Initialize with Railway DATABASE_URL format.
     * Parses: postgresql://user:password@host:port/database
     */
    fun init(url: String, userOverride: String, passwordOverride: String) {
        // Parse Railway URL format: postgresql://user:pass@host:port/database
        val parsed = parseRailwayUrl(url)
        
        val jdbcUrl = "jdbc:postgresql://${parsed.host}:${parsed.port}/${parsed.database}"
        val dbUser = userOverride.ifBlank { parsed.user }
        val dbPassword = passwordOverride.ifBlank { parsed.password }
        
        logger.info("Connecting to database at ${parsed.host}:${parsed.port}/${parsed.database}")
        
        val hikariConfig = HikariConfig().apply {
            this.jdbcUrl = jdbcUrl
            driverClassName = "org.postgresql.Driver"
            username = dbUser
            this.password = dbPassword
            maximumPoolSize = 5
            minimumIdle = 1
            connectionTimeout = 30000
            isAutoCommit = false
            transactionIsolation = "TRANSACTION_REPEATABLE_READ"
            validate()
        }

        dataSource = HikariDataSource(hikariConfig)
        Database.connect(dataSource!!)
        
        logger.info("Database connected, creating tables if needed...")

        transaction {
            SchemaUtils.create(SpotsTable, ReportsTable)
        }
        
        logger.info("Database initialization complete")
    }
    
    /**
     * Parse Railway DATABASE_URL format.
     * Format: postgresql://user:password@host:port/database
     */
    private data class DbConnectionInfo(
        val host: String,
        val port: Int,
        val database: String,
        val user: String,
        val password: String
    )
    
    private fun parseRailwayUrl(url: String): DbConnectionInfo {
        // Remove protocol prefix
        val withoutProtocol = url
            .removePrefix("postgresql://")
            .removePrefix("postgres://")
            .removePrefix("jdbc:postgresql://")
        
        // Split into credentials@hostInfo
        val atIndex = withoutProtocol.lastIndexOf("@")
        if (atIndex == -1) {
            throw IllegalArgumentException("Invalid DATABASE_URL format - missing @")
        }
        
        val credentials = withoutProtocol.substring(0, atIndex)
        val hostInfo = withoutProtocol.substring(atIndex + 1)
        
        // Parse credentials (user:password)
        val colonIndex = credentials.indexOf(":")
        val user = if (colonIndex != -1) credentials.substring(0, colonIndex) else credentials
        val password = if (colonIndex != -1) credentials.substring(colonIndex + 1) else ""
        
        // Parse hostInfo (host:port/database)
        val slashIndex = hostInfo.indexOf("/")
        val hostPort = if (slashIndex != -1) hostInfo.substring(0, slashIndex) else hostInfo
        val database = if (slashIndex != -1) hostInfo.substring(slashIndex + 1).substringBefore("?") else "railway"
        
        val portColonIndex = hostPort.lastIndexOf(":")
        val host = if (portColonIndex != -1) hostPort.substring(0, portColonIndex) else hostPort
        val port = if (portColonIndex != -1) hostPort.substring(portColonIndex + 1).toIntOrNull() ?: 5432 else 5432
        
        return DbConnectionInfo(host, port, database, user, password)
    }

    /**
     * Execute a database query within a coroutine context.
     */
    suspend fun <T> dbQuery(block: suspend () -> T): T =
        newSuspendedTransaction(Dispatchers.IO) { block() }

    /**
     * Close the database connection pool.
     */
    fun close() {
        dataSource?.close()
        logger.info("Database connection pool closed")
    }

    /**
     * Check if database is connected.
     */
    fun isConnected(): Boolean = dataSource?.isRunning == true
}
