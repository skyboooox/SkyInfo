package app.skyinfo.vehicle

import org.json.JSONArray
import org.json.JSONObject

fun haNumericField(field: JSONObject): Boolean = field.getString("id").let {
    isDerived(it) || it.contains("/5/") || it.contains("/7/")
}

fun haReading(sample: JSONObject, field: JSONObject): JSONObject {
    val result = JSONObject(sample.toString())
    val value = sample.opt("value")
    val valid = sample.optString("quality") in listOf("available","unverified") && value != null && value != JSONObject.NULL &&
        (!haNumericField(field) || value is Number && value.toDouble().isFinite())
    result.put("value",if (valid) value else JSONObject.NULL)
    if (!valid && sample.optString("quality") in listOf("available","unverified")) result.put("quality","invalid")
    return result
}

fun haSensorDiscovery(device: String, prefix: String, version: String, field: JSONObject, entity: String): JSONObject {
    val key = field.getString("entityKey")
    val topic = "skyinfo/ha/$device/$key/state"
    val unit = field.optString("unit")
    val numeric = unit.isNotEmpty() && haNumericField(field) && field.optString("encoding") !in listOf(NativeStrings.text_d7f8312638,NativeStrings.text_f1926e9b33)
    return JSONObject().put("name",field.getString("name")).put("unique_id","skyinfo_${device}_$key")
        .put("default_entity_id",entity).put("state_topic",topic).put("value_template","{{ value_json.value }}")
        .put("json_attributes_topic",topic).put("qos",1)
        .put("availability_topic",topic)
        .put("availability_template","{{ 'online' if value_json.quality in ['available','unverified'] and value_json.value is not none else 'offline' }}")
        .put("device",JSONObject().put("identifiers",JSONArray().put("skyinfo_$device"))
            .put("name","SkyInfo $prefix").put("manufacturer","SkyInfo").put("model",NativeStrings.text_1d1ae1792d).put("sw_version",version))
        .also { definition ->
            if (unit.isNotEmpty()) definition.put("unit_of_measurement",unit)
            if (numeric) {
                definition.put("state_class","measurement")
                definition.put("suggested_display_precision",if (unit in listOf("rpm","mV","%","°C","°F")) 0 else 2)
                val deviceClass = when (unit) {
                    "V","mV" -> "voltage"
                    "A","mA" -> "current"
                    "W","kW" -> "power"
                    "°C","°F" -> "temperature"
                    else -> null
                }
                if (deviceClass != null) definition.put("device_class",deviceClass)
            }
        }
}
