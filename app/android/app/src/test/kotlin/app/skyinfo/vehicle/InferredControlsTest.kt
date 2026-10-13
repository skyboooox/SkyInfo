package app.skyinfo.vehicle

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class InferredControlsTest {
    private class Port : VehicleControls.Port {
        var identity = JSONObject().put("uid",2000).put("user",10).put("firmware","59.7.4.26080703.1").put("protocol","CANFD")
        var gear = 1
        var invalid: Int? = null
        var actual = 0
        val reads=mutableListOf<Int>()
        val writes=mutableListOf<Triple<Int,List<Int>,List<Int>>>()
        override fun environment()=identity
        override fun read(device: Int, field: Int): Int { reads.add(field);return if (field==555745336) gear else if(field==invalid) 65535 else actual }
        override fun write(device: Int, fields: IntArray, values: IntArray): Int { writes.add(Triple(device,fields.toList(),values.toList()));return 0 }
    }
    @Test fun snapshotDoesNotProbeCandidatesOrWrite() {
        val port=Port();val control=VehicleControls(port)
        val snapshot=control.snapshot().getJSONArray("controls")
        val candidate=VehicleControls.definition("window_right_front")
        assertFalse(port.reads.contains(candidate.read))
        assertEquals(173,snapshot.length());assertEquals(134,VehicleControls.definitions.count { it.inferred })
        assertTrue(port.writes.isEmpty())
    }
    @Test fun inferredExecutionHasNoGearGateAndCannotClaimConfirmedEffect() {
        val port=Port();port.gear=4;port.actual=1
        assertEquals("accepted_unconfirmed",VehicleControls(port).execute("window_right_front",1).getString("status"))
        assertEquals(Triple(1001,listOf(1125122107),listOf(1)),port.writes.single())
        assertFalse(port.reads.contains(555745336))
    }
    @Test fun fixedIntegerChoiceExpandsFullAirflowVectorWithoutAcceptingAnArbitraryArray() {
        val port=Port();val result=VehicleControls(port).execute("ac_blow_mode_driver",2)
        assertEquals("accepted_unconfirmed",result.getString("status"))
        assertEquals(listOf(0,1,0),port.writes.single().third)
        assertEquals(listOf(1324367888,1324367892,1324367898),port.writes.single().second)
        assertEquals(3,result.getJSONObject("before_values").length())
        port.writes.clear();port.invalid=1269825946
        assertEquals("unsupported_state",VehicleControls(port).execute("ac_blow_mode_driver",3).getString("status"))
        assertTrue(port.writes.isEmpty())
    }
    @Test fun conflictingAndInapplicableEntriesAreNotMadeExecutable() {
        for(id in listOf("esp_control","drive_mode_low","slide_door_left","third_row_temp")) {
            try { VehicleControls.definition(id);fail(id) } catch (_: IllegalArgumentException) { }
        }
        val d=VehicleControls.definition("hud_brightness")
        assertEquals("inferred",VehicleControls.metadata(d).getString("validation"))
        try { d.validate(d.max+1);fail("outside range") } catch (_: IllegalArgumentException) { }
    }
    @Test fun removedInferencePreferenceCannotChangeConfiguration() {
        assertFalse(ConfigValidator.validate(JSONObject(),emptyMap()).has("inferredControlsEnabled"))
        for (oldValue in listOf(false,true,"true")) {
            assertFalse(ConfigValidator.validate(JSONObject().put("inferredControlsEnabled",oldValue),emptyMap()).has("inferredControlsEnabled"))
        }
    }
    @Test fun inferredCompatibilityUsesProtocolRatherThanFixedIdentity() {
        val port=Port();port.identity.put("uid",0).put("user",12).put("firmware","new")
        assertEquals("accepted_unconfirmed",VehicleControls(port).execute("window_right_front",1).getString("status"))
        val incompatible=Port();incompatible.identity.put("protocol","CAN")
        assertEquals("unsupported_environment",VehicleControls(incompatible).execute("window_right_front",1).getString("status"))
        assertTrue(incompatible.reads.isEmpty());assertTrue(incompatible.writes.isEmpty())
    }
    @Test fun invalidInferenceParameterIsRejectedBeforeReadingOrWriting() {
        val port=Port()
        try { VehicleControls(port).execute("window_right_front",254);fail("invalid parameter accepted") } catch (_: IllegalArgumentException) { }
        assertTrue(port.reads.isEmpty());assertTrue(port.writes.isEmpty())
    }
    @Test fun pulseStillStopsWhileMarkedUnverified() {
        val port=Port()
        val result=VehicleControls(port).execute("seat_move_front_passenger",1)
        assertEquals("accepted_unconfirmed",result.getString("status"))
        assertEquals(listOf(listOf(1),listOf(0)),port.writes.map { it.third })
        assertEquals(0,result.getInt("stop_native_status"))
    }
}
