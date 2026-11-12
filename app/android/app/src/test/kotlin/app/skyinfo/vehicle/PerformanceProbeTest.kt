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
import java.io.PrintWriter
import java.io.StringWriter
import java.util.concurrent.ExecutorService
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
@SQLiteMode(SQLiteMode.Mode.NATIVE)
class PerformanceProbeTest {
    @Test fun disabledAndNonAlphaNeverOpenWindow() {
        val off = PerformanceProbe(false) { error("disabled probe must not read clock") }
        assertNull(off.start(120,JSONObject()))
        assertFalse(off.active)
        assertEquals(0L,off.beginTiming())
        off.add("sample"); off.sample("a"); off.timing("work",0)
        assertFalse(off.acceptFlutter(1,JSONObject()))
    }
    @Test fun boundedWindowRejectsReentryAndStopsCountingAtDeadline() {
        var now = 1_000_000_000L
        val probe = PerformanceProbe(true) { now }
        assertEquals("disabled",probe.snapshot().getString("state"))
        val id = probe.start(1,JSONObject())!!
        assertNull(probe.start(1,JSONObject()))
        probe.sample("a"); probe.sample("a"); probe.sample("b")
        val measured = probe.beginTiming(); now += 100
        probe.timing("convert",measured)
        now = 2_000_000_000L
        probe.sample("c"); probe.add("late"); probe.timing("convert",measured)
        val snapshot = probe.snapshot()
        assertEquals("complete",snapshot.getString("state"))
        assertEquals(1000,snapshot.getInt("elapsedMillis"))
        assertEquals(3,snapshot.getJSONObject("counts").getInt("samples_received"))
        assertEquals(2,snapshot.getInt("uniqueSampleFields"))
        assertFalse(snapshot.getJSONObject("counts").has("late"))
        assertEquals(100,snapshot.getJSONObject("timingsWallNanos").getJSONObject("convert").getInt("total"))
        assertTrue(probe.stop(id,"timeout")); assertFalse(probe.stop(id,"timeout"))
    }
    @Test fun reportSessionIsolationAndFixedNumericShape() {
        var now = 1L
        val probe = PerformanceProbe(true) { now }
        val first = probe.start(1,JSONObject())!!
        probe.stop(first,"stopped")
        assertTrue(probe.acceptFlutter(first,JSONObject().put("frames",2).put("address","private").put("rasterMicros",-1)))
        assertFalse(probe.acceptFlutter(first,JSONObject().put("frames",3)))
        assertEquals(setOf("frames"),probe.snapshot().getJSONObject("flutter").keys().asSequence().toSet())
        now++
        val second = probe.start(1,JSONObject())!!
        assertFalse(probe.acceptFlutter(first,JSONObject()))
        assertFalse(probe.stop(first,"stopped"))
        assertTrue(probe.active)
        assertTrue(probe.stop(second,"stopped"))
    }
    @Test fun durationAndUniqueFieldStorageAreBounded() {
        val probe = PerformanceProbe(true) { 1L }
        for (duration in listOf(0,181)) {
            try { probe.start(duration,JSONObject()); fail("invalid duration") } catch (_: IllegalArgumentException) { }
        }
        probe.start(180,JSONObject())
        repeat(1000) { probe.sample(it.toString()) }
        assertEquals(256,probe.snapshot().getInt("uniqueSampleFields"))
    }
    @Test fun historyInstrumentationPreservesPendingQueriesAndDoesNotFlushOrChangePragmas() {
        var now = 1_000_000_000L
        val probe = PerformanceProbe(true) { now++ }
        val context = RuntimeEnvironment.getApplication()
        val history = LocalHistory(context,performance = probe)
        history.clear()
        history.configure(JSONObject().put("localHistory",true).put("tiles",JSONArray().put(JSONObject().put("fields",JSONArray().put("a")))))
        val settings = history.performanceSettings().toString()
        val cachedSettings = JSONObject(settings)
        assertEquals(setOf("open","journal_mode","synchronous","page_size","wal_autocheckpoint","cache_size","cache_spill"),cachedSettings.keys().asSequence().toSet())
        assertNotNull(cachedSettings.getString("cache_size").toIntOrNull())
        assertNotNull(cachedSettings.getString("cache_spill").toIntOrNull())
        probe.start(180,JSONObject())
        val sample = JSONObject().put("value",1).put("raw",1).put("receivedAt",System.currentTimeMillis()).put("quality","available")
        history.append("a",sample)
        assertEquals(1,history.query("a",30).getJSONArray("points").length())
        assertEquals(settings,history.performanceSettings().toString())
        assertEquals(0,history.storageStats().getInt("batchTransactions"))
        var counts = probe.snapshot().getJSONObject("counts")
        assertEquals(1,counts.getInt("history_append_rows"))
        assertEquals(sample.toString().length,counts.getInt("history_returned_sample_chars"))
        assertFalse(counts.has("history_transactions"))
        history.flush()
        counts = probe.snapshot().getJSONObject("counts")
        assertEquals(1,counts.getInt("history_committed_rows"))
        assertEquals(1,counts.getInt("history_transactions"))
        assertEquals(1,history.query("a",30).getJSONArray("points").length())
        history.clear()
    }
    @Test fun serviceGateAndRuntimeLifecycleCleanTheScheduledWindow() {
        val output = StringWriter()
        if (BuildConfig.FLAVOR != "alpha") {
            // A rejected command must work without an attached Context or coordinator.
            RuntimeService::class.java.getDeclaredMethod("dump",java.io.FileDescriptor::class.java,PrintWriter::class.java,Array<String>::class.java)
                .apply { isAccessible = true }.invoke(RuntimeService(),java.io.FileDescriptor(),PrintWriter(output),arrayOf("perf-start","180"))
            assertTrue(output.toString().contains("unavailable"))
            return
        }
        val constructor = RuntimeCoordinator::class.java.getDeclaredConstructor(android.content.Context::class.java).apply { isAccessible = true }
        val runtime = constructor.newInstance(RuntimeEnvironment.getApplication())
        fun field(name: String) = RuntimeCoordinator::class.java.getDeclaredField(name).apply { isAccessible = true }
        val worker = field("worker").get(runtime) as ExecutorService
        val probe = field("performance").get(runtime) as PerformanceProbe
        fun drain() { worker.submit {}.get(10,TimeUnit.SECONDS) }
        try {
            runtime.dumpPerformance(PrintWriter(output),arrayOf("perf-start","180")); drain()
            assertTrue(output.toString().contains("queued")); assertTrue(probe.active)
            val firstTimeout = field("performanceStop").get(runtime) as Future<*>
            worker.submit { runtime.stop() }.get(10,TimeUnit.SECONDS)
            assertFalse(probe.active); assertTrue(firstTimeout.isCancelled)
            assertNull(field("performanceStop").get(runtime))
            runtime.dumpPerformance(PrintWriter(output),arrayOf("perf-start","180")); drain()
            assertTrue(probe.active)
            val secondTimeout = field("performanceStop").get(runtime) as Future<*>
            val service = RuntimeService()
            field("service").set(runtime,service)
            runtime.detach(service); drain()
            assertFalse(probe.active); assertTrue(secondTimeout.isCancelled)
            assertEquals("service_detached",probe.snapshot().getString("reason"))
        } finally {
            (field("localHistory").get(runtime) as LocalHistory).clear()
            for (name in listOf("worker","network","source")) (field(name).get(runtime) as ExecutorService).shutdownNow()
        }
    }
}
