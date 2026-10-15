package app.skyinfo.vehicle

import org.json.JSONObject

internal fun stampSampleTimes(fresh: JSONObject, old: JSONObject?, epoch: Long) {
    if (fresh.has("value") && !fresh.isNull("value")) {
        val at = fresh.optLong("receivedAt", System.currentTimeMillis())
        fresh.put("updatedAt", at)
        val same = old != null && old.optLong("sourceEpoch", -1) == epoch &&
            old.has("value") && old.opt("value") == fresh.opt("value")
        fresh.put("changedAt", if (same && old?.opt("unit") == fresh.opt("unit")) old!!.optLong("changedAt", old.optLong("updatedAt", at)) else fresh.optLong("interpretationChangedAt",at))
    } else if (old != null) {
        for (key in listOf("value", "updatedAt", "changedAt", "definitionVersion", "unit", "unitCode", "unitReceivedAt", "stateLabel"))
            if (old.has(key)) fresh.put(key, old.get(key))
        if (!fresh.has("raw") && old.has("raw")) fresh.put("raw", old.get("raw"))
    }
    if (fresh.optString("source") == GNSS_ALTITUDE && fresh.optString("quality") != "available") fresh.remove("value")
    fresh.put("sourceEpoch", epoch)
}

internal fun migrateConvertedUnits(config: JSONObject, fields: Map<String, JSONObject>): Boolean {
    var changed = false
    config.optJSONArray("tiles")?.let { tiles ->
        for (i in 0 until tiles.length()) tiles.getJSONObject(i).optJSONObject("units")?.let { units ->
            units.keys().asSequence().toList().forEach { id ->
                if ((fields[id]?.has("valueOffset") == true || fields[id]?.has("unitField") == true || fields[id]?.optString("unit")?.isNotEmpty() == true) && (units.optString(id) == NativeStrings.raw_value || units.optString(id) in RuntimeCoordinator.list(fields[id]?.optJSONArray("legacyUnits")))) {
                    units.remove(id); changed = true
                }
            }
        }
    }
    config.optJSONArray("tiles")?.let { tiles ->
        for (i in 0 until tiles.length()) {
            val tile = tiles.getJSONObject(i)
            val selected = RuntimeCoordinator.list(tile.optJSONArray("fields"))
            for (id in selected) {
                val field = fields[id] ?: continue
                val oldNames = RuntimeCoordinator.list(field.optJSONArray("legacyNames"))
                if (selected.size == 1 && tile.optString("title") in oldNames) {
                    tile.put("title",field.getString("name")); changed = true
                }
                tile.optJSONObject("labels")?.let { labels ->
                    if (labels.optString(id) in oldNames) { labels.put(id,field.getString("name")); changed = true }
                }
            }
        }
    }
    config.optJSONArray("overlays")?.let { modules ->
        for (i in 0 until modules.length()) {
            val module = modules.getJSONObject(i)
            val field = fields[module.optString("field")]
            if ((field?.has("valueOffset") == true || field?.has("unitField") == true || field?.optString("unit")?.isNotEmpty() == true) && field?.optString("unit")?.isNotEmpty() == true && (module.optString("unit") == NativeStrings.raw_value || module.optString("unit") in RuntimeCoordinator.list(field.optJSONArray("legacyUnits")))) {
                module.put("unit", field.getString("unit")); changed = true
            }
        }
    }
    return changed
}
