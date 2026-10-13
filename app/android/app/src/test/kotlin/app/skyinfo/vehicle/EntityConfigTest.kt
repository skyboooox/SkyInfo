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
class EntityConfigTest {
    private val fields get() = EntityCatalog.fields(RuntimeEnvironment.getApplication())
    private fun config(kind:String,vararg selected:String) = JSONObject().put("schema",2).put("tiles",JSONArray().put(JSONObject().put("id","one").put("title","测试").put("kind",kind).put("columns",2).put("rows",2).put("fields",JSONArray(selected.toList()))))
    @Test fun dashboardSizePersistsOnlySupportedModes() {
        val id = "1032/7/1128267816"
        for (size in listOf("standard","enlarged")) {
            val result = ConfigValidator.validate(config("number",id).put("dashboardSize",size),fields)
            assertEquals(size,result.getString("dashboardSize"))
            assertEquals(2,result.getJSONArray("tiles").getJSONObject(0).getInt("columns"))
        }
        for (invalid in listOf("small", 2, false)) {
            assertTrue(runCatching { ConfigValidator.validate(config("number",id).put("dashboardSize",invalid),fields) }.isFailure)
        }
    }
    @Test fun mixedEntitiesAndLegacySensorConfigurationRemainValid() {
        val id="1032/7/1128267816"
        assertEquals("number",ConfigValidator.validate(config("number",id),fields).getJSONArray("tiles").getJSONObject(0).getString("kind"))
        for(kind in listOf("entities","device")) assertEquals(2,ConfigValidator.validate(config(kind,id,"control.ac_cycle"),fields).getJSONArray("tiles").getJSONObject(0).getJSONArray("fields").length())
    }
    @Test fun dedicatedFeaturesRejectWrongCapabilitiesAndMissingActions() {
        for(c in listOf(config("number","control.ac_cycle"),config("toggle","control.ac_cycle"),config("numberControl","control.main_temp"),config("entity","control.missing"))) {
            try { ConfigValidator.validate(c,fields);fail("unexpected valid feature") } catch(_:IllegalArgumentException) {}
        }
        for((kind,action) in listOf("toggle" to "ac_power","select" to "ac_cycle","numberControl" to "ac_temperature","action" to "main_temp")) ConfigValidator.validate(config(kind,"control.$action"),fields)
    }
}
