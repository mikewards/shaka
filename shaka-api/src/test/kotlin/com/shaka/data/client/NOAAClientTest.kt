package com.shaka.data.client

import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Regression tests for the ERDDAP SST parser.
 *
 * Context: the regex-based parser introduced in 3022c8c (Mar 2026) could
 * structurally never capture a complete row — every HTTP-200 response parsed
 * to null and SST silently died for 5 months. The fixture is a REAL
 * coastwatch.noaa.gov griddap response (noaacwBLENDEDsstDNDaily, Catalina
 * Channel bbox, fetched Jul 19 2026) including a genuine null cell.
 */
class NOAAClientTest {

    private val client = NOAAClient()

    private fun fixture(name: String): String =
        checkNotNull(javaClass.getResource("/$name")) { "missing test resource $name" }.readText()

    @Test
    fun `parses real ERDDAP response averaging non-null cells`() {
        val sst = client.parseSSTFromERDDAP(fixture("erddap_sst_response.json"))
        assertNotNull(sst, "real ERDDAP response must parse to a value (the Mar-Jul 2026 regression parsed it to null)")
        // 19 non-null analysed_sst cells; 20th row's cell is null and must be skipped.
        assertTrue(abs(sst - 21.4878889) < 1e-4, "expected avg ~21.4879°C, got $sst")
    }

    @Test
    fun `null cells and NaN are skipped without failing the row set`() {
        val json = """
            {"table": {
              "columnNames": ["time", "latitude", "longitude", "analysed_sst"],
              "rows": [
                ["2026-07-16T12:00:00Z", 33.5, -118.5, null],
                ["2026-07-16T12:00:00Z", 33.5, -118.4, "NaN"],
                ["2026-07-16T12:00:00Z", 33.5, -118.3, 20.0]
              ]
            }}
        """.trimIndent()
        assertEquals(20.0, client.parseSSTFromERDDAP(json))
    }

    @Test
    fun `kelvin values are converted defensively`() {
        val json = """
            {"table": {
              "columnNames": ["time", "latitude", "longitude", "analysed_sst"],
              "rows": [["2026-07-16T12:00:00Z", 33.5, -118.5, 294.15]]
            }}
        """.trimIndent()
        val sst = client.parseSSTFromERDDAP(json)
        assertNotNull(sst)
        assertTrue(abs(sst - 21.0) < 1e-6, "294.15K should convert to 21.0°C, got $sst")
    }

    @Test
    fun `all-null bbox returns null (progressive caller widens search)`() {
        val json = """
            {"table": {
              "columnNames": ["time", "latitude", "longitude", "analysed_sst"],
              "rows": [["2026-07-16T12:00:00Z", 33.5, -118.5, null]]
            }}
        """.trimIndent()
        assertNull(client.parseSSTFromERDDAP(json))
    }

    @Test
    fun `malformed responses return null without throwing`() {
        // ERDDAP HTML error page
        assertNull(client.parseSSTFromERDDAP("<html><body>Error: no data</body></html>"))
        // Truncated JSON
        assertNull(client.parseSSTFromERDDAP("""{"table": {"columnNames": ["time"], "rows": [["2026-"""))
        // Valid JSON, wrong shape
        assertNull(client.parseSSTFromERDDAP("""{"error": {"message": "no such dataset"}}"""))
        // Empty body
        assertNull(client.parseSSTFromERDDAP(""))
    }
}
