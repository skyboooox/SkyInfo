package app.skyinfo.vehicle

import org.json.JSONArray
import org.json.JSONObject

internal data class HaControlDefinition(val topic: String, val stateTopic: String, val payload: JSONObject, val group: String = "")

internal fun haControlDefinitions(device: String, prefix: String, version: String, entity: JSONObject, commandTopic: String): List<HaControlDefinition> {
    val action = entity.getString("id")
    val options = entity.getJSONArray("options")
    val stateTopic = "skyinfo/ha/$device/control/$action/state"
    val commandOnly = entity.getString("capability") == "button"
    val kind = when {
        action == "ac_wind_level" -> "select"
        commandOnly && options.length() > 1 -> "select"
        else -> when(entity.getString("capability")) { "toggle" -> "switch"; "number" -> "number"; "select" -> "select"; else -> "button" }
    }
    val group = haControlGroup(action)
    val groupDevice = JSONObject().put("identifiers",JSONArray().put("skyinfo_${device}_$group"))
        .put("name",NativeStrings.text("ha_device_$group"))
    fun base(suffix: String, name: String): JSONObject = JSONObject()
        .put("name",name).put("unique_id","skyinfo_${device}_control_$suffix")
        .put("default_entity_id","$kind.skyinfo_${prefix}_$suffix")
        .put("command_topic",commandTopic).put("qos",0).put("retain",false)
        .put("enabled_by_default",true)
        .put("availability_topic",stateTopic)
        .put("availability_template","{{ 'online' if value_json.available else 'offline' }}")
        .put("json_attributes_topic",stateTopic)
        .put("device",JSONObject().put("identifiers",JSONArray().put("skyinfo_$device"))
            .put("name","SkyInfo $prefix").put("manufacturer","SkyInfo").put("model","BYD 车机").put("sw_version",version).put("child_device",groupDevice))
    fun command(value: Any) = JSONObject().put("action",action).put("value",value).toString()
    if (kind == "button") return (0 until options.length()).map { index ->
        val option = options.getJSONObject(index)
        val suffix = action+"_"+option.getInt("value")
        HaControlDefinition("homeassistant/button/skyinfo_$device/$suffix/config",stateTopic,
            base(suffix,entity.getString("name")+" · "+option.getString("label"))
                .put("payload_press",command(option.getInt("value"))),group)
    }
    val suffix = if (action == "ac_wind_level") action + "_selection" else action
    val name = if (commandOnly) NativeStrings.text("ha_control_operation",mapOf("name" to entity.getString("name"))) else entity.getString("name")
    val payload = base(suffix,name).put("state_topic",stateTopic).put("optimistic",false)
    when(kind) {
        "switch" -> {
            val on = (0 until options.length()).map(options::getJSONObject).first { it.getString("label") == NativeStrings.on }
            val off = (0 until options.length()).map(options::getJSONObject).first { it.getString("label") == NativeStrings.close }
            payload.put("payload_on",command(on.getInt("value"))).put("payload_off",command(off.getInt("value")))
                .put("state_on",on.getString("label")).put("state_off",off.getString("label"))
                .put("value_template","{{ value_json.state }}")
        }
        "select" -> {
            val values = JSONObject()
            for (i in 0 until options.length()) options.getJSONObject(i).let { values.put(it.getString("label"),it.getInt("value")) }
            // JSON permits escaped slashes; Jinja dictionary string keys preserve them.
            val mapping = values.toString().replace("\\/","/")
            payload.put("options",JSONArray((0 until options.length()).map { options.getJSONObject(it).getString("label") }))
                .put("value_template",if (commandOnly) "{{ 'None' }}" else "{{ value_json.state }}")
                .put("command_template","{\"action\":\"$action\",\"value\":{{ (${mapping}).get(value) | tojson }}}")
        }
        "number" -> payload.put("min",(0 until options.length()).minOf { options.getJSONObject(it).getInt("value") })
            .put("max",(0 until options.length()).maxOf { options.getJSONObject(it).getInt("value") }).put("step",1).put("mode","slider")
            .put("value_template","{{ value_json.raw }}")
            .put("command_template","{\"action\":\"$action\",\"value\":{{ value | float | tojson }}}")
            .also { if (entity.optString("unit").isNotEmpty()) it.put("unit_of_measurement",entity.getString("unit")) }
    }
    return listOf(HaControlDefinition("homeassistant/$kind/skyinfo_$device/$suffix/config",stateTopic,payload,group))
}

internal fun haControlState(entity: JSONObject, samples: Map<String, JSONObject>, enabled: Boolean): JSONObject {
    val read = entity.optString("readField")
    val sample = samples[read]
    val raw = sample?.opt("raw")
    val options = entity.getJSONArray("options")
    val expected = (0 until options.length()).map { options.getJSONObject(it).opt("expected") }
    val recognized = entity.optString("capability") == "button" || expected.any { it is Number && raw is Number && it.toDouble() == raw.toDouble() }
    val unitValid = entity.optString("unit") != "°C" || sample?.optString("unit") == "°C"
    val feedback = entity.optString("capability") != "button"
    val valid = feedback && recognized && unitValid && sample?.optString("quality") in listOf("available","unverified") && raw is Number && raw.toInt() != 65535
    val coherent = entity.getString("id") != "ac_temperature" || RuntimeCoordinator.list(entity.optJSONArray("feedbackFields")).all {
        samples[it]?.optString("quality") in listOf("available","unverified") && samples[it]?.opt("raw") == raw
    }
    return JSONObject().put("available",enabled && (entity.optString("capability") == "button" || valid && coherent))
        .put("raw",if (valid && coherent) raw else JSONObject.NULL)
        .put("state",if (valid && coherent) entity.getJSONObject("states").optString(raw.toString(),raw.toString()) else JSONObject.NULL)
        .put("state_semantics",if (feedback) "feedback" else "command_only")
        .put("validation",entity.optString("validation")).put("updatedAt",sample?.opt("updatedAt") ?: JSONObject.NULL)
}

internal fun haControlGroup(action: String): String = when {
    action.startsWith("seat_") || "seat_heating" in action || "seat_ventilation" in action -> when {
        "rear_left" in action -> "rear_left_seat"
        "rear_right" in action -> "rear_right_seat"
        "passenger" in action -> "passenger_seat"
        else -> "driver_seat"
    }
    "steering_wheel" in action -> "steering_wheel"
    "mirror" in action -> "mirrors"
    "window" in action || "sunroof" in action -> "windows"
    action in setOf("door_lock","child_lock","child_lock_right") -> "locks"
    action.startsWith("hud_") || action in setOf("entertainment_screen","panorama_camera","camera_view_mode") -> "displays"
    "light" in action || action.startsWith("turn_signal") || action == "smart_high_beam" -> "lights"
    "suspension" in action || action in setOf("cloud_mode","road_preview","steering_assist","comfort_mode_2_level","drive_mode_high") -> "chassis"
    action in setOf("auto_hold","aeb_control","hdc_control","fcta_switch","itac_control","super_itac_control","sand_abs","brake_assist","lane_departure_low","lane_departure_high","fcw_level","vector_control","super_itac_mode") -> "driver_assistance"
    "charge" in action || action in setOf("wireless_charging","soc_keep_set","force_power_keep","energy_feedback","overseas_feedback") -> "charging"
    action.startsWith("fridge_") -> "fridge"
    action in setOf("front_trunk","trunk_control","elec_spoiler","electric_pedal","etc_switch","wiper_service") -> "body_equipment"
    action in setOf("engine_sound_sim","sound_effect_sim") -> "sound"
    action in setOf("ac_power","ac_control_mode","ac_cycle","ac_wind_level","ac_front_defrost","ac_temperature","ac_rear_defrost","ac_mode","air_purify","blow_mode_cycle","deputy_temp","dual_zone","fragrance_level","fragrance_type","main_temp","parking_vent","pm25","rear_auto","sync_zone","rear_wind_mode","rear_temp","rear_left_temp","rear_right_temp","deputy_wind","driver_wind_multi","deputy_wind_multi","rear_wind","rear_left_wind","rear_right_wind","ac_blow_mode_driver","ac_blow_mode_passenger","ac_blow_mode_rear_left","ac_blow_mode_rear_right","max_cool") -> "climate"
    else -> "equipment"
}

// These component IDs were published by the preceding device-discovery layout.
internal fun haRemovedControlComponents(device: String, entities: List<JSONObject>): JSONObject = JSONObject().apply {
    for (entity in entities) {
        val action = entity.getString("id")
        if (action == "ac_wind_level") put("skyinfo_${device}_control_$action",JSONObject().put("platform","number"))
        if (entity.getString("capability") == "button" && entity.getJSONArray("options").length() > 1) {
            val options = entity.getJSONArray("options")
            for (i in 0 until options.length()) put("skyinfo_${device}_control_${action}_${options.getJSONObject(i).getInt("value")}",JSONObject().put("platform","button"))
        }
    }
}

internal fun haControlDeviceDiscovery(definitions: List<HaControlDefinition>, version: String, removed: JSONObject = JSONObject()): JSONObject {
    require(definitions.isNotEmpty())
    val children = JSONArray()
    for ((_, group) in definitions.groupBy { it.group }) {
        val components = JSONObject()
        for (definition in group) {
            val payload = JSONObject(definition.payload.toString())
            payload.remove("device")
            payload.put("platform",definition.topic.split('/')[1])
            components.put(payload.getString("unique_id"),payload)
        }
        val child = JSONObject(group.first().payload.getJSONObject("device").getJSONObject("child_device").toString())
        children.put(child.put("components",components))
    }
    val parent = JSONObject(definitions.first().payload.getJSONObject("device").toString()).apply { remove("child_device") }
    return JSONObject().put("device",parent)
        .put("origin",JSONObject().put("name","SkyInfo").put("sw_version",version))
        .put("child_devices",children).put("components",removed)
}
