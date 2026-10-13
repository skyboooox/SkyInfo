package app.skyinfo.vehicle

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.UserHandle
import org.json.JSONArray
import org.json.JSONObject

object ShellVehicleMain {
    @JvmStatic fun main(args: Array<String>) {
        require(args.size == 2)
        val user = args[0].toInt()
        val owner = args[1].toInt()
        require(user >= 0 && owner > 0)
        try { android.graphics.Typeface::class.java.getMethod("setSystemFontMap",android.os.SharedMemory::class.java).invoke(null,null) } catch (_: NoSuchMethodException) { }
        Looper.prepareMainLooper()
        val thread = Class.forName("android.app.ActivityThread").getMethod("systemMain").invoke(null)
        val system = thread.javaClass.getMethod("getSystemContext").invoke(thread) as Context
        val handle = UserHandle::class.java.getConstructor(Int::class.javaPrimitiveType).newInstance(user)
        val context = Context::class.java.getMethod("createPackageContextAsUser",String::class.java,Int::class.javaPrimitiveType,UserHandle::class.java)
            .invoke(system,"app.skyinfo.vehicle",Context.CONTEXT_INCLUDE_CODE or Context.CONTEXT_IGNORE_SECURITY,handle) as Context
        val fields = EntityCatalog.fields(context)
        val reader = ReadOnlyVehicle(fields)
        val observer = VehicleSubscription(context,reader)
        val controls by lazy { VehicleControls(context) }
        fun send(message: JSONObject) { synchronized(System.out) { System.out.println(message.toString()); System.out.flush() } }
        val display = context.getSystemService(android.hardware.display.DisplayManager::class.java).getDisplay(0)
        val overlay = OverlayWindow(context.createDisplayContext(display),true) { state -> send(JSONObject().put("event","overlay").put("value",state)) }
        val main = Handler(Looper.getMainLooper())
        Thread {
            while (java.io.File("/proc/$owner").exists()) Thread.sleep(10000)
            observer.close(); main.post { overlay.close(); kotlin.system.exitProcess(0) }
        }.apply { name = "SkyInfo-readonly-owner"; isDaemon = true; start() }
        Thread {
            try {
                System.`in`.bufferedReader().useLines { lines -> lines.forEach { line ->
                    require(line.length <= 512*1024)
                    val command = JSONObject(line)
                    val request = command.getLong("request")
                    try {
                        val result = when(command.getString("op")) {
                            "identity" -> JSONObject().put("uid",Process.myUid()).put("pid",Process.myPid()).put("backend","shell_bridge")
                            "read" -> reader.read(command.getString("field"))
                            "controls" -> controls.snapshot()
                            "control" -> controls.execute(command.getString("action"),command.getInt("value"))
                            "subscribe" -> {
                                val ids = RuntimeCoordinator.list(command.getJSONArray("fields")).toSet()
                                require(ids.size <= fields.size && ids.all(fields::containsKey))
                                val state = observer.configure(ids,
                                    { id, sample -> send(JSONObject().put("event","sample").put("field",id).put("sample",sample)) },
                                    { state -> send(JSONObject().put("event","status").put("state",state)) })
                                JSONObject().put("state",state).put("registered",JSONArray(observer.registered.toList()))
                            }
                            "cancel" -> { observer.close(); JSONObject() }
                            "overlayEdit" -> {
                                val result = java.util.concurrent.CompletableFuture<Boolean>()
                                main.post { result.complete(overlay.arm()) }
                                JSONObject().put("editing",result.get(2,java.util.concurrent.TimeUnit.SECONDS))
                            }
                            "overlay" -> {
                                val config = command.getJSONObject("config")
                                val raw = command.getJSONObject("samples")
                                val displayFields = fields + (config.optJSONObject("haFields") ?: JSONObject()).let { ha -> ha.keys().asSequence().associateWith { ha.getJSONObject(it) } }
                                val samples = raw.keys().asSequence().filter(displayFields::containsKey).associateWith(raw::getJSONObject)
                                val result = java.util.concurrent.CompletableFuture<JSONObject>()
                                main.post {
                                    try { overlay.update(config,displayFields,samples); result.complete(JSONObject().put("visible",overlay.visible).put("error",overlay.failure ?: JSONObject.NULL)) }
                                    catch (error: Throwable) { overlay.close(); result.complete(JSONObject().put("visible",false).put("error",error.javaClass.simpleName)); android.util.Log.w("SkyInfo.Vehicle","Bridge status strip failed",error) }
                                }
                                result.get(2,java.util.concurrent.TimeUnit.SECONDS)
                            }
                            "stop" -> { observer.close(); main.post { overlay.close(); kotlin.system.exitProcess(0) }; JSONObject() }
                            else -> throw IllegalArgumentException("Unsupported operation")
                        }
                        send(JSONObject().put("request",request).put("result",result))
                    } catch (error: Throwable) { send(JSONObject().put("request",request).put("error",error.javaClass.simpleName)) }
                } }
            } finally { observer.close(); main.post { overlay.close(); kotlin.system.exitProcess(0) } }
        }.apply { name = "SkyInfo-readonly-commands"; start() }
        Looper.loop()
    }
}
