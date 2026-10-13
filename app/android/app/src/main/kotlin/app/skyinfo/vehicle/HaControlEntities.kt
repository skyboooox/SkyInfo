package app.skyinfo.vehicle

import org.json.JSONArray
import org.json.JSONObject

internal data class HaControlDefinition(val topic: String, val stateTopic: String, val payload: JSONObject)

internal fun haControlDefinitions(device: String, prefix: String, version: String, entity: JSONObject, commandTopic: String): List<HaControlDefinition> {
    val action = entity.getString("id")
    val options = entity.getJSONArray("options")
    val stateTopic = "skyinfo/ha/$device/control/$action/state"
    val kind = when(entity.getString("capability")) { "toggle" -> "switch"; "number" -> "number"; "select" -> "select"; else -> "button" }
    fun base(suffix: String, name: String): JSONObject = JSONObject()
        .put("name",name).put("unique_id","skyinfo_${device}_control_$suffix")
        .put("default_entity_id","$kind.skyinfo_${prefix}_$suffix")
        .put("command_topic",commandTopic).put("qos",0).put("retain",false)
        .put("enabled_by_default",true)
        .put("availability_topic",stateTopic)
        .put("availability_template","{{ 'online' if value_json.available else 'offline' }}")
        .put("json_attributes_topic",stateTopic)
        .put("device",JSONObject().put("identifiers",JSONArray().put("skyinfo_$device"))
            .put("name","SkyInfo $prefix").put("manufacturer","SkyInfo").put("model","BYD 车机").put("sw_version",version))
    fun command(value: Any) = JSONObject().put("action",action).put("value",value).toString()
    if (kind == "button") return (0 until options.length()).map { index ->
        val option = options.getJSONObject(index)
        val suffix = action+"_"+option.getInt("value")
        HaControlDefinition("homeassistant/button/skyinfo_$device/$suffix/config",stateTopic,
            base(suffix,entity.getString("name")+" · "+option.getString("label"))
                .put("payload_press",command(option.getInt("value"))))
    }
    val payload = base(action,entity.getString("name")).put("state_topic",stateTopic).put("optimistic",false)
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
            payload.put("options",JSONArray((0 until options.length()).map { options.getJSONObject(it).getString("label") }))
                .put("value_template","{{ value_json.state }}")
                .put("command_template","{\"action\":\"$action\",\"value\":{{ (${values}).get(value) | tojson }}}")
        }
        "number" -> payload.put("min",(0 until options.length()).minOf { options.getJSONObject(it).getInt("value") })
            .put("max",(0 until options.length()).maxOf { options.getJSONObject(it).getInt("value") }).put("step",1).put("mode","slider")
            .put("value_template","{{ value_json.raw }}")
            .put("command_template","{\"action\":\"$action\",\"value\":{{ value | float | tojson }}}")
            .also { if (entity.optString("unit").isNotEmpty()) it.put("unit_of_measurement",entity.getString("unit")) }
    }
    return listOf(HaControlDefinition("homeassistant/$kind/skyinfo_$device/$action/config",stateTopic,payload))
}

internal fun haControlState(entity: JSONObject, samples: Map<String, JSONObject>, enabled: Boolean): JSONObject {
    val read = entity.optString("readField")
    val sample = samples[read]
    val raw = sample?.opt("raw")
    val options = entity.getJSONArray("options")
    val expected = (0 until options.length()).map { options.getJSONObject(it).opt("expected") }
    val recognized = entity.optString("capability") == "button" || expected.any { it is Number && raw is Number && it.toDouble() == raw.toDouble() }
    val unitValid = entity.optString("unit") != "°C" || sample?.optString("unit") == "°C"
    val valid = recognized && unitValid && sample?.optString("quality") in listOf("available","unverified") && raw is Number && raw.toInt() != 65535
    val coherent = entity.getString("id") != "ac_temperature" || RuntimeCoordinator.list(entity.optJSONArray("feedbackFields")).all {
        samples[it]?.optString("quality") in listOf("available","unverified") && samples[it]?.opt("raw") == raw
    }
    return JSONObject().put("available",enabled && (entity.optString("capability") == "button" || valid && coherent))
        .put("raw",if (valid && coherent) raw else JSONObject.NULL)
        .put("state",if (valid && coherent) entity.getJSONObject("states").optString(raw.toString(),raw.toString()) else JSONObject.NULL)
        .put("validation",entity.optString("validation")).put("updatedAt",sample?.opt("updatedAt") ?: JSONObject.NULL)
}

internal fun haControlDeviceDiscovery(definitions: List<HaControlDefinition>, version: String): JSONObject {
    require(definitions.isNotEmpty())
    val components = JSONObject()
    for (definition in definitions) {
        val payload = JSONObject(definition.payload.toString())
        payload.remove("device")
        payload.put("platform",definition.topic.split('/')[1])
        components.put(payload.getString("unique_id"),payload)
    }
    return JSONObject().put("device",definitions.first().payload.getJSONObject("device"))
        .put("origin",JSONObject().put("name","SkyInfo").put("sw_version",version))
        .put("components",components)
}
