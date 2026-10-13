package app.skyinfo.vehicle

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.concurrent.CopyOnWriteArrayList

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class VerifiedControlsTest {
    private class Port : VehicleControls.Port {
        var identity = JSONObject().put("uid",2000).put("user",10).put("firmware","59.7.4.26080703.1").put("protocol","CANFD")
        var gear = 1
        var unit = 1
        var actual = 0
        var after = 0
        var startDelayMs = 0L
        var failStart = false
        var failStop = false
        val writes = CopyOnWriteArrayList<Triple<Int,List<Int>,List<Int>>>()
        override fun environment() = identity
        override fun read(device: Int, field: Int) = when(field) { 555745336 -> gear; 1077936167 -> unit; else -> actual }
        override fun write(device: Int, fields: IntArray, values: IntArray): Int {
            writes.add(Triple(device,fields.toList(),values.toList()))
            if (values[0] != 0 && startDelayMs > 0) Thread.sleep(startDelayMs)
            if (failStart && values[0] != 0) throw SecurityException()
            actual = after
            return if (failStop && values[0] == 0) -1 else 0
        }
    }
    private fun denied(action: String, value: Int) {
        val port=Port()
        try { VehicleControls(port).execute(action,value); fail("unverified value accepted") } catch (_: IllegalArgumentException) { }
        assertTrue(port.writes.isEmpty())
    }
    @Test fun sparseWhitelistRejectsUnprovenActionsAndValues() {
        assertEquals(173,VehicleControls.definitions.size)
        denied("headlight_height",0); denied("seat_massage_cycle_driver",1)
        denied("main_temp",24); denied("deputy_temp",25); denied("unknown_window",1)
        val labels=VehicleControls.metadata(VehicleControls.definition("seat_massage_cycle_driver"))
        assertEquals(2,labels.getJSONArray("options").length())
    }
    @Test fun differentUsersRootAndFirmwareUseCompatibleInterfaceWithoutGearGate() {
        for ((key,value) in listOf("uid" to 0,"uid" to 10183,"user" to 0,"user" to 12,"firmware" to "updated")) {
            val port=Port();port.identity.put(key,value);port.actual=1;port.after=1;port.gear=4
            assertEquals("accepted_unconfirmed",VehicleControls(port).execute("door_lock",2).getString("status"))
            assertEquals(1,port.writes.size)
        }
        val port=Port();port.identity.put("protocol","CAN")
        assertEquals("unsupported_environment",VehicleControls(port).execute("door_lock",2).getString("status"))
        assertTrue(port.writes.isEmpty())
    }
    @Test fun roadPreviewUsesObservedFeedbackEncoding() {
        val port=Port();port.actual=1;port.after=0
        val result=VehicleControls(port).execute("road_preview",1)
        assertEquals("confirmed",result.getString("status"));assertEquals(0,result.getInt("actual"))
        assertEquals(Triple(1023,listOf(1324576806),listOf(1)),port.writes.single())
        assertEquals("关闭",VehicleControls.metadata(VehicleControls.definition("road_preview")).getJSONObject("states").getString("0"))
    }
    @Test fun actuatorPositionDoesNotProveCommandCompletion() {
        val port=Port();port.actual=4;port.after=4
        assertEquals("accepted_unconfirmed",VehicleControls(port).execute("window_left_front",4).getString("status"))
        assertEquals(Triple(1001,listOf(1125122104),listOf(4)),port.writes.single())
        port.writes.clear()
        assertEquals("accepted_unconfirmed",VehicleControls(port).execute("door_lock",2).getString("status"))
    }
    @Test fun independentTemperatureKeepsOtherZoneOutOfWrite() {
        val port=Port();port.actual=23;port.after=24
        assertEquals("confirmed",VehicleControls(port).execute("deputy_temp",24).getString("status"))
        assertEquals(listOf(1,0,24,0,0),port.writes.single().third)
        port.writes.clear();port.unit=0
        assertEquals("unsupported_state",VehicleControls(port).execute("main_temp",25).getString("status"))
        assertTrue(port.writes.isEmpty())
    }
    @Test fun pulseAlwaysStopsIncludingStartFailure() {
        for (fail in listOf(false,true)) {
            val port=Port();port.failStart=fail
            val result=VehicleControls(port).execute("seat_leg_rest_passenger",1)
            assertEquals(if (fail) "permission" else "accepted_unconfirmed",result.getString("status"))
            assertEquals(listOf(listOf(1),listOf(0)),port.writes.map { it.third })
            assertEquals(0,result.getInt("stop_native_status"))
        }
    }
    @Test fun delayedStartGetsFinalStopAfterEarlyWatchdogStop() {
        val port=Port();port.startDelayMs=400
        val result=VehicleControls(port).execute("seat_leg_rest_passenger",1)
        assertEquals("accepted_unconfirmed",result.getString("status"))
        assertEquals(listOf(listOf(1),listOf(0),listOf(0)),port.writes.map { it.third })
        assertEquals(0,result.getInt("early_stop_native_status"));assertEquals(0,result.getInt("stop_native_status"))
    }
    @Test fun interruptedCallerDoesNotCancelStopAndStopRejectionIsVisible() {
        val port=Port();var result: JSONObject?=null
        val caller=Thread { result=VehicleControls(port).execute("seat_move_up_down_driver",1) }
        caller.start()
        val deadline=System.nanoTime()+java.util.concurrent.TimeUnit.SECONDS.toNanos(2)
        while(port.writes.isEmpty() && System.nanoTime()<deadline) Thread.yield()
        caller.interrupt();caller.join(3000)
        assertFalse(caller.isAlive);assertEquals(listOf(0),port.writes.last().third)
        assertEquals("accepted_unconfirmed",result!!.getString("status"))
        val rejected=Port();rejected.failStop=true
        assertEquals("stop_unconfirmed",VehicleControls(rejected).execute("seat_leg_rest_passenger",1).getString("status"))
    }
    @Test fun remoteCommandsShareExactSparseWhitelist() {
        val now=1791473000000L
        fun event(value: Any)=JSONObject().put("event_type","skyinfo_command").put("time_fired",java.time.Instant.ofEpochMilli(now).toString())
            .put("context",JSONObject().put("id","command_1")).put("data",JSONObject().put("target","skyinfo_demo").put("action","sunroof_control").put("value",value))
        assertEquals(253,RemoteCommands({true}) { now }.validate(event(253),"skyinfo_demo").getInt("value"))
        for (value in listOf(254,25.5,"253")) {
            try { RemoteCommands({true}) { now }.validate(event(value),"skyinfo_demo");fail("invalid command accepted") } catch (_: IllegalArgumentException) { }
        }
    }
}
