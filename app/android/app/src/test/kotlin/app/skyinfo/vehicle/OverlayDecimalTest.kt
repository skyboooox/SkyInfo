package app.skyinfo.vehicle

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class OverlayDecimalTest {
    private fun module(id: String, digits: Int? = null) = JSONObject().put("id",id).put("field","v").put("icon","").put("unit","V").put("alignment","center").also { if(digits != null) it.put("digits",digits) }
    private val fields = mapOf("v" to JSONObject().put("displayAllowed",true).put("unit","V"))
    @Test fun precisionSurvivesValidationAndAdbPayloadRoundTripPerModule() {
        val config = JSONObject().put("overlayEnabled",true).put("overlays",JSONArray().put(module("a",0)).put(module("b",3)).put(module("c")))
        val validated = ConfigValidator.validate(config,fields)
        val reimported = ConfigValidator.validate(JSONObject(validated.toString()),fields)
        val samples = mapOf("v" to JSONObject().put("value",13.67).put("quality","available"))
        val request = overlayRequest(reimported,samples)
        val safe = request.getJSONObject("config")
        assertEquals(listOf("14","13.670","13.7"),prepareStripGroups(safe,fields,samples).single().modules.map { it.text })
        assertEquals(listOf("V","V","V"),prepareStripGroups(safe,fields,samples).single().modules.map { it.unit })
        assertEquals(0,safe.getJSONArray("overlays").getJSONObject(0).getInt("digits"))
        assertEquals(13.67,request.getJSONObject("samples").getJSONObject("v").getDouble("value"),0.0)
    }
    @Test fun integerPrecisionRoundsBothSignsAndPreservesTextAndUnavailableState() {
        val config = JSONObject().put("overlays",JSONArray().put(module("a",0)).put(module("b",2)))
        fun text(value: Any, quality: String="available") = prepareStripGroups(config,fields,mapOf("v" to JSONObject().put("value",value).put("quality",quality))).single().modules.map { it.text }
        assertEquals(listOf("39","39.00"),text(39))
        assertEquals(listOf("-14","-13.67"),text(-13.67))
        assertEquals(listOf("运行","运行"),text("运行"))
        val labelled = mapOf("v" to JSONObject().put("value",1).put("quality","available").put("stateLabel","开启"))
        assertEquals(listOf("开启","开启"),prepareStripGroups(config,fields,labelled).single().modules.map { it.text })
        labelled.getValue("v").put("value",JSONObject.NULL)
        assertEquals(listOf("—","—"),prepareStripGroups(config,fields,labelled).single().modules.map { it.text })
        assertEquals(listOf("—","—"),text(13.67,"unavailable"))
    }
    @Test fun precisionChangeInvalidatesOnlyPreparedStripConfiguration() {
        val config = JSONObject().put("overlayEnabled",true).put("overlays",JSONArray().put(module("a",2)))
        val samples = mapOf("v" to JSONObject().put("value",13.67).put("quality","available"))
        val before = overlayRenderKey(config,fields,samples)
        config.getJSONArray("overlays").getJSONObject(0).put("digits",0)
        assertNotEquals(before,overlayRenderKey(config,fields,samples))
        val labelled = samples.mapValues { (_,sample) -> JSONObject(sample.toString()).put("stateLabel","开启") }
        assertNotEquals(overlayRenderKey(config,fields,samples),overlayRenderKey(config,fields,labelled))
        for (invalid in listOf(-1,5)) assertTrue(runCatching { ConfigValidator.validate(JSONObject(config.toString()).also { it.getJSONArray("overlays").getJSONObject(0).put("digits",invalid) },fields) }.isFailure)
    }
}
