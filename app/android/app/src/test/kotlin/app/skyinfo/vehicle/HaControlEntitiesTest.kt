package app.skyinfo.vehicle

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[34])
class HaControlEntitiesTest {
    private fun entity(id:String) = EntityCatalog.controls(RuntimeEnvironment.getApplication()).first { it.getString("id") == id }
    @Test fun nativeEntitiesShareDeviceAndNeverUseOptimisticFeedback() {
        val types=mutableSetOf<String>()
        for(e in EntityCatalog.controls(RuntimeEnvironment.getApplication())) for(d in haControlDefinitions("device","car","0.5.0",e,"live/session/command")) {
            types.add(d.topic.split('/')[1])
            assertEquals("skyinfo_device",d.payload.getJSONObject("device").getJSONArray("identifiers").getString(0))
            assertEquals(0,d.payload.getInt("qos"));assertFalse(d.payload.getBoolean("retain"))
            assertEquals("live/session/command",d.payload.getString("command_topic"))
            if (d.payload.has("optimistic")) assertFalse(d.payload.getBoolean("optimistic"))
            assertTrue(d.payload.getBoolean("enabled_by_default"))
        }
        assertEquals(setOf("switch","select","number","button"),types)
    }
    @Test fun allControlComponentsUseOneDeviceDiscoveryPayload() {
        val definitions=EntityCatalog.controls(RuntimeEnvironment.getApplication()).flatMap { haControlDefinitions("device","car","0.5.0",it,"live/command") }
        val payload=haControlDeviceDiscovery(definitions,"0.5.0")
        assertEquals("SkyInfo",payload.getJSONObject("origin").getString("name"))
        val components=payload.getJSONObject("components")
        assertEquals(516,components.length())
        for (key in components.keys()) {
            val component=components.getJSONObject(key)
            assertEquals(key,component.getString("unique_id"))
            assertTrue(component.getString("platform") in listOf("switch","select","number","button"))
            assertFalse(component.has("device"))
        }
        assertEquals("skyinfo_device",payload.getJSONObject("device").getJSONArray("identifiers").getString(0))
    }
    @Test fun readsUseConfirmedEnumMappingsAndRejectUnknownCodes() {
        val e=entity("wireless_charging");val f=e.getString("readField")
        fun state(raw:Int)=haControlState(e,mapOf(f to JSONObject().put("raw",raw).put("quality","available")),true)
        assertEquals("开启",state(1).getString("state"));assertEquals("关闭",state(2).getString("state"))
        assertFalse(state(65535).getBoolean("available"));assertFalse(state(42).getBoolean("available"))
        val d=haControlDefinitions("x","car","0.5.0",e,"cmd").single().payload
        assertEquals(1,JSONObject(d.getString("payload_on")).getInt("value"))
        assertEquals(2,JSONObject(d.getString("payload_off")).getInt("value"))
    }
    @Test fun dualTemperatureRequiresBothFeedbackAndInferredAddsNoReadSubscriptions() {
        val e=entity("ac_temperature");val samples=mutableMapOf<String,JSONObject>()
        for (f in RuntimeCoordinator.list(e.getJSONArray("feedbackFields"))) samples[f]=JSONObject().put("raw",23).put("quality","available").put("unit","°C")
        assertTrue(haControlState(e,samples,true).getBoolean("available"))
        samples.values.first().put("unit","°F")
        assertFalse(haControlState(e,samples,true).getBoolean("available"))
        samples.values.first().put("unit","°C")
        samples.values.last().put("raw",24)
        assertFalse(haControlState(e,samples,true).getBoolean("available"))
        assertTrue(haControlState(entity("hud_brightness"),emptyMap(),true).getBoolean("available"))
        assertFalse(haControlState(entity("hud_brightness"),emptyMap(),false).getBoolean("available"))
        assertEquals("inferred",haControlState(entity("hud_brightness"),emptyMap(),true).getString("validation"))
        for (i in EntityCatalog.controls(RuntimeEnvironment.getApplication()).filter{ it.optString("validation")=="inferred" }) {
            assertEquals(0,i.getJSONArray("feedbackFields").length());assertTrue(i.isNull("readField"))
        }
    }
    @Test fun generatedMetadataMatchesAllAllowedNativeOptions() {
        val entities=EntityCatalog.controls(RuntimeEnvironment.getApplication())
        assertEquals(VehicleControls.definitions.map{it.id}.toSet(),entities.map{it.getString("id")}.toSet())
        for(e in entities) {
            val d=VehicleControls.definition(e.getString("id"))
            assertEquals(e.getString("capability"),VehicleControls.entityCapability(d))
            for(i in 0 until e.getJSONArray("options").length()) d.validate(e.getJSONArray("options").getJSONObject(i).getInt("value"))
        }
    }
}
