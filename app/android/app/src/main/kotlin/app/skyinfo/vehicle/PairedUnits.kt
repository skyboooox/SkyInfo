package app.skyinfo.vehicle

import org.json.JSONObject

internal fun expandDependencies(ids: Set<String>, fields: Map<String, JSONObject>): Set<String> {
    val all = ids.filter { it in fields || HaBinding.parse(it) != null }.toMutableSet()
    val pending = java.util.ArrayDeque(all)
    while (pending.isNotEmpty()) {
        val field = fields[pending.removeFirst()] ?: continue
        val dependencies = RuntimeCoordinator.list(field.optJSONArray("derivedInputs")) + listOf(field.optString("unitField"))
        dependencies.filter { it in fields }.forEach { if (all.add(it)) pending.add(it) }
    }
    return all
}

internal fun resolvePairedUnit(id: String, fresh: JSONObject, samples: Map<String, JSONObject>, fields: Map<String, JSONObject>) {
    val field = fields.getValue(id)
    val dependency = field.optString("unitField")
    if (dependency.isEmpty() || fresh.optString("quality") !in listOf("available", "unverified")) return
    val raw = fresh.opt("raw") as? Number ?: return
    val source = samples[dependency]
    val code = if (source?.optString("quality") in listOf("available", "unverified")) (source?.opt("value") as? Number)?.toInt() else null
    fresh.put("value",raw).put("unit","")
    if (dependency == "1000/5/1077936167" && code in listOf(0,1)) {
        fresh.put("value",if (code == 0) (raw.toDouble()-32)*5/9 else raw).put("unit","°C").put("quality","available")
    } else if (dependency == "1007/5/1246761027" && code != null && code in 1..4) {
        fresh.put("value",raw.toDouble()).put("unit",mapOf(1 to "L/100km",2 to "km/L",3 to "MPG",4 to "L/h").getValue(code)).put("quality","available")
    } else fresh.put("quality","unverified")
    fresh.put("unitCode",code ?: JSONObject.NULL)
    fresh.put("unitReceivedAt",source?.opt("updatedAt") ?: JSONObject.NULL)
}
