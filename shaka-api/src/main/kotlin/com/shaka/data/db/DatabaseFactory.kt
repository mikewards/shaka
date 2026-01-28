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
     * Initialize with explicit connection parameters (for testing).
     */
    fun init(url: String, user: String, password: String) {
        val hikariConfig = HikariConfig().apply {
            jdbcUrl = url
            driverClassName = "org.postgresql.Driver"
            username = user
            this.password = password
            maximumPoolSize = 5
            isAutoCommit = false
            transactionIsolation = "TRANSACTION_REPEATABLE_READ"
            validate()
        }

        dataSource = HikariDataSource(hikariConfig)
        Database.connect(dataSource!!)

        transaction {
            SchemaUtils.create(SpotsTable, ReportsTable)
        }
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
