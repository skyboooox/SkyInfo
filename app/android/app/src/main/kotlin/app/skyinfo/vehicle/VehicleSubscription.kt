package app.skyinfo.vehicle

import android.content.Context
import java.lang.reflect.Proxy
import org.json.JSONObject

class VehicleSubscription(private val context: Context, private val reader: ReadOnlyVehicle) {
    private var manager: Any? = null
    private var listener: Any? = null
    private var listenerType: Class<*>? = null
    private var devices = setOf<Int>()
    @Volatile private var requested = setOf<String>()
    var registered = setOf<String>()
        private set
    fun configure(ids: Set<String>, sample: (String, JSONObject) -> Unit, status: (String) -> Unit): String {
        if (ids == requested && listener != null) return NativeStrings.text("native_subscription_pending",mapOf("count" to registered.size))
        close()
        if (ids.isEmpty()) return NativeStrings.text_8bb38ef00c
        return try {
            val type = Class.forName("android.hardware.BYDAutoManager")
            val observer = Class.forName("android.hardware.BYDAutoManager\$OnBYDAutoListener")
            val instance = manager ?: type.getConstructor(Context::class.java).newInstance(context)
            requested = ids
            val proxy = Proxy.newProxyInstance(observer.classLoader, arrayOf(observer)) { self, method, args ->
                when (method.name) {
                    "equals" -> self === args?.get(0)
                    "hashCode" -> System.identityHashCode(self)
                    "toString" -> "SkyInfoVehicleObserver"
                    "onChanged" -> {
                        if (args != null && args.size >= 3 && args[2] is Number) {
                            val tx = if (args[2] is Float) 7 else 5
                            val id = "${args[0]}/$tx/${args[1]}"
                            if (id in requested) sample(id, reader.fromRaw(id, args[2]).put("transport", "sdk_callback").put("clientUid",android.os.Process.myUid()))
                        }
                        null
                    }
                    "onError" -> { status(NativeStrings.text_7ca3d143c0); null }
                    else -> null
                }
            }
            manager = instance; listener = proxy; listenerType = observer
            type.getMethod("registerListener", observer).invoke(instance, proxy)
            val grouped = ids.filter { !it.startsWith("system.") }.groupBy { it.split('/')[0].toInt() }
            val enabled = mutableSetOf<String>()
            val enabledDevices = mutableSetOf<Int>()
            for ((device, fields) in grouped) {
                val features = fields.map { it.split('/')[2].toInt() }.distinct().toIntArray()
                val result = type.getMethod("enableDevice", Int::class.javaPrimitiveType, IntArray::class.java).invoke(instance, device, features) as Int
                if (result == 0) { enabled.addAll(fields); enabledDevices.add(device); devices = enabledDevices.toSet() }
            }
            devices = enabledDevices; registered = enabled
            if (enabled.isEmpty()) { close(); NativeStrings.text_c4a117419b } else NativeStrings.text("native_subscription_pending",mapOf("count" to enabled.size))
        } catch (error: Throwable) {
            val cause = error.cause ?: error
            android.util.Log.w("SkyInfo.Vehicle", "SDK subscription unavailable", cause)
            close(); NativeStrings.text("native_sdk_subscription_error",mapOf("error" to cause.javaClass.simpleName))
        }
    }
    fun close() {
        requested = emptySet(); registered = emptySet()
        val current = manager
        if (current != null) {
            for (device in devices) try { current.javaClass.getMethod("disableDevice", Int::class.javaPrimitiveType).invoke(current, device) } catch (_: Throwable) { }
            val proxy = listener; val type = listenerType
            if (proxy != null && type != null) try { current.javaClass.getMethod("unregisterListener", type).invoke(current, proxy) } catch (_: Throwable) { }
        }
        devices = emptySet(); listener = null; listenerType = null
    }
}
