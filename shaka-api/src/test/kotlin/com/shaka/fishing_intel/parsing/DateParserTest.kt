package com.shaka.fishing_intel.parsing

import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class DateParserTest {

    @Test
    fun `parses sportfishingreport page date`() {
        assertEquals(
            LocalDate.of(2025, 12, 17),
            DateParser.parseSoCalFishReports("December 17, 2025")
        )
    }

    @Test
    fun `trims whitespace`() {
        assertEquals(
            LocalDate.of(2026, 6, 11),
            DateParser.parseSoCalFishReports("  June 11, 2026 ")
        )
    }

    @Test
    fun `returns null for garbage`() {
        assertNull(DateParser.parseSoCalFishReports("Dock Totals"))
        assertNull(DateParser.parseSoCalFishReports(""))
        assertNull(DateParser.parseSoCalFishReports("2026-06-11"))
    }
}
