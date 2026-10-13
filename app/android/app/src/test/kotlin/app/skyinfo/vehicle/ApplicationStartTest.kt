package app.skyinfo.vehicle

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class ApplicationStartTest {
    @Test fun launchResumesCollectionAndChecksSavedEndpointWithoutEnablingWrites() {
        val saved = JSONObject().put("collect",false).put("adbEnabled",false)
            .put("adbHost","127.0.0.1").put("adbPort",5566).put("adbMode","pair")
            .put("dashboardSize","enlarged").put("publishEnabled",false)
            .put("overlayEnabled",false).put("haControlEnabled",false).put("mqttControlEnabled",false)
        val launched = applicationStartConfig(saved)
        assertTrue(launched.getBoolean("collect")); assertTrue(launched.getBoolean("adbEnabled"))
        assertEquals(5566,launched.getInt("adbPort")); assertEquals("pair",launched.getString("adbMode"))
        assertEquals("enlarged",launched.getString("dashboardSize"))
        for(flag in listOf("publishEnabled","overlayEnabled","haControlEnabled","mqttControlEnabled"))assertFalse(launched.getBoolean(flag))
        assertFalse(saved.getBoolean("collect")); assertFalse(saved.getBoolean("adbEnabled"))
    }
    @Test fun freshLaunchDefaultsToStandardWithoutInventingUserEntities() {
        val launched = applicationStartConfig(JSONObject())
        assertEquals("standard",launched.getString("dashboardSize"))
        assertTrue(launched.getBoolean("collect"));assertTrue(launched.getBoolean("adbEnabled"))
        assertFalse(launched.has("tiles"));assertFalse(launched.has("uploaded"))
    }
}
