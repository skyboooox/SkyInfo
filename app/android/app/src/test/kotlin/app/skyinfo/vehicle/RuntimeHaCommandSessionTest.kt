package app.skyinfo.vehicle

import android.content.Context
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.lang.reflect.Proxy
import java.time.Instant
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class RuntimeHaCommandSessionTest {
    private class Harness : AutoCloseable {
        val context = RuntimeEnvironment.getApplication()
        val runtime: RuntimeCoordinator
        val controlCalls = AtomicInteger()
        init {
            context.getSharedPreferences("skyinfo",Context.MODE_PRIVATE).edit().clear().putBoolean("stopped",false)
                .putString("config","{\"localHistory\":false,\"collect\":false,\"autoSystemAdb\":false,\"haControlEnabled\":true}").commit()
            runtime = RuntimeCoordinator::class.java.getDeclaredConstructor(Context::class.java).apply { isAccessible = true }.newInstance(context)
            val vehicle = field("session").get(runtime)
            val source = Proxy.newProxyInstance(IVehicleSource::class.java.classLoader,arrayOf(IVehicleSource::class.java)) { _, method, _ ->
                when (method.name) {
                    "control" -> { controlCalls.incrementAndGet(); "{\"status\":\"confirmed\"}" }
                    "read" -> "{\"quality\":\"unavailable\"}"
                    else -> null
                }
            }
            VehicleSession::class.java.getDeclaredField("remote").apply { isAccessible = true }.set(vehicle,source)
            ready(10,"test/session/10")
        }
        fun field(name: String) = RuntimeCoordinator::class.java.getDeclaredField(name).apply { isAccessible = true }
        val ha get() = field("haSession").get(runtime) as HaSession
        val config get() = field("config").get(runtime) as JSONObject
        val worker get() = field("worker").get(runtime) as ExecutorService
        fun ready(epoch: Long, topic: String) {
            fun set(name: String, value: Any) = HaSession::class.java.getDeclaredField(name).apply { isAccessible = true }.set(ha,value)
            set("epoch",epoch); set("controlEnabled",true); set("sessionState",NativeStrings.text_09f11a24a6)
            set("target","https://ha.example.invalid")
            set("entitySubscription",true); set("entityCommandTopic",topic)
            val subscription = HaSession::class.java.getDeclaredField("commandMqtt").apply { isAccessible = true }.get(ha)
            subscription.javaClass.getDeclaredField("state").apply { isAccessible = true }.set(subscription,"ready")
        }
        fun block(executor: ExecutorService): CountDownLatch {
            val entered = CountDownLatch(1); val release = CountDownLatch(1)
            executor.submit { entered.countDown(); check(release.await(8,TimeUnit.SECONDS)) }
            check(entered.await(2,TimeUnit.SECONDS)); return release
        }
        fun drain() { worker.submit {}.get(8,TimeUnit.SECONDS) }
        fun awaitSourceQueue() {
            val source = field("source").get(runtime) as ThreadPoolExecutor
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2)
            while (source.queue.isEmpty() && System.nanoTime() < deadline) Thread.sleep(5)
            assertFalse("Command did not reach the source queue",source.queue.isEmpty())
        }
        fun commands(epoch: Long = 10, topic: String = "test/session/10") {
            ha.entityCommand(JSONObject().put("action","ac_cycle").put("value",1),HaCommandContext(epoch,topic))
            ha.command(JSONObject().put("event_type","skyinfo_command").put("time_fired",Instant.now().toString())
                .put("context",JSONObject().put("id","script_$epoch"))
                .put("data",JSONObject().put("target",config.getString("prefix")).put("action","ac_cycle").put("value",1)),HaCommandContext(epoch))
        }
        override fun close() {
            runtime.store.stopped(true)
            config.put("haControlEnabled",false).put("mqttControlEnabled",false)
            ha.close()
            drain()
            (field("network").get(runtime) as ExecutorService).submit {}.get(8,TimeUnit.SECONDS)
            drain()
            (field("localHistory").get(runtime) as LocalHistory).clear()
            for (name in listOf("worker","network","source")) (field(name).get(runtime) as ExecutorService).shutdownNow()
        }
    }
    @Test fun queuedCommandsFromBothHaPathsAreDroppedAfterReconnect() {
        Harness().use { h ->
            val release = h.block(h.worker)
            h.commands()
            h.ha.networkLost(); h.ready(11,"test/session/11")
            release.countDown(); h.drain()
            assertEquals(0,h.controlCalls.get()); assertNull(h.field("lastCommand").get(h.runtime))
            h.commands(11,"test/session/11"); h.drain()
            assertEquals(2,h.controlCalls.get())
        }
    }
    @Test fun queuedCommandsAreRejectedWhenStoppedOrRemoteControlIsDisabled() {
        for (stopped in listOf(true,false)) Harness().use { h ->
            val release = h.block(h.worker)
            h.commands()
            if (stopped) h.runtime.store.stopped(true) else h.config.put("haControlEnabled",false)
            release.countDown(); h.drain()
            assertEquals(0,h.controlCalls.get()); assertNull(h.field("lastCommand").get(h.runtime))
        }
    }
    @Test fun sourceQueueRechecksTheHaSessionImmediatelyBeforeVehicleExecution() {
        Harness().use { h ->
            val release = h.block(h.field("source").get(h.runtime) as ExecutorService)
            h.commands(); h.awaitSourceQueue()
            h.ha.networkLost(); h.ready(11,"test/session/11")
            release.countDown(); h.drain()
            assertEquals(0,h.controlCalls.get()); assertNull(h.field("lastCommand").get(h.runtime))
        }
    }
    @Test fun sourceQueueRechecksTheMqttSessionImmediatelyBeforeVehicleExecution() {
        Harness().use { h ->
            h.config.put("connection","mqtt").put("haControlEnabled",false).put("mqttControlEnabled",true)
            val publisher = h.field("publisher").get(h.runtime) as ConnectionClient
            val nonce = ConnectionClient::class.java.getDeclaredField("commandSession").apply { isAccessible = true }
            nonce.set(publisher,"mqtt-session-10")
            val release = h.block(h.field("source").get(h.runtime) as ExecutorService)
            val now = Instant.now()
            publisher.command!!.invoke(JSONObject().put("schema_version",1).put("command_session","mqtt-session-10")
                .put("target",h.config.getString("prefix")).put("issued_at",now.toString()).put("expires_at",now.plusSeconds(30).toString())
                .put("command_id","mqtt-source").put("action","ac_cycle").put("value",1),"mqtt-session-10",false)
            h.awaitSourceQueue()
            nonce.set(publisher,"mqtt-session-11")
            release.countDown(); h.drain()
            assertEquals(0,h.controlCalls.get()); assertNull(h.field("lastCommand").get(h.runtime))
        }
    }
}
