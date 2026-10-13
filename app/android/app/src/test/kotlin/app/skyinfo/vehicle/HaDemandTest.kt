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
class HaDemandTest {
    @Test fun haBindingsSurviveVehicleDependencyExpansion() {
        val state = HaBinding("qa-connection", "input_boolean.qa_test").id
        val attribute = HaBinding("qa-connection", "sensor.qa_test", "voltage").id
        assertEquals(setOf(state, attribute), expandDependencies(setOf(state, attribute), emptyMap()))
    }

    @Test fun mixedDemandKeepsVehicleDependenciesWithoutInventingUnknownFields() {
        val state = HaBinding("qa-connection", "input_number.qa_test").id
        val fields = mapOf(
            "derived.power" to JSONObject().put("derivedInputs", JSONArray(listOf("voltage", "current"))),
            "voltage" to JSONObject(), "current" to JSONObject(),
        )
        assertEquals(setOf(state, "derived.power", "voltage", "current"),
            expandDependencies(setOf(state, "derived.power", "unknown", "ha|bad"), fields))
    }
}
