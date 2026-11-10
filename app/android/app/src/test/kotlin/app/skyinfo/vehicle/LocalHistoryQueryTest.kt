package app.skyinfo.vehicle

import android.database.sqlite.SQLiteDatabase
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.SQLiteMode
import org.robolectric.util.ReflectionHelpers

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
@SQLiteMode(SQLiteMode.Mode.NATIVE)
class LocalHistoryQueryTest {
    @Test fun indexedWindowKeepsTheLatestBoundaryAndOrdersDuplicateAndOutOfOrderTimes() {
        val history = LocalHistory(RuntimeEnvironment.getApplication())
        val id = "field"
        history.configure(JSONObject().put("localHistory",true).put("retainHistory",true)
            .put("tiles",JSONArray().put(JSONObject().put("fields",JSONArray().put(id)))))
        val db = ReflectionHelpers.getField<SQLiteDatabase>(history,"database")
        val now = System.currentTimeMillis()
        val rows = listOf(now-400_000,now-30_000,now-400_000,now-15_000,now-30_000,now-390_000,now+60_000)
        try {
            rows.forEachIndexed { index,at -> db.execSQL("INSERT INTO samples(id,at,value,state,segment,sample) VALUES(?,?,?,?,?,?)",
                arrayOf<Any>(id,at,index,index.toString(),"session|field|0|available|V|2",JSONObject().put("raw",index).toString())) }
            history.append(id,JSONObject().put("receivedAt",now-20_000).put("value",7).put("quality","available"))
            val points = history.query(id,1).getJSONArray("points")
            assertEquals(listOf(5,1,4,7,3),(0 until points.length()).map { points.getJSONObject(it).getInt("value") })
            val plan = db.rawQuery("EXPLAIN QUERY PLAN $HISTORY_WINDOW_QUERY",arrayOf(id,(now-60_000).toString(),now.toString(),id,(now-60_000).toString(),now.toString())).use { cursor ->
                buildList { while (cursor.moveToNext()) add(cursor.getString(3)) }
            }
            assertTrue(plan.toString(),plan.any { it.contains("samples_id_at") && it.contains("at>?") && it.contains("at<?") })
            assertEquals(0,history.storageStats().getLong("batchTransactions"))
        } finally { history.clear() }
    }
    @Test fun retentionMaintenanceUsesElapsedTimeAndKeepsEveryFieldBoundary() {
        val history = LocalHistory(RuntimeEnvironment.getApplication())
        history.configure(JSONObject().put("localHistory",true).put("retainHistory",true)
            .put("tiles",JSONArray().put(JSONObject().put("fields",JSONArray().put("field")))))
        val db = ReflectionHelpers.getField<SQLiteDatabase>(history,"database")
        val now = System.currentTimeMillis()
        fun old(id:String,at:Long,value:Int) = db.execSQL("INSERT INTO samples(id,at,value,state,segment) VALUES(?,?,?,?,?)",arrayOf<Any>(id,at,value,value.toString(),"session|$id|0|available|V|2"))
        fun persistedCount() = db.rawQuery("SELECT COUNT(*) FROM samples",null).use { it.moveToFirst();it.getInt(0) }
        try {
            old("field",now-5_000_000,1); old("other",now-4_000_000,2)
            old("field",now-6_000_000,3); old("other",now-7_000_000,4)
            repeat(1024) { index -> history.append("field",JSONObject().put("quality","available").put("value",index).put("receivedAt",now-1000+index)) }
            history.flush()
            assertEquals(1028,persistedCount())
            assertEquals(1,history.storageStats().getLong("batchTransactions"))
            org.robolectric.shadows.ShadowSystemClock.advanceBy(java.time.Duration.ofSeconds(59))
            history.append("field",JSONObject().put("quality","available").put("value",1024).put("receivedAt",now))
            history.flush()
            assertEquals(1029,persistedCount())
            org.robolectric.shadows.ShadowSystemClock.advanceBy(java.time.Duration.ofSeconds(1))
            history.append("field",JSONObject().put("quality","available").put("value",1025).put("receivedAt",now))
            history.flush()
            assertEquals(1028,persistedCount())
            db.rawQuery("SELECT id,value FROM samples WHERE at<? ORDER BY id",arrayOf((now-2_000_000).toString())).use { cursor ->
                assertTrue(cursor.moveToNext()); assertEquals("field",cursor.getString(0)); assertEquals(1,cursor.getInt(1))
                assertTrue(cursor.moveToNext()); assertEquals("other",cursor.getString(0)); assertEquals(2,cursor.getInt(1)); assertFalse(cursor.moveToNext())
            }
        } finally { history.clear() }
    }

    @Test fun capacityRecoveryKeepsTheLatestTimeForEachFieldIncludingTies() {
        val history = LocalHistory(RuntimeEnvironment.getApplication())
        history.configure(JSONObject().put("localHistory",true).put("retainHistory",true).put("tiles",JSONArray()))
        val db = ReflectionHelpers.getField<SQLiteDatabase>(history,"database")
        try {
            val now = System.currentTimeMillis()
            listOf("one","two").forEach { id ->
                for ((index,offset) in listOf(0,0,-100,-200,-150).withIndex()) db.execSQL("INSERT INTO samples(id,at,value,state,segment) VALUES(?,?,?,?,?)",
                    arrayOf<Any>(id,now+offset,index,index.toString(),"session|$id|0|available|V|2"))
            }
            while (ReflectionHelpers.callInstanceMethod<Boolean>(history,"reclaimOldestWindow",ReflectionHelpers.ClassParameter.from(SQLiteDatabase::class.java,db))) { }
            db.rawQuery("SELECT id,value FROM samples ORDER BY id",null).use { cursor ->
                assertTrue(cursor.moveToNext());assertEquals("one",cursor.getString(0));assertEquals(1,cursor.getInt(1))
                assertTrue(cursor.moveToNext());assertEquals("two",cursor.getString(0));assertEquals(1,cursor.getInt(1));assertFalse(cursor.moveToNext())
            }
        } finally { history.clear() }
    }

}
