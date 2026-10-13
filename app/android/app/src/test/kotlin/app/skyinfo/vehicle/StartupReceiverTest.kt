package app.skyinfo.vehicle

import android.content.Intent
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.Shadows.shadowOf

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class StartupReceiverTest {
    @Test fun updatePreservesManualStopAndDisabledAutostartDoesNotResume() {
        val app = RuntimeEnvironment.getApplication()
        val store = SecureConfig(app)
        store.save(JSONObject().put("autoStart",true)); store.stopped(true)
        StartupReceiver().onReceive(app,Intent(Intent.ACTION_MY_PACKAGE_REPLACED))
        assertTrue(store.stopped()); assertNull(shadowOf(app).nextStartedService)
        store.save(JSONObject().put("autoStart",false))
        StartupReceiver().onReceive(app,Intent(Intent.ACTION_BOOT_COMPLETED))
        assertTrue(store.stopped()); assertNull(shadowOf(app).nextStartedService)
    }
}
