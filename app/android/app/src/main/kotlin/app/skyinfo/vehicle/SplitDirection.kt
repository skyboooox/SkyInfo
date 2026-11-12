package app.skyinfo.vehicle

import android.app.Activity
import android.provider.Settings
import android.util.Log
import java.lang.reflect.InvocationTargetException

data class SplitDirectionState(val position: Int, val dual: Boolean)
data class SplitLayoutCheck(val reason: String? = null, val directionVerified: Boolean = false)

/** Bounded, launch-scoped direction adjustment after both start requests. */
class SplitDirectionSequence(
    private val read: () -> SplitDirectionState?,
    private val swap: () -> String?,
    private val delay: (Long, () -> Unit) -> (() -> Unit)
) {
    private var generation = 0
    private var cancel: (() -> Unit)? = null
    fun ensure(ratio: String, reply: (SplitLayoutCheck) -> Unit) {
        val token = ++generation
        cancel?.invoke(); cancel = null
        val wanted = if (ratio == "3/7") 1 else 2
        var reads = 0
        var swapped = false
        fun finish(value: SplitLayoutCheck) {
            if (generation != token) return
            generation++; cancel?.invoke(); cancel = null; reply(value)
        }
        fun check() {
            if (generation != token) return
            val state = read() ?: run { finish(SplitLayoutCheck("direction_unavailable")); return }
            if (state.position !in 1..2) { finish(SplitLayoutCheck("direction_unavailable")); return }
            if (state.dual && state.position == wanted) { finish(SplitLayoutCheck(directionVerified = true)); return }
            if (state.dual && !swapped) {
                val failure = swap()
                if (failure != null) { finish(SplitLayoutCheck(failure)); return }
                swapped = true
                // The checked OEM implementation animates the containers for 1000 ms.
                cancel = delay(1250L, ::check)
            } else if (++reads < 12) {
                cancel = delay(250L, ::check)
            } else {
                finish(SplitLayoutCheck(if (state.dual) "direction_unconfirmed" else "split_not_established"))
            }
        }
        cancel = delay(250L, ::check)
    }
    fun close() { generation++; cancel?.invoke(); cancel = null }
}

/** OEM direction methods resolved by their checked framework names. */
class SplitDirection(private val activity: Activity) {
    private val taskInterface by lazy { Class.forName("android.app.IActivityTaskManager") }
    private val service by lazy { Class.forName("android.app.ActivityTaskManager").getMethod("getService").invoke(null) }
    private fun cause(error: Exception): Throwable = (error as? InvocationTargetException)?.targetException ?: error
    fun read(): SplitDirectionState? = try {
        val area = taskInterface.getMethod("getScreenAreaInfoForMulti").invoke(service) as Int
        val position = Settings.System.getInt(activity.contentResolver, "byd_smart_multi_primary_position", 0)
        if (ChannelDiagnostics.enabled) Log.i("SkyInfoSplit", "direction state position=$position area=$area")
        SplitDirectionState(position, area and 3 == 3 && area and (4 or 16) == 0)
    } catch (error: Exception) {
        Log.w("SkyInfoSplit", "Cannot read OEM split direction", cause(error)); null
    }
    fun swap(): String? = try {
        taskInterface.getMethod("SwapSplitPosition").invoke(service)
        if (ChannelDiagnostics.enabled) Log.i("SkyInfoSplit", "direction swap requested")
        null
    } catch (error: Exception) {
        val failure = cause(error)
        Log.w("SkyInfoSplit", "OEM split direction adjustment failed", failure)
        if (failure is SecurityException) "direction_denied" else "direction_unavailable"
    }
}
