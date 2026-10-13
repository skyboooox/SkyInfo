package app.skyinfo.vehicle

import android.content.Context
import android.content.ContextWrapper
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class PublicConfigurationTest {
    @Test fun identitiesPersistPerInstallationAndPreserveUserNaming() {
        fun context(suffix: String) = object: ContextWrapper(RuntimeEnvironment.getApplication()) {
            override fun getSharedPreferences(name: String, mode: Int) = super.getSharedPreferences(name+suffix,mode)
        }
        val a = DeviceIdentity(context("a")); val same = DeviceIdentity(context("a")); val b = DeviceIdentity(context("b"))
        assertEquals(a.id,same.id); assertNotEquals(a.id,b.id)
        val defaults = a.defaults(JSONObject())
        assertEquals(a.prefix,defaults.getString("prefix")); assertEquals(a.topic,defaults.getString("mqttTopic"))
        assertTrue(Regex("^[a-z0-9_]{1,48}$").matches(a.prefix))
        val custom = a.defaults(JSONObject().put("prefix","my_car").put("mqttTopic","cars/mine"))
        assertEquals("my_car",custom.getString("prefix")); assertEquals("cars/mine",custom.getString("mqttTopic"))
    }
    @Test fun transportAndBirthConfigurationAcceptUserValuesAndRejectInvalidTopics() {
        for(transport in listOf("tls","tcp")) {
            val config = JSONObject().put("mqttTransport",transport).put("haBirthTopic","ha/custom_status").put("haBirthPayload","ready")
            assertEquals(transport,ConfigValidator.validate(config,emptyMap()).getString("mqttTransport"))
        }
        ConfigValidator.validate(JSONObject().put("haBirthTopic",""),emptyMap())
        for(config in listOf(JSONObject().put("mqttTransport","udp"),JSONObject().put("haBirthTopic","ha/#"),
            JSONObject().put("haBirthTopic","status").put("haBirthPayload",""))) {
            try { ConfigValidator.validate(config,emptyMap());fail("Invalid public setting accepted") }
            catch (_: IllegalArgumentException) {}
        }
    }
    @Test fun unknownActionStateDoesNotMeanUnavailableOrCreateNumericFeedback() {
        for(domain in listOf("button","input_button","scene","script")) {
            val state = JSONObject().put("entity_id","$domain.test").put("state","unknown").put("attributes",JSONObject())
            assertTrue(HaEntityModel.availableForAction(state))
            val sample = HaEntityModel.sample(HaBinding("one","$domain.test"),state,true,1)
            assertEquals("unknown",sample.getString("quality")); assertFalse(sample.has("value"))
            state.put("state","unavailable");assertFalse(HaEntityModel.availableForAction(state))
        }
        assertFalse(HaEntityModel.availableForAction(JSONObject().put("entity_id","switch.test").put("state","unknown")))
    }
    @Test fun absentSdkMethodsAndActualPermissionDenialRemainDistinct() {
        val port = object:VehicleControls.Port {
            var supported = false
            var writes = 0
            override fun supports(readRequired:Boolean,arrayWrite:Boolean)=supported
            override fun environment() = JSONObject().put("protocol","CANFD").put("uid",0).put("user",12)
            override fun read(device:Int,field:Int)=1
            override fun write(device:Int,fields:IntArray,values:IntArray):Int { writes++;throw SecurityException("test permission") }
        }
        val controls=VehicleControls(port)
        assertEquals("unsupported_environment",controls.execute("wireless_charging",2).getString("status"))
        assertEquals("unsupported_environment",controls.execute("window_right_front",1).getString("status"));assertEquals(0,port.writes)
        port.supported=true
        assertEquals("permission",controls.execute("window_right_front",1).getString("status"));assertEquals(1,port.writes)
    }
    @Test fun capacityPressureReclaimsOldDataAndKeepsNewestSampleWithoutRowLimit() {
        val context=RuntimeEnvironment.getApplication()
        val history=LocalHistory(context,2L*1024*1024)
        val id="test"
        val config=JSONObject().put("retainHistory",true).put("localHistory",true).put("localHistoryMinutes",30)
            .put("tiles",org.json.JSONArray().put(JSONObject().put("fields",org.json.JSONArray().put(id))))
        history.configure(config)
        val base=System.currentTimeMillis()-100000
        try {
            repeat(100) { n -> history.append(id,JSONObject().put("value",n).put("quality","available")
                .put("receivedAt",base+n*1000).put("testPadding","p".repeat(65536))) }
            val points=history.query(id,30).getJSONArray("points")
            assertTrue(points.length()>1);assertTrue(points.length()<100)
            assertEquals(99.0,points.getJSONObject(points.length()-1).getDouble("value"),0.0)
            val stats=history.storageStats()
            assertEquals(2L*1024*1024,stats.getLong("maximumBytes"))
            assertTrue(stats.getLong("allocatedBytes")<=2L*1024*1024)
        } finally { history.clear() }
    }
    @Test fun temporaryHistoryUsesDiskAndPreferenceSwitchKeepsCurrentSessionOnly() {
        val context=RuntimeEnvironment.getApplication()
        val history=LocalHistory(context)
        val config=JSONObject().put("retainHistory",false).put("localHistory",true)
            .put("tiles",org.json.JSONArray().put(JSONObject().put("fields",org.json.JSONArray().put("test"))))
        history.configure(config);history.append("test",JSONObject().put("value",13.6).put("quality","available"))
        assertEquals("sqlite_file",history.storageStats().getString("storage"))
        assertTrue(java.io.File(context.cacheDir,"skyinfo-session-history.db").isFile)
        history.configure(JSONObject(config.toString()).put("retainHistory",true))
        assertEquals(1,history.query("test",30).getJSONArray("points").length())
        assertFalse(java.io.File(context.cacheDir,"skyinfo-session-history.db").exists())
        history.configure(config)
        assertEquals(1,history.query("test",30).getJSONArray("points").length())
        assertFalse(context.getDatabasePath("mqtt-history.db").exists())
        val next=LocalHistory(context);next.configure(config)
        try { assertEquals(0,next.query("test",30).getJSONArray("points").length()) }
        finally { next.clear();history.clear() }
    }

}
