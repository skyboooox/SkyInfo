package app.skyinfo.vehicle

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowLog
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class BuildChannelTest {
    @Test fun channelDoesNotDependOnDebugMode() {
        assertEquals(BuildConfig.FLAVOR == "beta", ChannelDiagnostics.enabled)
        assertEquals("app.skyinfo.vehicle", BuildConfig.APPLICATION_ID)
        assertEquals(BuildConfig.FLAVOR == "beta", Regex("-beta[.][0-9]+$").containsMatchIn(BuildConfig.VERSION_NAME))
    }

    @Test fun stableCannotInvokeAuditAndBetaCanCompleteAnEmptyOfflineAudit() {
        val source = ThreadPoolExecutor(1, 1, 0, TimeUnit.SECONDS, ArrayBlockingQueue<Runnable>(1))
        var timedOut = false
        ShadowLog.clear()
        try {
            if (BuildConfig.FLAVOR == "stable") {
                assertThrows(UnsupportedOperationException::class.java) {
                    ChannelDiagnostics.audit(emptyMap(), source) { timedOut = true }
                }
                assertTrue(ShadowLog.getLogsForTag("SkyInfo.Adaptation").isEmpty())
            } else {
                val result = ChannelDiagnostics.audit(emptyMap(), source) { timedOut = true }
                assertTrue(result.has("audit_id"))
                assertEquals(0, result.getJSONObject("qualities").length())
                assertEquals(2, ShadowLog.getLogsForTag("SkyInfo.Adaptation").size)
            }
            assertFalse(timedOut)
            assertEquals(0L, source.taskCount)
        } finally { source.shutdownNow() }
    }
}
