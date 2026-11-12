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
    @Test fun nativeEntitiesUseStableChildDevicesAndNeverUseOptimisticFeedback() {
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
    @Test fun groupedDiscoveryPreservesStableComponentsAndReplacesOnlyChangedPlatforms() {
        val entities=EntityCatalog.controls(RuntimeEnvironment.getApplication())
        val definitions=entities.flatMap { haControlDefinitions("device","car","0.5.0",it,"live/command") }
        assertEquals(173,definitions.size)
        assertTrue(entities.all { haControlGroup(it.getString("id"))!="equipment" })
        assertEquals("equipment",haControlGroup("future_device_action"))
        val payload=haControlDeviceDiscovery(definitions,"0.5.0")
        assertEquals("SkyInfo",payload.getJSONObject("origin").getString("name"))
        assertEquals(0,payload.getJSONObject("components").length())
        val children=payload.getJSONArray("child_devices")
        assertEquals(17,children.length())
        val components=mutableMapOf<String,JSONObject>()
        for (i in 0 until children.length()) {
            val child=children.getJSONObject(i)
            assertEquals(setOf("identifiers","name","components"),child.keys().asSequence().toSet())
            assertTrue(child.getString("name").isNotBlank())
            val values=child.getJSONObject("components")
            for(key in values.keys()) { assertNull(components.put(key,values.getJSONObject(key)));assertFalse(values.getJSONObject(key).has("device")) }
        }
        assertEquals(173,components.size)
        assertEquals("switch",components.getValue("skyinfo_device_control_ac_power").getString("platform"))
        assertEquals("number",components.getValue("skyinfo_device_control_ac_temperature").getString("platform"))
        assertEquals("select",components.getValue("skyinfo_device_control_ac_wind_level_selection").getString("platform"))
        assertEquals("button",components.getValue("skyinfo_device_control_main_temp_25").getString("platform"))
        val removed=haRemovedControlComponents("device",entities)
        System.getenv("SKYINFO_HA_QA_FIXTURES")?.let { path ->
            val directory=java.io.File(path).apply { mkdirs() }
            java.io.File(directory,"discovery-final.json").writeText(payload.toString(2))
            java.io.File(directory,"discovery-migration.json").writeText(haControlDeviceDiscovery(definitions,"0.5.0",removed).toString(2))
            java.io.File(directory,"control-definitions.json").writeText(JSONArray(definitions.map { it.payload }).toString(2))
        }
        assertEquals(472,removed.length())
        assertTrue(removed.keys().asSequence().none { it in components })
        assertEquals("number",removed.getJSONObject("skyinfo_device_control_ac_wind_level").getString("platform"))
        assertEquals("button",removed.getJSONObject("skyinfo_device_control_rear_wind_1").getString("platform"))
        assertTrue(removed.keys().asSequence().all { removed.getJSONObject(it).length()==1 })
        assertEquals("skyinfo_device",payload.getJSONObject("device").getJSONArray("identifiers").getString(0))
    }
    @Test fun everyCatalogActionHasItsExpectedFunctionalDevice() {
        for(e in EntityCatalog.controls(RuntimeEnvironment.getApplication())) {
            val id=e.getString("id")
            val expected=when(e.getString("category")) {
                "空调" -> "climate"
                "座椅" -> when {
                    "steering_wheel" in id -> "steering_wheel"
                    "rear_left" in id -> "rear_left_seat"
                    "rear_right" in id -> "rear_right_seat"
                    "passenger" in id -> "passenger_seat"
                    else -> "driver_seat"
                }
                "车窗门锁" -> when { "lock" in id -> "locks"; id=="trunk_control" -> "body_equipment"; else -> "windows" }
                "灯光" -> "lights"
                "显示镜屏" -> if("mirror" in id) "mirrors" else "displays"
                "底盘辅助驾驶" -> if(id in setOf("cloud_mode","road_preview","suspension_adjust","suspension_height_lock","suspension_ultra_low","suspension_ultra_high","steering_assist","comfort_mode_2_level","drive_mode_high")) "chassis" else "driver_assistance"
                "充电及其他设备" -> when(id) {
                    "wireless_charging","soc_keep_set","right_charge_port","force_power_keep","energy_feedback","overseas_feedback" -> "charging"
                    "fridge_mode","fridge_lock" -> "fridge"
                    "engine_sound_sim","sound_effect_sim" -> "sound"
                    else -> "body_equipment"
                }
                else -> error("unclassified catalog category")
            }
            assertEquals(id,expected,haControlGroup(id))
        }
    }
    @Test fun commandOnlySelectionsKeepUnknownStateAndExactAllowedValues() {
        for (entity in EntityCatalog.controls(RuntimeEnvironment.getApplication())) {
            val definition=haControlDefinitions("device","car","0.5.0",entity,"command").single()
            if(entity.getString("capability")=="button" && entity.getJSONArray("options").length()>1) {
                assertEquals("select",definition.topic.split('/')[1])
                assertFalse(definition.payload.getBoolean("optimistic"))
                assertEquals("{{ 'None' }}",definition.payload.getString("value_template"))
                assertTrue(definition.payload.getString("name").endsWith("操作"))
                assertEquals(entity.getJSONArray("options").length(),definition.payload.getJSONArray("options").length())
                val state=haControlState(entity,emptyMap(),true)
                assertTrue(state.getBoolean("available"));assertTrue(state.isNull("state"));assertTrue(state.isNull("raw"))
                assertEquals("command_only",state.getString("state_semantics"))
                assertFalse(haControlState(entity,emptyMap(),false).getBoolean("available"))
            }
        }
        assertEquals("driver_seat",haControlGroup("driver_seat_heating_5_level"))
        assertEquals("passenger_seat",haControlGroup("seat_driver_passenger"))
        assertNotEquals(haControlGroup("door_lock"),haControlGroup("window_left_front"))
        assertNotEquals(haControlGroup("hud_control"),haControlGroup("elec_mirror_brightness"))
        assertNotEquals(haControlGroup("wireless_charging"),haControlGroup("fridge_mode"))
    }
    @Test fun actionOptionLabelsKeepSlashQuotesAndBackslashesAcrossJinjaMapping() {
        val labels=listOf("前/上（点动）","\"模式\"\\路径","驾驶员's")
        val options=JSONArray(labels.mapIndexed { index,label -> JSONObject().put("value",index).put("label",label) })
        val entity=JSONObject().put("id","qa_label_options").put("name","操作标签")
            .put("capability","button").put("validation","inferred").put("readField",JSONObject.NULL)
            .put("feedbackFields",JSONArray()).put("states",JSONObject()).put("options",options)
        val definition=haControlDefinitions("device","car","0.5.0",entity,"live/command").single().payload
        assertEquals(labels,(0 until definition.getJSONArray("options").length()).map { definition.getJSONArray("options").getString(it) })
        assertTrue(definition.getString("command_template").contains("\"前/上（点动）\":0"))
        for(label in labels) assertTrue(definition.getString("command_template").contains(JSONObject.quote(label).replace("\\/","/")))
        System.getenv("SKYINFO_HA_QA_FIXTURES")?.let { path ->
            java.io.File(path,"control-label-boundaries.json").writeText(JSONObject().put("definition",definition).put("entity",entity).toString(2))
        }
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
