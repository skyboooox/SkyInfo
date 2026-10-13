package app.skyinfo.vehicle

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.time.Instant
import java.util.concurrent.ExecutorService

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class DrivingReplayTest {
    private val fuel = "1014/7/1246760996"
    private val fuelUnit = "1007/5/1246761027"
    private fun fixture() = JSONObject(javaClass.getResource("/driving-20261011.json")!!.readText())
    private fun catalog(): Map<String, JSONObject> {
        val rows = JSONArray(java.io.File("src/main/assets/catalog.json").readText())
        return (0 until rows.length()).map(rows::getJSONObject).associateBy { it.getString("id") }
    }

    @Test fun archivedReadingsKeepConfirmedConversionsAndRejectOnlyDocumentedInvalidRpm() {
        val fields = catalog()
        val reader = ReadOnlyVehicle(fields)
        val groups = fixture().getJSONArray("samples")
        var total = 0
        var invalidRpm = 0
        for (i in 0 until groups.length()) {
            val group = groups.getJSONArray(i)
            val id = group.getString(0)
            val readings = group.getJSONArray(1)
            for (j in 0 until readings.length()) {
                val row = readings.getJSONArray(j)
                val raw = row.get(0) as Number
                val count = row.getInt(1)
                total += count
                val sample = reader.fromRaw(id, raw)
                assertEquals(id, raw.toDouble(), sample.getDouble("raw"), 0.0)
                if (id == "1012/5/339738642" && raw.toInt() == 8191) {
                    invalidRpm += count
                    assertEquals("invalid", sample.getString("quality"))
                    assertFalse(sample.has("value"))
                    continue
                }
                val expected = when (id) {
                    BATTERY_CURRENT -> (raw.toDouble() - 30000) / 10
                    "1012/5/1141899272" -> -raw.toDouble()
                    "1014/5/1148190752", "1014/5/1148190736", "1014/5/1148190776" -> raw.toDouble() - 30
                    else -> raw.toDouble()
                }
                assertEquals(id, expected, sample.getDouble("value"), 1e-9)
                assertEquals(id, fields.getValue(id).getString("unit"), sample.getString("unit"))
                assertEquals(id, if (sample.getString("unit").isEmpty()) "unverified" else "available", sample.getString("quality"))
            }
        }
        assertEquals(34, groups.length())
        assertEquals(62854, total)
        assertEquals(12, invalidRpm)
    }

    @Test fun realFuelUnitTransitionsReachTheRuntimeChangedSetEvenAtZero() {
        val context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences("skyinfo", Context.MODE_PRIVATE).edit().clear()
            .putBoolean("stopped", true).putString("config", "{\"localHistory\":false}").commit()
        val constructor = RuntimeCoordinator::class.java.getDeclaredConstructor(Context::class.java).apply { isAccessible = true }
        val runtime = constructor.newInstance(context)
        val accept = RuntimeCoordinator::class.java.getDeclaredMethod("accept", String::class.java, JSONObject::class.java).apply { isAccessible = true }
        val samplesField = RuntimeCoordinator::class.java.getDeclaredField("samples").apply { isAccessible = true }
        val reader = ReadOnlyVehicle(catalog())
        val events = fixture().getJSONArray("fuelEvents")
        var previousCode: Int? = null
        var transitions = 0
        var zeroTransitions = 0
        try {
            for (i in 0 until events.length()) {
                val row = events.getJSONArray(i)
                val isUnit = row.getInt(0) == 1
                val id = if (isUnit) fuelUnit else fuel
                val raw = row.get(1) as Number
                val fresh = reader.fromRaw(id, raw).put("receivedAt", row.getLong(2))
                val changed = accept.invoke(runtime, id, fresh) as Set<*>
                if (isUnit) {
                    val code = raw.toInt()
                    if (previousCode != null && previousCode != code) {
                        transitions++
                        assertTrue("Unit transition at ${Instant.ofEpochMilli(row.getLong(2))} was omitted", fuel in changed)
                        val sample = (samplesField.get(runtime) as Map<*, *>)[fuel] as JSONObject
                        if (sample.getDouble("value") == 0.0) zeroTransitions++
                        assertEquals(if (code == 1) "L/100km" else "L/h", sample.getString("unit"))
                        assertEquals(sample.getLong("receivedAt"), sample.getLong("updatedAt"))
                    }
                    previousCode = code
                }
            }
            assertEquals(43, transitions)
            assertTrue(zeroTransitions > 0)
            val last = events.getJSONArray(events.length() - 1)
            val same = reader.fromRaw(fuelUnit, last.get(1)).put("receivedAt", last.getLong(2) + 1000)
            assertFalse(fuel in (accept.invoke(runtime, fuelUnit, same) as Set<*>))
        } finally {
            for (name in listOf("worker", "network", "source")) {
                val field = RuntimeCoordinator::class.java.getDeclaredField(name).apply { isAccessible = true }
                (field.get(runtime) as ExecutorService).shutdownNow()
            }
        }
    }

    @Test fun repeatedFuelUnitsCannotTurnAnUnchangedZeroIntoANewChangeTime() {
        val fields = catalog()
        val row = fixture().getJSONArray("fuelEvents").getJSONArray(0)
        assertEquals(0, row.getInt(0))
        assertEquals(0.0, row.getDouble(1), 0.0)
        val at = row.getLong(2)
        val unit = JSONObject().put("value", 4).put("quality", "unverified").put("updatedAt", at)
        val first = ReadOnlyVehicle(fields).fromRaw(fuel, row.getDouble(1)).put("receivedAt", at)
        resolvePairedUnit(fuel, first, mapOf(fuelUnit to unit), fields)
        stampSampleTimes(first, null, 1)
        val repeated = JSONObject(first.toString()).put("interpretationChangedAt", at + 2000)
        resolvePairedUnit(fuel, repeated, mapOf(fuelUnit to unit.put("updatedAt", at + 2000)), fields)
        stampSampleTimes(repeated, first, 1)
        assertEquals(first.getDouble("value"), repeated.getDouble("value"), 0.0)
        assertEquals(at, repeated.getLong("updatedAt"))
        assertEquals(at, repeated.getLong("changedAt"))
        assertEquals(at + 2000, repeated.getLong("unitReceivedAt"))
    }
}
