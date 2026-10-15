package app.skyinfo.vehicle

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.EventChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

class RuntimeCoordinator private constructor(context: Context) {
    private val context = context.applicationContext
    val store = SecureConfig(this.context)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadScheduledExecutor()
    private val network = Executors.newSingleThreadExecutor()
    private val source = java.util.concurrent.ThreadPoolExecutor(1,1,0,TimeUnit.SECONDS,java.util.concurrent.ArrayBlockingQueue<Runnable>(1))
    private var readBlocked = false
    private var publishInFlight = false
    private val fields: Map<String, JSONObject>
    private val altitude = GnssAltitude(this.context)
    private val reader: ReadOnlyVehicle
    private val session: VehicleSession
    private var callbackFlush: ScheduledFuture<*>? = null
    private val callbackChanged = mutableSetOf<String>()
    private val samples = mutableMapOf<String, JSONObject>()
    private val localHistory = LocalHistory(this.context)
    private val publisher = ConnectionClient(this.context, store)
    private val haSession = HaSession(store, { execute { publishControlEntities(); if (enabled() && config.optBoolean("publishEnabled")) { readCurrent(); publishSelected() } } }, { state -> execute { publisher.connectionState(state); publishControlEntities(); emit() } })
    private var overlayPermissionWatcher: android.app.AppOpsManager.OnOpChangedListener? = null
    private var activeNetwork: android.net.Network? = null
    private var networkCallback: android.net.ConnectivityManager.NetworkCallback? = null
    private val deviceIdentity = DeviceIdentity(this.context)
    private var config = deviceIdentity.defaults(store.load()).also(store::save)
    private val systemAdbSettings = AutoAdbSettings(AndroidAdbSettings(this.context))
    private val appearance = VehicleAppearance(this.context) { execute { appearanceChanged() } }
    private var systemAdbResult = JSONObject().put("state", "disabled")
    private val haEntityUpdates = mutableMapOf<String,JSONObject>()
    private var haFlush: ScheduledFuture<*>? = null
    private var haDirectoryChanged = false
    private val haSource = HaEntitySource(haSession, ::execute,
        { delay, task -> worker.schedule({ execute(task) }, delay, TimeUnit.MILLISECONDS) },
        { directory ->
            haDirectoryChanged = haDirectoryChanged || directory
            if (haFlush == null) haFlush = worker.schedule({
                haFlush = null
                val full = haDirectoryChanged; haDirectoryChanged = false
                emit(full)
            },100,TimeUnit.MILLISECONDS)
        }, { id, sample ->
            samples[id] = sample; localHistory.append(id,sample)
        }, { entity -> haEntityUpdates[entity.getString("id")] = entity })
    private fun displayFields(): Map<String,JSONObject> {
        val saved = config.optJSONObject("haFields") ?: JSONObject()
        return fields + saved.keys().asSequence().associateWith { saved.getJSONObject(it) } + haSource.fields()
    }
    fun refreshHa() { haSession.close(); reconfigure() }
    fun haDirectory(): JSONObject = haSource.directory()
    fun haControl(id: String, key: String, value: Any?, confirmed: Boolean, callback: (JSONObject) -> Unit) {
        val tiles = config.optJSONArray("tiles") ?: JSONArray()
        val added = (0 until tiles.length()).any { tile -> tiles.getJSONObject(tile).let { it.optString("kind") in setOf("entity","toggle","select","action","numberControl","entities","device") && id in list(it.optJSONArray("fields")) } }
        if (store.stopped()) callback(JSONObject().put("status","stopped")) else haSource.control(id,key,value,confirmed,added,callback)
    }
    private var service: Service? = null
    private var overlay: OverlayWindow? = null
    private var overlayInteraction = NativeStrings.text_d62b59c59b
    private var poll: ScheduledFuture<*>? = null
    private var retry: ScheduledFuture<*>? = null
    private var retrySeconds = 1L
    private val pendingFields = mutableSetOf<String>()
    private var sink: EventChannel.EventSink? = null
    private var visible = false
    private var informationVisible = true
    private var heartbeat: ScheduledFuture<*>? = null
    private var heartbeatInFlight = false
    private var mqttRetrySeconds = 1L
    @Volatile private var generation = 0L
    private var sourceEpoch = 0L
    private var runtimeError: String? = null
    private var adaptationAudit: JSONObject? = null
    private var lastCommand: JSONObject? = null
    private var commandError: String? = null
    private val receipts = CommandReceipts()
    private var receiptInFlight = false
    private var receiptRetry: ScheduledFuture<*>? = null
    private var receiptSeconds = 1L
    private val mqttCommands = RemoteCommands(store::rememberCommand)
    private val commands = RemoteCommands(store::rememberCommand) { haSession.currentTime() }
    private var previousDemand = setOf<String>()
    private var previewDemand = emptySet<String>()
    init {
        haSession.entityCommand = { data -> execute {
            if (!store.stopped() && config.optString("connection","ha") == "ha" && config.optBoolean("haControlEnabled") && haSession.entitySubscription) {
                try {
                    val value = data.get("value"); require(value is Number && value.toDouble().isFinite() && value.toDouble() == value.toInt().toDouble())
                    val action = data.getString("action"); VehicleControls.definition(action).validate(value.toInt())
                    performCommand(java.util.UUID.randomUUID().toString(),action,value.toInt())
                } catch (_: Throwable) { commandError = NativeStrings.invalid }
            }
        } }
        haSession.command = { event -> execute { handleCommand(event) } }
        haSession.controlPublicationRestored = { execute { restoreControlPublication() } }
        publisher.command = { data, nonce, retained -> execute { handleCommand(data, "mqtt", nonce, retained) } }
        fields = EntityCatalog.fields(this.context)
        if (migrateConvertedUnits(config, fields)) store.save(config)
        reader = ReadOnlyVehicle(fields, altitude)
        localHistory.configure(config)
        session = VehicleSession(this.context, reader, ::execute, { id, fresh ->
            receiveSample(id, fresh)
        }, { previousDemand = emptySet(); readBlocked = false; reconfigure() }, { markDisconnected(); emit(); publishSelected() }, ::overlayChanged,
            { restoreSystemAdb() })
        restoreSystemAdb()
    }
    fun execute(action: () -> Unit) { worker.execute(action) }
    private fun receiveSample(id: String, fresh: JSONObject) {
        callbackChanged.addAll(accept(id, fresh))
        if (callbackFlush == null) callbackFlush = worker.schedule({
            callbackFlush = null; val batch = callbackChanged.toSet(); callbackChanged.clear()
            emit(); publishControlEntities(); if (batch.isNotEmpty()) publishSelected(batch)
        }, 100, TimeUnit.MILLISECONDS)
    }

    private fun handleCommand(event: JSONObject, transport: String = "ha", nonce: String = "", retained: Boolean = false) {
        val flag = if (transport == "ha") "haControlEnabled" else "mqttControlEnabled"
        if (store.stopped() || !config.optBoolean(flag) || config.optString("connection","ha") != transport) return
        val command = try {
            if (transport == "ha") commands.validate(event,config.optString("prefix",deviceIdentity.prefix))
            else {
                require(nonce == publisher.commandSession) { "session_mismatch" }
                mqttCommands.validateMqtt(event,config.optString("prefix",deviceIdentity.prefix),nonce,retained)
            }
        } catch (error: Throwable) { commandError = "${error.javaClass.simpleName}: ${error.message}"; return }
        commandError = null
        performCommand(command.getString("id"),command.getString("action"),command.getInt("value"))
    }
    fun controlLocal(action: String, value: Int): JSONObject {
        VehicleControls.definition(action).validate(value)
        val tiles = config.optJSONArray("tiles") ?: JSONArray()
        if ((0 until tiles.length()).none { "control.$action" in list(tiles.getJSONObject(it).optJSONArray("fields")) }) return JSONObject().put("status","not_added")
        if (store.stopped()) return JSONObject().put("status","stopped")
        return performCommand(java.util.UUID.randomUUID().toString(),action,value)
    }
    private fun performCommand(id: String, action: String, value: Int): JSONObject {
        val result = if (action in RemoteCommands.appActions) {
            try {
                if (action == "app_refresh") { if (value == 1) refresh() }
                else {
                    val key = when (action) { "app_overlay" -> "overlayEnabled"; "app_collect" -> "collect"; "app_publish" -> "publishEnabled"; else -> error("unknown_action") }
                    save(JSONObject(config.toString()).put(key,value == 1),emptyMap())
                    main.post { sink?.success(jsonMap(snapshot())) }
                }
                JSONObject().put("status","confirmed").put("actual",value)
            } catch (_: Throwable) { JSONObject().put("status","error") }
        } else try {
            val task = source.submit<JSONObject> { session.control(action,value) }
            try { task.get(5,TimeUnit.SECONDS) } catch (_: java.util.concurrent.TimeoutException) { task.cancel(true); source.purge(); JSONObject().put("status","timeout_unconfirmed") }
        } catch (_: Throwable) { JSONObject().put("status","error") }
        lastCommand = result.put("id",id).put("action",action).put("requested",value).put("received_at",System.currentTimeMillis())
        if (remoteControlEnabled()) {
            receipts.add(config,lastCommand!!)
            flushReceipts()
        }
        readCurrent()
        emit()
        return lastCommand!!
    }
    private fun flushReceipts() {
        if (store.stopped() || receiptInFlight || receiptRetry != null) return
        val entry = receipts.next(config) ?: return
        receiptInFlight = true
        network.execute {
            val error = try { publisher.controlResult(entry.config,entry.result); null } catch (failure: Throwable) { failure.javaClass.simpleName }
            execute {
                receiptInFlight = false
                if (error == null) { receipts.delivered(entry.result.getString("id")); receiptSeconds = 1; commandError = null; flushReceipts() }
                else {
                    commandError = NativeStrings.text("native_receipt_error",mapOf("error" to error))
                    if (!store.stopped() && receipts.next(config) != null) {
                        receiptRetry = worker.schedule({ receiptRetry = null; flushReceipts() },receiptSeconds,TimeUnit.SECONDS)
                        receiptSeconds = (receiptSeconds*2).coerceAtMost(30)
                    }
                }
                emit()
            }
        }
    }
    fun controls(): JSONObject = session.controls()
    fun reconnectAdb() { session.close(); markDisconnected(); readBlocked = false; previousDemand = emptySet(); reconfigure(); emit() }
    fun pairAdb(host: String, port: Int, code: String, callback: (JSONObject) -> Unit) {
        val endpoint = AdbEndpoint.from(JSONObject().put("adbHost",host).put("adbPort",5555).put("adbMode","pair"))
        NetworkAdb.operations.execute {
            val status = try { NetworkAdb(context, endpoint).pair(port, code); "paired" } catch (_: Throwable) { "pair_failed" }
            execute { callback(JSONObject().put("result", status)) }
        }
    }
    fun listen(value: EventChannel.EventSink?) { sink = value; execute { emit() } }
    fun status(): JSONObject = JSONObject().put("stopped",store.stopped())
        .put("vehicle", runtimeError ?: if (samples.values.any { it.optString("quality") in listOf("available", "unverified") && it.has("value") }) NativeStrings.text_c6f7c57883 else NativeStrings.text_38093d864b)
        .put("path", session.identity)
        .put("adb", session.adbState)
        .put("systemAdb", systemAdbResult)
        .put("appearance", appearance.current.json())
        .put("overlayGranted", Settings.canDrawOverlays(context))
        .put("overlay", if (Settings.canDrawOverlays(context)) NativeStrings.text_284cc0bae1 else NativeStrings.text_86bddceb9d)
        .put("overlayInteraction",overlayInteraction).put("haImport",haSource.state)
        .put("subscription", session.state)
        .put("connection", if (config.optString("connection","ha") == "ha" && config.optBoolean("haControlEnabled") && haSession.sessionState == NativeStrings.text_09f11a24a6) NativeStrings.text_65fe35c45e else publisher.status)
    fun snapshot(): JSONObject = JSONObject().put("config", config).put("samples", JSONObject(samples as Map<*, *>)).put("status", status()).put("haDirectory",haDirectory())
    private var positionResetTime = 0L
    private fun overlayChanged(state: JSONObject) {
        overlayInteraction = if (!state.optBoolean("visible")) NativeStrings.text_d62b59c59b else when (state.optString("state")) {
            "armed" -> NativeStrings.text_2452e4fd2d
            "unlocked" -> NativeStrings.text_59c3eda1b1
            else -> if (state.optBoolean("gesture")) NativeStrings.text_e3ada582bd else NativeStrings.text_ead919fb39
        }
        val payload = JSONObject().put("status",status())
        if (state.has("x") && state.has("y") && state.optLong("positionTime") > positionResetTime && config.optBoolean("overlayEnabled") && !store.stopped()) {
            val x = state.getDouble("x"); val y = state.getDouble("y")
            if (x.isFinite() && y.isFinite() && x in 0.0..1.0 && y in 0.0..1.0) {
                config.put("overlayX",x).put("overlayY",y); store.save(config)
                payload.put("overlayPosition",JSONObject().put("x",x).put("y",y))
            }
        }
        if (visible) main.post { sink?.success(jsonMap(payload)) }
    }
    fun editOverlay() {
        require(config.optBoolean("overlayEnabled") && !store.stopped() && (config.optJSONArray("overlays")?.length() ?: 0) > 0)
        if (!session.editOverlay()) {
            val result = java.util.concurrent.CompletableFuture<Boolean>()
            main.post { result.complete(overlay?.arm() == true) }
            check(result.get(2,TimeUnit.SECONDS))
        }
    }
    fun resetOverlayPosition() {
        session.resetOverlayPosition()
        val result = java.util.concurrent.CompletableFuture<Boolean>()
        main.post { overlay?.resetPosition(); result.complete(true) }
        check(result.get(2,TimeUnit.SECONDS))
        positionResetTime = android.os.SystemClock.elapsedRealtimeNanos()
        val next = JSONObject(config.toString()).put("overlayX",JSONObject.NULL).put("overlayY",JSONObject.NULL)
        try { store.save(next) } catch (error: Throwable) { drawOverlay(); throw error }
        config = next
        emit()
    }
    private var overlayStyleDraft: JSONObject? = null
    fun saveOverlayAppearance(style: JSONObject) {
        val patch = overlayAppearancePatch(style)
        val next = JSONObject(config.toString())
        patch.keys().forEach { next.put(it,patch.get(it)) }
        store.save(next)
        config = next
        overlayStyleDraft = null
        emit()
    }
    fun previewOverlayStyle(style: JSONObject?) {
        if (!visible && style != null) return
        overlayStyleDraft = style?.let(::overlayStylePatch)
        drawOverlay()
    }
    private fun emit(directory: Boolean = false) {
        val message = JSONObject().put("samples", JSONObject(samples as Map<*, *>)).put("status", status())
            .put("overlayPosition",JSONObject().put("x",config.opt("overlayX") ?: JSONObject.NULL).put("y",config.opt("overlayY") ?: JSONObject.NULL))
        if (directory) message.put("haDirectory",haDirectory())
        else if (haEntityUpdates.isNotEmpty()) message.put("haEntityUpdates",JSONArray(haEntityUpdates.values.toList()))
        haEntityUpdates.clear()
        val payload = jsonMap(message)
        if (visible) main.post { sink?.success(payload) }
        drawOverlay()
    }
    private fun drawOverlay() {
        val preview = JSONObject(config.toString())
        overlayStyleDraft?.let { patch -> patch.keys().forEach { preview.put(it,patch.get(it)) } }
        val overlayConfig = appearance.current.overlayConfig(preview)
        if (!Settings.canDrawOverlays(context) || store.stopped()) overlayConfig.put("overlayEnabled",false)
        val overlayIds = overlayFieldIds(overlayConfig)
        val overlaySamples = samples.filterKeys { it in overlayIds }.mapValues { JSONObject(it.value.toString()) }
        val overlayFields = if (overlayIds.any { HaBinding.parse(it) != null }) displayFields().filterKeys { it in overlayIds }
            else fields.filterKeys { it in overlayIds }
        val remoteOverlay = session.overlay(JSONObject(overlayConfig.toString()).put("haFields",JSONObject(overlayFields.filterKeys { HaBinding.parse(it) != null } as Map<*,*>)),overlaySamples)
        main.post { if (remoteOverlay) overlay?.close() else overlay?.update(overlayConfig, overlayFields, overlaySamples) }
    }
    fun save(next: JSONObject, secrets: Map<String, String>) {
        val autoAdbWasEnabled = config.optBoolean("autoSystemAdb")
        val validated = ConfigValidator.validate(deviceIdentity.defaults(JSONObject(next.toString())), displayFields())
        if (HaEndpoint.identity(validated.optString("haUrl")) != HaEndpoint.identity(config.optString("haUrl"))) validated.put("haConnectionId",java.util.UUID.randomUUID().toString())
        secrets.forEach { (name, value) -> if (value.isNotEmpty()) store.setSecret(name, value) }
        require(next.optString("connection", "ha") in listOf("ha", "mqtt"))
        list(next.optJSONArray("uploaded")).forEach { require(fields.containsKey(it)) }
        val descriptors = JSONObject()
        val selectedHa = (0 until (validated.optJSONArray("tiles")?.length() ?: 0)).flatMap { list(validated.getJSONArray("tiles").getJSONObject(it).optJSONArray("fields")) } +
            (0 until (validated.optJSONArray("overlays")?.length() ?: 0)).map { validated.getJSONArray("overlays").getJSONObject(it).optString("field") }
        selectedHa.filter { HaBinding.parse(it) != null }.distinct().forEach { id ->
            val b = HaBinding.parse(id)!!
            descriptors.put(id,displayFields()[id] ?: HaEntityModel.field(b,null,next.optJSONObject("haFields")?.optJSONObject(id)))
        }
        validated.put("haFields",descriptors)
        if (AdbEndpoint.from(config) != AdbEndpoint.from(validated)) { session.close(); markDisconnected() }
        overlayStyleDraft = null
        config = validated
        store.save(config)
        if (!config.optBoolean("autoSystemAdb") || !autoAdbWasEnabled) restoreSystemAdb()
        localHistory.configure(config)
        store.stopped(false)
        generation++; retry?.cancel(false); retry = null; retrySeconds = 1; pendingFields.clear()
        network.execute { if (secrets.values.any { it.isNotEmpty() }) publisher.close(); publisher.configure(config) }
        ensureRunning(); reconfigure(); publishSelected(); emit()
    }
    private fun wanted(): Set<String> {
        val ids = mutableSetOf<String>()
        if (visible) ids.addAll(previewDemand)
        if ((visible && informationVisible) || config.optBoolean("collect") || config.optBoolean("localHistory",true)) config.optJSONArray("tiles")?.let { tiles ->
            for (i in 0 until tiles.length()) ids.addAll(list(tiles.getJSONObject(i).optJSONArray("fields")))
        }
        if (config.optBoolean("overlayEnabled")) config.optJSONArray("overlays")?.let { modules ->
            for (i in 0 until modules.length()) ids.add(modules.getJSONObject(i).getString("field"))
        }
        if (config.optBoolean("publishEnabled")) ids.addAll(list(config.optJSONArray("uploaded")))
        if (remoteControlEnabled()) {
            ids.add("1032/7/1128267816")
            ids.addAll(EntityCatalog.controls(context).flatMap { list(it.optJSONArray("feedbackFields")) })
        }
        if (visible && ids.any { it.startsWith("control.") }) ids.add("1032/7/1128267816")
        return expandDependencies(EntityCatalog.demand(context,ids),fields)
    }
    fun setVisible(value: Boolean, information: Boolean? = null) {
        if (!value) overlayStyleDraft = null
        val resumed = value && !visible
        if (resumed) appearance.refresh()
        visible = value; if (information != null) informationVisible = information
        reconfigure()
        if (resumed) emit(true)
    }
    fun preview(ids: Set<String>) {
        require(ids.size <= 2048 && ids.all { fields[it]?.optBoolean("displayAllowed") == true || HaBinding.parse(it)?.connection == config.optString("haConnectionId") || EntityCatalog.controls(context).any { entity -> "control."+entity.getString("id") == it } })
        previewDemand = ids
        reconfigure()
    }
    private fun remoteControlEnabled() = if (config.optString("connection", "ha") == "ha") config.optBoolean("haControlEnabled") else config.optBoolean("mqttControlEnabled")
    private fun enabled() = !store.stopped() && (config.optBoolean("haImportEnabled") || (visible && previewDemand.any { it.startsWith("control.") }) || config.optBoolean("collect") || config.optBoolean("overlayEnabled") || config.optBoolean("publishEnabled") || remoteControlEnabled() || (config.optBoolean("localHistory",true) && (config.optJSONArray("tiles")?.length() ?: 0) > 0))
    fun ensureRunning(fromBoot: Boolean = false) {
        if (!enabled()) { main.post { service?.stopSelf() }; return }
        try { context.startForegroundService(Intent(context, RuntimeService::class.java)); runtimeError = null }
        catch (_: Exception) { runtimeError = if (fromBoot) NativeStrings.text_30caebe3f1 else NativeStrings.text_aa00745af5 }
    }
    fun attach(current: Service) { service = current; overlay = OverlayWindow(current,changed = { value -> execute { if (service === current) overlayChanged(value) } }); execute { network.execute { publisher.configure(config) }; reconfigure() } }
    fun detach(current: Service) { if (service === current) { overlay?.close(); overlay = null; service = null; execute { if (!visible) altitude.close(); poll?.cancel(false); poll = null } } }
    private fun registeredFields() = session.registered + if (altitude.subscribed) setOf(GNSS_ALTITUDE) else emptySet()
    fun reconfigure() {
        appearance.setActive(visible || (!store.stopped() && config.optBoolean("overlayEnabled")))
        val appOps = context.getSystemService(android.app.AppOpsManager::class.java)
        if (config.optBoolean("overlayEnabled") && overlayPermissionWatcher == null) {
            val listener = android.app.AppOpsManager.OnOpChangedListener { _, pkg -> if (pkg == context.packageName) execute { emit() } }
            try { appOps.startWatchingMode(android.app.AppOpsManager.OPSTR_SYSTEM_ALERT_WINDOW,context.packageName,listener); overlayPermissionWatcher = listener } catch (_: Throwable) { }
        } else if (!config.optBoolean("overlayEnabled")) releaseOverlayWatcher()
        poll?.cancel(false); poll = null
        val demand = wanted()
        val added = demand - previousDemand
        previousDemand = demand
        val active = !store.stopped() && ((visible && (informationVisible || previewDemand.isNotEmpty())) || enabled())
        val locationWanted = active && GNSS_ALTITUDE in demand
        val locationForeground = (service as? RuntimeService)?.setLocationActive(locationWanted && altitude.permitted) == true
        altitude.configure(locationWanted, visible || locationForeground) { fresh -> execute {
            if (!store.stopped() && GNSS_ALTITUDE in previousDemand) receiveSample(GNSS_ALTITUDE, fresh)
        } }
        session.configure(if (active) demand.filter { it != GNSS_ALTITUDE && !isDerived(it) && HaBinding.parse(it) == null }.toSet() else emptySet(), config.optBoolean("adbEnabled"),
            active && config.optBoolean("overlayEnabled") && (config.optJSONArray("overlays")?.length() ?: 0) > 0, visible && !store.stopped())
        haSource.configure(config, !store.stopped(), demand.filter { HaBinding.parse(it) != null }.toSet())
        haSession.configure(config, enabled() && (config.optBoolean("haImportEnabled") || config.optBoolean("haControlEnabled") || (config.optBoolean("publishEnabled") && list(config.optJSONArray("uploaded")).isNotEmpty())))
        if (enabled() && networkCallback == null) {
            val monitor = object : android.net.ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: android.net.Network) { execute {
                    activeNetwork = network
                    if (enabled()) {
                        haSession.networkAvailable()
                        if (config.optBoolean("publishEnabled")) { readCurrent(); publishSelected() }
                        if (config.optString("connection") == "mqtt") { heartbeat?.cancel(false); heartbeat = null; mqttRetrySeconds = 1; scheduleHeartbeat(0) }
                    }
                } }
                override fun onLost(lostNetwork: android.net.Network) { execute {
                    if (activeNetwork == lostNetwork) { activeNetwork = null; haSession.networkLost(); network.execute { publisher.close() }; emit() }
                } }
            }
            try { context.getSystemService(android.net.ConnectivityManager::class.java).registerDefaultNetworkCallback(monitor); networkCallback = monitor } catch (_: Throwable) { }
        } else if (!enabled()) releaseNetworkMonitor()
        val mqttActive = enabled() && (config.optBoolean("publishEnabled") || config.optBoolean("mqttControlEnabled")) && config.optString("connection", "ha") == "mqtt"
        if (!mqttActive) { heartbeat?.cancel(false); heartbeat = null }
        else if (heartbeat == null && !heartbeatInFlight) scheduleHeartbeat(0)
        if (active) {
            added.filter { it.startsWith("system.") }.forEach { accept(it, reader.read(it)) }
            if (added.any { !it.startsWith("system.") }) readCurrent(added)
            if (config.optBoolean("fallbackPolling") && demand.any { !isDerived(it) && !it.startsWith("system.") && HaBinding.parse(it) == null && it != GNSS_ALTITUDE && it !in registeredFields() }) {
                val captured = generation
                poll = worker.scheduleWithFixedDelay({ if (captured == generation && !store.stopped()) readCurrent(wanted() - registeredFields() - GNSS_ALTITUDE) }, 0, 10, TimeUnit.SECONDS)
            }
        }
        emit()
    }
    private fun scheduleHeartbeat(delay: Long) {
        if (!enabled() || config.optString("connection") != "mqtt" || (!config.optBoolean("publishEnabled") && !config.optBoolean("mqttControlEnabled")) || heartbeatInFlight) return
        heartbeat = worker.schedule({
            heartbeat = null
            heartbeatInFlight = true
            val settings = JSONObject(config.toString())
            val collection = status().put("last_sample_at", samples.values.maxOfOrNull { it.optLong("updatedAt") } ?: JSONObject.NULL)
            val captured = generation
            network.execute {
                val before = publisher.commandSession
                if (captured == generation) publisher.heartbeat(settings, collection, fields)
                val connected = publisher.status == NativeStrings.text_65fe35c45e && before != publisher.commandSession
                execute {
                    if (captured == generation && connected && enabled()) { readCurrent(); publishSelected() }
                    heartbeatInFlight = false; emit()
                    if (publisher.status == NativeStrings.text_65fe35c45e) { mqttRetrySeconds = 1; scheduleHeartbeat(30) }
                    else if (publisher.status !in listOf(NativeStrings.text_2ee717f092, NativeStrings.text_dda97ab7aa, NativeStrings.text_9e94379c10)) {
                        val wait = mqttRetrySeconds; mqttRetrySeconds = (mqttRetrySeconds * 2).coerceAtMost(60); scheduleHeartbeat(wait)
                    }
                }
            }
        }, delay, TimeUnit.SECONDS)
    }
    private fun accept(id: String, fresh: JSONObject): Set<String> {
        val before = samples[id]?.let(::semantic)
        val changed = mutableSetOf<String>()
        resolvePairedUnit(id, fresh, samples, fields)
        stampSampleTimes(fresh, samples[id], sourceEpoch)
        samples[id] = fresh
        if (before != semantic(fresh)) changed.add(id)
        localHistory.append(id, fresh)
        fields.filterValues { it.optString("unitField") == id }.keys.forEach { dependent ->
            samples[dependent]?.takeIf { it.optString("quality") in listOf("available","unverified") && it.has("raw") }?.let {
                changed.addAll(accept(dependent,JSONObject(it.toString()).put("interpretationChangedAt",fresh.optLong("receivedAt",System.currentTimeMillis()))))
            }
        }
        if (id in listOf(BATTERY_VOLTAGE, BATTERY_CURRENT) && BATTERY_POWER in wanted())
            changed.addAll(accept(BATTERY_POWER, batteryPower(samples, sourceEpoch)))
        return changed
    }
    private fun markDisconnected() {
        sourceEpoch++
        samples.keys.filter { it != GNSS_ALTITUDE && !it.startsWith("system.") && HaBinding.parse(it) == null }.toList().forEach { id -> accept(id, JSONObject().put("quality", "disconnected").put("source", id).put("receivedAt", System.currentTimeMillis())) }
    }
    private fun readCurrent(ids: Set<String> = wanted()) {
        val before = samples.mapValues { semantic(it.value) }
        ids.filter { !isDerived(it) && HaBinding.parse(it) == null }.sortedBy { if (fields[it]?.has("unitField") == true) 1 else 0 }.forEach { id ->
            val fresh = if (id == GNSS_ALTITUDE) altitude.read()
            else if (readBlocked && !id.startsWith("system.")) JSONObject().put("quality", "timeout").put("source", id)
            else {
                try {
                    val future = source.submit<JSONObject> { session.read(id) }
                    try { future.get(2, TimeUnit.SECONDS) }
                    catch (_: java.util.concurrent.TimeoutException) { future.cancel(true); source.purge(); readBlocked = true; JSONObject().put("quality", "timeout").put("source", id) }
                } catch (_: java.util.concurrent.RejectedExecutionException) { readBlocked = true; JSONObject().put("quality", "timeout").put("source", id) }
                catch (_: Throwable) { JSONObject().put("quality", "error").put("source", id) }
            }
            accept(id, fresh)
        }
        if (BATTERY_POWER in ids && ids.none { it == BATTERY_VOLTAGE || it == BATTERY_CURRENT })
            accept(BATTERY_POWER, batteryPower(samples, sourceEpoch))
        emit()
        publishControlEntities()
        val changed = samples.filter { before[it.key] != semantic(it.value) }
        if (changed.isNotEmpty()) publishSelected(changed.keys)
    }
    fun auditFields(): JSONObject {
        adaptationAudit = ChannelDiagnostics.audit(fields, source, altitude) { readBlocked = true }
        return diagnostics()
    }
    fun refresh() { readBlocked = false; readCurrent() }
    fun appearanceChanged() { appearance.refresh(); emit() }
    private fun semantic(s: JSONObject) = "${s.opt("value")}|${s.opt("unit")}|${s.optString("quality")}|${s.optString("source")}|${s.optString("transport")}|${s.opt("clientUid")}"
    private var entitiesPublishing = false
    private var entitiesDirty = false
    private var controlRestoreGeneration = 0L
    private var controlRestoreKey: String? = null
    private var controlRestoreAttempts = 0
    private var controlRestoreRetry: ScheduledFuture<*>? = null
    private fun controlConnectionKey() = config.optString("haUrl")+"|"+haSession.entityCommandTopic
    private fun canRestoreControlPublication() = !store.stopped() && config.optString("connection","ha") == "ha" && config.optBoolean("haControlEnabled")
    private fun restoreControlPublication() {
        if (!canRestoreControlPublication()) return
        if (controlRestoreKey == controlConnectionKey()) return
        controlRestoreRetry?.cancel(false); controlRestoreRetry = null
        val captured = ++controlRestoreGeneration
        controlRestoreKey = controlConnectionKey(); controlRestoreAttempts = 0
        network.execute {
            publisher.invalidateControlStates()
            execute { if (captured == controlRestoreGeneration && controlRestoreKey == controlConnectionKey() && canRestoreControlPublication()) publishControlEntities() }
        }
    }
    private fun finishControlRestore(captured: Long, key: String, error: String?) {
        if (captured != controlRestoreGeneration || controlRestoreKey != key || key != controlConnectionKey() || !canRestoreControlPublication()) return
        controlRestoreRetry?.cancel(false); controlRestoreRetry = null
        if (error == null || controlRestoreAttempts >= 3) { controlRestoreKey = null; return }
        val delay = 1L shl controlRestoreAttempts++
        controlRestoreRetry = worker.schedule({
            controlRestoreRetry = null
            if (captured == controlRestoreGeneration && controlRestoreKey == controlConnectionKey() && canRestoreControlPublication()) publishControlEntities()
        }, delay, TimeUnit.SECONDS)
    }
    private fun publishControlEntities() {
        if (config.optString("connection","ha") != "ha" || haSession.entityCommandTopic.isEmpty()) return
        if (entitiesPublishing) { entitiesDirty = true; return }
        val settings = JSONObject(config.toString())
        val snapshot = samples.mapValues { JSONObject(it.value.toString()) }
        val topic = haSession.entityCommandTopic
        val online = !store.stopped() && haSession.entitySubscription
        val restoration = controlRestoreGeneration
        val key = controlConnectionKey()
        entitiesPublishing = true
        network.execute {
            val error = try { publisher.publishControlEntities(settings,snapshot,topic,online); null } catch (error: Throwable) { error.javaClass.simpleName }
            execute {
                entitiesPublishing = false
                if (error != null) commandError = error
                finishControlRestore(restoration,key,error)
                if (entitiesDirty) { entitiesDirty = false; publishControlEntities() }
            }
        }
    }
    private fun publishSelected(changed: Set<String>? = null) {
        if (!config.optBoolean("publishEnabled") || store.stopped()) return
        val selected = list(config.optJSONArray("uploaded")).toSet()
        if (changed != null) pendingFields.addAll(changed.intersect(selected))
        else pendingFields.addAll(selected)
        if (publishInFlight) return
        val batch = samples.filterKeys { it in selected && it in pendingFields }.mapValues { JSONObject(it.value.toString()) }
        if (batch.isEmpty()) return
        val captured = generation
        val settings = JSONObject(config.toString())
        publishInFlight = true
        network.execute {
            if (captured != generation) { execute { publishInFlight = false; publishSelected(emptySet()) }; return@execute }
            publisher.publish(settings, batch, fields) { captured == generation }
            execute {
                publishInFlight = false
                if (captured != generation) { publishSelected(emptySet()); return@execute }
                if (publisher.status == NativeStrings.text_65fe35c45e) {
                    if (config.optBoolean("mqttState")) {
                        val full = samples.filterKeys { it in selected }.mapValues { JSONObject(it.value.toString()) }
                        network.execute { if (captured == generation) publisher.publishState(settings, full, fields) }
                    }
                    for ((id, sent) in batch) if (samples[id]?.let { semantic(it) } == semantic(sent)) pendingFields.remove(id)
                    retrySeconds = 1
                    retry?.cancel(false); retry = null
                    if (pendingFields.isNotEmpty()) publishSelected(emptySet())
                } else if (publisher.status !in listOf(NativeStrings.text_dda97ab7aa, NativeStrings.text_2ee717f092, NativeStrings.text_9e94379c10) && retry == null) {
                    retry = worker.schedule({ retry = null; publishSelected(emptySet()) }, retrySeconds * 1000 + (0..500).random(), TimeUnit.MILLISECONDS)
                    retrySeconds = (retrySeconds * 2).coerceAtMost(60)
                }
                emit()
            }
        }
    }
    fun checkConnection(callback: (JSONObject) -> Unit) {
        network.execute { publisher.configure(config); publisher.check(); execute { callback(status()); emit() } }
    }
    fun history(id: String, minutes: Int, callback: (JSONObject) -> Unit) {
        require(displayFields().containsKey(id))
        val field = JSONObject(displayFields().getValue(id).toString())
        if (field.has("unitField")) field.put("unit",samples[id]?.optString("unit") ?: "")
        callback(localHistory.query(id, minutes.coerceIn(1, 1440), field))
    }
    private fun releaseOverlayWatcher() {
        overlayPermissionWatcher?.let { context.getSystemService(android.app.AppOpsManager::class.java).stopWatchingMode(it) }
        overlayPermissionWatcher = null
    }
    private fun releaseNetworkMonitor() {
        networkCallback?.let { try { context.getSystemService(android.net.ConnectivityManager::class.java).unregisterNetworkCallback(it) } catch (_: Throwable) { } }; networkCallback = null
    }
    fun diagnostics(): JSONObject = JSONObject().put("app_version", context.packageManager.getPackageInfo(context.packageName,0).versionName).put("android", android.os.Build.VERSION.RELEASE)
        .put("channel",BuildConfig.FLAVOR).put("build_type",BuildConfig.BUILD_TYPE)
        .put("uid",android.os.Process.myUid()).put("status",status()).put("demand_fields",wanted().size)
        .put("registered_fields",registeredFields().size).put("cached_fields",samples.size).put("local_history_storage",localHistory.storageStats())
        .put("quality_counts",JSONObject(samples.values.groupingBy { it.optString("quality") }.eachCount()))
        .put("adaptation_audit",adaptationAudit ?: JSONObject.NULL)
        .put("last_command",lastCommand ?: JSONObject.NULL)
        .put("ha_control_enabled",config.optBoolean("haControlEnabled")).put("mqtt_control_enabled",config.optBoolean("mqttControlEnabled")).put("pending_command_receipts",receipts.size)
        .put("ha_entity_subscription",haSession.entitySubscription).put("ha_import_state",haSource.state)
        .put("ha_command_subscription",haSession.commandSubscription).put("ha_command_events",haSession.commandEvents)
        .put("ha_session",haSession.sessionState).put("command_error",commandError ?: JSONObject.NULL)
        .put("read_transports",JSONObject(samples.values.groupingBy { it.optString("transport", if (it.optString("source").startsWith("system.")) "system" else "unknown") }.eachCount()))
        .put("subscription_identity",session.identity).put("adb_bridge",session.bindingState).put("status_strip",session.overlayState)
        .put("last_valid_received_at",samples.values.maxOfOrNull { it.optLong("updatedAt") } ?: JSONObject.NULL)
        .put("pending_publish_fields",pendingFields.size).put("native_heap_bytes",android.os.Debug.getNativeHeapAllocatedSize())
    fun clearCredentials() { store.clearSecrets(); save(JSONObject(config.toString()).put("publishEnabled",false).put("haImportEnabled",false).put("haControlEnabled",false).put("mqttControlEnabled",false), emptyMap()) }
    fun clearHistory() { localHistory.clear(); localHistory.configure(config) }
    fun applicationStarted() {
        appearance.refresh()
        config = applicationStartConfig(config)
        store.save(config)
        restoreSystemAdb()
        visible = true
        resume()
    }
    private fun restoreSystemAdb() {
        systemAdbResult = systemAdbSettings.restore(config.optBoolean("autoSystemAdb"))
        if (!config.optBoolean("autoSystemAdb") || session.adbState != "connected") return
        if (systemAdbResult.optString("state") == "enabled" && systemAdbResult.optBoolean("appPermission")) return
        try { session.restoreAdbSettings()?.let { systemAdbResult = it } }
        catch (_: Exception) { systemAdbResult.put("bridgeFailure", true) }
    }
    fun setOverlayEnabled(enabled: Boolean) {
        save(JSONObject(config.toString()).put("overlayEnabled", enabled && Settings.canDrawOverlays(context)), emptyMap())
    }
    fun resume() {
        store.stopped(false); readBlocked = false; previousDemand = emptySet(); generation++
        retry?.cancel(false); retry = null; retrySeconds = 1; pendingFields.clear()
        ensureRunning(); reconfigure(); publishSelected()
    }
    fun stop() {
        appearance.setActive(visible)
        controlRestoreGeneration++; controlRestoreKey = null; controlRestoreRetry?.cancel(false); controlRestoreRetry = null
        store.stopped(true); altitude.close(); (service as? RuntimeService)?.setLocationActive(false); publishControlEntities(); receipts.clear(); receiptRetry?.cancel(false); receiptRetry = null; haSession.close(); releaseOverlayWatcher(); releaseNetworkMonitor(); heartbeat?.cancel(false); heartbeat = null; session.close(); callbackFlush?.cancel(false); callbackFlush = null; callbackChanged.clear(); generation++; poll?.cancel(false); poll = null; retry?.cancel(false); retry = null; pendingFields.clear()
        markDisconnected()
        val captured = generation
        val settings = JSONObject(config.toString())
        val selected = list(settings.optJSONArray("uploaded")).toSet()
        val unavailable = samples.filterKeys { it in selected }.mapValues { JSONObject(it.value.toString()) }
        network.execute {
            if (settings.optString("connection","ha") == "ha" && settings.optBoolean("publishEnabled") && unavailable.isNotEmpty())
                publisher.publish(settings,unavailable,fields) { captured == generation && store.stopped() }
            publisher.close()
        }
        main.post { overlay?.close(); service?.stopSelf() }
        previousDemand = emptySet(); emit()
    }
    companion object {
        @Volatile private var instance: RuntimeCoordinator? = null
        fun get(context: Context): RuntimeCoordinator = instance ?: synchronized(this) { instance ?: RuntimeCoordinator(context).also { instance = it } }
        fun list(array: JSONArray?): List<String> = if (array == null) emptyList() else (0 until array.length()).map(array::getString)
        fun jsonMap(json: JSONObject): Map<String, Any?> = json.keys().asSequence().associateWith { key -> convert(json.get(key)) }
        private fun convert(value: Any?): Any? = when (value) {
            JSONObject.NULL -> null
            is JSONObject -> jsonMap(value)
            is JSONArray -> (0 until value.length()).map { convert(value.get(it)) }
            else -> value
        }
    }
}
