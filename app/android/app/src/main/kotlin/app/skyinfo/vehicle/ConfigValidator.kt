package app.skyinfo.vehicle

import org.json.JSONArray
import org.json.JSONObject

object ConfigValidator {
    private val tileKeys = setOf("id", "title", "kind", "fields", "columns", "rows", "time", "icons", "units", "labels", "digits", "historyMinutes", "minimum", "maximum", "column", "row", "icon", "fontSize", "glanceColumns", "rowHeight", "showTitle", "showUnits", "showIcon", "showDataIcons", "hiddenControls")
    private val keys = setOf("adbEnabled", "adbHost", "adbPort", "adbMode", "deviceId", "mqttTransport", "haBirthTopic", "haBirthPayload", "insecureAcknowledgements", "localHistoryPolicyVersion", "schema", "tiles", "overlays", "uploaded", "theme", "dashboardSize", "connection", "haUrl", "prefix", "mqttHost", "mqttPort", "mqttTopic", "mqttUser", "reduceMotion", "autoStart", "collect", "overlayEnabled", "publishEnabled", "fallbackPolling", "overlayFont", "overlayOpacity", "overlayOffset", "overlayLeft", "overlayRight", "overlayX", "overlayY", "localHistory", "retainHistory", "localHistoryMinutes", "mqttProtocol", "mqttState", "entityMappings", "haControlEnabled", "mqttControlEnabled", "haConnectionId", "haImportEnabled", "haFields")
    fun validate(input: JSONObject, fields: Map<String, JSONObject>): JSONObject {
        AdbEndpoint.from(input)
        require(input.optInt("schema", 1) in 1..2)
        val config = JSONObject(input.toString()); config.keys().asSequence().filter { it !in keys }.toList().forEach(config::remove)
        config.put("schema", 2)
        migrateLocalHistory(config)
        for (key in listOf("haControlEnabled", "mqttControlEnabled", "publishEnabled", "collect", "overlayEnabled", "autoStart", "localHistory", "retainHistory")) {
            if (config.has(key)) require(config.get(key) is Boolean) { "invalid_boolean:$key" }
        }
        require(config.optString("connection", "ha") in listOf("ha", "mqtt"))
        require(config.optString("theme", "system") in listOf("system", "light", "dark"))
        require(config.optString("dashboardSize", "standard") in listOf("standard", "enlarged"))
        require(Regex("^[a-z0-9_]{1,48}$").matches(config.optString("prefix", "skyinfo")))
        require(Regex("^[a-zA-Z0-9-]{1,64}$").matches(config.optString("haConnectionId","unconfigured")))
        if (config.has("haImportEnabled")) require(config.get("haImportEnabled") is Boolean)
        fun ha(id: String) = HaBinding.parse(id) != null
        val saved = input.optJSONObject("haFields") ?: JSONObject()
        require(saved.length() <= 512)
        saved.keys().asSequence().forEach { id -> require(ha(id)); val f = saved.getJSONObject(id); require(f.optString("id") == id && f.optString("unit").length <= 16 && f.optString("name").length <= 256) }
        val tiles = config.optJSONArray("tiles") ?: JSONArray()
        require(tiles.length() <= 64)
        val ids = mutableSetOf<String>()
        for (i in 0 until tiles.length()) {
            val original = tiles.getJSONObject(i)
            val tile = JSONObject(); original.keys().asSequence().filter { it in tileKeys }.forEach { tile.put(it, original.get(it)) }; tiles.put(i, tile)
            require(ids.add(tile.getString("id")) && tile.getString("id").length <= 64)
            require(tile.getString("title").length <= 64)
            val selected = RuntimeCoordinator.list(tile.optJSONArray("fields")); require(selected.isNotEmpty() && selected.size <= 128 && selected.distinct().size == selected.size)
            require(selected.all { ha(it) || fields[it]?.optBoolean("displayAllowed") == true ||
                it.startsWith("control.") && VehicleControls.definitions.any { d -> it == "control."+d.id } })
            if (tile.has("icon") && !tile.isNull("icon")) require(Regex("^[a-z0-9-]{1,64}$").matches(tile.getString("icon")))
            if (tile.has("fontSize") && !tile.isNull("fontSize")) require(tile.getDouble("fontSize") in listOf(24.0,32.0,48.0,56.0,72.0,96.0))
            require(tile.optInt("glanceColumns",2) in 2..3 && tile.optDouble("rowHeight",84.0) in listOf(64.0,84.0,104.0))
            if (tile.has("hiddenControls")) { val hidden = tile.getJSONArray("hiddenControls"); require(hidden.length() <= 128); for (h in 0 until hidden.length()) require((0 until tile.getJSONArray("fields").length()).any { tile.getJSONArray("fields").getString(it) == hidden.getString(h) }) }
            for (key in listOf("showTitle", "showUnits", "showIcon", "showDataIcons")) if (tile.has(key)) require(tile.get(key) is Boolean)
            val kind = tile.getString("kind")
            val shapes = when (kind) {
                "number", "state", "text" -> setOf(1 to 1, 1 to 2, 2 to 1, 2 to 2)
                "pair" -> setOf(1 to 2, 2 to 1, 2 to 2, 4 to 2)
                "list", "glance", "availability", "entities", "device" -> setOf(2 to 2, 2 to 4, 4 to 2)
                "entity", "toggle", "select", "action", "numberControl" -> setOf(2 to 1, 2 to 2)
                "range", "timeline" -> setOf(2 to 1, 2 to 2, 4 to 2)
                "gauge", "trend", "comparison" -> setOf(2 to 2, 4 to 2)
                else -> error("Unknown widget")
            }
            require((tile.optInt("columns", 2) to tile.optInt("rows", 2)) in shapes)
            require(tile.optString("time", "none") in listOf("none", "updated", "changed"))
            require(tile.optInt("digits", 1) in 0..4 && tile.optInt("historyMinutes", 30) in 1..1440)
            for (map in listOf("icons", "units", "labels")) tile.optJSONObject(map)?.let { values ->
                require(values.keys().asSequence().all { it in selected && values.getString(it).length <= if (map == "units") 16 else 64 })
                if (map == "icons") require(values.keys().asSequence().all { Regex("^[a-z0-9-]+$").matches(values.getString(it)) })
            }
            if (selected.any { it.startsWith("control.") }) require(kind in listOf("entity", "toggle", "select", "action", "numberControl", "entities", "device"))
            if (kind in listOf("toggle", "select", "action", "numberControl")) {
                val capability = when(kind) { "action" -> "button"; "numberControl" -> "number"; else -> kind }
                require(selected.all { (ha(it) || it.startsWith("control.") && VehicleControls.entityCapability(VehicleControls.definition(it.removePrefix("control."))) == capability) })
            }
            if (kind == "pair") require(selected.size == 2)
            if (kind !in listOf("pair", "list", "glance", "availability", "comparison", "entities", "device")) require(selected.size == 1)
            if (kind == "range" || kind == "gauge" || (tile.has("minimum") && !tile.isNull("minimum")) || (tile.has("maximum") && !tile.isNull("maximum"))) require(tile.getDouble("minimum").isFinite() && tile.getDouble("maximum").isFinite() && tile.getDouble("maximum") > tile.getDouble("minimum"))
            if (kind == "comparison") require(
                selected.map { (fields[it] ?: saved.optJSONObject(it) ?: error("Unknown field")).let { field -> field.optString("unit") to field.optString("encoding") } }.let { it.all { pair -> pair.first.isNotEmpty() } && it.distinct().size == 1 } ||
                selected.toSet() == setOf("1014/5/1148190752", "1014/5/1148190736")
            )
            for (coordinate in listOf("column", "row")) if (tile.has(coordinate) && !tile.isNull(coordinate)) require(tile.getInt(coordinate) in 0..512)
        }
        val overlays = config.optJSONArray("overlays") ?: JSONArray(); require(overlays.length() <= 24)
        val moduleIds = mutableSetOf<String>()
        for (i in 0 until overlays.length()) {
            val original = overlays.getJSONObject(i)
            val m = JSONObject(); original.keys().asSequence().filter { it in setOf("id", "field", "icon", "unit", "alignment", "digits", "unitAuto") }.forEach { m.put(it, original.get(it)) }; overlays.put(i, m)
            require(moduleIds.add(m.getString("id")) && (ha(m.getString("field")) || fields[m.getString("field")]?.optBoolean("displayAllowed") == true))
            require(m.optString("icon").isEmpty() || Regex("^[a-z0-9-]{1,64}$").matches(m.getString("icon")))
            require(m.getString("unit").length <= 16 && m.getString("alignment") in listOf("left", "center", "right"))
            require(m.optInt("digits",1) in 0..4)
        }
        val uploaded = RuntimeCoordinator.list(config.optJSONArray("uploaded")); require(uploaded.size <= fields.size && uploaded.all(fields::containsKey))
        require(config.optDouble("overlayLeft",128.0) in 0.0..640.0 && config.optDouble("overlayRight",320.0) in 0.0..640.0)
        for (key in listOf("overlayX","overlayY")) if (config.has(key) && !config.isNull(key)) {
            val value = config.getDouble(key); require(value.isFinite() && value in 0.0..1.0)
        }
        require(config.optDouble("overlayFont",18.0) in listOf(14.0,16.0,18.0,20.0,24.0))
        require(config.optDouble("overlayOpacity",0.8) in 0.1..0.8 && config.optDouble("overlayOffset",0.0) in 0.0..120.0)
        require(config.optInt("localHistoryMinutes",30) in 1..1440 && config.optString("mqttProtocol","5") in listOf("5","3.1.1"))
        require(config.optInt("mqttPort",8883) in 1..65535)
        val host = config.optString("mqttHost"); require(host.length <= 253 && !host.contains('/') && !host.contains('@'))
        val topic = config.optString("mqttTopic","skyinfo/device"); require(topic.isNotBlank() && topic.length <= 256 && !topic.contains('#') && !topic.contains('+'))
        val url = config.optString("haUrl")
        if (url.isNotBlank()) HaEndpoint.validate(url)
        require(config.optString("mqttTransport", "tls") in setOf("tls", "tcp"))
        val birthTopic = config.optString("haBirthTopic", "homeassistant/status")
        require(birthTopic.length <= 256 && !birthTopic.contains('#') && !birthTopic.contains('+') && !birthTopic.contains('\u0000'))
        require(birthTopic.isEmpty() || config.optString("haBirthPayload", "online").isNotEmpty())
        require(config.optString("haBirthPayload", "online").length <= 256)
        config.optJSONArray("insecureAcknowledgements")?.let { a -> for (i in 0 until a.length()) require(a.get(i) is String && a.getString(i).length <= 2048) }
        config.optJSONObject("entityMappings")?.let { values -> require(values.keys().asSequence().all { it in fields && Regex("^sensor\\.[a-z0-9_]+$").matches(values.getString(it)) }) }
        return config
    }
}
