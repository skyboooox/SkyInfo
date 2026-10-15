package app.skyinfo.vehicle

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

@org.junit.runner.RunWith(org.robolectric.RobolectricTestRunner::class)
@org.robolectric.annotation.Config(sdk = [34], manifest = org.robolectric.annotation.Config.NONE)
class OverlayStylePreviewTest {
    @Test fun appearancePatchCannotChangePositionOrRuntimePreferences() {
        val patch = overlayAppearancePatch(JSONObject().put("overlayFont",24).put("overlayOpacity",0.3))
        assertEquals(24,patch.getInt("overlayFont"))
        for (bad in listOf(JSONObject().put("overlayFont",17), JSONObject().put("overlayX",0.3), JSONObject().put("collect",true))) {
            assertThrows(IllegalArgumentException::class.java) { overlayAppearancePatch(bad) }
        }
    }
    @Test fun stylePreviewAcceptsOnlyBoundedPresentationValues() {
        val patch=overlayStylePatch(JSONObject().put("overlayOpacity",0.5))
        assertEquals(0.5,patch.getDouble("overlayOpacity"),0.0)
        for (bad in listOf(JSONObject().put("collect",false),JSONObject().put("overlayEnabled",true),JSONObject().put("overlayX",0.2),JSONObject().put("overlayOffset",0),JSONObject().put("overlayY",JSONObject.NULL),JSONObject().put("overlayLeft",0),JSONObject().put("overlayRight",0),JSONObject().put("overlayOpacity",0.9))) {
            assertThrows(IllegalArgumentException::class.java) { overlayStylePatch(bad) }
        }
    }
}
