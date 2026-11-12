package app.skyinfo.vehicle

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import android.util.Log
import java.io.ByteArrayOutputStream
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/** Component identifiers are structured data, never shell commands or flattened intents. */
data class SplitTarget(val packageName: String, val activityName: String? = null) {
    companion object {
        private val packagePattern = Regex("[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)*")
        private val activityPattern = Regex("\\.?[A-Za-z_$][A-Za-z0-9_$]*(\\.[A-Za-z_$][A-Za-z0-9_$]*)*")
        fun parse(value: Any?): SplitTarget? {
            val data = value as? Map<*, *> ?: return null
            val pkg = data["packageName"] as? String ?: return null
            val activity = data["activityName"]
            if (pkg.length !in 1..255 || !packagePattern.matches(pkg)) return null
            if (activity != null && (activity !is String || activity.length !in 1..512 || !activityPattern.matches(activity))) return null
            return SplitTarget(pkg, activity)
        }
        fun activityName(pkg: String, name: String) = when {
            name.startsWith('.') -> pkg + name
            !name.contains('.') -> "$pkg.$name"
            else -> name
        }
    }
}

data class SplitComponent(val packageName: String, val activityName: String)
data class SplitCheck(val component: SplitComponent? = null, val reason: String? = null)

/** Main-thread state machine; the Android adapter performs package queries on its worker. */
class SplitLaunchSequence(
    private val validate: (SplitTarget, (SplitCheck) -> Unit) -> Unit,
    private val start: (SplitComponent, String) -> String?,
    private val checkDirection: (String, (SplitLayoutCheck) -> Unit) -> Unit = { _, done -> done(SplitLayoutCheck()) },
    private val delay: (Long, () -> Unit) -> (() -> Unit)
) {
    companion object {
        const val PRIMARY = "byd.intent.category.START_IVI_PRIMARY"
        const val SECOND = "byd.intent.category.START_IVI_SECOND"
        // NEW_TASK | MULTIPLE_TASK | REORDER_TO_FRONT | NO_ANIMATION |
        // RETAIN_IN_RECENTS | LAUNCH_ADJACENT. OEM layout effects require device validation.
        const val FLAGS = 0x18033000
        const val DELAY_MS = 800L
    }
    private class Pending(val reply: (Map<String, Any>) -> Unit) {
        var leftRequested = false
        var rightRequested = false
        var cancelDelay: (() -> Unit)? = null
    }
    private var pending: Pending? = null
    private var closed = false
    fun launch(left: SplitTarget?, right: SplitTarget?, ratio: String?, reply: (Map<String, Any>) -> Unit) {
        if (closed) { reply(result("failed", "cancelled")); return }
        if (pending != null) { reply(result("busy", "busy")); return }
        if (ratio !in setOf("7/3", "3/7")) { reply(result("failed", "invalid_ratio")); return }
        if (left == null || right == null) { reply(result("failed", "invalid_target", if (left == null) "left" else "right")); return }
        val job = Pending(reply); pending = job
        fun current() = pending === job && !closed
        fun finish(status: String, reason: String? = null, side: String? = null, layout: SplitLayoutCheck? = null) {
            if (!current()) return
            pending = null; job.cancelDelay?.invoke()
            reply(result(status, reason, side, job.leftRequested, job.rightRequested, layout))
        }
        validate(left) leftCheck@ { leftResult ->
            if (!current()) return@leftCheck
            val l = leftResult.component ?: run { finish(if (leftResult.reason == "unsupported_device") "unsupported" else "failed", leftResult.reason ?: "invalid_target", "left"); return@leftCheck }
            validate(right) rightCheck@ { rightResult ->
                if (!current()) return@rightCheck
                if (rightResult.component == null) { finish(if (rightResult.reason == "unsupported_device") "unsupported" else "failed", rightResult.reason ?: "invalid_target", "right"); return@rightCheck }
                if (l == rightResult.component) { finish("failed", "duplicate_target", "right"); return@rightCheck }
                // Establish PRIMARY before SECOND: the OEM restores an empty PRIMARY
                // from its saved package, which can otherwise steal the SECOND task.
                val primaryIsLeft = ratio == "3/7"
                val first = if (primaryIsLeft) l else rightResult.component
                val second = if (primaryIsLeft) right else left
                val firstSide = if (primaryIsLeft) "left" else "right"
                val secondSide = if (primaryIsLeft) "right" else "left"
                val failure = start(first, PRIMARY)
                if (failure != null) { finish("failed", failure, firstSide); return@rightCheck }
                job.leftRequested = primaryIsLeft
                job.rightRequested = !primaryIsLeft
                job.cancelDelay = delay(DELAY_MS) {
                    if (current()) validate(second) finalCheck@ { fresh ->
                        if (!current()) return@finalCheck
                        val r = fresh.component ?: run { finish("partial", fresh.reason ?: "invalid_target", secondSide); return@finalCheck }
                        val secondFailure = start(r, SECOND)
                        if (secondFailure != null) finish("partial", secondFailure, secondSide)
                        else {
                            job.leftRequested = true
                            job.rightRequested = true
                            checkDirection(ratio!!) { layout -> if (current()) finish("requested", layout = layout) }
                        }
                    }
                }
            }
        }
    }
    fun close() {
        closed = true
        val job = pending; pending = null
        job?.cancelDelay?.invoke()
        job?.reply?.invoke(if (job.leftRequested && job.rightRequested) result("requested", leftRequested = true, rightRequested = true, layout = SplitLayoutCheck("direction_cancelled"))
            else result(if (job.leftRequested || job.rightRequested) "partial" else "failed", "cancelled",
                if (job.leftRequested) "right" else if (job.rightRequested) "left" else null, job.leftRequested, job.rightRequested))
    }
    private fun result(status: String, reason: String? = null, side: String? = null, leftRequested: Boolean = false, rightRequested: Boolean = false, layout: SplitLayoutCheck? = null): Map<String, Any> = buildMap {
        put("status", status)
        if (reason != null) put("reason", reason)
        if (side != null) put("side", side)
        put("requestedSides", buildList { if (leftRequested) add("left"); if (rightRequested) add("right") })
        layout?.let {
            put("directionVerified", it.directionVerified)
            put("layoutStatus", "unverified")
            it.reason?.let { reason -> put("layoutReason", reason) }
        }
    }
}

/** Queries only this Android user's visible packages; there is no polling or ADB dependency. */
class SplitScreen(private val activity: Activity) {
    private val pm = activity.packageManager
    private val main = Handler(Looper.getMainLooper())
    private val worker = ThreadPoolExecutor(1, 1, 15, TimeUnit.SECONDS, ArrayBlockingQueue(8)).apply { allowCoreThreadTimeOut(true) }
    private val icons = object : LruCache<String, ByteArray>(2 * 1024 * 1024) {
        override fun sizeOf(key: String, value: ByteArray) = value.size
    }
    private var closed = false
    private val queries = mutableSetOf<(Map<String, Any>) -> Unit>()
    private val direction = SplitDirection(activity)
    private val directionSequence = SplitDirectionSequence(direction::read, direction::swap) { milliseconds, action ->
        val runnable = Runnable(action); main.postDelayed(runnable, milliseconds)
        val cancel: () -> Unit = { main.removeCallbacks(runnable) }; cancel
    }
    private val sequence = SplitLaunchSequence({ target, done ->
        execute({ if (supported()) check(target) else SplitCheck(reason = "unsupported_device") }, { done(it) }, { done(SplitCheck(reason = it)) })
    }, ::start, directionSequence::ensure) { milliseconds, action ->
        val runnable = Runnable(action); main.postDelayed(runnable, milliseconds)
        val cancel: () -> Unit = { main.removeCallbacks(runnable) }; cancel
    }
    // BYD's framework categories have no public capability API. A visible OEM system
    // management package is a candidate signal; accepted requests still need layout verification.
    private fun supported(): Boolean = try {
        val info = pm.getApplicationInfo("com.byd.appstartmanagement", 0)
        info.enabled && info.flags and (ApplicationInfo.FLAG_SYSTEM or ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
    } catch (_: Exception) { false }
    fun apps(reply: (Map<String, Any>) -> Unit) = query("apps", reply) {
        val candidates = pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), PackageManager.MATCH_DISABLED_COMPONENTS)
        val apps = candidates.mapNotNull { it.activityInfo?.packageName }.distinct().mapNotNull { pkg ->
            try {
                val component = defaultComponent(pkg) ?: return@mapNotNull null
                val info = pm.getApplicationInfo(pkg, 0)
                buildMap<String, Any> {
                    put("packageName", pkg); put("label", pm.getApplicationLabel(info).toString()); put("defaultActivity", component.activityName)
                    icon(info)?.let { put("iconBytes", it) }
                }
            } catch (_: PackageManager.NameNotFoundException) { null }
        }.sortedBy { (it["label"] as String).lowercase(java.util.Locale.ROOT) }
        mapOf("apps" to apps, "supported" to supported())
    }
    fun activities(packageName: String?, reply: (Map<String, Any>) -> Unit) = query("activities", reply) {
        val target = SplitTarget.parse(mapOf("packageName" to packageName))
            ?: return@query mapOf("activities" to emptyList<Any>(), "reason" to "invalid_target")
        val info = pm.getPackageInfo(target.packageName, PackageManager.GET_ACTIVITIES or PackageManager.MATCH_DISABLED_COMPONENTS)
        val default = defaultComponent(target.packageName)
        val activities = (info.activities ?: emptyArray()).map { item ->
            val reason = unavailable(item)
            buildMap<String, Any> {
                put("packageName", item.packageName); put("activityName", item.name); put("label", item.loadLabel(pm).toString())
                put("isDefault", item.name == default?.activityName); put("enabled", enabled(item)); put("exported", item.exported); put("available", reason == null)
                if (reason != null) put("reason", reason)
            }
        }.sortedWith(compareByDescending<Map<String, Any>> { it["isDefault"] as Boolean }.thenBy { it["activityName"] as String })
        mapOf("activities" to activities)
    }
    fun launch(arguments: Any?, reply: (Map<String, Any>) -> Unit) {
        val args = arguments as? Map<*, *>
        sequence.launch(SplitTarget.parse(args?.get("left")), SplitTarget.parse(args?.get("right")), args?.get("ratio") as? String, reply)
    }
    private fun check(target: SplitTarget): SplitCheck = try {
        if (target.activityName == null) defaultComponent(target.packageName)?.let { SplitCheck(it) }
            ?: SplitCheck(reason = "activity_unavailable")
        else {
            val name = SplitTarget.activityName(target.packageName, target.activityName)
            val info = pm.getActivityInfo(ComponentName(target.packageName, name), PackageManager.MATCH_DISABLED_COMPONENTS)
            val reason = unavailable(info)
            if (reason == null) SplitCheck(SplitComponent(info.packageName, info.name)) else SplitCheck(reason = reason)
        }
    } catch (_: PackageManager.NameNotFoundException) { SplitCheck(reason = "activity_unavailable") }
    private fun defaultComponent(pkg: String): SplitComponent? {
        // Resolve the package's real launcher entry on every explicit query or launch.
        val intent = pm.getLaunchIntentForPackage(pkg) ?: return null
        val c = intent.component ?: return null
        if (c.packageName != pkg) return null
        val info = try { pm.getActivityInfo(c, PackageManager.MATCH_DISABLED_COMPONENTS) } catch (_: PackageManager.NameNotFoundException) { return null }
        return if (unavailable(info) == null) SplitComponent(info.packageName, info.name) else null
    }
    private fun enabled(info: ActivityInfo): Boolean {
        val appSetting = pm.getApplicationEnabledSetting(info.packageName)
        val componentSetting = pm.getComponentEnabledSetting(ComponentName(info.packageName, info.name))
        fun state(setting: Int, manifest: Boolean) = setting == PackageManager.COMPONENT_ENABLED_STATE_ENABLED || setting == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && manifest
        return state(appSetting, info.applicationInfo.enabled) && state(componentSetting, info.enabled) && info.applicationInfo.flags and ApplicationInfo.FLAG_SUSPENDED == 0
    }
    private fun unavailable(info: ActivityInfo): String? = when {
        !enabled(info) -> "disabled"
        !info.exported -> "not_exported"
        !info.permission.isNullOrEmpty() && pm.checkPermission(info.permission, activity.packageName) != PackageManager.PERMISSION_GRANTED -> "permission_denied"
        else -> null
    }
    private fun icon(info: ApplicationInfo): ByteArray? = try {
        val update = pm.getPackageInfo(info.packageName, 0).lastUpdateTime
        val key = "${info.packageName}:$update:${info.icon}"
        icons.get(key) ?: run {
            val drawable = pm.getApplicationIcon(info)
            val bitmap = Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888)
            try {
                drawable.setBounds(0, 0, 64, 64); drawable.draw(Canvas(bitmap))
                ByteArrayOutputStream().use { output -> bitmap.compress(Bitmap.CompressFormat.PNG, 100, output); output.toByteArray() }.also { icons.put(key, it) }
            } finally { bitmap.recycle() }
        }
    } catch (_: Exception) { null }
    private fun start(component: SplitComponent, category: String): String? = try {
        val target = ComponentName(component.packageName, component.activityName)
        // Keep this host's Flutter engine, event subscription and current page in its
        // existing task. Other apps retain the OEM candidate launch parameters.
        val flags = if (target == activity.componentName) SplitLaunchSequence.FLAGS and
            (Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK or Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT).inv()
        else SplitLaunchSequence.FLAGS
        if (ChannelDiagnostics.enabled) Log.i("SkyInfoSplit", "request component=${target.flattenToShortString()} category=$category flags=0x${flags.toString(16)}")
        activity.startActivity(Intent(Intent.ACTION_MAIN).addCategory(category).setComponent(target).addFlags(flags))
        null
    } catch (error: ActivityNotFoundException) { Log.w("SkyInfoSplit", "Split activity unavailable", error); "activity_not_found" }
    catch (error: SecurityException) { Log.w("SkyInfoSplit", "Split activity rejected", error); "launch_rejected" }
    catch (error: Exception) { Log.w("SkyInfoSplit", "Split activity failed", error); "launch_failed" }
    private fun query(key: String, reply: (Map<String, Any>) -> Unit, work: () -> Map<String, Any>) {
        if (closed) { reply(mapOf(key to emptyList<Any>(), "reason" to "cancelled")); return }
        queries.add(reply)
        fun finish(value: Map<String, Any>) { if (queries.remove(reply)) reply(value) }
        execute(work, ::finish) { finish(mapOf(key to emptyList<Any>(), "reason" to it)) }
    }
    private fun <T> execute(work: () -> T, done: (T) -> Unit, failure: (String) -> Unit) {
        try {
            worker.execute {
                try { val value = work(); main.post { if (!closed) done(value) } }
                catch (_: PackageManager.NameNotFoundException) { main.post { if (!closed) failure("package_unavailable") } }
                catch (_: Exception) { main.post { if (!closed) failure("query_failed") } }
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) { failure(if (closed) "cancelled" else "busy") }
    }
    fun close() {
        closed = true; directionSequence.close(); sequence.close(); worker.shutdownNow(); icons.evictAll()
        val replies = queries.toList(); queries.clear()
        replies.forEach { it(mapOf("apps" to emptyList<Any>(), "activities" to emptyList<Any>(), "reason" to "cancelled")) }
    }
}
