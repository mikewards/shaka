package com.shaka.util

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset

/**
 * Single source of truth for resolving a spot's timezone and local date.
 *
 * House convention (matches the tide system): prefer the spot's IANA timezone,
 * fall back to a longitude approximation, and NEVER fall back to the server
 * default zone for date boundaries (the server runs in UTC, which silently
 * produced wrong "today" values). Use absolute epoch-millis for "now" selection.
 */
object SpotTime {

    /** Coarse zone derived from longitude (15 deg per hour), used as a fallback. */
    fun zoneForLon(lon: Double): ZoneId {
        val offsetHours = (lon / 15).toInt().coerceIn(-12, 14)
        return ZoneOffset.ofHours(offsetHours)
    }

    /** IANA zone if valid, otherwise the longitude approximation. */
    fun resolveZone(timezoneId: String?, lon: Double): ZoneId {
        if (!timezoneId.isNullOrEmpty()) {
            try {
                return ZoneId.of(timezoneId)
            } catch (_: Exception) { /* fall through */ }
        }
        return zoneForLon(lon)
    }

    /** Today's date in the spot's local zone. */
    fun spotLocalDate(timezoneId: String?, lon: Double): LocalDate =
        Instant.now().atZone(resolveZone(timezoneId, lon)).toLocalDate()

    /** Local date of an absolute instant in the given zone. */
    fun localDateOf(epochMs: Long, zone: ZoneId): LocalDate =
        Instant.ofEpochMilli(epochMs).atZone(zone).toLocalDate()
}
