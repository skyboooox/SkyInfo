package app.skyinfo.vehicle

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

object EntityCatalog {
    private var cachedControls: List<JSONObject>? = null
    @Synchronized fun controls(context: Context): List<JSONObject> = cachedControls ?: JSONArray(context.assets.open("entities.json").bufferedReader().use { it.readText() }).let { rows ->
        (0 until rows.length()).map(rows::getJSONObject)
    }.also { cachedControls = it }
    fun fields(context: Context): Map<String, JSONObject> {
        val catalog = JSONArray(context.assets.open("catalog.json").bufferedReader().use { it.readText() })
        val result = (0 until catalog.length()).associate { index -> catalog.getJSONObject(index).let { it.getString("id") to it } }.toMutableMap()
        for (entity in controls(context)) for (id in RuntimeCoordinator.list(entity.optJSONArray("feedbackFields"))) {
            if (id !in result) result[id] = JSONObject().put("id",id).put("name",entity.getString("name"))
                .put("category",entity.getString("category")).put("encoding",NativeStrings.text_d7f8312638).put("unit",entity.optString("unit"))
                .put("displayAllowed",false).put("definitionVersion",1)
                .also { if (entity.optString("unit") == "°C") it.put("unitField","1000/5/1077936167") }
        }
        return result
    }
    fun demand(context: Context, ids: Collection<String>): Set<String> {
        val controls = controls(context).associateBy { "control."+it.getString("id") }
        return ids.flatMap { id -> controls[id]?.let { RuntimeCoordinator.list(it.optJSONArray("feedbackFields")) } ?: listOf(id) }.toSet()
    }
}
