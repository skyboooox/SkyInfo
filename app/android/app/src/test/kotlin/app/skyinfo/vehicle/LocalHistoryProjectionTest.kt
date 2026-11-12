package app.skyinfo.vehicle

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.SQLiteMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
@SQLiteMode(SQLiteMode.Mode.NATIVE)
class LocalHistoryProjectionTest {
    private fun history(id: String) = LocalHistory(RuntimeEnvironment.getApplication()).also {
        it.clear()
        it.configure(JSONObject().put("localHistory",true).put("retainHistory",true)
            .put("tiles",JSONArray().put(JSONObject().put("fields",JSONArray().put(id)))))
    }
    private fun sample(at: Long, value: Int, quality: String = "available", version: Int = 2, unit: String = "V") =
        JSONObject().put("receivedAt",at).put("value",value).put("raw",value).put("quality",quality)
            .put("unit",unit).put("definitionVersion",version).put("sourceEpoch",0).put("source","vehicle")
    private fun compare(history: LocalHistory, id: String, field: JSONObject? = null): Pair<JSONArray,JSONArray> {
        val full = history.query(id,1,field)
        val light = history.query(id,1,field,includeSample=false)
        val a = full.getJSONArray("points"); val b = light.getJSONArray("points")
        assertEquals(a.length(),b.length())
        repeat(a.length()) { i ->
            val expected = JSONObject(a.getJSONObject(i).toString()); val actual = JSONObject(b.getJSONObject(i).toString())
            assertTrue(expected.has("sample")); assertFalse(actual.has("sample")); expected.remove("sample")
            if (expected.has("observedUntil")) {
                assertEquals(full.getLong("queriedAt"),expected.getLong("observedUntil"))
                assertEquals(light.getLong("queriedAt"),actual.getLong("observedUntil"))
                expected.remove("observedUntil"); actual.remove("observedUntil")
            }
            assertEquals(expected.toString(),actual.toString())
        }
        return a to b
    }
    @Test fun pendingAndCommittedQueriesKeepBoundaryTiesGapsAndCompleteStorage() {
        val id = "field"; val history = history(id); val now = System.currentTimeMillis()
        try {
            history.append(id,sample(now-120000,1)); history.append(id,sample(now-30000,2)); history.append(id,sample(now-30000,3))
            history.flush()
            history.append(id,sample(now-20000,4,"disconnected")); history.append(id,sample(now-10000,5))
            history.append(id,sample(now+60000,6))
            val (full,light) = compare(history,id)
            assertEquals(listOf(1,2,3,null,5),(0 until light.length()).map { if(light.getJSONObject(it).isNull("value")) null else light.getJSONObject(it).getInt("value") })
            assertTrue(light.getJSONObject(3).getString("segment").contains("disconnected"))
            assertTrue(light.getJSONObject(4).has("observedUntil"))
            assertEquals(5,full.getJSONObject(4).getJSONObject("sample").getInt("raw"))
            assertEquals(1,history.storageStats().getInt("batchTransactions"))
            history.flush(); compare(history,id)
            assertEquals(2,history.storageStats().getInt("batchTransactions"))
        } finally { history.clear() }
    }
    @Test fun legacyConversionAndInvalidCurrentHaveIdenticalLightProjection() {
        val history = history(BATTERY_CURRENT); val now = System.currentTimeMillis()
        try {
            history.append(BATTERY_CURRENT,sample(now-3000,30010,version=1,unit="A"))
            history.append(BATTERY_CURRENT,sample(now-2000,65535,version=1,unit="A"))
            val field = JSONObject().put("valueScale",.1).put("valueOffset",-3000).put("definitionVersion",2)
            val (_,light) = compare(history,BATTERY_CURRENT,field)
            assertEquals(1.0,light.getJSONObject(0).getDouble("value"),.000001)
            assertTrue(light.getJSONObject(0).getString("segment").endsWith("converted:2"))
            assertTrue(light.getJSONObject(1).isNull("value"))
            assertEquals("unavailable",light.getJSONObject(1).getString("state"))
        } finally { history.clear() }
    }
    @Test fun lightPayloadOmitsRawJsonWithoutChangingStoredSamplesOrTransactions() {
        val history = history("field"); val now = System.currentTimeMillis()
        try {
            val original = sample(now-1000,7).put("raw",JSONObject().put("detail","x".repeat(20000)))
            history.append("field",original)
            val (full,light) = compare(history,"field")
            assertTrue(full.toString().length > light.toString().length+20000)
            assertEquals(0,history.storageStats().getInt("batchTransactions"))
            history.flush()
            assertEquals(original.toString(),history.query("field",1).getJSONArray("points").getJSONObject(0).getJSONObject("sample").toString())
            assertEquals(1,history.storageStats().getInt("batchTransactions"))
        } finally { history.clear() }
    }
}
