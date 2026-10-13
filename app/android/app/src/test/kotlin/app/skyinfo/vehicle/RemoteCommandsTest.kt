package app.skyinfo.vehicle

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class RemoteCommandsTest {
    private val now = 1791473000000L
    private fun event(action: String = "app_overlay", value: Any = 1) = JSONObject()
        .put("event_type","skyinfo_command").put("time_fired",java.time.Instant.ofEpochMilli(now).toString())
        .put("context",JSONObject().put("id","command_1"))
        .put("data",JSONObject().put("target","skyinfo_demo").put("action",action).put("value",value))
    private fun denied(block: () -> Unit) { try { block(); fail("command accepted") } catch (_: IllegalArgumentException) {} }
    @Test fun onlyFreshAddressedWhitelistedIntegralCommandsAreAcceptedOnce() {
        val seen = mutableSetOf<String>(); val guard = RemoteCommands(seen::add) { now }
        assertEquals("app_overlay",guard.validate(event(),"skyinfo_demo").getString("action"))
        denied { guard.validate(event(),"skyinfo_demo") }
        val first = event(); first.getJSONObject("data").put("command_id","separate_1")
        val second = event(); second.getJSONObject("data").put("command_id","separate_2")
        guard.validate(first,"skyinfo_demo"); guard.validate(second,"skyinfo_demo")
        denied { guard.validate(first,"skyinfo_demo") }
        denied { RemoteCommands({true}) { now + 30001 }.validate(event(),"skyinfo_demo") }
        denied { RemoteCommands({true}) { now }.validate(event(),"other") }
        denied { RemoteCommands({true}) { now }.validate(event("shell_command"),"skyinfo_demo") }
        denied { RemoteCommands({true}) { now }.validate(event("ac_cycle",2.5),"skyinfo_demo") }
        denied { RemoteCommands({true}) { now }.validate(event("ac_cycle",2),"skyinfo_demo") }
        denied { RemoteCommands({true}) { now }.validate(event("ac_wind_level",0),"skyinfo_demo") }
        denied { RemoteCommands({true}) { now }.validate(event("seat_driver_heat",4),"skyinfo_demo") }
    }
    @Test fun mqttCommandsRequireFreshNonretainedSessionAndNeverReplay() {
        val seen = mutableSetOf<String>(); val guard = RemoteCommands(seen::add) { now }
        val data = event().getJSONObject("data").put("schema_version",1).put("command_session","session_1")
            .put("command_id","mqtt_1").put("issued_at",java.time.Instant.ofEpochMilli(now).toString())
            .put("expires_at",java.time.Instant.ofEpochMilli(now+10000).toString())
        denied { guard.validateMqtt(data,"skyinfo_demo","session_1",true) }
        denied { guard.validateMqtt(data,"skyinfo_demo","session_2",false) }
        denied { guard.validateMqtt(data,"other","session_1",false) }
        assertEquals("app_overlay",guard.validateMqtt(data,"skyinfo_demo","session_1",false).getString("action"))
        denied { guard.validateMqtt(data,"skyinfo_demo","session_1",false) }
        denied { RemoteCommands({true}) { now+10001 }.validateMqtt(data,"skyinfo_demo","session_1",false) }
        data.put("expires_at",java.time.Instant.ofEpochMilli(now+30001).toString())
        denied { RemoteCommands({true}) { now }.validateMqtt(data,"skyinfo_demo","session_1",false) }
    }
    @Test fun removedInferenceActionIsRejectedByHaAndMqttBeforeCommandDeduplication() {
        var remembered=0
        val guard=RemoteCommands({ remembered++;true }) { now }
        val retired=event("app_inferred_controls")
        denied { guard.validate(retired,"skyinfo_demo") }
        val mqtt=retired.getJSONObject("data").put("schema_version",1).put("command_session","session_1")
            .put("command_id","retired_1").put("issued_at",java.time.Instant.ofEpochMilli(now).toString())
            .put("expires_at",java.time.Instant.ofEpochMilli(now+10000).toString())
        denied { guard.validateMqtt(mqtt,"skyinfo_demo","session_1",false) }
        assertEquals(0,remembered)
        assertEquals(setOf("app_overlay","app_collect","app_publish","app_refresh"),RemoteCommands.appActions)
    }
    @Test fun steeringWheelHeatingUsesConfirmedSdkValuesAndReadback() {
        var actual = 1
        val control = VehicleControls(object : VehicleControls.Port {
            override fun read(device: Int, field: Int) = if (device == 1011) 1 else actual
            override fun write(device: Int, fields: IntArray, values: IntArray): Int {
                assertEquals(1023,device); assertArrayEquals(intArrayOf(944767029),fields)
                assertArrayEquals(intArrayOf(2),values); actual = 2; return 0
            }
        })
        assertEquals("confirmed",control.execute("steering_wheel_heat",2).getString("status"))
        denied { control.execute("steering_wheel_heat",0) }
        denied { control.execute("steering_wheel_heat",3) }
    }
    @Test fun invalidReadbackAndPermissionDenialNeverProduceSuccess() {
        var writes = 0
        val invalid = VehicleControls(object : VehicleControls.Port {
            override fun read(device: Int, field: Int) = 65535
            override fun write(device: Int, fields: IntArray, values: IntArray): Int { writes++; return 0 }
        })
        assertEquals("unsupported_state",invalid.execute("ac_cycle",1).getString("status")); assertEquals(0,writes)
        val denied = VehicleControls(object : VehicleControls.Port {
            override fun read(device: Int, field: Int) = if (device == 1011) 1 else 0
            override fun write(device: Int, fields: IntArray, values: IntArray): Int = throw SecurityException()
        })
        assertEquals("permission",denied.execute("ac_cycle",1).getString("status"))
    }
    @Test fun temperatureChecksUnitsAndBothZones() {
        var driver = 24; var passenger = 24; var writes = 0
        val control = VehicleControls(object : VehicleControls.Port {
            override fun read(device: Int, field: Int) = when (field) { 555745336,1077936167 -> 1; 1077936176 -> passenger; else -> driver }
            override fun write(device: Int, fields: IntArray, values: IntArray): Int {
                assertArrayEquals(intArrayOf(501219392,501219368,501219376,501219384,501219349),fields)
                if (writes++ == 0) { assertArrayEquals(intArrayOf(1,25,0,0,0),values); driver = 25 }
                else { assertArrayEquals(intArrayOf(1,0,25,0,0),values); passenger = 25 }
                return 0
            }
        })
        val result = control.execute("ac_temperature",25)
        assertEquals("confirmed",result.getString("status")); assertEquals(25,result.getInt("actual_passenger")); assertEquals(2,writes)
        denied { control.execute("ac_temperature",34) }
    }
    @Test fun noApplicationGearRestrictionRemains() {
        var writes = 0
        val control = VehicleControls(object : VehicleControls.Port {
            override fun read(device: Int, field: Int) = if (device == 1011) 4 else 0
            override fun write(device: Int, fields: IntArray, values: IntArray): Int { writes++; return 0 }
        })
        assertEquals("accepted_unconfirmed",control.execute("ac_power",1).getString("status")); assertEquals(1,writes)
    }
    @Test fun commandUsesSdkArrayAndWaitsForActualState() {
        var actual = 0
        val control = VehicleControls(object : VehicleControls.Port {
            override fun read(device: Int, field: Int) = if (device == 1011) 1 else actual
            override fun write(device: Int, fields: IntArray, values: IntArray): Int {
                assertEquals(1000,device); assertArrayEquals(intArrayOf(501219355,501219349),fields)
                assertArrayEquals(intArrayOf(1,0),values); actual = 1; return 0
            }
        })
        val result = control.execute("ac_cycle",1)
        assertEquals("confirmed",result.getString("status")); assertEquals(0,result.getInt("before")); assertEquals(1,result.getInt("actual"))
        denied { control.execute("ac_cycle",4) }
    }
}
