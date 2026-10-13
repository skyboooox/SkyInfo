package app.skyinfo.vehicle

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import org.json.JSONObject

class VehicleSession(
    private val context: Context,
    private val reader: ReadOnlyVehicle,
    private val dispatch: (() -> Unit) -> Unit,
    private val sample: (String, JSONObject) -> Unit,
    private val changed: () -> Unit,
    private val lost: () -> Unit,
    private val overlayChanged: (JSONObject) -> Unit = {}
) {
    private val main = Handler(Looper.getMainLooper())
    private val ordinary = VehicleSubscription(context, reader)
    private var remote: IVehicleSource? = null
    private var bridge: ShellVehicleBridge? = null
    private var binding = false
    private var retryAt = 0L
    private var retryDelay = 1000L
    private var retryTask: Runnable? = null
    private var wanted = setOf<String>()
    private var keepOverlay = false
    private var keepConnection = false
    private var configured = setOf<String>()
    private var sequence = 0L
    private val callbacks = mutableSetOf<String>()
    var registered = setOf<String>()
        private set
    var bindingState = NativeStrings.text_8bb38ef00c
        private set
    var overlayState = NativeStrings.text_8bb38ef00c
        private set
    var state = NativeStrings.text_8bb38ef00c
        private set
    var identity = NativeStrings.text("native_app_identity",mapOf("uid" to android.os.Process.myUid()))
        private set
    var adbState = "disabled"
        private set
    private fun connected(created: ShellVehicleBridge) {
        dispatch {
            if (bridge !== created || !binding || (wanted.isEmpty() && !keepOverlay && !keepConnection)) { created.close(); return@dispatch }
            remote = created
            binding = false; configured = emptySet(); sequence++; callbacks.clear()
            ordinary.close(); registered = emptySet()
            try {
                val who = JSONObject(created.identity())
                identity = NativeStrings.text("native_adb_identity", mapOf("uid" to who.getInt("uid")))
                adbState = "connected"
                bindingState = NativeStrings.text_65fe35c45e; retryAt = 0; retryDelay = 1000; retryTask?.let(main::removeCallbacks); retryTask = null
                configure(wanted, true, keepOverlay, keepConnection)
            } catch (_: Throwable) { adbState = "error"; failed(NativeStrings.text_42d2e51d37) }
            changed()
        }
    }
    fun controls(): JSONObject = remote?.let { JSONObject(it.controls()) } ?: JSONObject().put("error","bridge_unavailable")
    fun control(action: String, value: Int): JSONObject = remote?.let { JSONObject(it.control(action,value)) } ?: JSONObject().put("status","bridge_unavailable")
    fun configure(ids: Set<String>, granted: Boolean, overlayRequired: Boolean = false, connectionRequired: Boolean = false) {
        keepConnection = connectionRequired && granted
        keepOverlay = overlayRequired && granted
        wanted = ids.filter { !it.startsWith("system.") }.toSet()
        if (wanted.isEmpty() && !keepOverlay && !keepConnection) { close(); return }
        if (!granted && (remote != null || binding)) close()
        keepOverlay = overlayRequired && granted
        wanted = ids.filter { !it.startsWith("system.") }.toSet()
        if (granted && remote == null && !binding && SystemClock.elapsedRealtime() >= retryAt) {
            binding = true; bindingState = NativeStrings.text("adb_status_connecting"); state = bindingState
            retryTask?.let(main::removeCallbacks)
            retryTask = Runnable { dispatch { retryTask = null; if (binding) { adbState = "timeout"; failed(NativeStrings.text_4e0a818e1c) } } }
            main.postDelayed(retryTask!!, 15000)
            adbState = "connecting"
            lateinit var created: ShellVehicleBridge
            created = ShellVehicleBridge(context, disconnected = { dispatch { if (bridge === created) {
                adbState = "disconnected"; failed(NativeStrings.text_e4a0178fb2); lost()
            } } }, overlayChanged = { state -> dispatch { if (bridge === created && remote === created) overlayChanged(state) } })
            bridge = created
            created.start({ connected(created) }, { error -> dispatch { if (bridge === created) {
                adbState = adbFailure(error); failed(NativeStrings.text("adb_status_" + adbState))
            } } })
        }
        if (configured == wanted) return
        configured = wanted; callbacks.clear(); sequence++
        val captured = sequence
        val sink = object : IVehicleSink.Stub() {
            override fun onSample(id: String, json: String) { dispatch {
                if (captured == sequence && id in wanted) {
                    callbacks.add(id); state = NativeStrings.text("native_subscription_count",mapOf("registered" to registered.size,"callbacks" to callbacks.size))
                    sample(id, JSONObject(json))
                }
            } }
            override fun onStatus(value: String) { dispatch { if (captured == sequence) { state = value; if (value == NativeStrings.text_7ca3d143c0) lost(); changed() } } }
        }
        try {
            val bound = remote
            if (bound != null) {
                val response = JSONObject(bound.subscribe(wanted.toTypedArray(), sink))
                state = response.getString("state")
                registered = RuntimeCoordinator.list(response.optJSONArray("registered")).toSet()
            } else {
                state = ordinary.configure(wanted, { id, fresh -> dispatch { if (captured == sequence && id in wanted) { callbacks.add(id); state = NativeStrings.text("native_subscription_count",mapOf("registered" to registered.size,"callbacks" to callbacks.size)); sample(id, fresh) } } },
                    { value -> dispatch { if (captured == sequence) { state = value; if (value == NativeStrings.text_7ca3d143c0) lost(); changed() } } })
                registered = ordinary.registered
            }
        } catch (_: Throwable) { registered = emptySet(); state = NativeStrings.text_c4a117419b }
    }
    private fun failed(message: String) {
        bridge?.close(); bridge = null
        remote = null; binding = false; configured = emptySet(); callbacks.clear(); registered = emptySet(); sequence++
        state = message; bindingState = message
        retryAt = SystemClock.elapsedRealtime() + retryDelay
        retryTask?.let(main::removeCallbacks)
        retryTask = Runnable { dispatch { retryTask = null; if (wanted.isNotEmpty() || keepOverlay || keepConnection) changed() } }
        main.postDelayed(retryTask!!, retryDelay)
        retryDelay = (retryDelay * 2).coerceAtMost(60000)
        changed()
    }
    fun read(id: String): JSONObject = remote?.read(id)?.let(::JSONObject) ?: reader.read(id)
    fun editOverlay(): Boolean = try { bridge?.takeIf { remote === it }?.editOverlay() ?: false } catch (_: Throwable) { false }
    fun overlay(config: JSONObject, samples: Map<String,JSONObject>): Boolean {
        val current = bridge ?: return false
        if (remote !== current) return false
        return try {
            val result = current.overlay(config,samples)
            overlayState = if (result.optBoolean("visible")) NativeStrings.text_f8de3e1ac7 else if (!result.isNull("error")) result.getString("error") else NativeStrings.text_8bb38ef00c
            !config.optBoolean("overlayEnabled") || result.optBoolean("visible")
        } catch (error: Throwable) { overlayState = error.javaClass.simpleName; false }
    }
    fun close() {
        retryTask?.let(main::removeCallbacks); retryTask = null; retryAt = 0; retryDelay = 1000; bindingState = NativeStrings.text_8bb38ef00c
        sequence++; ordinary.close()
        try { remote?.cancel() } catch (_: Throwable) { }
        bridge?.close(); bridge = null
        adbState = "disabled"
        remote = null; binding = false; keepOverlay = false; keepConnection = false; wanted = emptySet(); configured = emptySet(); registered = emptySet(); callbacks.clear(); state = NativeStrings.text_8bb38ef00c
    }
}

internal fun adbFailure(error: Throwable): String = when {
    error is io.github.muntashirakon.adb.AdbPairingRequiredException -> "pair_required"
    error.message == "adb_authorization_required" -> "authorization"
    error.message == "adb_other_device" -> "other_device"
    error is java.net.SocketTimeoutException -> "timeout"
    error is java.net.ConnectException || error is java.net.UnknownHostException -> "unreachable"
    else -> "error"
}
