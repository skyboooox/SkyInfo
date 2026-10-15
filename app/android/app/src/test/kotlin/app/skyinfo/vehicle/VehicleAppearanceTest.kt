package app.skyinfo.vehicle

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Looper
import android.provider.Settings
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowContentResolver
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class VehicleAppearanceTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private val uri = Uri.parse("content://carsettings/global/time_wallpaper_mode")
    private val provider = ThemeProvider()

    private class ThemeProvider : ContentProvider() {
        var mode: String? = "3"
        var denied = false
        var queries = 0
        override fun onCreate() = true
        override fun getType(uri: Uri): String? = null
        override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor {
            queries++
            if (denied) throw SecurityException()
            assertEquals(listOf("key", "value"), projection!!.toList())
            assertEquals("key=?", selection)
            assertEquals(listOf("time_wallpaper_mode"), selectionArgs!!.toList())
            return MatrixCursor(arrayOf("key", "value")).apply {
                if (mode != null) addRow(arrayOf("time_wallpaper_mode", mode))
            }
        }
        override fun insert(uri: Uri, values: ContentValues?): Uri = error("read only")
        override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = error("read only")
        override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = error("read only")
    }

    @Before fun setup() {
        ShadowContentResolver.registerProviderInternal("carsettings", provider)
        Settings.Global.putString(context.contentResolver, "key_byd_night_mode", null)
    }

    @Test fun manualAndAdaptiveUseOemEnumsRatherThanAndroidEnums() {
        assertEquals("light", AppearanceState(2, 1).brightness)
        assertEquals("dark", AppearanceState(1, 2).brightness)
        assertEquals("light", AppearanceState(3, 2).brightness)
        assertEquals("dark", AppearanceState(3, 1).brightness)
        assertEquals("byd_display_mode", AppearanceState(2, 1).source)
        assertEquals("byd_night_mode", AppearanceState(null, 2).source)
        for (state in listOf(AppearanceState(3, null), AppearanceState(3, 0), AppearanceState(3, 99), AppearanceState(99, 1))) {
            assertNull(state.brightness)
            assertEquals("android", state.source)
        }
    }

    @Test fun providerChangesAreObservedWithoutPollingAndReleasedWhenIdle() {
        provider.mode = "2"
        var callbacks = 0
        lateinit var monitor: VehicleAppearance
        monitor = VehicleAppearance(context) { callbacks++; monitor.refresh() }
        monitor.setActive(true)
        assertEquals("light", monitor.current.brightness)
        val before = provider.queries
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(5))
        assertEquals(before, provider.queries)
        provider.mode = "1"
        context.contentResolver.notifyChange(uri, null)
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(callbacks > 0)
        assertEquals("dark", monitor.current.brightness)
        monitor.setActive(false)
        val stopped = callbacks
        context.contentResolver.notifyChange(uri, null)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(stopped, callbacks)
        provider.mode = "2"
        monitor.setActive(true)
        assertEquals("light", monitor.current.brightness)
        monitor.setActive(false)
    }

    @Test fun adaptiveNightStatusUpdatesIndependentlyOfCollectionAndAdb() {
        Settings.Global.putInt(context.contentResolver, "key_byd_night_mode", 2)
        lateinit var monitor: VehicleAppearance
        monitor = VehicleAppearance(context) { monitor.refresh() }
        monitor.setActive(true)
        assertEquals("light", monitor.current.brightness)
        Settings.Global.putInt(context.contentResolver, "key_byd_night_mode", 1)
        context.contentResolver.notifyChange(Settings.Global.getUriFor("key_byd_night_mode"), null)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("dark", monitor.current.brightness)
        monitor.setActive(false)
    }

    @Test fun deniedMissingAndMalformedValuesFallBackWithoutUsingCachedOemState() {
        provider.mode = "2"
        val monitor = VehicleAppearance(context) {}
        monitor.refresh()
        assertEquals("light", monitor.current.brightness)
        for (mode in listOf(null, "invalid", "99")) {
            provider.mode = mode
            monitor.refresh()
            assertEquals("android", monitor.current.source)
        }
        provider.denied = true
        monitor.refresh()
        assertNull(monitor.current.brightness)
    }

    @Test fun overlayUsesSameResolutionWithoutPersistingItOrOverridingManualChoice() {
        val config = JSONObject().put("theme", "system").put("overlayEnabled", true)
        val resolved = AppearanceState(2, 1).overlayConfig(config)
        assertEquals("light", resolved.getString("theme"))
        assertEquals("system", config.getString("theme"))
        assertTrue(resolved.getBoolean("overlayEnabled"))
        assertEquals("dark", AppearanceState(2, 1).overlayConfig(JSONObject().put("theme", "dark")).getString("theme"))
        assertEquals("system", AppearanceState(3, null).overlayConfig(config).getString("theme"))
    }
}
