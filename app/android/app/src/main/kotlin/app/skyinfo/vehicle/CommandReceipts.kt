package app.skyinfo.vehicle

import org.json.JSONObject

class CommandReceipts(private val now: () -> Long = android.os.SystemClock::elapsedRealtime) {
    data class Entry(val config: JSONObject, val result: JSONObject, val deadline: Long)
    private val pending = linkedMapOf<String,Entry>()
    private fun target(config: JSONObject) = listOf("connection","haUrl","prefix","mqttHost","mqttPort","mqttTopic","mqttUser").joinToString("|") { config.optString(it) }
    fun add(config: JSONObject, result: JSONObject) {
        pending[result.getString("id")] = Entry(JSONObject(config.toString()),JSONObject(result.toString()),now()+120000)
        while (pending.size > 16) pending.remove(pending.keys.first())
    }
    fun next(config: JSONObject): Entry? {
        pending.entries.removeAll { it.value.deadline < now() || target(it.value.config) != target(config) }
        return pending.values.firstOrNull()
    }
    fun delivered(id: String) { pending.remove(id) }
    fun clear() { pending.clear() }
    val size: Int get() = pending.size
}
