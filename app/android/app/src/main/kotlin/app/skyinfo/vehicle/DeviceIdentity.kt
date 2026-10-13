package app.skyinfo.vehicle

import android.content.Context
import org.json.JSONObject
import java.util.UUID

internal class DeviceIdentity(context: Context) {
    private val prefs = context.getSharedPreferences("skyinfo.device", Context.MODE_PRIVATE)
    val id: String = prefs.getString("id", null) ?: UUID.randomUUID().toString().also {
        check(prefs.edit().putString("id", it).commit())
    }
    val prefix = "skyinfo_${id.replace("-", "").take(12)}"
    val topic = "skyinfo/$id"
    fun defaults(config: JSONObject): JSONObject = config.apply {
        put("deviceId", id)
        if (!has("dashboardSize")) put("dashboardSize", "standard")
        if (!has("collect")) put("collect", true)
        if (optString("prefix").isBlank()) put("prefix", prefix)
        if (optString("mqttTopic").isBlank()) put("mqttTopic", topic)
        if (optString("haConnectionId").isBlank()) put("haConnectionId", UUID.randomUUID().toString())
    }
}
