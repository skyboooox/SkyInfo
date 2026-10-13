package app.skyinfo.vehicle

import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class GbCurrentTest {
    private fun catalog(): Map<String, JSONObject> {
        val json = JSONArray(java.io.File("src/main/assets/catalog.json").readText())
        return (0 until json.length()).map { json.getJSONObject(it) }.associateBy { it.getString("id") }
    }
    @Test fun integerCallbacksAndInitialReadingsDecodeSignedAmpsAndRetainRaw() {
        val fields = catalog(); val reader = ReadOnlyVehicle(fields)
        for ((raw, amps) in mapOf(30008 to 0.8, 30000 to 0.0, 22544 to -745.6, 35000 to 500.0)) {
            val sample = reader.fromRaw(BATTERY_CURRENT, raw)
            assertEquals(amps, sample.getDouble("value"), 1e-9)
            assertEquals(raw, sample.getInt("raw"))
            assertEquals("A", sample.getString("unit")); assertEquals("available", sample.getString("quality"))
            assertEquals(2, sample.getInt("definitionVersion"))
        }
        assertEquals("user_supplied", fields.getValue(BATTERY_CURRENT).getString("unitConfidence"))
        assertEquals(-500.0, reader.fromRaw("1009/7/1145045016", -500).getDouble("value"), 0.0)
    }
    @Test fun sentinelsAndTransportErrorCodesCannotBecomeHugeCurrents() {
        val reader = ReadOnlyVehicle(catalog())
        for (raw in listOf(65534, 65535, -1, -10011, -10013)) {
            val sample = reader.fromRaw(BATTERY_CURRENT, raw)
            assertEquals("invalid", sample.getString("quality")); assertFalse(sample.has("value"))
            assertEquals(raw, sample.getInt("raw"))
        }
    }
    @Test fun localLegacyRecordsConvertOnceAndInvalidCodesRemainGaps() {
        val fields = catalog(); val cfg = JSONObject().put("localHistory", true)
            .put("tiles", JSONArray().put(JSONObject().put("fields", JSONArray().put(BATTERY_CURRENT))))
        val history = LocalHistory(RuntimeEnvironment.getApplication()); history.configure(cfg)
        for (raw in listOf(30008, 22544, 65535)) history.append(BATTERY_CURRENT,
            JSONObject().put("value", raw).put("raw", raw).put("quality", "unverified").put("definitionVersion", 1))
        history.append(BATTERY_CURRENT, ReadOnlyVehicle(fields).fromRaw(BATTERY_CURRENT, 22544))
        repeat(2) {
            val points = history.query(BATTERY_CURRENT, 30, fields.getValue(BATTERY_CURRENT)).getJSONArray("points")
            assertEquals(0.8, points.getJSONObject(0).getDouble("value"), 1e-9)
            assertEquals(-745.6, points.getJSONObject(1).getDouble("value"), 1e-9)
            assertTrue(points.getJSONObject(2).isNull("value"))
            assertEquals("unavailable", points.getJSONObject(2).getString("state"))
            assertEquals(-745.6, points.getJSONObject(3).getDouble("value"), 1e-9)
            assertEquals(22544, points.getJSONObject(1).getJSONObject("sample").getInt("value"))
            assertEquals(22544, points.getJSONObject(3).getJSONObject("sample").getInt("raw"))
            assertNotEquals(points.getJSONObject(1).getString("segment"), points.getJSONObject(3).getString("segment"))
        }
    }
    @Test fun oldDefaultUnitsMigrateWhileCustomUnitsAndUploadSelectionRemain() {
        val tile = JSONObject().put("fields", JSONArray().put(BATTERY_CURRENT))
            .put("units", JSONObject().put(BATTERY_CURRENT, "原值"))
        val overlay = JSONObject().put("field", BATTERY_CURRENT).put("unit", "原值")
        val cfg = JSONObject().put("tiles", JSONArray().put(tile)).put("overlays", JSONArray().put(overlay))
            .put("uploaded", JSONArray().put(BATTERY_POWER))
        assertTrue(migrateConvertedUnits(cfg, catalog()))
        assertFalse(tile.getJSONObject("units").has(BATTERY_CURRENT)); assertEquals("A", overlay.getString("unit"))
        assertEquals(BATTERY_POWER, cfg.getJSONArray("uploaded").getString(0))
        tile.getJSONObject("units").put(BATTERY_CURRENT, "自定义"); overlay.put("unit", "自定义")
        assertFalse(migrateConvertedUnits(cfg, catalog()))
        assertEquals("自定义", overlay.getString("unit"))
    }
    @Test fun haPublishesNumericAmpsAndDeclaresCurrentMeasurement() {
        var body = JSONObject()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            if (chain.request().method == "GET") return@addInterceptor Response.Builder().request(chain.request())
                .protocol(Protocol.HTTP_1_1).code(404).message("Not Found").body("{}".toResponseBody()).build()
            val buffer = okio.Buffer(); chain.request().body!!.writeTo(buffer)
            body = JSONObject(JSONObject(buffer.readUtf8()).getString("payload"))
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK").body("{}".toResponseBody()).build()
        }.build()
        val fields = catalog(); val reader = ReadOnlyVehicle(fields)
        val client = ConnectionClient(RuntimeEnvironment.getApplication(), object : SecretStore {
            override fun secret(name: String) = "test"
        }, http)
        val cfg = JSONObject().put("connection", "ha").put("prefix", "skyinfo_demo").put("haUrl", "http://192.168.10.20:8123/")
        client.publish(cfg, mapOf(BATTERY_CURRENT to reader.fromRaw(BATTERY_CURRENT, 22544)), fields)
        assertTrue(body.get("value") is Number); assertEquals(-745.6, body.getDouble("value"), 1e-9)
        assertEquals(22544, body.getInt("raw")); assertEquals("A", body.getString("unit"))
        assertEquals(2, body.getInt("definition_version"))
        val discovery = haSensorDiscovery("test", "skyinfo_demo", "0.4.17", fields.getValue(BATTERY_CURRENT), "sensor.test")
        assertEquals("A", discovery.getString("unit_of_measurement"))
        assertEquals("current", discovery.getString("device_class"))
        assertEquals("measurement", discovery.getString("state_class"))
        client.publish(cfg, mapOf(BATTERY_CURRENT to reader.fromRaw(BATTERY_CURRENT, 65535)), fields)
        assertTrue(body.isNull("value")); assertEquals("invalid", body.getString("quality"))
    }
}
