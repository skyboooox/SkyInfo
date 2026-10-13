package app.skyinfo.vehicle

import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant

internal fun JSONObject.haText(key: String, fallback: String = ""): String = opt(key) as? String ?: fallback

internal data class HaBinding(val connection: String, val entity: String, val attribute: String? = null) {
    val id: String get() = "ha|$connection|$entity" + (attribute?.let { "|$it" } ?: "")
    companion object {
        fun parse(id: String): HaBinding? {
            val parts = id.split('|')
            if (parts.size !in 3..4 || parts[0] != "ha" || !Regex("^[a-zA-Z0-9-]{1,64}$").matches(parts[1]) ||
                !Regex("^[a-z0-9_]+\\.[a-z0-9_]+$").matches(parts[2]) ||
                parts.size == 4 && !Regex("^[a-zA-Z0-9_]{1,128}$").matches(parts[3])) return null
            return HaBinding(parts[1], parts[2], parts.getOrNull(3))
        }
    }
}

internal object HaEntityModel {
    private val attributeKey = Regex("^[a-zA-Z0-9_]{1,128}$")
    private val metadataAttributes = setOf("friendly_name", "unit_of_measurement", "state_class", "temperature_unit",
        "supported_features", "supported_color_modes", "min_color_temp_kelvin", "max_color_temp_kelvin",
        "min", "max", "step", "options", "hvac_modes", "min_temp", "max_temp", "target_temp_step", "fan_modes",
        "percentage_step", "preset_modes", "code_format")
    fun metadataSignature(state: JSONObject): String {
        val attributes = state.optJSONObject("attributes") ?: JSONObject()
        val schema = JSONObject()
        val metadata = JSONObject()
        for (key in attributes.keys().asSequence().sorted()) {
            val value = attributes.opt(key)
            val type = when (value) { is Number -> "number"; is Boolean -> "boolean"; is String -> "string"; else -> null }
            if (type != null && attributeKey.matches(key)) schema.put(key, type)
            if (key in metadataAttributes) metadata.put(key, canonical(value))
        }
        return JSONObject().put("entity",state.optString("entity_id")).put("schema",schema).put("metadata",metadata).toString()
    }
    private fun canonical(value: Any?): Any = when(value) {
        is JSONObject -> JSONObject().apply { for(key in value.keys().asSequence().sorted()) put(key,canonical(value.opt(key))) }
        is JSONArray -> JSONArray().apply { for(index in 0 until value.length()) put(canonical(value.opt(index))) }
        null -> JSONObject.NULL
        else -> value
    }
    fun numeric(state: JSONObject): Boolean {
        val domain = state.optString("entity_id").substringBefore('.')
        val attributes = state.optJSONObject("attributes") ?: JSONObject()
        return domain in setOf("number", "input_number") || domain == "sensor" &&
            (attributes.haText("unit_of_measurement").isNotEmpty() || attributes.haText("state_class").isNotEmpty())
    }
    fun unit(state: JSONObject, attribute: String?): String {
        val a = state.optJSONObject("attributes") ?: JSONObject()
        return when (attribute) {
            null -> a.haText("unit_of_measurement")
            "temperature", "current_temperature", "target_temp_low", "target_temp_high" -> a.haText("temperature_unit").ifEmpty { a.haText("unit_of_measurement") }
            "current_position", "percentage", "humidity", "current_humidity" -> "%"
            else -> ""
        }
    }
    fun availableForAction(state: JSONObject): Boolean = state.optString("state") != "unavailable" &&
        (state.optString("state") != "unknown" || state.optString("entity_id").substringBefore('.') in setOf("button", "input_button", "scene", "script"))
    fun sample(binding: HaBinding, state: JSONObject?, connected: Boolean, epoch: Long, at: Long = System.currentTimeMillis()): JSONObject {
        val out = JSONObject().put("source", binding.id).put("transport", "ha_websocket").put("receivedAt", at)
            .put("sourceEpoch", epoch).put("definitionVersion", 1)
        val quality = when {
            !connected -> "disconnected"
            state == null -> "removed"
            state.optString("state") == "unavailable" -> "unavailable"
            state.optString("state") == "unknown" -> "unknown"
            else -> "available"
        }
        out.put("quality", quality)
        if (state == null || quality !in setOf("available", "disconnected")) return out
        val attributes = state.optJSONObject("attributes") ?: JSONObject()
        val raw = if (binding.attribute == null) state.opt("state") as? String else attributes.opt(binding.attribute)
        if (raw == null || raw === JSONObject.NULL || raw is JSONArray || raw is JSONObject)
            return out.put("quality", if (binding.attribute == null) "invalid" else "missing_attribute")
        val value = if (binding.attribute == null && numeric(state)) raw.toString().toDoubleOrNull()?.takeIf { it.isFinite() }
            else if (raw is Number) raw.toDouble().takeIf { it.isFinite() } else raw
        if (value == null) return out.put("quality", "invalid")
        val updated = runCatching { Instant.parse(state.getString("last_updated")).toEpochMilli() }.getOrDefault(at)
        val changed = runCatching { Instant.parse(state.getString("last_changed")).toEpochMilli() }.getOrDefault(updated)
        return out.put("value", value).put("raw", raw).put("unit", unit(state, binding.attribute))
            .put("updatedAt", updated).put("changedAt", if (binding.attribute == null) changed else updated)
    }
    fun field(binding: HaBinding, state: JSONObject?, fallback: JSONObject? = null): JSONObject {
        val a = state?.optJSONObject("attributes") ?: JSONObject()
        val raw = binding.attribute?.let(a::opt)
        return JSONObject().put("id", binding.id).put("name", a.haText("friendly_name").ifEmpty { binding.entity } + (binding.attribute?.let { " · $it" } ?: ""))
            .put("category", "Home Assistant").put("icon", "").put("entityKey", binding.entity).put("subscription", "callback_observed")
            .put("displayAllowed", true).put("unit", if (state == null) fallback?.haText("unit") ?: "" else unit(state, binding.attribute))
            .put("encoding", if (state == null) fallback?.haText("encoding", "文本") ?: "文本" else if (binding.attribute == null && numeric(state) || raw is Number) "数值" else "文本")
    }
    fun functions(state: JSONObject, services: JSONObject): JSONArray {
        val domain = state.getString("entity_id").substringBefore('.')
        val attrs = state.optJSONObject("attributes") ?: JSONObject()
        val features = attrs.optInt("supported_features")
        val available = services.optJSONObject(domain) ?: JSONObject()
        val result = JSONArray()
        fun action(key: String, service: String, label: String, confirmation: Boolean = false, flag: Int? = null) {
            if (available.has(service) && (flag == null || features and flag != 0)) result.put(JSONObject().put("key", key).put("service", service)
                .put("kind", "button").put("label", label).put("confirmation", confirmation))
        }
        fun toggle() {
            if (available.has("turn_on") && available.has("turn_off")) result.put(JSONObject().put("key", "power").put("kind", "toggle")
                .put("label", "ha_power").put("service", "turn_on").put("offService", "turn_off").put("expected", "state"))
        }
        fun select(key: String, service: String, parameter: String, options: JSONArray?, label: String, expected: String) {
            if (available.has(service) && options != null && options.length() > 0 && (0 until options.length()).all { options.opt(it) is String })
                result.put(JSONObject().put("key", key).put("kind", "select").put("label", label).put("service", service)
                    .put("parameter", parameter).put("options", options).put("expected", expected))
        }
        fun number(key: String, service: String, parameter: String, minimum: Double, maximum: Double, step: Double, label: String, expected: String, flag: Int? = null) {
            if (available.has(service) && minimum.isFinite() && maximum.isFinite() && step.isFinite() && maximum > minimum && step > 0 &&
                (flag == null || features and flag != 0)) result.put(JSONObject().put("key", key).put("kind", "number").put("label", label)
                .put("service", service).put("parameter", parameter).put("min", minimum).put("max", maximum).put("step", step).put("expected", expected))
        }
        when (domain) {
            "switch", "input_boolean" -> toggle()
            "light" -> { toggle(); if (RuntimeCoordinator.list(attrs.optJSONArray("supported_color_modes")).any { it !in setOf("onoff", "unknown") })
                number("brightness", "turn_on", "brightness", 0.0, 255.0, 1.0, "ha_brightness", "brightness")
                if (attrs.optDouble("min_color_temp_kelvin", Double.NaN).isFinite()) number("color_temperature", "turn_on", "color_temp_kelvin",
                    attrs.optDouble("min_color_temp_kelvin"), attrs.optDouble("max_color_temp_kelvin", Double.NaN), 1.0, "ha_color_temperature", "color_temp_kelvin") }
            "number", "input_number" -> number("value", "set_value", "value", attrs.optDouble("min", Double.NaN), attrs.optDouble("max", Double.NaN), attrs.optDouble("step", Double.NaN), "ha_value", "state")
            "select", "input_select" -> select("option", "select_option", "option", attrs.optJSONArray("options"), "ha_option", "state")
            "button", "input_button" -> action("press", "press", "ha_press")
            "scene", "script" -> action("run", "turn_on", "ha_run")
            "climate" -> { select("hvac", "set_hvac_mode", "hvac_mode", attrs.optJSONArray("hvac_modes"), "ha_hvac", "state")
                number("temperature", "set_temperature", "temperature", attrs.optDouble("min_temp", Double.NaN), attrs.optDouble("max_temp", Double.NaN), attrs.optDouble("target_temp_step", Double.NaN), "ha_temperature", "temperature", 1)
                if (features and 8 != 0) select("fan_mode", "set_fan_mode", "fan_mode", attrs.optJSONArray("fan_modes"), "ha_fan_mode", "fan_mode") }
            "cover" -> { action("open", "open_cover", "ha_open", flag = 1); action("close", "close_cover", "ha_close", flag = 2); action("stop", "stop_cover", "ha_stop", flag = 8)
                number("position", "set_cover_position", "position", 0.0, 100.0, 1.0, "ha_position", "current_position", 4) }
            "fan" -> { toggle(); number("percentage", "set_percentage", "percentage", 0.0, 100.0, attrs.optDouble("percentage_step", Double.NaN), "ha_percentage", "percentage", 1)
                if (features and 8 != 0) select("preset", "set_preset_mode", "preset_mode", attrs.optJSONArray("preset_modes"), "ha_preset", "preset_mode") }
            "lock" -> { action("lock", "lock", "ha_lock"); if (attrs.isNull("code_format") || attrs.opt("code_format") == "") action("unlock", "unlock", "ha_unlock", confirmation = true) }
            "media_player" -> { action("play", "media_play", "ha_play", flag = 16384); action("pause", "media_pause", "ha_pause", flag = 1)
                number("volume", "volume_set", "volume_level", 0.0, 1.0, 0.01, "ha_volume", "volume_level", 4) }
            "vacuum" -> { action("start", "start", "ha_start", flag = 8192); action("pause", "pause", "ha_pause", flag = 4); action("stop", "stop", "ha_stop", flag = 8); action("return", "return_to_base", "ha_return", flag = 16) }
        }
        return result
    }
    fun service(state: JSONObject, services: JSONObject, functionKey: String, value: Any?): Pair<JSONObject, JSONObject> {
        val function = functions(state, services).let { a -> (0 until a.length()).map(a::getJSONObject).first { it.getString("key") == functionKey } }
        val data = JSONObject()
        val service = when (function.getString("kind")) {
            "toggle" -> { require(value is Boolean); if (value) function.getString("service") else function.getString("offService") }
            "select" -> { require(value is String && value in RuntimeCoordinator.list(function.getJSONArray("options"))); data.put(function.getString("parameter"), value); function.getString("service") }
            "number" -> { require(value is Number); val v = value.toDouble(); val min = function.getDouble("min"); val step = function.getDouble("step")
                require(v.isFinite() && v >= min && v <= function.getDouble("max") && kotlin.math.abs((v-min)/step - kotlin.math.round((v-min)/step)) < 1e-6)
                data.put(function.getString("parameter"), v); function.getString("service") }
            else -> { require(value == null || value === JSONObject.NULL); function.getString("service") }
        }
        return JSONObject().put("type", "call_service").put("domain", state.getString("entity_id").substringBefore('.')).put("service", service)
            .put("service_data", data).put("target", JSONObject().put("entity_id", state.getString("entity_id"))) to function
    }
}
