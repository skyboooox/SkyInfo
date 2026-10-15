package app.skyinfo.vehicle

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.ByteArrayInputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class ShellVehicleBridgeTest {
    private val id = "1032/7/1128267816"
    private class Channel : InputStream() {
        private val bytes = LinkedBlockingQueue<Int>()
        @Volatile private var ended = false
        override fun read(): Int = if (ended && bytes.isEmpty()) -1 else bytes.take()
        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
            if (length == 0) return 0
            val first = read()
            if (first < 0) return -1
            buffer[offset] = first.toByte()
            var count = 1
            while (count < length) {
                val next = bytes.poll() ?: break
                if (next < 0) break
                buffer[offset + count++] = next.toByte()
            }
            return count
        }
        override fun close() { ended = true; bytes.offer(-1) }
        val output = object : OutputStream() {
            override fun write(value: Int) { check(!ended); bytes.offer(value and 255) }
            override fun close() { this@Channel.close() }
        }
    }
    private class Child : Process() {
        private val incoming = Channel()
        private val input = incoming.output
        private val outgoing = Channel()
        private val output = outgoing.output
        val messages = LinkedBlockingQueue<JSONObject>()
        @Volatile var destroyed = false
        val terminated = CountDownLatch(1)
        @Volatile var holdReads = false
        init {
            Thread {
                try { incoming.bufferedReader().useLines { lines -> lines.forEach { line ->
                    val command = JSONObject(line); messages.offer(command)
                    val result = when(command.getString("op")) {
                        "identity" -> JSONObject().put("uid",2000).put("backend","shell_bridge")
                        "subscribe" -> JSONObject().put("state","registered").put("registered",command.getJSONArray("fields"))
                        "read" -> JSONObject().put("value",13.7).put("quality","available")
                        "overlay" -> JSONObject().put("visible",true)
                        "restoreAdbSettings" -> JSONObject().put("state","enabled").put("appPermission",true)
                        else -> JSONObject()
                    }
                    if (command.getString("op") != "read" || !holdReads) {
                        output.write((JSONObject().put("request",command.getLong("request")).put("result",result).toString()+"\n").toByteArray()); output.flush()
                    }
                } } } catch (_: Throwable) { }
            }.apply { isDaemon = true; start() }
        }
        override fun getOutputStream() = input
        override fun getInputStream() = outgoing
        override fun getErrorStream() = ByteArrayInputStream(byteArrayOf())
        override fun waitFor() = 0
        override fun exitValue() = 0
        override fun destroy() { destroyed = true; input.close(); output.close(); terminated.countDown() }
    }
    @Test fun launchesOnlyPackagedBridgeAndOmitsConnectionSecrets() {
        val child = Child()
        val ready = CountDownLatch(1)
        val context = RuntimeEnvironment.getApplication()
        val bridge = ShellVehicleBridge(context,{}, { command, environment ->
            assertEquals("/system/bin/app_process",command.first())
            assertEquals("app.skyinfo.vehicle.ShellVehicleMain",command[3])
            assertEquals((android.os.Process.myUid()/100000).toString(),command[4])
            assertEquals("CLASSPATH=${context.applicationInfo.sourceDir}",environment.first())
            assertTrue(environment.all { it.substringBefore('=') in setOf("CLASSPATH","ANDROID_ROOT","ANDROID_DATA","ANDROID_ART_ROOT","ANDROID_I18N_ROOT","ANDROID_TZDATA_ROOT","BOOTCLASSPATH","DEX2OATBOOTCLASSPATH","SYSTEMSERVERCLASSPATH","LD_LIBRARY_PATH") })
            child
        })
        try {
            bridge.start({ ready.countDown() },{})
            assertTrue(ready.await(5,TimeUnit.SECONDS))
            val sink = object : IVehicleSink.Stub() { override fun onSample(id: String,json: String) {} ; override fun onStatus(value: String) {} }
            assertEquals(id,JSONObject(bridge.subscribe(arrayOf(id),sink)).getJSONArray("registered").getString(0))
            assertEquals(13.7,JSONObject(bridge.read(id)).getDouble("value"),0.001)
            bridge.overlay(JSONObject().put("overlayEnabled",true).put("overlays",JSONArray()).put("haToken","must-not-leave-app").put("mqttPassword","must-not-leave-app").put("uploaded",JSONArray(listOf(id))),emptyMap())
            val commands = mutableListOf<JSONObject>(); child.messages.drainTo(commands)
            val config = commands.single { it.optString("op") == "overlay" }.getJSONObject("config")
            assertFalse(config.has("haToken")); assertFalse(config.has("mqttPassword")); assertFalse(config.has("uploaded"))
        } finally { bridge.close() }
        assertTrue(child.terminated.await(4,TimeUnit.SECONDS)); assertTrue(child.destroyed)
    }
    @Test fun closingBridgeReleasesAnOutstandingRead() {
        val child = Child(); child.holdReads = true
        val ready = CountDownLatch(1); val released = CountDownLatch(1)
        val succeeded = java.util.concurrent.atomic.AtomicBoolean(false)
        val bridge = ShellVehicleBridge(RuntimeEnvironment.getApplication(),{}, { _,_ -> child })
        bridge.start({ ready.countDown() },{})
        assertTrue(ready.await(5,TimeUnit.SECONDS))
        Thread { try { bridge.read(id); succeeded.set(true) } catch (_: Exception) { } finally { released.countDown() } }.start()
        assertEquals("identity",child.messages.poll(5,TimeUnit.SECONDS)?.optString("op"))
        assertEquals("read",child.messages.poll(5,TimeUnit.SECONDS)?.optString("op"))
        bridge.close()
        assertTrue(released.await(1,TimeUnit.SECONDS)); assertFalse(succeeded.get()); assertTrue(child.terminated.await(4,TimeUnit.SECONDS)); assertTrue(child.destroyed)
    }
    @Test fun oversizedOverlayIsRejectedBeforeWritingAndBridgeRemainsUsable() {
        val child = Child(); val ready = CountDownLatch(1)
        val bridge = ShellVehicleBridge(RuntimeEnvironment.getApplication(),{}, { _,_ -> child })
        try {
            bridge.start({ ready.countDown() },{})
            assertTrue(ready.await(5,TimeUnit.SECONDS))
            val config = JSONObject().put("overlayEnabled",true).put("overlays",JSONArray().put(JSONObject().put("field",id)))
            assertTrue(runCatching { bridge.overlay(config,mapOf(id to JSONObject().put("value","x".repeat(513*1024)))) }.isFailure)
            assertEquals(2000,JSONObject(bridge.identity()).getInt("uid"))
            val commands = mutableListOf<JSONObject>(); child.messages.drainTo(commands)
            assertFalse(commands.any { it.optString("op") == "overlay" })
        } finally { bridge.close() }
        assertTrue(child.terminated.await(4,TimeUnit.SECONDS))
    }
    @Test fun systemSettingsRecoveryUsesOnlyTheFixedBridgeOperationAndKeepsTheSession() {
        val child = Child(); val ready = CountDownLatch(1)
        val bridge = ShellVehicleBridge(RuntimeEnvironment.getApplication(),{}, { _,_ -> child })
        try {
            bridge.start({ ready.countDown() },{})
            assertTrue(ready.await(5,TimeUnit.SECONDS))
            assertEquals("enabled",bridge.restoreAdbSettings().getString("state"))
            assertEquals(13.7,JSONObject(bridge.read(id)).getDouble("value"),0.001)
            val commands = mutableListOf<JSONObject>(); child.messages.drainTo(commands)
            val recovery = commands.single { it.optString("op") == "restoreAdbSettings" }
            assertEquals(setOf("op","request"),recovery.keys().asSequence().toSet())
        } finally { bridge.close() }
        assertTrue(child.terminated.await(4,TimeUnit.SECONDS))
    }
}
