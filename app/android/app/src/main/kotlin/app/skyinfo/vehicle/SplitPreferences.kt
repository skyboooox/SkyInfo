package app.skyinfo.vehicle

import org.json.JSONArray
import org.json.JSONObject

/** Persisted choices describe future explicit actions; validation never launches an app. */
object SplitPreferences {
    val keys = setOf("startupPage", "splitCombos")
    fun normalize(config: JSONObject) {
        val startup = if (config.has("startupPage")) config.get("startupPage") else "information"
        require(startup is String && startup in setOf("information", "overlay", "split", "connection", "settings")) { "invalid_startup_page" }
        config.put("startupPage", startup)
        val source = if (config.has("splitCombos")) config.getJSONArray("splitCombos") else JSONArray()
        require(source.length() <= 64) { "too_many_split_combos" }
        val ids = mutableSetOf<String>()
        val normalized = JSONArray()
        for (i in 0 until source.length()) {
            val combo = source.getJSONObject(i)
            val id = combo.get("id") as? String ?: throw IllegalArgumentException("invalid_split_id")
            require(id.length in 1..64 && id.none { it.isISOControl() } && ids.add(id)) { "invalid_split_id" }
            val name = combo.get("name") as? String ?: throw IllegalArgumentException("invalid_split_name")
            require(name.isNotBlank() && name.length <= 128 && name.none { it.isISOControl() }) { "invalid_split_name" }
            val ratio = combo.get("ratio")
            require(ratio is String && ratio in setOf("7/3", "3/7")) { "invalid_ratio" }
            val advanced = if (combo.has("advanced")) combo.get("advanced") else false
            require(advanced is Boolean) { "invalid_split_advanced" }
            fun side(key: String): JSONObject {
                val saved = combo.getJSONObject(key)
                val values = mutableMapOf<String, Any?>("packageName" to saved.get("packageName"))
                if (saved.has("activityName") && !saved.isNull("activityName")) values["activityName"] = saved.get("activityName")
                val target = SplitTarget.parse(values) ?: throw IllegalArgumentException("invalid_target")
                require(advanced || target.activityName == null) { "invalid_split_activity" }
                val label = saved.get("label") as? String ?: throw IllegalArgumentException("invalid_split_label")
                require(label.isNotBlank() && label.length <= 256 && label.none { it.isISOControl() }) { "invalid_split_label" }
                return JSONObject().put("packageName", target.packageName).put("label", label).also { value ->
                    target.activityName?.let { value.put("activityName", SplitTarget.activityName(target.packageName, it)) }
                }
            }
            normalized.put(JSONObject().put("id", id).put("name", name).put("ratio", ratio).put("advanced", advanced).put("left", side("left")).put("right", side("right")))
        }
        config.put("splitCombos", normalized)
    }
}
