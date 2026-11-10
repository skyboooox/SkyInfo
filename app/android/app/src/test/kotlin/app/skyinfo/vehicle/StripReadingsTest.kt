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
class StripReadingsTest {
    @Test fun preparedReadingsKeepAlignmentOrderDigitsQualityAndLiveUnits() {
        val field = JSONObject().put("unit","°C").put("unitField","unit")
        val fields = mapOf("temperature" to field)
        val module = JSONObject().put("field","temperature").put("digits",2).put("alignment","right")
            .put("unitAuto",true).put("icon","thermometer")
        val config = JSONObject().put("overlays",JSONArray().put(module)
            .put(JSONObject(module.toString()).put("alignment","left").put("digits",0)))
        val sample = JSONObject().put("value",25.125).put("unit","°F").put("quality","available")
        val readings = prepareStripGroups(config,fields,mapOf("temperature" to sample))
        assertEquals(listOf("left","right"),readings.map { it.alignment })
        assertEquals("25",readings.first().modules.single().text)
        assertEquals(StripModule("thermometer","25.13","°F"),readings.last().modules.single())
        sample.put("quality","disconnected").put("unit","")
        assertEquals("25.13",readings.last().modules.single().text)
        assertEquals(StripModule("thermometer","—",""),prepareStripGroups(config,fields,mapOf("temperature" to sample)).last().modules.single())
        module.put("unitAuto",false).put("unit","°C")
        assertEquals(NativeStrings.raw_value,prepareStripGroups(config,fields,mapOf("temperature" to sample)).last().modules.single().unit)
        sample.put("quality","unverified").put("value","Ready").put("unit","K")
        assertEquals(StripModule("thermometer","Ready","K"),prepareStripGroups(config,fields,mapOf("temperature" to sample)).last().modules.single())
    }
    @Test fun preparationFormatsEachNumericModuleOnceAndRedrawsReuseTheText() {
        class Reading : Number() {
            var conversions = 0
            override fun toDouble(): Double { conversions++; return 13.6 }
            override fun toFloat() = 13.6f
            override fun toByte() = 13.toByte()
            override fun toShort() = 13.toShort()
            override fun toInt() = 13
            override fun toLong() = 13L
        }
        val value = Reading()
        val config = JSONObject().put("overlays",JSONArray().put(JSONObject().put("field","voltage").put("alignment","center").put("unitAuto",true)))
        val sample = JSONObject().put("value",value).put("unit","V").put("quality","available")
        value.conversions = 0
        val groups = prepareStripGroups(config,mapOf("voltage" to JSONObject()),mapOf("voltage" to sample))
        assertEquals(1,value.conversions)
        repeat(10) { assertEquals("13.6",groups.single().modules.single().text) }
        assertEquals(1,value.conversions)
    }
}
