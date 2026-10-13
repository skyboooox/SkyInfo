package app.skyinfo.vehicle

import org.json.JSONObject

internal fun applicationStartConfig(saved: JSONObject): JSONObject = JSONObject(saved.toString()).apply {
    put("collect", true)
    put("adbEnabled", true)
    if (!has("dashboardSize")) put("dashboardSize", "standard")
}
