package app.skyinfo.vehicle

import android.os.SystemClock
import org.json.JSONObject

/** One bounded, opt-in window. Timings are elapsed wall time, not CPU time. */
class PerformanceProbe(private val enabled: Boolean = BuildConfig.FLAVOR == "alpha",
    private val clock: () -> Long = SystemClock::elapsedRealtimeNanos) {
    @Volatile private var running = false
    private var serial = 0L
    private var deadline = 0L
    private var started = 0L
    private var ended = 0L
    private var reason = "disabled"
    private val counts = linkedMapOf<String,Long>()
    private val timings = linkedMapOf<String,LongArray>()
    private val fields = linkedSetOf<String>()
    private var context = JSONObject()
    private var flutter: JSONObject? = null
    val active: Boolean get() = running && clock() < deadline
    fun beginTiming(): Long = if (active) clock() else 0L
    @Synchronized fun start(seconds: Int, metadata: JSONObject): Long? {
        if (!enabled || running) return null
        require(seconds in 1..180)
        serial++; started = clock(); deadline = started + seconds * 1_000_000_000L
        ended = 0; reason = "running"; counts.clear(); timings.clear(); fields.clear()
        context = metadata; flutter = null; running = true
        return serial
    }
    @Synchronized fun stop(id: Long, why: String): Boolean {
        if (id != serial || !running) return false
        ended = minOf(clock(),deadline); running = false; reason = why
        return true
    }
    @Synchronized fun add(key: String, amount: Long = 1) {
        if (active) counts[key] = (counts[key] ?: 0) + amount
    }
    @Synchronized fun sample(id: String) {
        if (!active) return
        counts["samples_received"] = (counts["samples_received"] ?: 0) + 1
        if (fields.size < 256) fields.add(id)
    }
    @Synchronized fun timing(key: String, since: Long) {
        if (since == 0L || since < started || !active) return
        val elapsed = (clock()-since).coerceAtLeast(0)
        val t = timings.getOrPut(key) { LongArray(3) }
        t[0]++; t[1] += elapsed; t[2] = maxOf(t[2],elapsed)
    }
    @Synchronized fun acceptFlutter(id: Long, report: JSONObject): Boolean {
        if (!enabled || serial == 0L || id != serial || flutter != null) return false
        // Only fixed numeric aggregates cross into the cached dump; never arbitrary Dart data.
        val safe = JSONObject()
        for (key in listOf("events", "sampleEntries", "sampleNotifications", "applyCalls", "applyMicros", "applyMaxMicros",
            "frames", "buildMicros", "rasterMicros", "buildMaxMicros", "rasterMaxMicros", "elapsedMicros",
            "buildLe4ms","buildLe8ms","buildLe16ms","buildLe32ms","buildGt32ms",
            "rasterLe4ms","rasterLe8ms","rasterLe16ms","rasterLe32ms","rasterGt32ms")) {
            val value = report.opt(key)
            if (value is Number && value.toDouble().isFinite() && value.toDouble() >= 0) safe.put(key,value)
        }
        flutter = safe
        return true
    }
    @Synchronized fun snapshot(): JSONObject {
        val now = clock()
        val state = if (!enabled) "unavailable" else if (serial == 0L) "disabled" else if (active) "running" else "complete"
        return JSONObject().put("state",state).put("session",serial)
            .put("reason",if (running && now >= deadline) "timeout" else reason)
            .put("elapsedMillis",if (serial == 0L) 0 else ((if (ended != 0L) ended else minOf(now,deadline))-started)/1_000_000)
            .put("remainingMillis",if (active) (deadline-now)/1_000_000 else 0)
            .put("context",context).put("counts",JSONObject(counts as Map<*,*>)).put("uniqueSampleFields",fields.size)
            .put("timingsWallNanos",JSONObject().also { out -> timings.forEach { (key,t) -> out.put(key,JSONObject().put("calls",t[0]).put("total",t[1]).put("max",t[2])) } })
            .put("flutter",flutter ?: JSONObject.NULL)
    }
}
