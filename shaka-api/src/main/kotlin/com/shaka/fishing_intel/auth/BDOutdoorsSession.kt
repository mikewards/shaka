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
    
    // Store last login debug info
    var lastLoginDebug: String = ""
        private set
    
    /**
     * Login to BD Outdoors and store session cookies.
     * Returns true if login successful.
     */
    fun login(username: String, password: String): Boolean {
        val debug = StringBuilder()
        try {
            debug.appendLine("Attempting BD Outdoors login with user: $username")
            logger.info("Attempting BD Outdoors login...")
            
            // First, get the login page to capture CSRF token and initial cookies
            debug.appendLine("Fetching login page: $BASE_URL/login/")
            val loginPageResponse = Jsoup.connect("$BASE_URL/login/")
                .userAgent(USER_AGENT)
                .timeout(30_000)
                .method(Connection.Method.GET)
                .execute()
            
            val loginPage = loginPageResponse.parse()
            val initialCookies = loginPageResponse.cookies()
            debug.appendLine("Initial cookies: ${initialCookies.keys}")
            
            // Find CSRF token (XenForo uses _xfToken)
            val xfToken = loginPage.select("input[name=_xfToken]").attr("value")
            debug.appendLine("Found xfToken: ${if (xfToken.isNotEmpty()) xfToken.take(30) + "..." else "EMPTY!"}")
            
            // Debug: show all form inputs we found
            val formInputs = loginPage.select("form input").map { "${it.attr("name")}=${it.attr("type")}" }
            debug.appendLine("Form inputs found: $formInputs")
            
            // Find the actual form action URL
            val formAction = loginPage.select("form[action*=login]").attr("action")
            debug.appendLine("Form action: $formAction")
            
            val actualLoginUrl = if (formAction.isNotEmpty() && formAction.startsWith("http")) {
                formAction
            } else if (formAction.isNotEmpty()) {
                "https://www.bdoutdoors.com$formAction"
            } else {
                LOGIN_URL
            }
            debug.appendLine("Using login URL: $actualLoginUrl")
            
            // Perform login POST
            val loginResponse = Jsoup.connect(actualLoginUrl)
                .userAgent(USER_AGENT)
                .timeout(30_000)
                .cookies(initialCookies)
                .data("login", username)
                .data("password", password)
                .data("_xfToken", xfToken)
                .data("remember", "1")
                .method(Connection.Method.POST)
                .followRedirects(false)
                .ignoreHttpErrors(true)
                .execute()
            
            // Merge cookies
            val allCookies = initialCookies.toMutableMap()
            allCookies.putAll(loginResponse.cookies())
            
            // Check if login succeeded
            val statusCode = loginResponse.statusCode()
            val hasUserCookie = allCookies.any { it.key.contains("xf_user") || it.key.contains("xf_session") }
            val location = loginResponse.header("Location")
            
            debug.appendLine("Login response status: $statusCode")
            debug.appendLine("Response Location header: $location")
            debug.appendLine("Cookies after login: ${allCookies.keys}")
            debug.appendLine("Has user cookie: $hasUserCookie")
            
            // Check for error in response body
            if (statusCode == 200) {
                val responseBody = loginResponse.parse()
                val errorMsg = responseBody.select(".blockMessage--error, .formRow--error").text()
                if (errorMsg.isNotEmpty()) {
                    debug.appendLine("Error message found: $errorMsg")
                }
            }
            
            logger.info("Login response: status=$statusCode, hasUserCookie=$hasUserCookie, cookies=${allCookies.keys}")
            
            if (statusCode in 300..399 || hasUserCookie) {
                // Follow redirect to capture final cookies
                val redirectUrl = location ?: BASE_URL
                val fullRedirectUrl = if (redirectUrl.startsWith("http")) redirectUrl else "https://www.bdoutdoors.com$redirectUrl"
                debug.appendLine("Following redirect to: $fullRedirectUrl")
                
                val finalResponse = Jsoup.connect(fullRedirectUrl)
                    .userAgent(USER_AGENT)
                    .cookies(allCookies)
                    .timeout(30_000)
                    .execute()
                
                allCookies.putAll(finalResponse.cookies())
                sessionCookies.set(allCookies)
                lastLoginTime = System.currentTimeMillis()
                
                debug.appendLine("Final cookies: ${allCookies.keys}")
                debug.appendLine("LOGIN SUCCESS!")
                logger.info("BD Outdoors login successful! Cookies: ${allCookies.keys}")
                lastLoginDebug = debug.toString()
                return true
            }
            
            debug.appendLine("LOGIN FAILED - no redirect or user cookie")
            logger.warn("BD Outdoors login may have failed - no redirect or user cookie")
            lastLoginDebug = debug.toString()
            return false
            
        } catch (e: Exception) {
            debug.appendLine("EXCEPTION: ${e.message}")
            debug.appendLine(e.stackTraceToString().take(500))
            logger.error("BD Outdoors login failed: ${e.message}", e)
            lastLoginDebug = debug.toString()
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
