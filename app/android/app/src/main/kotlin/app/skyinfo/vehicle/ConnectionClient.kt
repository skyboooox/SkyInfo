package app.skyinfo.vehicle

import android.content.Context
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.eclipse.paho.client.mqttv3.MqttClient
import org.eclipse.paho.client.mqttv3.MqttConnectOptions
import org.eclipse.paho.client.mqttv3.persist.MemoryPersistence
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.time.Instant
import java.util.UUID
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLSocketFactory

class ConnectionClient(private val context: Context, private val store: SecretStore, private val client: OkHttpClient = OkHttpClient.Builder().callTimeout(12, TimeUnit.SECONDS)
        .connectTimeout(5, TimeUnit.SECONDS).followRedirects(false).followSslRedirects(false).build(), private val mqttSocketFactory: javax.net.SocketFactory = SSLSocketFactory.getDefault()) {
    private val device = DeviceIdentity(context)
    private val deviceId = device.id
    private val sessionId = UUID.randomUUID().toString()
    private var mqtt: MqttClient? = null
    private var mqtt5: org.eclipse.paho.mqttv5.client.MqttClient? = null
    @Volatile var commandSession = ""
        private set
    @Volatile var command: ((JSONObject, String, Boolean) -> Unit)? = null
    @Volatile private var callbackEpoch = 0L
    private var metaSent = false
    private var settings = JSONObject()
    private var sequence = 0L
    private val haDefinitions = mutableMapOf<String,String>()
    @Volatile var status: String = NativeStrings.text_f2f3e9803c
        private set
    fun connectionState(value: String) { status = value }
    fun controlResult(config: JSONObject, result: JSONObject) {
        if (config.optString("connection", "ha") == "mqtt") {
            mqttConnection(config)
            send("${config.getString("mqttTopic").trimEnd('/')}/command_result", envelope("command_result").put("result",result).toString().toByteArray(), 1)
            return
        }
        val field = JSONObject().put("id","system.command_result").put("entityKey","command_result").put("name",NativeStrings.text_9e15c20007).put("encoding",NativeStrings.text_f1926e9b33)
        val payload = JSONObject(result.toString()).put("value",result.optString("status","error")).put("quality","available").put("skyinfo_device",deviceId)
        publishHa(config,field,"sensor.skyinfo_${config.optString("prefix",device.prefix)}_command_result",payload)
    }
    fun configure(config: JSONObject) {
        val keys = listOf("connection", "haUrl", "prefix", "mqttHost", "mqttPort", "mqttUser", "mqttTopic", "mqttProtocol", "mqttTransport", "mqttControlEnabled")
        if (keys.any { config.opt(it)?.toString() != settings.opt(it)?.toString() }) close()
        if (config.optJSONArray("uploaded")?.toString() != settings.optJSONArray("uploaded")?.toString()) metaSent = false
        settings = JSONObject(config.toString())
    }
    private fun haUrl(config: JSONObject, path: String): HttpUrl {
        val base = config.getString("haUrl").toHttpUrl()
        require(base.username.isEmpty() && base.password.isEmpty())
        HaEndpoint.validate(base.toString())
        return base.newBuilder().query(null).fragment(null).addPathSegments(path).build()
    }
    private fun haRequest(config: JSONObject, path: String): Request.Builder {
        val token = store.secret("haToken")
        require(token.isNotEmpty())
        return Request.Builder().url(haUrl(config, path)).header("Authorization", "Bearer $token")
    }
    fun check() {
        try {
            if (settings.optString("connection", "ha") == "mqtt") { mqttConnection(settings); status = NativeStrings.text_65fe35c45e }
            else client.newCall(haRequest(settings, "api/").build()).execute().use { response ->
                status = if (response.isSuccessful) NativeStrings.text_65fe35c45e else if (response.code in listOf(401, 403)) NativeStrings.text_dda97ab7aa else NativeStrings.text_2c056f182f
            }
        } catch (_: IllegalArgumentException) { status = NativeStrings.text_2ee717f092 }
        catch (e: Throwable) { failure(e) }
    }
    private fun mqttConnection(config: JSONObject) {
        if (mqtt?.isConnected == true || mqtt5?.isConnected == true) return
        close()
        commandSession = UUID.randomUUID().toString()
        val epoch = callbackEpoch
        val nonce = commandSession
        val host = config.getString("mqttHost")
        require(host.isNotBlank() && !host.contains('/') && !host.contains('@'))
        val port = config.optInt("mqttPort", 8883)
        require(port in 1..65535)
        val topic = config.optString("mqttTopic", "skyinfo/$deviceId").trimEnd('/')
        require(topic.isNotBlank() && !topic.contains('#') && !topic.contains('+'))
        val secure = config.optString("mqttTransport", "tls") == "tls"
        val server = "${if (secure) "ssl" else "tcp"}://$host:$port"
        if (config.optString("mqttProtocol", "5") == "5") {
            val next = org.eclipse.paho.mqttv5.client.MqttClient(server, "skyinfo-$deviceId", org.eclipse.paho.mqttv5.client.persist.MemoryPersistence())
            next.setCallback(object : org.eclipse.paho.mqttv5.client.MqttCallback {
                override fun disconnected(response: org.eclipse.paho.mqttv5.client.MqttDisconnectResponse?) { if (epoch == callbackEpoch) status = NativeStrings.text_f2f3e9803c }
                override fun mqttErrorOccurred(error: org.eclipse.paho.mqttv5.common.MqttException?) { if (epoch == callbackEpoch) status = NativeStrings.text_f2f3e9803c }
                override fun messageArrived(receivedTopic: String, message: org.eclipse.paho.mqttv5.common.MqttMessage) { receiveCommand(receivedTopic, message.payload, message.isRetained, topic, nonce, epoch, config.optBoolean("mqttControlEnabled")) }
                override fun deliveryComplete(token: org.eclipse.paho.mqttv5.client.IMqttToken?) { }
                override fun connectComplete(reconnect: Boolean, serverURI: String?) { }
                override fun authPacketArrived(reasonCode: Int, properties: org.eclipse.paho.mqttv5.common.packet.MqttProperties?) { }
            })
            val options = org.eclipse.paho.mqttv5.client.MqttConnectionOptions().apply {
                isCleanStart = true; connectionTimeout = 5; keepAliveInterval = 60
                if (secure) socketFactory = mqttSocketFactory; isHttpsHostnameVerificationEnabled = true
                if (config.optString("mqttUser").isNotEmpty()) userName = config.getString("mqttUser")
                val secret = store.secret("mqttPassword"); if (secret.isNotEmpty()) password = secret.toByteArray()
                setWill("$topic/availability", org.eclipse.paho.mqttv5.common.MqttMessage("offline".toByteArray()).apply { qos = 1; isRetained = true })
            }
            try { next.timeToWait = 12000; next.connect(options); mqtt5 = next; if (config.optBoolean("mqttControlEnabled")) next.subscribe(arrayOf(org.eclipse.paho.mqttv5.common.MqttSubscription("$topic/command", 1).apply { isRetainAsPublished = true })); send("$topic/availability", "online".toByteArray(), 1, true) }
            catch (e: Throwable) { next.close(true); throw e }
            return
        }
        val next = MqttClient(server, "skyinfo-$deviceId", MemoryPersistence())
        next.setCallback(object : org.eclipse.paho.client.mqttv3.MqttCallback {
            override fun connectionLost(cause: Throwable?) { if (epoch == callbackEpoch) status = NativeStrings.text_f2f3e9803c }
            override fun deliveryComplete(token: org.eclipse.paho.client.mqttv3.IMqttDeliveryToken?) { }
            override fun messageArrived(receivedTopic: String, message: org.eclipse.paho.client.mqttv3.MqttMessage) { receiveCommand(receivedTopic, message.payload, message.isRetained, topic, nonce, epoch, config.optBoolean("mqttControlEnabled")) }
        })
        val options = MqttConnectOptions().apply {
            mqttVersion = MqttConnectOptions.MQTT_VERSION_3_1_1
            isCleanSession = true
            connectionTimeout = 5
            keepAliveInterval = 60
            if (secure) socketFactory = mqttSocketFactory
            isHttpsHostnameVerificationEnabled = true
            if (config.optString("mqttUser").isNotEmpty()) userName = config.getString("mqttUser")
            val secret = store.secret("mqttPassword")
            if (secret.isNotEmpty()) password = secret.toCharArray()
            setWill("$topic/availability", "offline".toByteArray(), 1, true)
        }
        try { next.timeToWait = 12000; next.connect(options); mqtt = next; if (config.optBoolean("mqttControlEnabled")) next.subscribe("$topic/command", 1); next.publish("$topic/availability", "online".toByteArray(), 1, true) }
        catch (e: Throwable) { next.close(true); throw e }
    }
    private fun receiveCommand(receivedTopic: String, payload: ByteArray, retained: Boolean, topic: String, nonce: String, epoch: Long, allowed: Boolean) {
        if (!allowed || epoch != callbackEpoch || receivedTopic != "$topic/command" || payload.size > 16384) return
        try { command?.invoke(JSONObject(payload.toString(Charsets.UTF_8)), nonce, retained) } catch (_: Throwable) { }
    }
    private fun entity(config: JSONObject, field: JSONObject): String {
        val override = config.optJSONObject("entityMappings")?.optString(field.getString("id"))
        if (!override.isNullOrEmpty()) { require(Regex("^sensor\\.[a-z0-9_]+$").matches(override)); return override }
        return "sensor.skyinfo_${config.optString("prefix", device.prefix)}_${field.getString("entityKey")}"
    }
    private fun send(topic: String, payload: ByteArray, qos: Int = 1, retained: Boolean = false, expiry: Long? = null) {
        val five = mqtt5
        if (five != null) five.publish(topic, org.eclipse.paho.mqttv5.common.MqttMessage(payload).apply {
            this.qos = qos; isRetained = retained
            if (expiry != null) properties = org.eclipse.paho.mqttv5.common.packet.MqttProperties().apply { messageExpiryInterval = expiry }
        }) else mqtt!!.publish(topic, payload, qos, retained)
    }
    private fun envelope(kind: String) = JSONObject().put("schema_version", 1).put("device_id", deviceId).put("session_id", sessionId)
        .put("command_session", commandSession).put("sequence", ++sequence).put("published_at", Instant.now().toString()).put("message_kind", kind)
    fun heartbeat(config: JSONObject, collection: JSONObject, fields: Map<String, JSONObject>) {
        if (config.optString("connection", "ha") != "mqtt") return
        try {
            mqttConnection(config)
            val topic = config.getString("mqttTopic").trimEnd('/')
            send("$topic/heartbeat", envelope("heartbeat").put("collection", collection).toString().toByteArray())
            if (!metaSent) {
                val definitions = JSONArray(RuntimeCoordinator.list(config.optJSONArray("uploaded")).map { fields.getValue(it) })
                send("$topic/meta", envelope("meta").put("app_version", context.packageManager.getPackageInfo(context.packageName,0).versionName).put("fields", definitions).put("command_target",config.optString("prefix",device.prefix)).put("control_enabled",config.optBoolean("mqttControlEnabled")).put("controls",JSONArray(if (config.optBoolean("mqttControlEnabled")) VehicleControls.definitions.map { JSONObject().put("action",it.id).put("name",it.name).put("minimum",it.min).put("maximum",it.max).put("options",VehicleControls.metadata(it).getJSONArray("options")).put("validation",if (it.inferred) "inferred" else "verified") } + RemoteCommands.appActions.map { JSONObject().put("action",it).put("minimum",0).put("maximum",1) } else emptyList<JSONObject>())).toString().toByteArray(), 1, true)
                metaSent = true
            }
            status = NativeStrings.text_65fe35c45e
        } catch (e: Throwable) { failure(e) }
    }
    private fun failure(e: Throwable) {
        status = when {
            e is IllegalArgumentException -> NativeStrings.text_2ee717f092
            e is javax.net.ssl.SSLException || e.cause is javax.net.ssl.SSLException -> NativeStrings.text_9e94379c10
            e is org.eclipse.paho.client.mqttv3.MqttException && e.reasonCode in listOf(4, 5) -> NativeStrings.text_dda97ab7aa
            e is org.eclipse.paho.mqttv5.common.MqttException && e.reasonCode in listOf(134, 135) -> NativeStrings.text_dda97ab7aa
            else -> NativeStrings.text_f2f3e9803c
        }
    }
    fun publish(config: JSONObject, samples: Map<String, JSONObject>, fields: Map<String, JSONObject>, stillCurrent: () -> Boolean = { true }) {
        try {
            if (!stillCurrent()) return
            if (config.optString("connection", "ha") == "mqtt") {
                mqttConnection(config)
                val metrics = JSONObject()
                samples.forEach { (id, sample) -> metrics.put(id, attributes(sample, fields.getValue(id))) }
                val times = samples.values.mapNotNull { it.optLong("receivedAt").takeIf { at -> at > 0 } }
                val message = envelope("telemetry").put("metrics", metrics)
                    .put("batch_started_at", times.minOrNull()?.let { Instant.ofEpochMilli(it).toString() } ?: JSONObject.NULL)
                    .put("batch_finished_at", times.maxOrNull()?.let { Instant.ofEpochMilli(it).toString() } ?: JSONObject.NULL)
                send("${config.getString("mqttTopic").trimEnd('/')}/telemetry", message.toString().toByteArray())
            } else {
                samples.forEach { (id, sample) ->
                    if (!stillCurrent()) return
                    val field = fields.getValue(id)
                    val normalized = haReading(sample,field)
                    val payload = attributes(normalized,field).put("skyinfo_device",deviceId)
                    val definition = JSONObject(field.toString()).put("unit",payload.optString("unit"))
                    publishHa(config,definition,entity(config,field),payload)
                }
            }
            status = NativeStrings.text_65fe35c45e
        } catch (_: IllegalArgumentException) { status = NativeStrings.text_2ee717f092 }
        catch (e: Throwable) { failure(e) }
    }
    private fun mqttViaHa(config: JSONObject, topic: String, payload: String, retained: Boolean) {
        val body = JSONObject().put("topic",topic).put("payload",payload).put("qos",1).put("retain",retained)
        client.newCall(haRequest(config,"api/services/mqtt/publish").post(body.toString().toRequestBody("application/json".toMediaType())).build()).execute().use { response ->
            check(response.isSuccessful) { "HA MQTT publish HTTP ${response.code}" }
        }
    }
    private fun migrateHaState(config: JSONObject, field: JSONObject, entityId: String) {
        client.newCall(haRequest(config,"api/states/$entityId").build()).execute().use { response ->
            if (response.code == 404) return
            check(response.isSuccessful) { "HA state read HTTP ${response.code}" }
            val state = JSONObject(limitedBody(response))
            val attrs = state.optJSONObject("attributes") ?: return
            if (attrs.has("skyinfo_device")) {
                check(attrs.optString("skyinfo_device") == deviceId) { "HA entity belongs to another SkyInfo device" }
                return
            }
            val owned = if (field.getString("id") == "system.command_result")
                attrs.has("id") && attrs.optString("action") in RemoteCommands.appActions + VehicleControls.definitions.map { it.id }
            else attrs.optString("metric_id") == field.getString("id") && attrs.optString("source") == field.getString("id") && attrs.has("session_id")
            if (!owned) {
                val template = "{{ (device_attr(${JSONObject.quote(entityId)}, 'identifiers') or []) | list | tojson }}"
                val body = JSONObject().put("template",template)
                client.newCall(haRequest(config,"api/template").post(body.toString().toRequestBody("application/json".toMediaType())).build()).execute().use { registry ->
                    check(registry.isSuccessful) { "HA device lookup HTTP ${registry.code}" }
                    val identifiers = JSONArray(limitedBody(registry))
                    for (i in 0 until identifiers.length()) {
                        val identifier = identifiers.optJSONArray(i) ?: continue
                        if (identifier.optString(0) == "mqtt" && identifier.optString(1) == "skyinfo_$deviceId") return
                    }
                }
                error("HA entity is not managed by SkyInfo")
            }
        }
        client.newCall(haRequest(config,"api/states/$entityId").delete().build()).execute().use { response ->
            check(response.isSuccessful || response.code == 404) { "HA legacy state migration HTTP ${response.code}" }
        }
    }
    private fun publishHa(config: JSONObject, field: JSONObject, entityId: String, payload: JSONObject) {
        val version = context.packageManager.getPackageInfo(context.packageName,0).versionName ?: ""
        val definition = haSensorDiscovery(deviceId,config.optString("prefix",device.prefix),version,field,entityId)
        val key = config.getString("haUrl") + "|" + field.getString("id")
        if (haDefinitions[key] != definition.toString()) {
            migrateHaState(config,field,entityId)
            mqttViaHa(config,"homeassistant/sensor/skyinfo_${deviceId}/${field.getString("entityKey")}/config",definition.toString(),true)
            haDefinitions[key] = definition.toString()
        }
        mqttViaHa(config,definition.getString("state_topic"),payload.toString(),false)
    }
    private val controlDefinitions = EntityCatalog.controls(context)
    private val controlStates = mutableMapOf<String,String>()
    private var controlTopic = ""
    fun invalidateControlStates() { controlStates.clear() }
    fun publishControlEntities(config: JSONObject, samples: Map<String, JSONObject>, commandTopic: String, online: Boolean) {
        if (config.optString("connection","ha") != "ha" || commandTopic.isEmpty()) return
        val version = context.packageManager.getPackageInfo(context.packageName,0).versionName ?: ""
        val ready = online && config.optBoolean("haControlEnabled")
        val connectionKey = config.optString("haUrl")+"|"+commandTopic
        if (controlTopic != connectionKey) {
            val definitions = controlDefinitions.flatMap { haControlDefinitions(deviceId,config.optString("prefix",device.prefix),version,it,commandTopic) }
            mqttViaHa(config,"homeassistant/device/skyinfo_${deviceId}_controls/config",haControlDeviceDiscovery(definitions,version).toString(),true)
        }
        for (entity in controlDefinitions) {
            val state = haControlState(entity,samples,ready).toString()
            val topic = "skyinfo/ha/$deviceId/control/${entity.getString("id")}/state"
            if (controlTopic != connectionKey || controlStates[topic] != JSONObject(state).apply { remove("updatedAt") }.toString()) {
                mqttViaHa(config,topic,state,false)
                controlStates[topic] = JSONObject(state).apply { remove("updatedAt") }.toString()
            }
        }
        controlTopic = connectionKey
    }
    fun publishState(config: JSONObject, samples: Map<String, JSONObject>, fields: Map<String, JSONObject>) {
        if (config.optString("connection", "ha") != "mqtt" || !config.optBoolean("mqttState")) return
        try {
            mqttConnection(config)
            val metrics = JSONObject(); samples.forEach { (id, s) -> metrics.put(id, attributes(s, fields.getValue(id))) }
            send("${config.getString("mqttTopic").trimEnd('/')}/state", envelope("state").put("metrics", metrics).toString().toByteArray(), 1, true, 180)
        } catch (e: Throwable) { failure(e) }
    }
    private fun attributes(sample: JSONObject, field: JSONObject) = JSONObject(sample.toString())
        .put("metric_id", field.getString("id")).put("unit", if (field.has("unitField")) sample.optString("unit") else field.optString("unit"))
        .put("raw_type", if (isDerived(field.getString("id"))) "computed_number" else if (field.getString("id").contains("/7/")) "float32" else if (field.getString("id").contains("/5/")) "int32" else "text")
        .put("value", if (sample.optString("quality") in listOf("available", "unverified")) sample.opt("value") ?: JSONObject.NULL else JSONObject.NULL)
        .put("age_ms", if (sample.has("updatedAt")) (System.currentTimeMillis()-sample.getLong("updatedAt")).coerceAtLeast(0) else JSONObject.NULL)
        .put("source", field.getString("id")).put("definition_version", field.optInt("definitionVersion", 1)).put("source_timestamp", JSONObject.NULL)
        .put("unit_confidence", field.optString("unitConfidence", if ((if (field.has("unitField")) sample.optString("unit") else field.optString("unit")).isEmpty()) "unknown" else "confirmed"))
        .put("sampled_at", sample.optLong("updatedAt").takeIf { it > 0 } ?: JSONObject.NULL).put("session_id", sessionId)
    private fun limitedBody(response: Response): String {
        val body = response.body ?: return "[]"
        require(body.contentLength() <= 8 * 1024 * 1024)
        val output = ByteArrayOutputStream()
        body.byteStream().use { input ->
            val buffer = ByteArray(8192)
            while (true) { val count = input.read(buffer); if (count < 0) break
                require(output.size() + count <= 8 * 1024 * 1024); output.write(buffer, 0, count) }
        }
        return output.toString("UTF-8")
    }
    fun close() {
        callbackEpoch++; commandSession = ""
        mqtt5?.let { connection ->
            try { if (connection.isConnected) { send("${settings.optString("mqttTopic").trimEnd('/')}/availability", "offline".toByteArray(), 1, true); connection.disconnect() } } catch (_: Throwable) { }
            try { connection.close(true) } catch (_: Throwable) { }
        }
        mqtt5 = null; metaSent = false
        mqtt?.let { connection ->
            try { if (connection.isConnected) { connection.publish("${settings.optString("mqttTopic").trimEnd('/')}/availability", "offline".toByteArray(), 1, true); connection.disconnect() } } catch (_: Throwable) { }
            try { connection.close(true) } catch (_: Throwable) { }
        }
        mqtt = null; status = NativeStrings.text_f2f3e9803c
    }
}
