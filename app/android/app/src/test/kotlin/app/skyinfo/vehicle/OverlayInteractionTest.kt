package app.skyinfo.vehicle

import android.os.Looper
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowSettings
import org.robolectric.util.ReflectionHelpers
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w1280dp-h720dp-mdpi", manifest = Config.NONE)
class OverlayInteractionTest {
    @Test fun primaryTouchDeviceUsesExactNameAndReportedNode() {
        val output = """
            add device 1: /dev/input/event17
              name: "virt_display_7_touch_vir"
                ABS_MT_POSITION_X : value 0, min 0, max 3840, fuzz 0
                ABS_MT_POSITION_Y : value 0, min 0, max 1888, fuzz 0
            add device 2: /dev/input/event23
              name: "IVI_touch_vir"
                ABS_MT_POSITION_X : value 0, min 10, max 1930, fuzz 0
                ABS_MT_POSITION_Y : value 0, min 20, max 1100, fuzz 0
            add device 3: /dev/input/event9
              name: "PAS_touch_vir"
                ABS_MT_POSITION_X : value 0, min 0, max 1920, fuzz 0
                ABS_MT_POSITION_Y : value 0, min 0, max 720, fuzz 0
        """.trimIndent()
        assertEquals(TouchDevice("/dev/input/event23",10,1930,20,1100),primaryTouchDevice(output))
        assertTrue(runCatching { primaryTouchDevice(output.replace("IVI_touch_vir","IVI_touch_vir_extra")) }.isFailure)
        assertTrue(runCatching { primaryTouchDevice(output.replace("max 1930","max 10")) }.isFailure)
        assertTrue(runCatching { primaryTouchDevice(output + "\n" + output) }.isFailure)
    }
    private fun config() = JSONObject().put("overlayEnabled",true).put("overlays",JSONArray().put(
        JSONObject().put("field","voltage").put("icon","battery").put("unit","V").put("alignment","left")))
    private fun view(overlay: OverlayWindow) = ReflectionHelpers.getField<View>(overlay,"view")
    private fun params(overlay: OverlayWindow) = ReflectionHelpers.getField<WindowManager.LayoutParams>(overlay,"parameters")
    private fun window(events: MutableList<JSONObject> = mutableListOf()): OverlayWindow {
        ShadowSettings.setCanDrawOverlays(true)
        return OverlayWindow(RuntimeEnvironment.getApplication(),changed = events::add).also { it.update(config(),emptyMap(),emptyMap()) }
    }
    @Test fun armedWindowTimesOutWithoutExtendingForDataUpdates() {
        val overlay = window()
        assertTrue(params(overlay).flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE != 0)
        assertTrue(overlay.arm())
        assertEquals(0,params(overlay).flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(3))
        overlay.update(config(),emptyMap(),emptyMap())
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(3))
        assertTrue(params(overlay).flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE != 0)
        overlay.close()
    }
    @Test fun physicalTapInStripPaddingArmsBeforeAnyPaintAndOutsideDoesNot() {
        val overlay = window()
        val p = params(overlay)
        fun point(action: Int, x: Float, y: Float, time: Long) {
            ReflectionHelpers.callInstanceMethod<Unit>(overlay,"observeTap",
                ReflectionHelpers.ClassParameter.from(TouchPoint::class.java,TouchPoint(action,x,y,time)))
        }
        point(MotionEvent.ACTION_DOWN,p.x-1f,p.y+1f,100)
        point(MotionEvent.ACTION_UP,p.x-1f,p.y+1f,200)
        assertTrue(p.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE != 0)
        point(MotionEvent.ACTION_DOWN,p.x+1f,p.y+1f,300)
        point(MotionEvent.ACTION_UP,p.x+1f,p.y+1f,400)
        assertEquals(0,p.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(6))
        assertTrue(p.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE != 0)
        overlay.close()
    }
    @Test fun holdThenDragSavesPositionAndLocksAfterRelease() {
        val events = mutableListOf<JSONObject>(); val overlay = window(events)
        overlay.arm()
        val down = SystemClock.uptimeMillis()
        fun touch(action: Int, x: Float, y: Float) {
            val event = MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,x,y,0)
            view(overlay).dispatchTouchEvent(event); event.recycle()
        }
        touch(MotionEvent.ACTION_DOWN,20f,20f)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(700))
        touch(MotionEvent.ACTION_MOVE,120f,220f)
        touch(MotionEvent.ACTION_UP,120f,220f)
        val position = events.last { it.has("x") }
        assertTrue(position.getDouble("x") > 0); assertTrue(position.getDouble("y") > 0)
        assertEquals("unlocked",position.getString("state"))
        val x = params(overlay).x; val y = params(overlay).y
        overlay.update(config().put("overlayX",position.getDouble("x")).put("overlayY",position.getDouble("y")),emptyMap(),emptyMap())
        assertEquals(x,params(overlay).x); assertEquals(y,params(overlay).y)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(6))
        assertTrue(params(overlay).flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE != 0)
        overlay.close()
    }
    @Test fun resetDuringDragCancelsTheGestureWithoutSavingItsOldPosition() {
        val events = mutableListOf<JSONObject>(); val overlay = window(events)
        overlay.arm()
        val down = SystemClock.uptimeMillis()
        fun touch(action: Int, x: Float, y: Float) {
            val event = MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,x,y,0)
            view(overlay).dispatchTouchEvent(event); event.recycle()
        }
        touch(MotionEvent.ACTION_DOWN,20f,20f)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(700))
        touch(MotionEvent.ACTION_MOVE,120f,220f)
        assertTrue(params(overlay).y > 0)
        overlay.resetPosition()
        touch(MotionEvent.ACTION_UP,120f,220f)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(6))
        assertFalse(events.any { it.has("x") })
        assertEquals(0,params(overlay).y)
        assertEquals((1280-params(overlay).width)/2,params(overlay).x)
        assertTrue(params(overlay).flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE != 0)
        overlay.update(config(),emptyMap(),emptyMap())
        assertEquals(0,params(overlay).y)
        assertEquals((1280-params(overlay).width)/2,params(overlay).x)
        overlay.close()
    }
    @Test fun closeCancelsPendingUnlockAndCannotArmRemovedWindow() {
        val overlay = window()
        overlay.arm(); overlay.close()
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(6))
        assertFalse(overlay.visible); assertFalse(overlay.arm())
    }
    @Test fun stationaryHeldGestureAlsoLocksAndSavesPosition() {
        val events = mutableListOf<JSONObject>(); val overlay = window(events)
        overlay.arm()
        val down = SystemClock.uptimeMillis()
        val event = MotionEvent.obtain(down,down,MotionEvent.ACTION_DOWN,20f,20f,0)
        view(overlay).dispatchTouchEvent(event); event.recycle()
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(7))
        assertTrue(events.any { it.has("x") })
        assertTrue(params(overlay).flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE != 0)
        overlay.close()
    }
}
