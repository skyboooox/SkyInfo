package app.skyinfo.vehicle

import android.content.Context
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
import java.io.File
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
@SQLiteMode(SQLiteMode.Mode.NATIVE)
class LocalHistoryBatchTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private val id = "voltage"
    private fun config() = JSONObject().put("localHistory",true).put("retainHistory",true)
        .put("tiles",JSONArray().put(JSONObject().put("fields",JSONArray().put(id))))
    private fun sample(n: Int) = JSONObject().put("value",if (n == 153) 999 else 13.6).put("raw",n)
        .put("quality",if (n == 175) "disconnected" else "available").put("source",id).put("unit","V")
        .put("sourceEpoch",n/200).put("definitionVersion",2).put("receivedAt",System.currentTimeMillis()-10000+n)

    @Test fun queriesReadPendingSamplesWithoutTransactionsAndTimerFlushesOneBatch() {
        val tasks = mutableListOf<FutureTask<Unit>>()
        val delays = mutableListOf<Long>()
        val history = LocalHistory(context,scheduleFlush = { delay, callback -> delays.add(delay); FutureTask { callback() }.also(tasks::add) })
        history.configure(config())
        repeat(64) { n ->
            history.append(id,sample(n))
            assertEquals(n+1,history.query(id,30).getJSONArray("points").length())
        }
        assertEquals(0,history.storageStats().getLong("batchTransactions"))
        assertEquals(1,tasks.size)
        assertEquals(listOf(30L),delays)
        tasks.single().run()
        assertEquals(1,history.storageStats().getLong("batchTransactions"))
        assertEquals(0,history.storageStats().getInt("bufferedSamples"))
        history.close()
        val reopened = LocalHistory(context); reopened.configure(config())
        assertEquals(64,reopened.query(id,30).getJSONArray("points").length())
        reopened.clear()
    }
    @Test fun fullBatchesKeepEveryRepeatedValueRawTimestampPeakAndGap() {
        val history = LocalHistory(context); history.configure(config())
        val count = 6000
        repeat(count) { history.append(id,sample(it)) }
        assertTrue(history.storageStats().getLong("batchTransactions") > 0)
        assertTrue(history.storageStats().getLong("bufferedBytes") <= history.storageStats().getLong("bufferBudgetBytes"))
        val points = history.query(id,30).getJSONArray("points")
        assertEquals(count,points.length())
        assertEquals(999,points.getJSONObject(153).getInt("value"))
        assertTrue(points.getJSONObject(175).isNull("value"))
        repeat(count) { assertEquals(it,points.getJSONObject(it).getJSONObject("sample").getInt("raw")) }
        assertNotEquals(points.getJSONObject(199).getString("segment"),points.getJSONObject(200).getString("segment"))
        history.pause(); history.close()
        val reopened = LocalHistory(context); reopened.configure(config())
        assertEquals(count+1,reopened.query(id,30).getJSONArray("points").length())
        reopened.clear()
    }
    @Test fun clearCancelsPendingTimerAndNeverResurrectsDeletedSamples() {
        val tasks = mutableListOf<FutureTask<Unit>>()
        val history = LocalHistory(context,scheduleFlush = { _, callback -> FutureTask { callback() }.also(tasks::add) })
        history.configure(config()); history.append(id,sample(0)); history.clear(); history.configure(config())
        tasks.forEach { it.run() }
        assertEquals(0,history.query(id,30).getJSONArray("points").length())
        history.clear()
    }
    @Test fun idleQueriesHonorRetentionAndKeepOneBoundaryWithoutWriting() {
        val history = LocalHistory(context); history.configure(config())
        val now = System.currentTimeMillis()
        repeat(3) { n -> history.append(id,sample(n).put("receivedAt",now-90*60000+n)) }
        history.append(id,sample(3).put("receivedAt",now-10*60000))
        val points = history.query(id,120).getJSONArray("points")
        assertEquals(2,points.length())
        assertEquals(2,points.getJSONObject(0).getJSONObject("sample").getInt("raw"))
        assertEquals(0,history.storageStats().getLong("batchTransactions"))
        history.clear()
    }
    @Test fun writeFailureKeepsBoundedPendingRowsAndRecoveryRecordsTheLostRange() {
        val history = LocalHistory(context); history.configure(config())
        val db = org.robolectric.util.ReflectionHelpers.getField<SQLiteDatabase>(history,"database")
        db.execSQL("ALTER TABLE samples RENAME TO unavailable_samples")
        val count = 5000
        repeat(count) { history.append(id,sample(it)) }
        val buffered = history.storageStats().getInt("bufferedSamples")
        assertTrue(buffered in 1 until count)
        assertTrue(history.storageStats().getLong("bufferedBytes") <= history.storageStats().getLong("bufferBudgetBytes"))
        assertEquals((count-buffered).toLong(),history.storageStats().getLong("unrecordedSamples"))
        assertEquals(1,history.storageStats().getLong("transactionAttempts"))
        assertFalse(history.storageStats().isNull("writeError"))
        db.execSQL("ALTER TABLE unavailable_samples RENAME TO samples")
        history.flush()
        history.append(id,sample(count))
        val points = history.query(id,30).getJSONArray("points")
        assertEquals(buffered+2,points.length())
        val gap = points.getJSONObject(buffered)
        assertTrue(gap.isNull("value"))
        assertEquals("storage_error",gap.getJSONObject("sample").getString("quality"))
        assertTrue(gap.getJSONObject("sample").getLong("lostUntil") >= gap.getJSONObject("sample").getLong("receivedAt"))
        history.clear(); history.configure(config())
        assertEquals(0,history.storageStats().getLong("unrecordedSamples"))
        history.clear()
    }

    @Test fun failedOpenBuffersSamplesBeforeRecordingAnExplicitOverflowGap() {
        for (count in listOf(64,5000)) {
            val file = context.getDatabasePath("mqtt-history.db")
            SQLiteDatabase.deleteDatabase(file); file.mkdirs(); File(file,"blocked").writeText("fixture")
            val tasks = mutableListOf<FutureTask<Unit>>()
            val history = LocalHistory(context,scheduleFlush = { _, callback -> FutureTask { callback() }.also(tasks::add) })
            history.configure(config())
            repeat(count) { history.append(id,sample(it)) }
            val pending = org.robolectric.util.ReflectionHelpers.getField<List<*>>(history,"pending")
            val buffered = pending.size
            assertTrue(buffered in 1..minOf(count,LocalHistory.MAX_BUFFER_ROWS))
            assertTrue(history.storageStats().getLong("bufferedBytes") <= history.storageStats().getLong("bufferBudgetBytes"))
            assertEquals((count-buffered).toLong(),history.storageStats().getLong("unrecordedSamples"))
            file.deleteRecursively(); tasks.first().run()
            val points = history.query(id,30).getJSONArray("points")
            assertEquals(buffered+if (count > buffered) 1 else 0,points.length())
            repeat(buffered) { assertEquals(it,points.getJSONObject(it).getJSONObject("sample").getInt("raw")) }
            if (count > buffered) assertEquals("storage_error",points.getJSONObject(buffered).getJSONObject("sample").getString("quality"))
            history.clear()
        }
    }
    @Test fun pauseTakesPriorityOverDeferredConfigurationAndCloseFailurePreservesTheBuffer() {
        val file = context.getDatabasePath("mqtt-history.db")
        SQLiteDatabase.deleteDatabase(file); file.mkdirs(); File(file,"blocked").writeText("fixture")
        val tasks = mutableListOf<FutureTask<Unit>>()
        val history = LocalHistory(context,scheduleFlush = { _, callback -> FutureTask { callback() }.also(tasks::add) })
        history.configure(config()); history.append(id,sample(0)); history.pause(); history.close()
        file.deleteRecursively(); tasks.first().run()
        history.append(id,sample(1))
        val points = history.query(id,30).getJSONArray("points")
        assertEquals(2,points.length()); assertTrue(points.getJSONObject(1).isNull("value"))
        assertFalse(points.getJSONObject(0).has("observedUntil"))
        history.clear()
    }
    @Test fun failedPersistenceMigrationKeepsTheOriginalFileUntilRecovery() {
        val history = LocalHistory(context); history.configure(config().put("retainHistory",false))
        history.append(id,sample(0))
        val file = context.getDatabasePath("mqtt-history.db")
        SQLiteDatabase.deleteDatabase(file); file.mkdirs(); File(file,"blocked").writeText("fixture")
        history.configure(config())
        assertEquals(1,history.query(id,30).getJSONArray("points").length())
        assertFalse(history.storageStats().getBoolean("retainedAcrossStarts"))
        file.deleteRecursively(); history.configure(config())
        assertTrue(history.storageStats().getBoolean("retainedAcrossStarts"))
        assertEquals(1,history.query(id,30).getJSONArray("points").length())
        history.clear()
    }

    @Test fun maintenanceRecoveryClearsTheErrorAndASeparateFailureLogsAgain() {
        val history = LocalHistory(context); history.configure(config())
        val db = org.robolectric.util.ReflectionHelpers.getField<SQLiteDatabase>(history,"database")
        fun warnings() = org.robolectric.shadows.ShadowLog.getLogsForTag("SkyInfo.Vehicle").count { it.msg == "Local history batch pending" }
        val before = warnings()
        repeat(2) { round ->
            db.execSQL("ALTER TABLE samples RENAME TO unavailable_samples")
            history.configure(config()); history.configure(config())
            assertFalse(history.storageStats().isNull("writeError"))
            assertEquals(before+round+1,warnings())
            db.execSQL("ALTER TABLE unavailable_samples RENAME TO samples")
            history.configure(config())
            assertTrue(history.storageStats().isNull("writeError"))
        }
        history.clear()
    }
    @Test fun capacityReclaimsOldestRowsAndKeepsTheLatestCompleteBatch() {
        val history = LocalHistory(context,512*1024L); history.configure(config())
        repeat(1024) { history.append(id,sample(it).put("fixturePadding","x".repeat(600))) }
        history.flush()
        val stats = history.storageStats()
        assertTrue(stats.isNull("writeError")); assertEquals(0,stats.getLong("unrecordedSamples"))
        assertTrue(stats.getLong("allocatedBytes") <= stats.getLong("maximumBytes"))
        val points = history.query(id,30).getJSONArray("points")
        assertTrue(points.length() >= 256); assertTrue(points.length() < 1024)
        assertEquals(1023,points.getJSONObject(points.length()-1).getJSONObject("sample").getInt("raw"))
        history.clear()
    }

    @Test fun sqliteIoBenchmarkPreservesAllRowsWithFewerWrites() = benchmark(false)
    @Test fun pacedSqliteIoBenchmark() = benchmark(true)
    private fun benchmark(paced: Boolean) {
        fun io(): Map<String,Long> = File("/proc/self/io").readLines().associate { line ->
            val parts = line.split(':'); parts[0] to parts[1].trim().toLong()
        }
        val count = if (paced) 512 else 2048
        val samples = (0 until count).map(::sample)
        val baselineFile = context.getDatabasePath("history-benchmark-unbatched.db")
        baselineFile.parentFile!!.mkdirs()
        SQLiteDatabase.deleteDatabase(baselineFile)
        val baseline = SQLiteDatabase.openOrCreateDatabase(baselineFile,null)
        baseline.execSQL("CREATE TABLE samples (seq INTEGER PRIMARY KEY,id TEXT NOT NULL,at INTEGER NOT NULL,value REAL,state TEXT,segment TEXT NOT NULL,sample TEXT)")
        baseline.execSQL("CREATE INDEX samples_id_at ON samples(id,at)")
        baseline.rawQuery("PRAGMA journal_mode=DELETE",null).use { it.moveToFirst() }; baseline.execSQL("PRAGMA synchronous=FULL")
        val before = io(); val started = System.nanoTime()
        fun pace(start: Long, index: Int) {
            if (paced) {
                val wait = start + index*15_625_000L - System.nanoTime()
                if (wait > 0) TimeUnit.NANOSECONDS.sleep(wait)
            }
        }
        val legacySession = java.util.UUID.randomUUID().toString()
        for ((index,s) in samples.withIndex()) {
            pace(started,index)
            val valid = s.optString("quality") in listOf("available","unverified") && s.has("value")
            baseline.execSQL("INSERT INTO samples(id,at,value,state,segment,sample) VALUES(?,?,?,?,?,?)",arrayOf<Any?>(id,s.getLong("receivedAt"),if (valid) s.getDouble("value") else null,if (valid) s.get("value").toString() else "unavailable","$legacySession|$id|${s.optLong("sourceEpoch")}|${s.optString("quality")}|${s.optString("unit")}|${s.optInt("definitionVersion",1)}",s.toString()))
            if ((index+1)%256 == 0) {
                val cutoff = System.currentTimeMillis()-30*60000L
                baseline.execSQL("DELETE FROM samples WHERE at < ? AND seq NOT IN (SELECT MAX(seq) FROM samples WHERE at < ? GROUP BY id)",arrayOf(cutoff,cutoff))
            }
        }
        val baselineMs = (System.nanoTime()-started)/1_000_000
        val after = io()
        baseline.rawQuery("SELECT COUNT(*) FROM samples",null).use { it.moveToFirst(); assertEquals(count,it.getInt(0)) }
        baseline.close()
        val scheduler = java.util.concurrent.Executors.newSingleThreadScheduledExecutor()
        val history = if (paced) LocalHistory(context,scheduleFlush = { _, callback -> scheduler.schedule(callback,LocalHistory.FLUSH_INTERVAL_SECONDS,TimeUnit.SECONDS) }) else LocalHistory(context)
        history.configure(config())
        val batchDb = org.robolectric.util.ReflectionHelpers.getField<SQLiteDatabase>(history,"database")
        batchDb.rawQuery("PRAGMA journal_mode=DELETE",null).use { it.moveToFirst() }; batchDb.execSQL("PRAGMA synchronous=FULL")
        val batchBefore = io(); val batchStarted = System.nanoTime()
        for ((index,s) in samples.withIndex()) { pace(batchStarted,index); history.append(id,s) }
        history.flush()
        val batchMs = (System.nanoTime()-batchStarted)/1_000_000
        val batchAfter = io()
        val result = JSONObject().put("samples",count).put("pacedSamplesPerSecond",if (paced) 64 else JSONObject.NULL)
            .put("journalMode",batchDb.rawQuery("PRAGMA journal_mode",null).use { it.moveToFirst(); it.getString(0) })
            .put("synchronous",batchDb.rawQuery("PRAGMA synchronous",null).use { it.moveToFirst(); it.getInt(0) }).put("baselineMs",baselineMs).put("batchMs",batchMs)
            .put("baselineWrittenCharacters",after.getValue("wchar")-before.getValue("wchar"))
            .put("batchWrittenCharacters",batchAfter.getValue("wchar")-batchBefore.getValue("wchar"))
            .put("baselineWriteBytes",after.getValue("write_bytes")-before.getValue("write_bytes"))
            .put("batchWriteBytes",batchAfter.getValue("write_bytes")-batchBefore.getValue("write_bytes"))
            .put("baselineWriteSyscalls",after.getValue("syscw")-before.getValue("syscw"))
            .put("batchWriteSyscalls",batchAfter.getValue("syscw")-batchBefore.getValue("syscw"))
            .put("batchTransactions",history.storageStats().getLong("batchTransactions"))
        println("SKYINFO_HISTORY_BENCHMARK_JSON $result")
        val points = history.query(id,30).getJSONArray("points")
        assertEquals(count,points.length())
        repeat(count) { assertEquals(samples[it].toString(),points.getJSONObject(it).getJSONObject("sample").toString()) }
        assertEquals(999,points.getJSONObject(153).getInt("value"))
        assertTrue(points.getJSONObject(175).isNull("value"))
        assertTrue(result.getLong("batchWrittenCharacters") < result.getLong("baselineWrittenCharacters")/10)
        assertTrue(result.getLong("batchWriteSyscalls") < result.getLong("baselineWriteSyscalls")/10)
        history.clear(); scheduler.shutdownNow(); SQLiteDatabase.deleteDatabase(baselineFile)
    }
}
