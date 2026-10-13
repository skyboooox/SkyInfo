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
class OverlayPayloadTest {
    @Test fun overlayIncludesOnlySelectedFieldsEvenWithLargeHaDirectory() {
        val selected = "ha|qa|input_number.selected"
        val definitions = JSONObject(); val samples = mutableMapOf<String,JSONObject>()
        repeat(1500) { i ->
            val id = "ha|qa|sensor.entity_$i"
            definitions.put(id,JSONObject().put("name","x".repeat(500)))
            samples[id] = JSONObject().put("value",i)
        }
        definitions.put(selected,JSONObject().put("name","Selected").put("unit","V"))
        samples[selected] = JSONObject().put("value",3.5)
        val config = JSONObject().put("overlayEnabled",true).put("haFields",definitions).put("haToken","secret")
            .put("overlays",JSONArray().put(JSONObject().put("field",selected)))
        val request = overlayRequest(config,samples)
        assertEquals(setOf(selected),overlayFieldIds(config))
        assertEquals(1,request.getJSONObject("config").getJSONObject("haFields").length())
        assertEquals(1,request.getJSONObject("samples").length())
        assertEquals(3.5,request.getJSONObject("samples").getJSONObject(selected).getDouble("value"),0.0)
        assertFalse(request.toString().contains("secret")); assertTrue(request.toString().length < 1024)
        config.put("overlayEnabled",false)
        assertEquals(0,overlayRequest(config,samples).getJSONObject("samples").length())
        assertEquals(0,overlayRequest(config,samples).getJSONObject("config").getJSONObject("haFields").length())
    }
    @Test fun wholeStripIsTapTargetIncludingPaddingButOutsideIsNot() {
        assertTrue(overlayHit(1f,1f,700,84)); assertTrue(overlayHit(350f,82f,700,84))
        assertFalse(overlayHit(-1f,20f,700,84)); assertFalse(overlayHit(700f,20f,700,84))
        assertFalse(overlayHit(20f,84f,700,84))
    }
}
