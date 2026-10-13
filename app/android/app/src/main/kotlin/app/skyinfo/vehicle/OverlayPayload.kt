package app.skyinfo.vehicle

import org.json.JSONObject

internal fun overlayFieldIds(config: JSONObject): Set<String> {
    if (!config.optBoolean("overlayEnabled")) return emptySet()
    val modules = config.optJSONArray("overlays") ?: return emptySet()
    return (0 until modules.length()).map { modules.getJSONObject(it).optString("field") }.filter(String::isNotEmpty).toSet()
}

internal fun overlayRequest(config: JSONObject, samples: Map<String, JSONObject>): JSONObject {
    val ids = overlayFieldIds(config)
    val safe = JSONObject()
    for (key in listOf("overlayEnabled","overlays","theme","overlayFont","overlayOpacity","overlayOffset","overlayLeft","overlayRight","overlayX","overlayY")) {
        if (config.has(key)) safe.put(key, config.get(key))
    }
    val definitions = config.optJSONObject("haFields") ?: JSONObject()
    val selected = JSONObject()
    ids.filter { HaBinding.parse(it) != null && definitions.has(it) }.forEach { selected.put(it,definitions.get(it)) }
    safe.put("haFields",selected)
    return JSONObject().put("config",safe).put("samples",JSONObject(samples.filterKeys { it in ids } as Map<*,*>))
}
