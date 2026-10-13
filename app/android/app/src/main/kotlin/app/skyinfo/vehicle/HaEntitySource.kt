package app.skyinfo.vehicle

import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

internal class HaEntitySource(private val session: HaSession, private val execute: (() -> Unit) -> Unit,
    private val schedule: (Long, () -> Unit) -> ScheduledFuture<*>, private val changed: (Boolean) -> Unit,
    private val received: (String, JSONObject) -> Unit, private val entityUpdated: (JSONObject) -> Unit = {}) {
    private var connection = ""
    private var enabled = false
    private var connected = false
    private var epoch = 0L
    private var eventId: Int? = null
    private var loadingSnapshot = false
    private val snapshotEvents = linkedMapOf<String, JSONObject?>()
    private var fieldCache: Map<String, JSONObject>? = null
    private val descriptorMetadata = mutableMapOf<String, JSONObject>()
    private val states = linkedMapOf<String, JSONObject>()
    private var services = JSONObject()
    private var areas = JSONObject()
    private var devices = JSONObject()
    private var registry = JSONObject()
    private var demand = emptySet<String>()
    private val pending = mutableMapOf<String, Pending>()
    private val attributeChanges = mutableMapOf<String, Pair<String, Long?>>()
    var state = "disabled"
        private set
    private data class Pending(val binding: HaBinding, val function: JSONObject, val value: Any?, val issued: Long,
        val callback: (JSONObject) -> Unit, var accepted: Boolean = false, var timeout: ScheduledFuture<*>? = null)
    init {
        session.inboundConnected = { execute { if (enabled) start() } }
        session.inboundDisconnected = { execute { disconnect() } }
        session.inboundEvent = { message -> execute {
            if (enabled && message.optInt("id") == eventId && connected) {
                val data = message.optJSONObject("event")?.optJSONObject("data") ?: return@execute
                val entity = data.optString("entity_id")
                val before = states[entity]
                val after = data.optJSONObject("new_state")
                if (loadingSnapshot) snapshotEvents[entity] = after
                if (after == null) states.remove(entity) else states[entity] = after
                val metadataChanged = before == null || after == null || HaEntityModel.metadataSignature(before) != HaEntityModel.metadataSignature(after)
                emitEntity(entity); finishFeedback(entity)
                if (metadataChanged) { fieldCache = null; descriptorMetadata.remove(entity) }
                else entityDescriptor(entity)?.let(entityUpdated)
                changed(metadataChanged)
            }
        } }
    }
    fun configure(config: JSONObject, active: Boolean, fields: Set<String>) {
        val uuid = config.optString("haConnectionId")
        val next = active && config.optBoolean("haImportEnabled")
        val connectionChanged = uuid != connection
        if (connectionChanged) { eventId?.let { session.request(JSONObject().put("type","unsubscribe_events").put("subscription",it)) {} }; eventId = null; disconnect(); states.clear(); fieldCache = null; descriptorMetadata.clear(); services = JSONObject(); areas = JSONObject(); devices = JSONObject(); registry = JSONObject(); connection = uuid }
        val added = fields - demand
        demand = fields.filter { HaBinding.parse(it)?.connection == connection }.toSet()
        if (enabled != next) { enabled = next; if (!next) { disconnect(); eventId?.let { session.request(JSONObject().put("type","unsubscribe_events").put("subscription",it)) {} }; eventId = null; state = "disabled" }
            else if (session.sessionState == NativeStrings.text_09f11a24a6) start() }
        else if (next && connectionChanged && session.sessionState == NativeStrings.text_09f11a24a6) start()
        if (enabled && !connected) state = if (session.sessionState == NativeStrings.text_dda97ab7aa) "auth_failed" else "disconnected"
        for (id in added) HaBinding.parse(id)?.takeIf { it.connection == connection }?.let { received(id, sample(it)) }
    }
    fun start() {
        if (!enabled) return
        connected = true; state = "loading"; epoch++; eventId = null; loadingSnapshot = true; snapshotEvents.clear()
        val captured = epoch
        fun request(type: String, callback: (JSONObject) -> Unit) = session.request(JSONObject().put("type",type)) { r -> execute { if (captured == epoch && enabled) callback(r) } }
        eventId = session.request(JSONObject().put("type","subscribe_events").put("event_type","state_changed")) { r -> execute {
            if (captured != epoch || !enabled) return@execute
            if (!r.optBoolean("success")) { disconnect(); state = "permission"; changed(true) }
        } }
        request("get_states") { result ->
            if (!result.optBoolean("success")) { disconnect(); state = "permission"; changed(true); return@request }
            val snapshot = result.optJSONArray("result") ?: JSONArray()
            val fresh = linkedMapOf<String,JSONObject>()
            for (i in 0 until snapshot.length()) snapshot.optJSONObject(i)?.let { s ->
                val id = s.optString("entity_id")
                fresh[id] = s
            }
            snapshotEvents.forEach { (id, value) -> if (value == null) fresh.remove(id) else fresh[id] = value }
            snapshotEvents.clear(); loadingSnapshot = false
            states.clear(); states.putAll(fresh); fieldCache = null; descriptorMetadata.clear(); state = "connected"
            demand.forEach { id -> HaBinding.parse(id)?.let { received(id,sample(it)) } }
            changed(true)
        }
        request("get_services") { r -> services = r.optJSONObject("result") ?: JSONObject(); descriptorMetadata.clear(); changed(true) }
        for ((type,key) in listOf("config/area_registry/list" to "area_id", "config/device_registry/list" to "id", "config/entity_registry/list" to "entity_id")) {
            request(type) { r -> val out = JSONObject(); val list = r.optJSONArray("result") ?: JSONArray()
                for(i in 0 until list.length()) list.optJSONObject(i)?.let { out.put(it.optString(key),it) }
                when(key) { "area_id" -> areas = out; "id" -> devices = out; else -> registry = out }; descriptorMetadata.clear(); changed(true)
            }
        }
        changed(true)
    }
    fun disconnect() {
        loadingSnapshot = false; snapshotEvents.clear(); attributeChanges.clear()
        val wasConnected = connected; connected = false; epoch++
        if (wasConnected) { demand.forEach { id -> HaBinding.parse(id)?.let { received(id,sample(it)) } } }
        pending.keys.toList().forEach { finish(it, "disconnected") }
        state = when {
            !enabled -> "disabled"
            session.sessionState == NativeStrings.text_dda97ab7aa -> "auth_failed"
            else -> "disconnected"
        }
        changed(true)
    }
    private fun emitEntity(entity: String) = demand.filter { HaBinding.parse(it)?.entity == entity }.forEach { id ->
        val binding = HaBinding.parse(id)!!; received(id,sample(binding))
    }
    private fun sample(binding: HaBinding): JSONObject {
        val out = HaEntityModel.sample(binding,states[binding.entity],connected,epoch)
        if (binding.attribute != null) {
            var at: Long? = null
            if (out.optString("quality") == "available") {
                val value = out.opt("value")?.toString() ?: "null"
                val previous = attributeChanges[binding.id]
                at = if (previous != null && previous.first != value) out.optLong("updatedAt") else previous?.second
                attributeChanges[binding.id] = value to at
            }
            out.put("changedAt",at ?: JSONObject.NULL)
        }
        return out
    }
    fun fields(): Map<String,JSONObject> {
        fieldCache?.let { return it }
        val out = linkedMapOf<String,JSONObject>()
        for((id,s) in states) {
            val binding = HaBinding(connection,id); out[binding.id] = HaEntityModel.field(binding,s)
            val a = s.optJSONObject("attributes") ?: JSONObject()
            a.keys().asSequence().filter { a.opt(it) is Number || a.opt(it) is Boolean || a.opt(it) is String }.forEach { attr ->
                val b = HaBinding(connection,id,attr); if(HaBinding.parse(b.id) != null) out[b.id] = HaEntityModel.field(b,s)
            }
        }
        fieldCache = out
        return out
    }
    fun directory(): JSONObject {
        val entities = JSONArray()
        for (id in states.keys) entityDescriptor(id)?.let(entities::put)
        return JSONObject().put("state",state).put("entities",entities).put("fields",JSONObject(fields() as Map<*,*>))
    }
    private fun entityDescriptor(id: String): JSONObject? {
        val s = states[id] ?: return null
        val metadata = descriptorMetadata.getOrPut(id) {
            val entry = registry.optJSONObject(id); val deviceId = entry?.haText("device_id") ?: ""
            val device = devices.optJSONObject(deviceId)
            val areaId = entry?.haText("area_id")?.takeIf { it.isNotEmpty() } ?: device?.haText("area_id") ?: ""
            val binding = HaBinding(connection,id)
            JSONObject().put("id",binding.id).put("entityId",id).put("name",s.optJSONObject("attributes")?.haText("friendly_name")?.takeIf { it.isNotEmpty() } ?: id)
                .put("domain",id.substringBefore('.')).put("deviceId",deviceId).put("device",device?.haText("name_by_user")?.takeIf { it.isNotEmpty() } ?: device?.haText("name") ?: "")
                .put("area",areas.optJSONObject(areaId)?.haText("name") ?: "")
                .put("functions", HaEntityModel.functions(s,services)).put("field",HaEntityModel.field(binding,s))
        }
        return JSONObject().apply {
            for(key in metadata.keys()) put(key,metadata.get(key))
            put("state",s.opt("state")).put("attributes",s.optJSONObject("attributes") ?: JSONObject())
        }
    }
    fun control(id: String, key: String, value: Any?, confirmed: Boolean, added: Boolean, callback: (JSONObject) -> Unit) {
        val binding = HaBinding.parse(id)
        if(!enabled || !connected || state != "connected") { callback(JSONObject().put("status","disconnected")); return }
        if(binding == null || binding.connection != connection || binding.attribute != null || !added) { callback(JSONObject().put("status","not_added")); return }
        if(pending.containsKey(binding.entity)) { callback(JSONObject().put("status","busy")); return }
        val entity = states[binding.entity]
        if(entity == null || !HaEntityModel.availableForAction(entity)) { callback(JSONObject().put("status","unavailable")); return }
        val (request,function) = try { HaEntityModel.service(entity,services,key,value) } catch (_: Throwable) { callback(JSONObject().put("status","invalid_value")); return }
        if(function.optBoolean("confirmation") && !confirmed) { callback(JSONObject().put("status","confirmation_required")); return }
        val command = Pending(binding,function,value,session.currentTime(),callback)
        pending[binding.entity] = command
        command.timeout = schedule(12000) { finish(binding.entity, "timeout_unconfirmed") }
        session.request(request) { r -> execute {
            if (pending[binding.entity] !== command) return@execute
            if (!r.optBoolean("success")) finish(binding.entity, when(r.optJSONObject("error")?.optString("code")) { "unauthorized" -> "permission"; "disconnected" -> "disconnected"; "timeout" -> "timeout_unconfirmed"; else -> "error" })
            else if(!function.has("expected")) finish(binding.entity,"accepted_unconfirmed")
            else { command.accepted = true; finishFeedback(binding.entity) }
        } }
    }
    private fun finishFeedback(entity: String) {
        val p = pending[entity] ?: return
        if(!p.accepted) return
        val s = states[entity] ?: return
        val updated = runCatching { java.time.Instant.parse(s.getString("last_updated")).toEpochMilli() }.getOrDefault(0)
        if(updated < p.issued || s.optString("state") in setOf("unknown","unavailable")) return
        val expected = p.function.getString("expected")
        val actual = if(expected == "state") s.optString("state") else s.optJSONObject("attributes")?.opt(expected)
        val target = if(p.function.getString("kind") == "toggle") if(p.value == true) "on" else "off" else p.value
        val matches = if(target is Number) actual.toString().toDoubleOrNull()?.let { kotlin.math.abs(it-target.toDouble()) <= 1e-6 } == true else actual.toString() == target.toString()
        if(matches) finish(entity,"confirmed")
    }
    private fun finish(entity: String, status: String) { pending.remove(entity)?.let { it.timeout?.cancel(false); it.callback(JSONObject().put("status",status)) } }
}
