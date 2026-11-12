package app.skyinfo.vehicle

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.os.Looper
import java.time.Duration
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RuntimeEnvironment
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SplitScreenTest {
    private val left = SplitTarget("test.left", "test.left.Main")
    private val right = SplitTarget("test.right", "test.right.Main")
    private class Fixture {
        var supported = true
        var invalid: String? = null
        var failure: String? = null
        val checks = mutableListOf<SplitTarget>()
        val starts = mutableListOf<Pair<SplitComponent, String>>()
        var delayed: (() -> Unit)? = null
        var cancelled = false
        val results = mutableListOf<Map<String, Any>>()
        val sequence = SplitLaunchSequence({ target, done ->
            if (!supported) { done(SplitCheck(reason = "unsupported_device")); return@SplitLaunchSequence }
            checks.add(target)
            done(if (invalid == target.packageName) SplitCheck(reason = "disabled") else SplitCheck(SplitComponent(target.packageName, target.activityName ?: "${target.packageName}.Main")))
        }, { component, category ->
            starts.add(component to category); failure
        }) { delay, action ->
            assertEquals(800L, delay); delayed = action
            val cancel: () -> Unit = { cancelled = true }; cancel
        }
    }
    @Test fun mapsRatiosToPrimaryFirstAndRefreshesSecondTarget() {
        for (ratio in listOf("7/3", "3/7")) {
            val f = Fixture()
            f.sequence.launch(left, right, ratio, f.results::add)
            assertEquals(listOf(left, right), f.checks)
            assertEquals(1, f.starts.size)
            assertTrue(f.results.isEmpty())
            assertEquals(if (ratio == "7/3") right.packageName else left.packageName, f.starts[0].first.packageName)
            assertEquals(SplitLaunchSequence.PRIMARY, f.starts[0].second)
            f.delayed!!.invoke()
            assertEquals(listOf(left, right, if (ratio == "7/3") left else right), f.checks)
            assertEquals(if (ratio == "7/3") left.packageName else right.packageName, f.starts[1].first.packageName)
            assertEquals(SplitLaunchSequence.SECOND, f.starts[1].second)
            assertEquals("requested", f.results.single()["status"])
            assertEquals(listOf("left", "right"), f.results.single()["requestedSides"])
            assertEquals(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_NO_ANIMATION or
                Intent.FLAG_ACTIVITY_RETAIN_IN_RECENTS or Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT, SplitLaunchSequence.FLAGS)
        }
    }
    @Test fun validatesBothTargetsBeforeStartingAndRejectsDuplicateComponents() {
        val f = Fixture(); f.invalid = right.packageName
        f.sequence.launch(left, right, "7/3", f.results::add)
        assertTrue(f.starts.isEmpty()); assertEquals("right", f.results.single()["side"])
        val duplicate = Fixture()
        duplicate.sequence.launch(left, left, "7/3", duplicate.results::add)
        assertTrue(duplicate.starts.isEmpty()); assertEquals("duplicate_target", duplicate.results.single()["reason"])
    }
    @Test fun preventsOverlapAndReportsPartialRequestWhenRightChangesOrFails() {
        val f = Fixture()
        f.sequence.launch(left, right, "3/7", f.results::add)
        f.sequence.launch(left, right, "3/7", f.results::add)
        assertEquals("busy", f.results.single()["status"])
        f.invalid = right.packageName; f.delayed!!.invoke()
        assertEquals("partial", f.results.last()["status"])
        assertEquals(listOf("left"), f.results.last()["requestedSides"])
        assertEquals(1, f.starts.size)
        val rejected = Fixture()
        rejected.sequence.launch(left, right, "3/7", rejected.results::add)
        rejected.failure = "launch_rejected"; rejected.delayed!!.invoke()
        assertEquals("partial", rejected.results.single()["status"])
        assertEquals("launch_rejected", rejected.results.single()["reason"])
    }
    @Test fun destroyCompletesPendingReplyOnceAndCancelsSecondPane() {
        val f = Fixture()
        f.sequence.launch(left, right, "3/7", f.results::add)
        f.sequence.close(); f.delayed!!.invoke(); f.sequence.close()
        assertTrue(f.cancelled); assertEquals(1, f.starts.size)
        assertEquals("partial", f.results.single()["status"])
        assertEquals("cancelled", f.results.single()["reason"])
    }
    @Test fun destroyDuringValidationFinishesWithoutStarting() {
        var callback: ((SplitCheck) -> Unit)? = null
        val results = mutableListOf<Map<String, Any>>()
        val sequence = SplitLaunchSequence({ _, done -> callback = done }, { _, _ -> fail("unexpected launch"); null }, delay = { _, _ -> {} })
        sequence.launch(left, right, "7/3", results::add)
        sequence.close(); callback!!(SplitCheck(SplitComponent(left.packageName, left.activityName!!)))
        assertEquals("failed", results.single()["status"])
        assertEquals("cancelled", results.single()["reason"])
    }
    @Test fun rightPrimaryRequestSurvivesLeftFailureAndCancellation() {
        val invalidSecond = Fixture()
        invalidSecond.sequence.launch(left, right, "7/3", invalidSecond.results::add)
        invalidSecond.invalid = left.packageName; invalidSecond.delayed!!.invoke()
        assertEquals("partial", invalidSecond.results.single()["status"])
        assertEquals("left", invalidSecond.results.single()["side"])
        assertEquals(listOf("right"), invalidSecond.results.single()["requestedSides"])
        val rejectedSecond = Fixture()
        rejectedSecond.sequence.launch(left, right, "7/3", rejectedSecond.results::add)
        rejectedSecond.failure = "launch_rejected"; rejectedSecond.delayed!!.invoke()
        assertEquals("left", rejectedSecond.results.single()["side"])
        assertEquals(listOf("right"), rejectedSecond.results.single()["requestedSides"])
        val cancelled = Fixture()
        cancelled.sequence.launch(left, right, "7/3", cancelled.results::add)
        cancelled.sequence.close(); cancelled.delayed!!.invoke(); cancelled.sequence.close()
        assertEquals("partial", cancelled.results.single()["status"])
        assertEquals("left", cancelled.results.single()["side"])
        assertEquals(listOf("right"), cancelled.results.single()["requestedSides"])
    }
    @Test fun directionFailureKeepsBothRequestsAndLocksUntilCheckCompletes() {
        var delayed: (() -> Unit)? = null
        var directionReply: ((SplitLayoutCheck) -> Unit)? = null
        val results = mutableListOf<Map<String, Any>>()
        val sequence = SplitLaunchSequence({ target, done -> done(SplitCheck(SplitComponent(target.packageName, target.activityName!!))) },
            { _, _ -> null }, { _, done -> directionReply = done }) { _, action -> delayed = action; {} }
        sequence.launch(left, right, "3/7", results::add); delayed!!.invoke()
        sequence.launch(left, right, "7/3", results::add)
        assertEquals("busy", results.single()["status"])
        directionReply!!(SplitLayoutCheck("direction_unconfirmed"))
        assertEquals("requested", results.last()["status"])
        assertEquals(listOf("left", "right"), results.last()["requestedSides"])
        assertEquals("direction_unconfirmed", results.last()["layoutReason"])
        assertEquals("unverified", results.last()["layoutStatus"])
    }
    @Test fun destroyAfterBothRequestsKeepsBothRequestedSides() {
        var delayed: (() -> Unit)? = null
        var directionReply: ((SplitLayoutCheck) -> Unit)? = null
        val results = mutableListOf<Map<String, Any>>()
        val sequence = SplitLaunchSequence({ target, done -> done(SplitCheck(SplitComponent(target.packageName, target.activityName!!))) },
            { _, _ -> null }, { _, done -> directionReply = done }) { _, action -> delayed = action; {} }
        sequence.launch(left, right, "3/7", results::add); delayed!!.invoke(); sequence.close()
        directionReply!!(SplitLayoutCheck(directionVerified = true)); sequence.close()
        assertEquals("requested", results.single()["status"])
        assertEquals(listOf("left", "right"), results.single()["requestedSides"])
        assertEquals("direction_cancelled", results.single()["layoutReason"])
    }
    @Test fun rejectsUnsupportedInvalidInputsAndLeftFailure() {
        val f = Fixture(); f.supported = false
        f.sequence.launch(left, right, "7/3", f.results::add)
        assertEquals("unsupported", f.results.single()["status"]); assertTrue(f.checks.isEmpty())
        val invalid = Fixture()
        invalid.sequence.launch(null, right, "7/3", invalid.results::add)
        assertEquals("invalid_target", invalid.results.single()["reason"])
        val rejected = Fixture(); rejected.failure = "launch_rejected"
        rejected.sequence.launch(left, right, "3/7", rejected.results::add)
        assertEquals("failed", rejected.results.single()["status"]); assertNull(rejected.delayed)
        for (bad in listOf("pkg/name", "pkg;am start", "pkg Main", "pkg\nother")) assertNull(SplitTarget.parse(mapOf("packageName" to bad)))
        assertNull(SplitTarget.parse(mapOf("packageName" to "test.app", "activityName" to "test.app/Main")))
        assertEquals("test.app.Main", SplitTarget.activityName("test.app", ".Main"))
    }
    private fun packageInfo(pkg: String, vararg activities: Pair<String, String?>): PackageInfo = PackageInfo().apply {
        packageName = pkg
        applicationInfo = ApplicationInfo().apply { packageName = pkg; enabled = true; nonLocalizedLabel = "Label $pkg" }
        val app = applicationInfo
        this.activities = activities.map { (activityName, permissionName) -> ActivityInfo().apply {
            packageName = pkg; name = activityName; enabled = true; exported = true
            applicationInfo = app; permission = permissionName; nonLocalizedLabel = "Entry $activityName"
        } }.toTypedArray()
    }
    private fun awaitResult(action: ((Map<String, Any>) -> Unit) -> Unit): Map<String, Any> {
        var value: Map<String, Any>? = null
        action { value = it }
        val deadline = System.nanoTime() + 5_000_000_000L
        while (value == null && System.nanoTime() < deadline) { Thread.sleep(5); shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(50)) }
        return value ?: error("query did not complete")
    }
    @Test fun queriesActualLauncherLabelsAndActivityAvailabilityWithoutLaunching() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val pm = activity.packageManager
        val shadow = shadowOf(pm)
        val pkg = packageInfo("test.visible", "test.visible.Main" to null, "test.visible.Hidden" to null, "test.visible.Protected" to "test.permission.SECRET", "test.visible.Disabled" to null)
        pkg.activities!![1].exported = false; pkg.activities!![3].enabled = false
        shadow.installPackage(pkg)
        val launch = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER).setPackage(pkg.packageName)
        val resolved = ResolveInfo().apply { activityInfo = pkg.activities!![0] }
        shadow.addResolveInfoForIntent(launch, resolved)
        shadow.addResolveInfoForIntent(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), resolved)
        val screen = SplitScreen(activity)
        try {
            val apps = awaitResult(screen::apps)["apps"] as List<*>
            val app = apps.map { it as Map<*, *> }.single { it["packageName"] == pkg.packageName }
            assertEquals("Label test.visible", app["label"]); assertEquals("test.visible.Main", app["defaultActivity"])
            val entries = awaitResult { screen.activities(pkg.packageName, it) }["activities"] as List<*>
            val byName = entries.map { it as Map<*, *> }.associateBy { it["activityName"] }
            assertEquals(true, byName["test.visible.Main"]!!["available"])
            assertEquals("not_exported", byName["test.visible.Hidden"]!!["reason"])
            assertEquals("permission_denied", byName["test.visible.Protected"]!!["reason"])
            assertEquals("disabled", byName["test.visible.Disabled"]!!["reason"])
            assertNull(shadowOf(activity).nextStartedActivity)
            pm.setComponentEnabledSetting(ComponentName(pkg.packageName, "test.visible.Main"), PackageManager.COMPONENT_ENABLED_STATE_DISABLED, 0)
            val disabled = awaitResult(screen::apps)["apps"] as List<*>
            assertFalse(disabled.any { (it as Map<*, *>)["packageName"] == pkg.packageName })
        } finally { screen.close(); activity.finish() }
    }
    @Test fun oemCandidateRequiresEnabledSystemManagementPackage() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val shadow = shadowOf(activity.packageManager)
        val screen = SplitScreen(activity)
        fun supported() = awaitResult(screen::apps)["supported"]
        try {
            assertEquals(false, supported())
            val oem = packageInfo("com.byd.appstartmanagement")
            shadow.installPackage(oem)
            assertEquals(false, supported())
            oem.applicationInfo!!.flags = ApplicationInfo.FLAG_SYSTEM
            shadow.installPackage(oem)
            assertEquals(true, supported())
            oem.applicationInfo!!.flags = ApplicationInfo.FLAG_UPDATED_SYSTEM_APP
            shadow.installPackage(oem)
            assertEquals(true, supported())
            activity.packageManager.setApplicationEnabledSetting(oem.packageName, PackageManager.COMPONENT_ENABLED_STATE_DISABLED, 0)
            assertEquals(false, supported())
        } finally { screen.close(); activity.finish() }
    }
    @Test fun adapterSendsExplicitIntentsAndContinuesWhenLaunchingActivityPauses() {
        val owner = Robolectric.buildActivity(Activity::class.java).setup()
        val activity = owner.get()
        val shadow = shadowOf(activity.packageManager)
        val oem = packageInfo("com.byd.appstartmanagement").apply { applicationInfo!!.flags = ApplicationInfo.FLAG_SYSTEM }
        shadow.installPackage(oem)
        shadow.installPackage(packageInfo(left.packageName, left.activityName!! to null))
        shadow.installPackage(packageInfo(right.packageName, right.activityName!! to null))
        val screen = SplitScreen(activity)
        var result: Map<String, Any>? = null
        try {
            screen.launch(mapOf("left" to mapOf("packageName" to left.packageName, "activityName" to left.activityName),
                "right" to mapOf("packageName" to right.packageName, "activityName" to right.activityName), "ratio" to "7/3")) { result = it }
            var first: Intent? = null
            val deadline = System.nanoTime() + 5_000_000_000L
            while (first == null && System.nanoTime() < deadline) {
                Thread.sleep(5); shadowOf(Looper.getMainLooper()).idle(); first = shadowOf(activity).nextStartedActivity
            }
            assertNotNull(first)
            val firstIntent = first ?: error("first request missing")
            assertEquals(ComponentName(right.packageName, right.activityName!!), firstIntent.component)
            assertEquals(Intent.ACTION_MAIN, firstIntent.action)
            assertEquals(setOf(SplitLaunchSequence.PRIMARY), firstIntent.categories)
            assertEquals(SplitLaunchSequence.FLAGS, firstIntent.flags)
            owner.pause()
            assertNull(shadowOf(activity).nextStartedActivity)
            assertNull(result)
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(1050))
            val completion = awaitResult { done ->
                // The native result remains pending through the pause; completion is driven by
                // the worker's second validation, not by another launch request.
                val end = System.nanoTime() + 5_000_000_000L
                while (result == null && System.nanoTime() < end) { Thread.sleep(5); shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(50)) }
                result?.let(done)
            }
            assertEquals("requested", completion["status"])
            val second = shadowOf(activity).nextStartedActivity
            assertEquals(ComponentName(left.packageName, left.activityName!!), second.component)
            assertEquals(setOf(SplitLaunchSequence.SECOND), second.categories)
            assertEquals(SplitLaunchSequence.FLAGS, second.flags)
        } finally { screen.close(); owner.stop().destroy() }
    }
    @Test fun validatesRealComponentsAndPermissionsBeforeOpeningEitherSide() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val shadow = shadowOf(activity.packageManager)
        shadow.installPackage(packageInfo("com.byd.appstartmanagement").apply { applicationInfo!!.flags = ApplicationInfo.FLAG_SYSTEM })
        shadow.installPackage(packageInfo(left.packageName, left.activityName!! to null))
        val target = packageInfo(right.packageName, "test.right.Hidden" to null, "test.right.Protected" to "test.permission.SECRET", "test.right.Disabled" to null)
        target.activities!![0].exported = false; target.activities!![2].enabled = false
        shadow.installPackage(target)
        val screen = SplitScreen(activity)
        try {
            for ((entry, reason) in listOf("test.right.Hidden" to "not_exported", "test.right.Protected" to "permission_denied",
                "test.right.Disabled" to "disabled", "test.left.Main" to "activity_unavailable")) {
                val result = awaitResult { done -> screen.launch(mapOf(
                    "left" to mapOf("packageName" to left.packageName, "activityName" to left.activityName),
                    "right" to mapOf("packageName" to right.packageName, "activityName" to entry), "ratio" to "7/3"), done) }
                assertEquals("failed", result["status"]); assertEquals("right", result["side"]); assertEquals(reason, result["reason"])
                assertEquals(emptyList<String>(), result["requestedSides"])
                assertNull(shadowOf(activity).nextStartedActivity)
            }
        } finally { screen.close(); activity.finish() }
    }
    @Test fun currentHostComponentUsesExistingTaskOnEitherSideAndKeepsOemCategory() {
        for (selfOnLeft in listOf(true, false)) {
            val owner = Robolectric.buildActivity(Activity::class.java).setup()
            val activity = owner.get()
            val host = SplitTarget(activity.packageName, activity.componentName.className)
            val other = right
            val shadow = shadowOf(activity.packageManager)
            shadow.installPackage(packageInfo("com.byd.appstartmanagement").apply { applicationInfo!!.flags = ApplicationInfo.FLAG_SYSTEM })
            shadow.installPackage(packageInfo(host.packageName, host.activityName!! to null))
            shadow.installPackage(packageInfo(other.packageName, other.activityName!! to null))
            val l = if (selfOnLeft) host else other
            val r = if (selfOnLeft) other else host
            val screen = SplitScreen(activity)
            var result: Map<String, Any>? = null
            fun nextRequest(): Intent {
                var request: Intent? = null
                val end = System.nanoTime() + 5_000_000_000L
                while (request == null && System.nanoTime() < end) {
                    Thread.sleep(5); shadowOf(Looper.getMainLooper()).idle(); request = shadowOf(activity).nextStartedActivity
                }
                return request ?: error("split request missing")
            }
            try {
                screen.launch(mapOf(
                    "left" to mapOf("packageName" to l.packageName, "activityName" to l.activityName),
                    "right" to mapOf("packageName" to r.packageName, "activityName" to r.activityName), "ratio" to "7/3")) { result = it }
                val first = nextRequest()
                owner.pause()
                shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(1050))
                val second = nextRequest()
                shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(250))
                assertEquals("requested", result!!["status"])
                assertEquals(listOf("left", "right"), result!!["requestedSides"])
                assertEquals(ComponentName(r.packageName, r.activityName!!), first.component)
                assertEquals(ComponentName(l.packageName, l.activityName!!), second.component)
                assertEquals(setOf(SplitLaunchSequence.PRIMARY), first.categories)
                assertEquals(setOf(SplitLaunchSequence.SECOND), second.categories)
                val selfIntent = if (selfOnLeft) second else first
                val otherIntent = if (selfOnLeft) first else second
                assertEquals(activity.componentName, selfIntent.component)
                assertEquals(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_NO_ANIMATION or Intent.FLAG_ACTIVITY_RETAIN_IN_RECENTS, selfIntent.flags)
                assertEquals(0, selfIntent.flags and (Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK or Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT))
                assertEquals(SplitLaunchSequence.FLAGS, otherIntent.flags)
            } finally { screen.close(); owner.stop().destroy() }
        }
    }
    private fun combo(id: String = "one") = JSONObject().put("id", id).put("name", "地图与音乐").put("ratio", "7/3").put("advanced", true)
        .put("left", JSONObject().put("packageName", "test.maps").put("label", "地图").put("activityName", ".Main"))
        .put("right", JSONObject().put("packageName", "test.music").put("label", "音乐"))
    @Test fun configurationRoundTripsAndValidatesStoredChoicesWithoutInstalledApps() {
        val original = JSONObject().put("startupPage", "split").put("splitCombos", JSONArray().put(combo()))
        val validated = ConfigValidator.validate(original, emptyMap())
        assertEquals("split", validated.getString("startupPage"))
        assertEquals("test.maps.Main", validated.getJSONArray("splitCombos").getJSONObject(0).getJSONObject("left").getString("activityName"))
        val store = SecureConfig(RuntimeEnvironment.getApplication())
        store.save(validated)
        val restored = SecureConfig(RuntimeEnvironment.getApplication()).load()
        assertEquals("split", restored.getString("startupPage"))
        assertEquals("one", restored.getJSONArray("splitCombos").getJSONObject(0).getString("id"))
        val reimported = ConfigValidator.validate(JSONObject(validated.toString()), emptyMap())
        assertEquals(validated.toString(), reimported.toString())
        assertEquals("information", ConfigValidator.validate(JSONObject(), emptyMap()).getString("startupPage"))
        val invalid = listOf(
            JSONObject().put("startupPage", "unknown"),
            JSONObject().put("startupPage", 1),
            JSONObject().put("splitCombos", JSONArray().put(combo()).put(combo())),
            JSONObject().put("splitCombos", JSONArray().put(combo().put("ratio", "1/1"))),
            JSONObject().put("splitCombos", JSONArray().put(combo().put("advanced", false))),
            JSONObject().put("splitCombos", JSONArray().put(combo().put("left", JSONObject().put("packageName", "test.maps;am start").put("label", "地图"))))
        )
        invalid.forEach { assertTrue(runCatching { ConfigValidator.validate(it, emptyMap()) }.isFailure) }
    }
}
