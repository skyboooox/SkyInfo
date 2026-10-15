package app.skyinfo.vehicle

import android.provider.Settings
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class AutoAdbSettingsTest {
    private class Port : AutoAdbSettings.Port {
        val values = mutableMapOf(Settings.Global.ADB_ENABLED to 0, "adb_wifi_enabled" to 0)
        val writes = mutableListOf<String>()
        var writable = true
        var appGranted = false
        var grants = 0
        var rejectGrant = false
        var ignoredWrite: String? = null
        var deniedWrite: String? = null
        override fun read(key: String) = values[key]
        override fun canWrite() = writable
        override fun appPermission() = appGranted
        override fun grantAppPermission(): Boolean { grants++; if (!rejectGrant) appGranted = true; return appGranted }
        override fun write(key: String): Boolean {
            writes.add(key)
            if (key == deniedWrite) throw SecurityException()
            if (key != ignoredWrite) values[key] = 1
            return true
        }
    }
    @Test fun defaultOffDoesNotGrantOrChangeSettings() {
        val port = Port()
        assertEquals("disabled", AutoAdbSettings(port).restore(false, true).getString("state"))
        assertEquals(0, port.grants); assertTrue(port.writes.isEmpty())
        assertEquals(listOf(0, 0), port.values.values.toList())
        val config = ConfigValidator.validate(JSONObject(), emptyMap())
        assertFalse(config.getBoolean("autoSystemAdb"))
        assertTrue(ConfigValidator.validate(JSONObject().put("autoSystemAdb", true), emptyMap()).getBoolean("autoSystemAdb"))
        assertTrue(runCatching { ConfigValidator.validate(JSONObject().put("autoSystemAdb", 1), emptyMap()) }.isFailure)
    }
    @Test fun authorizedRecoveryReadsBackBothSettingsAndDoesNotWriteAgain() {
        val port = Port(); val helper = AutoAdbSettings(port)
        val restored = helper.restore(true, true)
        assertEquals("enabled", restored.getString("state")); assertTrue(restored.getBoolean("appPermission"))
        assertEquals(setOf("adb_enabled", "adb_wifi_enabled"), port.writes.toSet())
        port.writes.clear()
        assertEquals("enabled", helper.restore(true).getString("state")); assertTrue(port.writes.isEmpty())
        helper.restore(false)
        assertEquals(listOf(1, 1), port.values.values.toList()); assertTrue(port.appGranted)
    }
    @Test fun missingPermissionDefersRecoveryWithoutAttemptingAWritingLoop() {
        val port = Port().apply { writable = false }
        val result = AutoAdbSettings(port).restore(true)
        assertEquals("permission_required", result.getString("state"))
        assertFalse(result.getBoolean("appPermission")); assertTrue(port.writes.isEmpty()); assertEquals(0, port.grants)
    }
    @Test fun aSuccessfulWriteWithoutReadbackIsNotAccepted() {
        val port = Port().apply { ignoredWrite = "adb_wifi_enabled" }
        val result = AutoAdbSettings(port).restore(true)
        assertEquals("error", result.getString("state"))
        assertEquals("enabled", result.getJSONObject("settings").getString("adb_enabled"))
        assertEquals("error", result.getJSONObject("settings").getString("adb_wifi_enabled"))
    }
    @Test fun oneDeniedSettingDoesNotSkipTheOther() {
        val port = Port().apply { deniedWrite = "adb_enabled" }
        val result = AutoAdbSettings(port).restore(true)
        assertEquals("permission_required", result.getString("state"))
        assertEquals("enabled", result.getJSONObject("settings").getString("adb_wifi_enabled"))
    }
    @Test fun shellRecoveryCanSucceedEvenIfAppGrantIsRejected() {
        val port = Port().apply { rejectGrant = true }
        val result = AutoAdbSettings(port).restore(true, true)
        assertEquals("enabled", result.getString("state")); assertFalse(result.getBoolean("appPermission"))
        assertEquals(1, port.grants)
    }
}
