package com.shaka.fishing_intel.parsing

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Regression tests for dock-totals count parsing, using real strings
 * captured from sportfishingreport.com. If the site changes format,
 * these stay green but the scraper fixture/probe catches it; if WE
 * break parsing, these fail in CI.
 */
class CountsParserTest {

    @Test
    fun `parses standard kept counts`() {
        val result = CountsParser.parse("12 Sand Bass, 1 Halibut, 90 Whitefish")
        assertEquals(3, result.size)
        assertEquals(12, result[0].kept)
        assertEquals(0, result[0].released)
        assertEquals(90, result[2].kept)
    }

    @Test
    fun `parses released suffix`() {
        val result = CountsParser.parse("838 calico bass released, 548 rockfish")
        assertEquals(2, result.size)
        assertEquals(838, result[0].released)
        assertEquals(0, result[0].kept)
        assertEquals(548, result[1].kept)
    }

    @Test
    fun `parses released prefix`() {
        val result = CountsParser.parse("57 Whitefish, 3 Released Halibut")
        assertEquals(2, result.size)
        assertEquals(3, result[1].released)
        assertEquals(0, result[1].kept)
    }

    @Test
    fun `handles and conjunction`() {
        val result = CountsParser.parse("40 rockfish, 34 red snapper and 1 trigger fish")
        assertEquals(3, result.size)
        assertEquals(1, result[2].kept)
    }

    @Test
    fun `skips non-species totals`() {
        val result = CountsParser.parse("123 fish, 5 Halibut")
        assertEquals(1, result.size)
        assertTrue(result[0].species.contains("alibut", ignoreCase = true) || result[0].kept == 5)
    }

    @Test
    fun `empty input yields no counts`() {
        assertEquals(emptyList(), CountsParser.parse(""))
    }
}
