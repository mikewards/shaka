package com.shaka.fishing_intel.auth

import org.jsoup.Connection
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.slf4j.LoggerFactory
import java.util.concurrent.atomic.AtomicReference

/**
 * Session manager for BD Outdoors (Bloodydecks) forums.
 * Handles login and maintains session cookies for authenticated scraping.
 */
object BDOutdoorsSession {
    private val logger = LoggerFactory.getLogger(BDOutdoorsSession::class.java)
    
    private const val BASE_URL = "https://www.bdoutdoors.com/forums"
    private const val LOGIN_URL = "$BASE_URL/login/login"
    private const val USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    
    // Thread-safe cookie storage
    private val sessionCookies = AtomicReference<Map<String, String>>(emptyMap())
    private var lastLoginTime: Long = 0
    private val SESSION_TIMEOUT_MS = 3600_000L // 1 hour
    
    /**
     * Login to BD Outdoors and store session cookies.
     * Returns true if login successful.
     */
    fun login(username: String, password: String): Boolean {
        try {
            logger.info("Attempting BD Outdoors login...")
            
            // First, get the login page to capture CSRF token and initial cookies
            val loginPageResponse = Jsoup.connect("$BASE_URL/login/")
                .userAgent(USER_AGENT)
                .timeout(30_000)
                .method(Connection.Method.GET)
                .execute()
            
            val loginPage = loginPageResponse.parse()
            val initialCookies = loginPageResponse.cookies()
            
            // Find CSRF token (XenForo uses _xfToken)
            val xfToken = loginPage.select("input[name=_xfToken]").attr("value")
            logger.debug("Found xfToken: ${xfToken.take(20)}...")
            
            // Perform login POST
            val loginResponse = Jsoup.connect(LOGIN_URL)
                .userAgent(USER_AGENT)
                .timeout(30_000)
                .cookies(initialCookies)
                .data("login", username)
                .data("password", password)
                .data("_xfToken", xfToken)
                .data("remember", "1")
                .method(Connection.Method.POST)
                .followRedirects(false)
                .execute()
            
            // Merge cookies
            val allCookies = initialCookies.toMutableMap()
            allCookies.putAll(loginResponse.cookies())
            
            // Check if login succeeded (should redirect to forums or have xf_user cookie)
            val statusCode = loginResponse.statusCode()
            val hasUserCookie = allCookies.any { it.key.contains("xf_user") || it.key.contains("xf_session") }
            
            logger.info("Login response: status=$statusCode, hasUserCookie=$hasUserCookie, cookies=${allCookies.keys}")
            
            if (statusCode in 300..399 || hasUserCookie) {
                // Follow redirect to capture final cookies
                val redirectUrl = loginResponse.header("Location") ?: BASE_URL
                val finalResponse = Jsoup.connect(
                    if (redirectUrl.startsWith("http")) redirectUrl else "$BASE_URL$redirectUrl"
                )
                    .userAgent(USER_AGENT)
                    .cookies(allCookies)
                    .timeout(30_000)
                    .execute()
                
                allCookies.putAll(finalResponse.cookies())
                sessionCookies.set(allCookies)
                lastLoginTime = System.currentTimeMillis()
                
                logger.info("BD Outdoors login successful! Cookies: ${allCookies.keys}")
                return true
            }
            
            logger.warn("BD Outdoors login may have failed - no redirect or user cookie")
            return false
            
        } catch (e: Exception) {
            logger.error("BD Outdoors login failed: ${e.message}", e)
            return false
        }
    }
    
    /**
     * Check if we have a valid session.
     */
    fun hasValidSession(): Boolean {
        val cookies = sessionCookies.get()
        if (cookies.isEmpty()) return false
        if (System.currentTimeMillis() - lastLoginTime > SESSION_TIMEOUT_MS) return false
        return cookies.any { it.key.contains("xf_user") || it.key.contains("xf_session") }
    }
    
    /**
     * Fetch a page with authentication.
     */
    fun fetchAuthenticated(url: String): Document? {
        val cookies = sessionCookies.get()
        if (cookies.isEmpty()) {
            logger.warn("No session cookies - need to login first")
            return null
        }
        
        return try {
            Jsoup.connect(url)
                .userAgent(USER_AGENT)
                .cookies(cookies)
                .timeout(30_000)
                .get()
        } catch (e: Exception) {
            logger.error("Failed to fetch $url: ${e.message}")
            null
        }
    }
    
    /**
     * Get current session cookies for use with Jsoup connections.
     */
    fun getCookies(): Map<String, String> = sessionCookies.get()
}
