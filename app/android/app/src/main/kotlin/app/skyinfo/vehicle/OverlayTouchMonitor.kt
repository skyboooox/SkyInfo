package app.skyinfo.vehicle

import android.os.Handler
import android.os.SystemClock
import android.view.MotionEvent
import java.util.concurrent.TimeUnit

internal data class TouchPoint(val action: Int, val x: Float, val y: Float, val time: Long)

internal data class TouchDevice(val path: String, val minimumX: Int, val maximumX: Int, val minimumY: Int, val maximumY: Int)

internal fun primaryTouchDevice(capabilities: String): TouchDevice {
    val block = capabilities.split(Regex("(?m)(?=^add device [0-9]+:)"))
        .singleOrNull { Regex("(?m)^\\s*name:\\s*\"IVI_touch_vir\"\\s*$").containsMatchIn(it) }
        ?: error("Primary touch device unavailable")
    val path = Regex("^add device [0-9]+: (/dev/input/event[0-9]+)").find(block)?.groupValues?.get(1)
        ?: error("Touch node unavailable")
    fun range(axis: String): Pair<Int,Int> {
        val match = Regex("$axis\\s*:.*min (-?[0-9]+), max (-?[0-9]+)").find(block)
            ?: error("Touch axis unavailable")
        val min = match.groupValues[1].toInt(); val max = match.groupValues[2].toInt()
        check(min < max)
        return min to max
    }
    val (minX,maxX) = range("ABS_MT_POSITION_X"); val (minY,maxY) = range("ABS_MT_POSITION_Y")
    return TouchDevice(path,minX,maxX,minY,maxY)
}

internal class TouchFrameDecoder(private val width: Int, private val height: Int,
    private val minimumX: Int, private val maximumX: Int, private val minimumY: Int, private val maximumY: Int) {
    private var slot = 0
    private val active = mutableSetOf<Int>()
    private val x = mutableMapOf<Int, Int>()
    private val y = mutableMapOf<Int, Int>()
    private var previous = 0
    private var lastX = 0f
    private var lastY = 0f
    private var dropping = false
    fun line(line: String, time: Long): TouchPoint? {
        val parts = line.trim().split(Regex("\\s+"))
        if (parts.size < 3) return null
        val type = parts[parts.size - 3]; val code = parts[parts.size - 2]
        val value = parts.last().toLongOrNull(16)?.toInt() ?: return null
        if (type == "EV_ABS" && !dropping) when (code) {
            "ABS_MT_SLOT" -> slot = value
            "ABS_MT_TRACKING_ID" -> if (value < 0) active.remove(slot) else active.add(slot)
            "ABS_MT_POSITION_X" -> x[slot] = value
            "ABS_MT_POSITION_Y" -> y[slot] = value
        }
        if (type != "EV_SYN") return null
        if (code == "SYN_DROPPED") { dropping = true; active.clear(); previous = 0; return TouchPoint(MotionEvent.ACTION_CANCEL,lastX,lastY,time) }
        if (code != "SYN_REPORT") return null
        if (dropping) { dropping = false; return null }
        val count = active.size
        if (count == 1) {
            val id = active.single()
            val px = x[id] ?: return null; val py = y[id] ?: return null
            lastX = ((px - minimumX).toFloat() / (maximumX - minimumX) * width).coerceIn(0f,width.toFloat())
            lastY = ((py - minimumY).toFloat() / (maximumY - minimumY) * height).coerceIn(0f,height.toFloat())
        }
        val action = when {
            count > 1 || previous > 1 -> MotionEvent.ACTION_CANCEL
            count == 1 && previous == 0 -> MotionEvent.ACTION_DOWN
            count == 1 -> MotionEvent.ACTION_MOVE
            previous == 1 -> MotionEvent.ACTION_UP
            else -> null
        }
        previous = count
        return action?.let { TouchPoint(it,lastX,lastY,time) }
    }
}

internal class OverlayTouchMonitor(private val main: Handler, private val width: Int, private val height: Int,
    private val point: (TouchPoint) -> Unit, private val state: (String) -> Unit) {
    @Volatile private var closed = false
    private var process: Process? = null
    fun start() {
        Thread {
            try {
                val probe = ProcessBuilder("/system/bin/getevent","-lp").redirectErrorStream(true).start()
                val timeout = Runnable { probe.destroy() }
                main.postDelayed(timeout,2000)
                val capabilities = try { probe.inputStream.bufferedReader().use { it.readText() } }
                    finally { main.removeCallbacks(timeout) }
                check(probe.waitFor(200,TimeUnit.MILLISECONDS))
                val device = primaryTouchDevice(capabilities)
                val decoder = TouchFrameDecoder(width,height,device.minimumX,device.maximumX,device.minimumY,device.maximumY)
                val reading = ProcessBuilder("/system/bin/getevent","-l",device.path).redirectErrorStream(true).start()
                synchronized(this) { if (closed) { reading.destroy(); return@Thread }; process = reading }
                main.post { if (!closed) state("ready") }
                reading.inputStream.bufferedReader().useLines { lines -> lines.forEach { line ->
                    decoder.line(line,SystemClock.uptimeMillis())?.let { p -> main.post { if (!closed) point(p) } }
                } }
                if (!closed) error("Touch stream ended")
            } catch (_: Throwable) { main.post { if (!closed) state("unavailable") } }
            finally { synchronized(this) { process?.destroy(); process = null } }
        }.apply { name = "SkyInfo-overlay-touch"; isDaemon = true; start() }
    }
    @Synchronized fun close() { closed = true; process?.destroy(); process = null }
}
