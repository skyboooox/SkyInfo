package app.skyinfo.vehicle

import org.json.JSONObject
import java.util.Locale

internal data class StripModule(val icon: String, val text: String, val unit: String)
internal data class StripGroup(val alignment: String, val modules: List<StripModule>)

/** Text follows the reading/configuration update; layout still uses the current viewport and font. */
internal fun prepareStripGroups(config: JSONObject, fields: Map<String,JSONObject>, samples: Map<String,JSONObject>): List<StripGroup> {
    val modules = config.optJSONArray("overlays") ?: return emptyList()
    val grouped = linkedMapOf<String,MutableList<StripModule>>()
    for (index in 0 until modules.length()) {
        val module = modules.getJSONObject(index)
        val id = module.optString("field")
        val field = fields[id]
        val sample = samples[id]?.takeIf { field != null }
        val raw = sample?.opt("value")
        val text = if (sample?.optString("quality") !in listOf("available","unverified") || raw == null) "—"
            else if (raw is Number) String.format(Locale.ROOT,"%.${module.optInt("digits",1).coerceIn(0,4)}f",raw.toDouble()) else raw.toString()
        val custom = module.optString("unit")
        val unit = if (module.optBoolean("unitAuto")) sample?.optString("unit") ?: field?.optString("unit") ?: ""
            else if (field?.has("unitField") == true && (custom == NativeStrings.raw_value || custom == field.optString("unit")))
                sample?.optString("unit")?.takeIf(String::isNotEmpty) ?: NativeStrings.raw_value else custom
        grouped.getOrPut(module.optString("alignment")) { mutableListOf() }.add(StripModule(module.optString("icon"),text,unit))
    }
    return listOf("left","center","right").mapNotNull { alignment -> grouped[alignment]?.let { StripGroup(alignment,it) } }
}
