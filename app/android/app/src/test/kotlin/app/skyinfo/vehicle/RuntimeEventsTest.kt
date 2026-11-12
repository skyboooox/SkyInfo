package app.skyinfo.vehicle

import android.content.Context
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class RuntimeEventsTest {
    companion object {
        private const val A = "1012/5/1141899272"
        private const val B = "1012/5/339738642"
    }
    private class Sink : EventChannel.EventSink {
        val messages = mutableListOf<Map<*,*>>()
        override fun success(value: Any?) { messages.add(value as Map<*,*>) }
        override fun error(code: String, message: String?, details: Any?) { fail(code) }
        override fun endOfStream() { }
        fun samples() = messages.last { it.containsKey("samples") }["samples"] as? Map<*,*> ?: emptyMap<Any,Any>()
    }
    private class Harness : AutoCloseable {
        val context = RuntimeEnvironment.getApplication()
        val runtime: RuntimeCoordinator
        init {
            context.getSharedPreferences("skyinfo",Context.MODE_PRIVATE).edit().clear().putBoolean("stopped",true)
                .putString("config","{\"localHistory\":false,\"collect\":false,\"autoSystemAdb\":false}").commit()
            runtime = RuntimeCoordinator::class.java.getDeclaredConstructor(Context::class.java).apply { isAccessible = true }.newInstance(context)
            field("visible").set(runtime,true)
        }
        fun field(name: String) = RuntimeCoordinator::class.java.getDeclaredField(name).apply { isAccessible = true }
        fun run(action: () -> Unit) { (field("worker").get(runtime) as ExecutorService).submit(action).get(10,TimeUnit.SECONDS) }
        fun flushMain() { shadowOf(Looper.getMainLooper()).idle() }
        fun listen(sink: Sink) { runtime.listen(sink); run {}; flushMain() }
        fun accept(id: String, at: Long, value: Int = 1, quality: String = "available"): Set<*> {
            val sample = JSONObject().put("value",value).put("raw",value).put("quality",quality).put("receivedAt",at).put("source",id)
            return RuntimeCoordinator::class.java.getDeclaredMethod("accept",String::class.java,JSONObject::class.java)
                .apply { isAccessible = true }.invoke(runtime,id,sample) as Set<*>
        }
        fun emit() { RuntimeCoordinator::class.java.getDeclaredMethod("emit",Boolean::class.javaPrimitiveType).apply { isAccessible = true }.invoke(runtime,false) }
        override fun close() {
            (field("localHistory").get(runtime) as LocalHistory).clear()
            for (name in listOf("worker","network","source")) (field(name).get(runtime) as ExecutorService).shutdownNow()
            flushMain()
        }
    }
    @Test fun listenerStartsFullThenSameValueFreshnessAndQualityUseOnlyAcceptedFields() {
        Harness().use { h ->
            h.run { h.accept(A,1000); h.accept(B,1000) }
            val sink = Sink(); h.listen(sink)
            assertEquals(setOf(A,B),sink.samples().keys)
            h.run { assertTrue(h.accept(A,2000).isEmpty()); h.emit() }; h.flushMain()
            assertEquals(setOf(A),sink.samples().keys)
            assertEquals(2000L,((sink.samples()[A] as Map<*,*>)["updatedAt"] as Number).toLong())
            h.run { h.accept(B,3000,quality="invalid"); h.emit() }; h.flushMain()
            assertEquals(setOf(B),sink.samples().keys)
            assertEquals("invalid",(sink.samples()[B] as Map<*,*>)["quality"])
            h.run { h.emit() }; h.flushMain()
            assertFalse(sink.messages.last().containsKey("samples"))
            assertEquals(setOf(A,B),h.runtime.snapshot().getJSONObject("samples").keys().asSequence().toSet())
        }
    }
    @Test fun newSinkDropsQueuedOldEventsAndReceivesFullCache() {
        Harness().use { h ->
            h.run { h.accept(A,1000); h.accept(B,1000) }
            val first = Sink(); h.listen(first)
            h.run { h.accept(A,2000); h.accept(A,3000); h.emit() }
            val next = Sink(); h.runtime.listen(next); h.run {}; h.flushMain()
            assertEquals(1,first.messages.size)
            assertEquals(setOf(A,B),next.samples().keys)
            assertEquals(3000L,((next.samples()[A] as Map<*,*>)["updatedAt"] as Number).toLong())
        }
    }
    @Test fun backgroundSamplesAreSynchronizedInFullOnResume() {
        Harness().use { h ->
            h.run { h.accept(A,1000); h.accept(B,1000) }
            val sink = Sink(); h.listen(sink)
            h.run { h.runtime.setVisible(false); h.accept(B,2000); h.emit() }; h.flushMain()
            assertEquals(1,sink.messages.size)
            h.run { h.runtime.setVisible(true) }; h.flushMain()
            assertEquals(setOf(A,B),sink.samples().keys)
            assertEquals(2000L,((sink.samples()[B] as Map<*,*>)["updatedAt"] as Number).toLong())
        }
    }
    @Test fun derivedDependenciesAndHaDirectUpdatesJoinTheDelta() {
        Harness().use { h ->
            val sink = Sink(); h.listen(sink)
            h.field("previousDemand").set(h.runtime,setOf(BATTERY_POWER))
            h.run { h.accept(BATTERY_VOLTAGE,1000,400); h.accept(BATTERY_CURRENT,1000,1); h.emit() }; h.flushMain()
            assertTrue(sink.samples().keys.containsAll(listOf(BATTERY_VOLTAGE,BATTERY_CURRENT,BATTERY_POWER)))
            h.run { h.accept(BATTERY_VOLTAGE,2000,401); h.emit() }; h.flushMain()
            assertEquals(setOf(BATTERY_VOLTAGE,BATTERY_POWER),sink.samples().keys)
            h.run {
                val source = h.field("haSource").get(h.runtime)
                @Suppress("UNCHECKED_CAST")
                val received = HaEntitySource::class.java.getDeclaredField("received").apply { isAccessible = true }.get(source) as (String,JSONObject) -> Unit
                received("ha|test|sensor.temperature",JSONObject().put("value",12).put("quality","available").put("updatedAt",3000))
                h.emit()
            }; h.flushMain()
            assertEquals(setOf("ha|test|sensor.temperature"),sink.samples().keys)
        }
    }
}
