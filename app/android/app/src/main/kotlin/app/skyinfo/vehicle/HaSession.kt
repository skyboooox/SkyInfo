package app.skyinfo.vehicle

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.net.URI
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

class HaSession(private val secrets: SecretStore, private val restored: () -> Unit, private val changed: (String) -> Unit,
    private val http: OkHttpClient = OkHttpClient.Builder().pingInterval(60,TimeUnit.SECONDS).connectTimeout(5,TimeUnit.SECONDS).followRedirects(false).followSslRedirects(false).build()) {
    var inboundConnected: () -> Unit = {}
    var inboundDisconnected: () -> Unit = {}
    var inboundEvent: (JSONObject) -> Unit = {}
    private var nextRequest = 100
    private val requests = mutableMapOf<Int, (JSONObject) -> Unit>()
    private val timeouts = mutableMapOf<Int, ScheduledFuture<*>>()
    @Synchronized fun request(message: JSONObject, callback: (JSONObject) -> Unit): Int? {
        if (sessionState != NativeStrings.text_09f11a24a6 || socket == null) { callback(JSONObject().put("success",false).put("error",JSONObject().put("code","disconnected"))); return null }
        val id = nextRequest++
        requests[id] = callback
        timeouts[id] = executor.schedule({ synchronized(this) {
            timeouts.remove(id); requests.remove(id)?.invoke(JSONObject().put("success",false).put("error",JSONObject().put("code","timeout")))
        } }, 10, TimeUnit.SECONDS)
        if (socket?.send(JSONObject(message.toString()).put("id",id).toString()) != true) {
            timeouts.remove(id)?.cancel(false); requests.remove(id)?.invoke(JSONObject().put("success",false).put("error",JSONObject().put("code","disconnected")))
            return null
        }
        return id
    }
    @Synchronized private fun releaseRequests() {
        publicationRestore?.cancel(false); publicationRestore = null
        timeouts.values.forEach { it.cancel(false) }; timeouts.clear()
        val waiting = requests.values.toList(); requests.clear()
        waiting.forEach { it(JSONObject().put("success",false).put("error",JSONObject().put("code","disconnected"))) }
        inboundDisconnected()
    }
    var command: (JSONObject) -> Unit = {}
    var entityCommand: (JSONObject) -> Unit = {}
    var controlPublicationRestored: () -> Unit = {}
    private var publicationRestore: ScheduledFuture<*>? = null
    @Volatile var entityCommandTopic = ""
        private set
    private var prefix = "skyinfo"
    private var birthTopic = "homeassistant/status"
    private var birthPayload = "online"
    @Volatile var entitySubscription = false
        private set
    private var serverTime: Long? = null
    private var clockStarted = 0L
    @Synchronized fun currentTime(): Long = serverTime?.let { it + android.os.SystemClock.elapsedRealtime() - clockStarted } ?: System.currentTimeMillis()
    private var controlEnabled = false
    @Volatile var commandSubscription = NativeStrings.text_8bb38ef00c
        private set
    @Volatile var commandEvents = 0
        private set
    @Volatile var sessionState = NativeStrings.text_f2f3e9803c
        private set
    private val executor = Executors.newSingleThreadScheduledExecutor()
    private var socket: WebSocket? = null
    private var retry: ScheduledFuture<*>? = null
    private var authenticationTimeout: ScheduledFuture<*>? = null
    private var target = ""
    private var token = ""
    private var seconds = 1L
    private var epoch = 0L
    @Synchronized fun configure(config: JSONObject, active: Boolean) {
        val nextUrl = if (active && (config.optString("connection","ha") == "ha" || config.optBoolean("haImportEnabled"))) config.optString("haUrl") else ""
        val nextToken = if (nextUrl.isNotEmpty()) try { secrets.secret("haToken") } catch (_: Throwable) { "" } else ""
        val controls = active && config.optString("connection","ha") == "ha" && config.optBoolean("haControlEnabled")
        if (target == nextUrl && token == nextToken && controlEnabled == controls && prefix == config.optString("prefix","skyinfo") && birthTopic == config.optString("haBirthTopic", "homeassistant/status") && birthPayload == config.optString("haBirthPayload", "online")) return
        close(); target = nextUrl; token = nextToken
        controlEnabled = controls
        prefix = config.optString("prefix","skyinfo")
        birthTopic = config.optString("haBirthTopic", "homeassistant/status")
        birthPayload = config.optString("haBirthPayload", "online")
        commandSubscription = if (controls) NativeStrings.text_f1a81f913b else NativeStrings.text_8bb38ef00c
        if (target.isNotEmpty() && token.isNotEmpty()) connect()
    }
    @Synchronized private fun connect() {
        val captured = ++epoch
        entitySubscription = false
        entityCommandTopic = "skyinfo/ha/control/$prefix/${java.util.UUID.randomUUID()}/command"
        try {
            val uri = HaEndpoint.validate(target)
            val path = (uri.path ?: "/").trimEnd('/') + "/api/websocket"
            val url = URI(if (uri.scheme.equals("https",true)) "wss" else "ws",null,uri.host,uri.port,path,null,null).toString()
            authenticationTimeout?.cancel(false)
            authenticationTimeout = executor.schedule({ synchronized(this) { if (captured == epoch) { socket?.cancel(); reconnect(captured, NativeStrings.text_8524c33678) } } },10,TimeUnit.SECONDS)
            socket = http.newWebSocket(Request.Builder().url(url).build(), object : WebSocketListener() {
                override fun onOpen(ws: WebSocket, response: Response) {
                    synchronized(this@HaSession) {
                        if (captured != epoch) return
                        serverTime = response.header("Date")?.let { date -> try { java.time.ZonedDateTime.parse(date,java.time.format.DateTimeFormatter.RFC_1123_DATE_TIME).toInstant().toEpochMilli() } catch (_: Throwable) { null } }
                        clockStarted = android.os.SystemClock.elapsedRealtime()
                    }
                }
                override fun onMessage(ws: WebSocket, text: String) {
                    synchronized(this@HaSession) {
                        if (captured != epoch || text.length > 8*1024*1024) return
                        try {
                            val message = JSONObject(text)
                            when (message.optString("type")) {
                                "auth_required" -> ws.send(JSONObject().put("type","auth").put("access_token",token).toString())
                                "auth_ok" -> { authenticationTimeout?.cancel(false); authenticationTimeout = null; seconds = 1; sessionState = NativeStrings.text_09f11a24a6; changed(NativeStrings.text_65fe35c45e); ws.send(JSONObject().put("id",1).put("type","subscribe_events").put("event_type","homeassistant_started").toString()); if (controlEnabled) { ws.send(JSONObject().put("id",2).put("type","subscribe_events").put("event_type","skyinfo_command").toString()); ws.send(JSONObject().put("id",3).put("type","mqtt/subscribe").put("topic",entityCommandTopic).put("qos",0).toString()); if (birthTopic.isNotEmpty()) ws.send(JSONObject().put("id",4).put("type","mqtt/subscribe").put("topic",birthTopic).put("qos",0).toString()) }; inboundConnected(); restored() }
                                "result" -> if (message.optInt("id") >= 100) { val id = message.getInt("id"); timeouts.remove(id)?.cancel(false); requests.remove(id)?.invoke(message) } else if (message.optInt("id") == 3) { entitySubscription = message.optBoolean("success"); restored() } else if (message.optInt("id") == 2) commandSubscription = if (message.optBoolean("success")) NativeStrings.text_d60537c090 else NativeStrings.text_d7eda605a7
                                "auth_invalid" -> { authenticationTimeout?.cancel(false); authenticationTimeout = null; sessionState = NativeStrings.text_dda97ab7aa; changed(NativeStrings.text_dda97ab7aa); releaseRequests(); epoch++; socket?.cancel(); socket = null }
                                "event" -> message.optJSONObject("event")?.let { event ->
                                    if (message.optInt("id") >= 100) inboundEvent(message)
                                    if (controlEnabled && entitySubscription && message.optInt("id") == 3 && event.optString("topic") == entityCommandTopic && !event.optBoolean("retain") && event.optString("payload").length <= 16384) {
                                        entityCommand(JSONObject(event.getString("payload")))
                                    } else if (controlEnabled && message.optInt("id") == 4 && birthTopic.isNotEmpty() && event.optString("topic") == birthTopic && event.optString("payload") == birthPayload) restoreControlPublication(captured)
                                    else if (event.optString("event_type") == "homeassistant_started") { restored(); if (controlEnabled) restoreControlPublication(captured) }
                                    else if (controlEnabled && message.optInt("id") == 2 && event.optString("event_type") == "skyinfo_command") { commandEvents++; command(event) }
                                }
                            }
                        } catch (_: Throwable) { changed(NativeStrings.text_041e88dac0) }
                    }
                }
                override fun onFailure(ws: WebSocket, error: Throwable, response: Response?) { reconnect(captured, if (error is javax.net.ssl.SSLException) NativeStrings.text_9e94379c10 else NativeStrings.text_f2f3e9803c) }
                override fun onClosing(ws: WebSocket, code: Int, reason: String) { ws.close(code,reason) }
                override fun onClosed(ws: WebSocket, code: Int, reason: String) { reconnect(captured,NativeStrings.text_f2f3e9803c) }
            })
        } catch (_: Throwable) { changed(NativeStrings.text_2ee717f092) }
    }
    @Synchronized private fun restoreControlPublication(captured: Long) {
        if (publicationRestore != null) return
        publicationRestore = executor.schedule({ synchronized(this) {
            publicationRestore = null
            if (captured == epoch && controlEnabled && sessionState == NativeStrings.text_09f11a24a6) controlPublicationRestored()
        } }, 250, TimeUnit.MILLISECONDS)
    }
    @Synchronized private fun reconnect(captured: Long, state: String) {
        if (captured != epoch || target.isEmpty()) return
        releaseRequests()
        entitySubscription = false
        authenticationTimeout?.cancel(false); authenticationTimeout = null
        commandSubscription = if (controlEnabled) NativeStrings.text_f1a81f913b else NativeStrings.text_8bb38ef00c
        changed(state); socket = null
        sessionState = state
        if (state == NativeStrings.text_9e94379c10 || retry != null) return
        retry = executor.schedule({ synchronized(this) { retry = null; if (captured == epoch) connect() } },seconds*1000+(0..500).random(),TimeUnit.MILLISECONDS)
        seconds = (seconds*2).coerceAtMost(60)
    }
    @Synchronized fun networkLost() {
        if (target.isEmpty()) return
        releaseRequests(); entitySubscription = false; epoch++; retry?.cancel(false); retry = null; authenticationTimeout?.cancel(false); authenticationTimeout = null
        socket?.cancel(); socket = null; serverTime = null
        sessionState = NativeStrings.text_f2f3e9803c; commandSubscription = if (controlEnabled) NativeStrings.text_f1a81f913b else NativeStrings.text_8bb38ef00c; changed(NativeStrings.text_f2f3e9803c)
    }
    @Synchronized fun networkAvailable() {
        if (target.isEmpty() || token.isEmpty() || sessionState in listOf(NativeStrings.text_09f11a24a6, NativeStrings.text_dda97ab7aa, NativeStrings.text_9e94379c10)) return
        releaseRequests(); entitySubscription = false; epoch++; retry?.cancel(false); retry = null; authenticationTimeout?.cancel(false); authenticationTimeout = null
        socket?.cancel(); socket = null; seconds = 1; connect()
    }
    @Synchronized fun close() { releaseRequests(); entitySubscription = false; commandSubscription = NativeStrings.text_8bb38ef00c; serverTime = null; sessionState = NativeStrings.text_f2f3e9803c; entitySubscription = false; epoch++; retry?.cancel(false); retry = null; authenticationTimeout?.cancel(false); authenticationTimeout = null; socket?.cancel(); socket = null; target = ""; token = ""; seconds = 1 }
}
