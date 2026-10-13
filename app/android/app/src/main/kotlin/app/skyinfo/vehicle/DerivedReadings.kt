package app.skyinfo.vehicle

import org.json.JSONObject

internal const val BATTERY_POWER = "derived.battery_power"
internal const val BATTERY_VOLTAGE = "1009/5/1145045000"
internal const val BATTERY_CURRENT = "1039/5/677380120"
internal fun isDerived(id: String) = id.startsWith("derived.")

internal fun batteryPower(samples: Map<String, JSONObject>, epoch: Long): JSONObject {
    val inputs = JSONObject()
    val result = JSONObject().put("source", BATTERY_POWER).put("transport", "derived")
        .put("unit", "kW").put("definitionVersion", 2).put("inputs", inputs)
    val sources = listOf(BATTERY_VOLTAGE, BATTERY_CURRENT).map { id ->
        samples[id]?.also { inputs.put(id, JSONObject(it.toString())) }
    }
    result.put("receivedAt", sources.filterNotNull().maxOfOrNull { it.optLong("receivedAt") } ?: System.currentTimeMillis())
    val failed = sources.firstOrNull { it == null || it.optString("quality") !in listOf("available", "unverified") ||
        it.optLong("sourceEpoch", -1) != epoch || it.opt("value") !is Number }
    if (sources.any { it == null } || failed != null) {
        return result.put("quality", failed?.optString("quality")?.takeIf { it !in listOf("available", "unverified") } ?: "disconnected")
    }
    val voltage = (sources[0]!!.get("value") as Number).toDouble()
    val current = (sources[1]!!.get("value") as Number).toDouble()
    val currentSample = sources[1]!!
    val currentRaw = currentSample.opt("raw") as? Number
    if (!voltage.isFinite() || voltage <= 0 || !current.isFinite() || voltage == 65535.0 ||
        currentSample.optString("unit") != "A" || currentSample.optInt("definitionVersion", 1) < 2 ||
        currentRaw == null || invalidGbCurrentRaw(currentRaw)) {
        return result.put("quality", "invalid")
    }
    val power = voltage * current / 1000
    return if (power.isFinite()) result.put("value", if (power == 0.0) 0.0 else power).put("quality", "available")
    else result.put("quality", "invalid")
}
