package app.skyinfo.vehicle

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class HaEntityModelTest {
    @Test fun metadataSignatureIgnoresValuesButTracksFieldShapeUnitsAndCapabilities() {
        val original = entity("climate.test","heat","""{"friendly_name":"Room","temperature_unit":"°C","current_temperature":21,"temperature":23,"supported_features":9,"hvac_modes":["off","heat"],"min_temp":16,"max_temp":30,"target_temp_step":0.5,"fan_modes":["auto","high"]}""")
        val signature = HaEntityModel.metadataSignature(original)
        val updated = JSONObject(original.toString()).put("state","off").put("last_updated","different")
        updated.getJSONObject("attributes").put("temperature",24).put("current_temperature",22)
        assertEquals(signature,HaEntityModel.metadataSignature(updated))
        for ((key,value) in listOf("temperature_unit" to "°F", "supported_features" to 1, "hvac_modes" to org.json.JSONArray("[\"off\"]"),
            "min_temp" to 15, "max_temp" to 32, "target_temp_step" to 1, "fan_modes" to org.json.JSONArray("[\"auto\"]"), "friendly_name" to "Other", "temperature" to "24")) {
            val changed = JSONObject(original.toString()); changed.getJSONObject("attributes").put(key,value)
            assertNotEquals(key,signature,HaEntityModel.metadataSignature(changed))
        }
        val added = JSONObject(original.toString()); added.getJSONObject("attributes").put("humidity",50)
        assertNotEquals(signature,HaEntityModel.metadataSignature(added))
        val reordered = JSONObject(original.toString()).put("attributes",JSONObject().apply {
            for(key in original.getJSONObject("attributes").keys().asSequence().toList().reversed()) put(key,original.getJSONObject("attributes").get(key))
        })
        assertEquals(signature,HaEntityModel.metadataSignature(reordered))
    }
    private fun entity(id: String, value: String, attributes: String = "{}") = JSONObject().put("entity_id",id).put("state",value)
        .put("attributes",JSONObject(attributes)).put("last_updated","2026-10-11T10:00:01Z").put("last_changed","2026-10-11T10:00:00Z")
    private fun services(domain: String, vararg actions: String) = JSONObject().put(domain,JSONObject().also { o -> actions.forEach { o.put(it,JSONObject()) } })
    @Test fun sensorContractsPreserveTypesAndNeverApplyVehicleConversions() {
        val b = HaBinding("one","sensor.temperature")
        val sample = HaEntityModel.sample(b,entity(b.entity,"68","{\"unit_of_measurement\":\"°C\"}"),true,2)
        assertTrue(sample.get("value") is Number); assertEquals(68.0,sample.getDouble("value"),0.0); assertEquals("°C",sample.getString("unit"))
        assertEquals(java.time.Instant.parse("2026-10-11T10:00:00Z").toEpochMilli(),sample.getLong("changedAt")); assertEquals("68",sample.getString("raw"))
        assertEquals("1234",HaEntityModel.sample(b,entity(b.entity,"1234"),true,2).get("value"))
        assertEquals("on",HaEntityModel.sample(HaBinding("one","binary_sensor.door"),entity("binary_sensor.door","on"),true,2).get("value"))
        for(value in listOf("unknown","unavailable","NaN","Infinity","bad")) {
            val bad = HaEntityModel.sample(b,entity(b.entity,value,"{\"unit_of_measurement\":\"°C\"}"),true,2)
            assertNotEquals("available",bad.getString("quality")); assertFalse(bad.has("value"))
        }
    }
    @Test fun namespaceScalarAttributesRemovalAndDisconnectionAreDistinct() {
        assertNotEquals(HaBinding("one","sensor.same").id,HaBinding("two","sensor.same").id)
        for (id in listOf("ha|one|sensor.a|nested|x", "ha|one|../sensor.a", "ha||sensor.a", "sensor.a")) assertNull(HaBinding.parse(id))
        val binding = HaBinding("one","light.lamp","brightness")
        val s = entity(binding.entity,"on","{\"brightness\":128,\"nested\":{\"x\":1}}")
        assertEquals(128.0,HaEntityModel.sample(binding,s,true,1).getDouble("value"),0.0)
        assertEquals("",HaEntityModel.sample(binding,s,true,1).getString("unit"))
        assertEquals("missing_attribute",HaEntityModel.sample(binding.copy(attribute="nested"),s,true,1).getString("quality"))
        assertEquals("removed",HaEntityModel.sample(binding,null,true,1).getString("quality"))
        assertEquals("disconnected",HaEntityModel.sample(binding,s,false,2).getString("quality"))
    }
    @Test fun nullableMetadataDoesNotBecomeLiteralTextOrNumericContract() {
        val binding = HaBinding("one", "sensor.code")
        val state = entity(binding.entity, "1234", "{\"unit_of_measurement\":null,\"state_class\":null,\"friendly_name\":null}")
        assertFalse(HaEntityModel.numeric(state))
        val sample = HaEntityModel.sample(binding, state, true, 1)
        assertEquals("1234", sample.get("value"))
        assertEquals("", sample.getString("unit"))
        assertEquals(binding.entity, HaEntityModel.field(binding, state).getString("name"))
        val temperature = entity("climate.test", "off", "{\"temperature_unit\":null,\"unit_of_measurement\":\"°C\",\"temperature\":22}")
        assertEquals("°C", HaEntityModel.unit(temperature, "temperature"))
        assertEquals("invalid", HaEntityModel.sample(binding, JSONObject(state.toString()).put("state", JSONObject.NULL), true, 1).getString("quality"))
        val lockServices = services("lock", "lock", "unlock")
        assertTrue(HaEntityModel.service(entity("lock.test", "locked", "{\"code_format\":null}"), lockServices, "unlock", null).second.getBoolean("confirmation"))
        assertEquals(1, HaEntityModel.functions(entity("lock.test", "locked", "{\"code_format\":42}"), lockServices).length())
    }
    @Test fun serviceParametersAreExactAndBoundedByLiveCapabilities() {
        val s = entity("number.target","5","{\"min\":0,\"max\":10,\"step\":0.5}")
        val srv = services("number","set_value")
        val request = HaEntityModel.service(s,srv,"value",6.5).first
        assertEquals("call_service",request.getString("type")); assertEquals("number.target",request.getJSONObject("target").getString("entity_id"))
        assertEquals(6.5,request.getJSONObject("service_data").getDouble("value"),0.0)
        for (bad in listOf<Any>(11.0, 6.2, Double.NaN, "6.5")) assertThrows(Throwable::class.java) { HaEntityModel.service(s,srv,"value",bad) }
        assertEquals(0,HaEntityModel.functions(s,JSONObject()).length())
        assertEquals(0,HaEntityModel.functions(entity("number.target","5"),srv).length())
    }
    @Test fun optionToggleAndLockCannotExpandIntoArbitraryCommands() {
        val select = entity("select.mode","a","{\"options\":[\"a\",\"b\"]}")
        assertThrows(Throwable::class.java) { HaEntityModel.service(select,services("select","select_option"),"option","c") }
        val toggle = HaEntityModel.service(entity("switch.test","off"),services("switch","turn_on","turn_off"),"power",true).first
        assertEquals("turn_on",toggle.getString("service")); assertEquals(0,toggle.getJSONObject("service_data").length())
        assertThrows(Throwable::class.java) { HaEntityModel.service(entity("switch.test","off"),services("switch","turn_on","turn_off"),"power",1) }
        val lockServices = services("lock","lock","unlock")
        assertTrue(HaEntityModel.service(entity("lock.test","locked"),lockServices,"unlock",null).second.getBoolean("confirmation"))
        assertEquals(1,HaEntityModel.functions(entity("lock.test","locked","{\"code_format\":\"number\"}"),lockServices).length())
    }
    @Test fun featureFlagsHideUnsupportedControls() {
        val cover = entity("cover.test","open","{\"supported_features\":4}")
        val features = HaEntityModel.functions(cover,services("cover","open_cover","close_cover","stop_cover","set_cover_position"))
        assertEquals(1,features.length()); assertEquals("position",features.getJSONObject(0).getString("key"))
        assertEquals(0,HaEntityModel.functions(entity("media_player.test","idle"),services("media_player","media_play","media_pause","volume_set")).length())
        val climate=entity("climate.test","off","{\"supported_features\":0,\"fan_modes\":[\"auto\"],\"min_temp\":16,\"max_temp\":30,\"target_temp_step\":0.5}")
        assertEquals(0,HaEntityModel.functions(climate,services("climate","set_temperature","set_fan_mode")).length())
    }    @Test fun savedHaHistoryRemainsNumericAndQueryableAfterDisconnection() {
        val binding=HaBinding("one","sensor.temperature")
        val history=LocalHistory(org.robolectric.RuntimeEnvironment.getApplication())
        history.configure(JSONObject().put("localHistory",true).put("retainHistory",false).put("haImportEnabled",false)
            .put("tiles",org.json.JSONArray().put(JSONObject().put("fields",org.json.JSONArray().put(binding.id)))))
        try {
            val state=entity(binding.entity,"68","{\"unit_of_measurement\":\"°C\"}")
            history.append(binding.id,HaEntityModel.sample(binding,state,true,1))
            history.append("ha|one|sensor.preview",HaEntityModel.sample(binding,state,true,1))
            history.append(binding.id,HaEntityModel.sample(binding,state,false,2))
            val points=history.query(binding.id,30,HaEntityModel.field(binding,state)).getJSONArray("points")
            assertEquals(2,points.length());assertEquals(68.0,points.getJSONObject(0).getDouble("value"),0.0)
            assertTrue(points.getJSONObject(1).isNull("value"));assertNotEquals(points.getJSONObject(0).getString("segment"),points.getJSONObject(1).getString("segment"))
            assertEquals(0,history.query("ha|one|sensor.preview",30).getJSONArray("points").length())
        } finally { history.clear() }
    }

}
