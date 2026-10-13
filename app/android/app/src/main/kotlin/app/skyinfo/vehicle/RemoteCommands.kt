package app.skyinfo.vehicle

import org.json.JSONObject
import java.time.Instant

class RemoteCommands(private val remember: (String) -> Boolean, private val now: () -> Long = System::currentTimeMillis) {
    fun validate(event: JSONObject, target: String): JSONObject {
        require(event.getString("event_type") == "skyinfo_command")
        val time = Instant.parse(event.getString("time_fired")).toEpochMilli()
        require(now() - time in -2000..30000) { "expired" }
        val data = event.getJSONObject("data")
        require(data.getString("target") == target) { "target_mismatch" }
        return validateData(data, event.getJSONObject("context").getString("id"))
    }
    fun validateMqtt(data: JSONObject, target: String, session: String, retained: Boolean): JSONObject {
        require(!retained) { "retained" }
        require(data.get("schema_version") is Number && data.getDouble("schema_version") == 1.0)
        require(session.isNotEmpty() && data.getString("command_session") == session) { "session_mismatch" }
        require(data.getString("target") == target) { "target_mismatch" }
        val issued = Instant.parse(data.getString("issued_at")).toEpochMilli()
        val expires = Instant.parse(data.getString("expires_at")).toEpochMilli()
        require(expires - issued in 1..30000 && now() - issued in -30000..30000 && now() <= expires) { "expired" }
        return validateData(data, "")
    }
    private fun validateData(data: JSONObject, fallbackId: String): JSONObject {
        val action = data.getString("action")
        require(action in appActions || action in VehicleControls.definitions.map { it.id }) { "unknown_action" }
        val value = data.get("value")
        require(value is Number && value.toDouble().isFinite() && value.toDouble() == value.toInt().toDouble()) { "non_integer" }
        if (action in appActions) require(value.toInt() in 0..1)
        else VehicleControls.definition(action).validate(value.toInt())
        val id = data.optString("command_id", fallbackId)
        require(Regex("^[A-Za-z0-9_-]{1,128}$").matches(id))
        require(remember(id)) { "duplicate" }
        return JSONObject().put("id",id).put("action",action).put("value",value.toInt())
    }
    companion object { val appActions = setOf("app_overlay", "app_collect", "app_publish", "app_refresh") }
}
