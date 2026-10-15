package app.skyinfo.vehicle

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

class ShellVehicleBridge(private val context: Context, private val disconnected: () -> Unit,
    private val launch: (Array<String>,Array<String>) -> Process = { command, environment ->
        NetworkAdb(context, AdbEndpoint.from(SecureConfig(context).load())).launch(command, environment)
    }, private val overlayChanged: (JSONObject) -> Unit = {}) : IVehicleSource.Stub() {
    private var process: Process? = null
    private var writer: java.io.BufferedWriter? = null
    private val pending = ConcurrentHashMap<Long,CompletableFuture<JSONObject>>()
    private val sequence = AtomicLong()
    @Volatile private var sink: IVehicleSink? = null
    @Volatile private var closed = false
    fun start(connected: () -> Unit, failed: (Throwable) -> Unit) {
        try { NetworkAdb.operations.execute {
            try {
                if (closed) return@execute
                val user = android.os.Process.myUid() / 100000
                val command = arrayOf("/system/bin/app_process","/system/bin","--nice-name=app.skyinfo.vehicle:bridge",ShellVehicleMain::class.java.name,user.toString(),android.os.Process.myPid().toString())
                val environment = mutableListOf("CLASSPATH=${context.applicationInfo.sourceDir}")
                val launched = launch(command,environment.toTypedArray())
                synchronized(this) { if (closed) { launched.destroy(); return@execute }; process = launched; writer = launched.outputStream.bufferedWriter() }
                Thread {
                    try { launched.inputStream.bufferedReader().useLines { lines -> lines.forEach { line ->
                        if (line.length > 512*1024 || !line.startsWith('{')) return@forEach
                        val message = try { JSONObject(line) } catch (_: Throwable) { return@forEach }
                        if (message.has("request")) pending.remove(message.getLong("request"))?.complete(message)
                        else when(message.optString("event")) {
                            "sample" -> sink?.onSample(message.getString("field"),message.getJSONObject("sample").toString())
                            "status" -> sink?.onStatus(message.getString("state"))
                            "overlay" -> overlayChanged(message.getJSONObject("value"))
                        }
                    } } } catch (_: Throwable) { }
                    finally { val notify = !closed; close(); if (notify) disconnected() }
                }.apply { name = "SkyInfo-readonly-events"; start() }
                Thread { try { launched.errorStream.bufferedReader().useLines { lines -> lines.forEach { line ->
                    android.util.Log.w("SkyInfo.Vehicle","Readonly bridge stderr: ${line.take(2048)}")
                } } } catch (_: Throwable) {} }.apply { name = "SkyInfo-readonly-stderr"; start() }
                identity()
                if (!closed) connected()
            } catch (error: Throwable) { android.util.Log.w("SkyInfo.Vehicle","Readonly bridge startup failed",error); close(); failed(error) }
        } } catch (error: java.util.concurrent.RejectedExecutionException) { failed(error) }
    }
    private fun request(op: String, body: JSONObject = JSONObject()): JSONObject {
        val id = sequence.incrementAndGet()
        val future = CompletableFuture<JSONObject>()
        pending[id] = future
        try {
            val line = body.put("op",op).put("request",id).toString()
            require(line.length <= 512*1024) { "Bridge request too large" }
            synchronized(this) { check(!closed); val output = checkNotNull(writer); output.write(line); output.newLine(); output.flush() }
            val response = future.get(if (op == "restoreAdbSettings") 5 else if (op == "control") 4 else 3,TimeUnit.SECONDS)
            check(!response.has("error")) { response.optString("error") }
            return response.getJSONObject("result")
        } finally { pending.remove(id) }
    }
    override fun identity(): String = request("identity").toString()
    override fun read(id: String): String = request("read",JSONObject().put("field",id)).toString()
    override fun controls(): String = request("controls").toString()
    override fun control(action: String, value: Int): String = request("control",JSONObject().put("action",action).put("value",value)).toString()
    override fun subscribe(ids: Array<out String>, sink: IVehicleSink): String {
        this.sink = sink
        return request("subscribe",JSONObject().put("fields",JSONArray(ids))).toString()
    }
    override fun cancel() { sink = null; request("cancel") }
    override fun destroy() { close() }
    fun overlay(config: JSONObject, samples: Map<String,JSONObject>): JSONObject {
        return request("overlay",overlayRequest(config,samples))
    }
    fun resetOverlayPosition(): Boolean = request("overlayReset").optBoolean("reset")
    fun editOverlay(): Boolean = request("overlayEdit").optBoolean("editing")
    fun restoreAdbSettings(): JSONObject = request("restoreAdbSettings")
    @Synchronized fun close() {
        if (closed) return
        closed = true; sink = null
        try { writer?.close() } catch (_: Throwable) {}
        writer = null
        val child = process; process = null
        if (child != null) Thread {
            try { child.waitFor(3,TimeUnit.SECONDS) } catch (_: Throwable) { }
            finally { child.destroy() }
        }.apply { name = "SkyInfo-readonly-close"; isDaemon = true; start() }
        pending.values.forEach { it.completeExceptionally(IllegalStateException("Readonly bridge disconnected")) }; pending.clear()
    }
}
