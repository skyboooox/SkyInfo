package app.skyinfo.vehicle

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.RuntimeEnvironment
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class DerivedReadingsTest {
    private fun reading(value: Double, at: Long = 1000, epoch: Long = 1, quality: String = "available") =
        JSONObject().put("value", value).put("raw", value).put("receivedAt", at).put("sourceEpoch", epoch).put("quality", quality)
    private fun inputs(current: Double = 0.7) = mapOf(BATTERY_VOLTAGE to reading(506.0), BATTERY_CURRENT to
        reading(current, 1100).put("raw", 30000 + current * 10).put("unit", "A").put("definitionVersion", 2))
    @Test fun signedPowerUsesUnroundedInputsAndRetainsSourceTimes() {
        val power = batteryPower(inputs(), 1)
        assertEquals(0.3542, power.getDouble("value"), 1e-12)
        assertEquals("kW", power.getString("unit")); assertEquals("available", power.getString("quality"))
        assertEquals(2, power.getInt("definitionVersion"))
        assertEquals(1100, power.getLong("receivedAt"))
        assertEquals(1000, power.getJSONObject("inputs").getJSONObject(BATTERY_VOLTAGE).getLong("receivedAt"))
        assertEquals(-50.6, batteryPower(inputs(-100.0), 1).getDouble("value"), 1e-12)
        assertEquals(0.0, batteryPower(inputs(0.0), 1).getDouble("value"), 0.0)
    }
    @Test fun missingDisconnectedAndPreviousSessionInputsCannotProducePower() {
        assertFalse(batteryPower(emptyMap(), 1).has("value"))
        val missing = inputs().toMutableMap(); missing.remove(BATTERY_CURRENT)
        assertFalse(batteryPower(missing, 1).has("value"))
        for (quality in listOf("disconnected", "invalid", "error", "permission", "timeout")) {
            val failed = inputs().toMutableMap(); failed[BATTERY_CURRENT] = reading(0.7, quality = quality)
            val power = batteryPower(failed, 1)
            assertFalse(power.has("value")); assertEquals(quality, power.getString("quality"))
        }
        assertFalse(batteryPower(inputs(), 2).has("value"))
    }
    @Test fun unconvertedOrInvalidGbCurrentAndVoltageDoNotPublishAFalseNumber() {
        for (sample in listOf(reading(30008.0), reading(0.8).put("unit", "A").put("definitionVersion", 1),
            reading(3553.5).put("raw", 65535).put("unit", "A").put("definitionVersion", 2),
            reading(-4001.3).put("raw", -10013).put("unit", "A").put("definitionVersion", 2))) {
            val values = inputs().toMutableMap(); values[BATTERY_CURRENT] = sample
            val power = batteryPower(values, 1)
            assertEquals("invalid", power.getString("quality")); assertFalse(power.has("value"))
        }
        for (voltage in listOf(0.0, -1.0, 65535.0)) {
            val values = inputs().toMutableMap(); values[BATTERY_VOLTAGE] = reading(voltage)
            assertFalse(batteryPower(values, 1).has("value"))
        }
    }
    @Test fun archivedFastChargingPeakUsesConvertedGbRatherThanClippedLegacyCurrent() {
        val json = JSONArray(java.io.File("src/main/assets/catalog.json").readText())
        val catalog = (0 until json.length()).map { json.getJSONObject(it) }.associateBy { it.getString("id") }
        val reader = ReadOnlyVehicle(catalog)
        val values = mapOf(BATTERY_VOLTAGE to reader.fromRaw(BATTERY_VOLTAGE, 569).put("sourceEpoch", 1),
            BATTERY_CURRENT to reader.fromRaw(BATTERY_CURRENT, 22544).put("sourceEpoch", 1),
            "1009/7/1145045016" to reader.fromRaw("1009/7/1145045016", -500).put("sourceEpoch", 1))
        val power = batteryPower(values, 1)
        assertEquals(-424.2464, power.getDouble("value"), 1e-9)
        assertEquals(-745.6, power.getJSONObject("inputs").getJSONObject(BATTERY_CURRENT).getDouble("value"), 1e-9)
        assertEquals(22544, power.getJSONObject("inputs").getJSONObject(BATTERY_CURRENT).getInt("raw"))
        assertFalse(power.getJSONObject("inputs").has("1009/7/1145045016"))
        assertEquals(setOf(BATTERY_VOLTAGE, BATTERY_CURRENT, BATTERY_POWER), expandDependencies(setOf(BATTERY_POWER), catalog))
        val history = LocalHistory(RuntimeEnvironment.getApplication())
        history.configure(JSONObject().put("localHistory", true).put("tiles", JSONArray().put(JSONObject().put("fields", JSONArray().put(BATTERY_POWER)))))
        val recordedAt = System.currentTimeMillis()
        history.append(BATTERY_POWER, reading(-284.5, recordedAt).put("unit", "kW").put("definitionVersion", 1))
        history.append(BATTERY_POWER, JSONObject(power.toString()).put("receivedAt", recordedAt))
        val points = history.query(BATTERY_POWER, 30, catalog.getValue(BATTERY_POWER)).getJSONArray("points")
        assertEquals(-284.5, points.getJSONObject(0).getDouble("value"), 0.0)
        assertEquals(-424.2464, points.getJSONObject(1).getDouble("value"), 1e-9)
        assertNotEquals(points.getJSONObject(0).getString("segment"), points.getJSONObject(1).getString("segment"))
    }
    @Test fun selectingOnlyPowerExpandsSharedInputsAndNeverReadsADerivedBinderAddress() {
        val fields = mapOf(BATTERY_POWER to JSONObject().put("derivedInputs", JSONArray(listOf(BATTERY_VOLTAGE, BATTERY_CURRENT))),
            BATTERY_VOLTAGE to JSONObject(), BATTERY_CURRENT to JSONObject())
        val demand = expandDependencies(setOf(BATTERY_POWER, BATTERY_VOLTAGE), fields)
        assertEquals(setOf(BATTERY_POWER, BATTERY_VOLTAGE, BATTERY_CURRENT), demand)
        assertEquals(setOf(BATTERY_VOLTAGE, BATTERY_CURRENT), demand.filterNot(::isDerived).toSet())
        assertEquals("unsupported", ReadOnlyVehicle(fields).read(BATTERY_POWER).getString("quality"))
    }
    @Test fun powerUpdateAndChangeTimesFollowSourceUpdatesAndSessionRecovery() {
        val first = batteryPower(inputs(), 1); stampSampleTimes(first, null, 1)
        val sameInputs = inputs().toMutableMap(); sameInputs[BATTERY_CURRENT] = inputs().getValue(BATTERY_CURRENT).put("receivedAt", 2000)
        val same = batteryPower(sameInputs, 1); stampSampleTimes(same, first, 1)
        assertEquals(2000, same.getLong("updatedAt")); assertEquals(1100, same.getLong("changedAt"))
        sameInputs[BATTERY_CURRENT] = inputs(0.8).getValue(BATTERY_CURRENT).put("receivedAt", 3000)
        val changed = batteryPower(sameInputs, 1); stampSampleTimes(changed, same, 1)
        assertEquals(3000, changed.getLong("changedAt"))
        val disconnected = batteryPower(sameInputs, 2); stampSampleTimes(disconnected, changed, 2)
        assertEquals("disconnected", disconnected.getString("quality")); assertEquals(3000, disconnected.getLong("updatedAt"))
    }
    @Test fun haReceivesSignedKilowattsWithGbInputsAndUnavailableOnInvalidInput() {
        var body = JSONObject(); var path = ""
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            if (chain.request().method == "GET") return@addInterceptor Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(404).message("Not Found").body("{}".toResponseBody()).build()
            val buffer = okio.Buffer(); chain.request().body!!.writeTo(buffer)
            body = JSONObject(JSONObject(buffer.readUtf8()).getString("payload")); path = chain.request().url.encodedPath
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK").body("{}".toResponseBody()).build()
        }.build()
        val client = ConnectionClient(RuntimeEnvironment.getApplication(), object : SecretStore { override fun secret(name: String) = "test" }, http)
        val config = JSONObject().put("connection", "ha").put("prefix", "skyinfo_demo").put("haUrl", "http://192.168.10.20:8123/")
        val fields = mapOf(BATTERY_POWER to JSONObject().put("id", BATTERY_POWER).put("name", "动力电池功率").put("unit", "kW").put("entityKey", "battery_power"))
        client.publish(config, mapOf(BATTERY_POWER to batteryPower(inputs(-100.0), 1)), fields)
        assertEquals("/api/services/mqtt/publish", path)
        assertEquals(-50.6, body.getDouble("value"), 1e-12)
        assertEquals("kW", body.getString("unit"))
        assertEquals("computed_number", body.getString("raw_type"))
        assertEquals(29000.0, body.getJSONObject("inputs").getJSONObject(BATTERY_CURRENT).getDouble("raw"), 0.0)
        client.publish(config, mapOf(BATTERY_POWER to batteryPower(inputs(-745.6), 1)), fields)
        assertEquals(-377.2736, body.getDouble("value"), 1e-9)
        val invalid = inputs().toMutableMap(); invalid[BATTERY_CURRENT] = reading(30008.0)
        client.publish(config, mapOf(BATTERY_POWER to batteryPower(invalid, 1)), fields)
        assertTrue(body.isNull("value")); assertEquals("invalid",body.getString("quality"))
    }
}
