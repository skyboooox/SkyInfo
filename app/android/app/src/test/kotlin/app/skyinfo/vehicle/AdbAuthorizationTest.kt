package app.skyinfo.vehicle

import android.content.Context
import android.os.Looper
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.time.Duration
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class AdbAuthorizationTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()

    @Test fun pauseSurvivesRecreationAndOnlyManualAttemptOrAuthorizationChangesIt() {
        val first = AdbAuthorization(context)
        first.pause()
        val restored = AdbAuthorization(context)
        assertEquals("authorization", restored.required)
        assertFalse(restored.takeAttempt())
        restored.retry()
        assertTrue(restored.takeAttempt())
        assertFalse(restored.takeAttempt())
        assertEquals("authorization", AdbAuthorization(context).required)
        restored.authorized()
        assertNull(AdbAuthorization(context).required)
        assertTrue(restored.takeAttempt())
    }

    @Test fun sessionPreservesPauseAcrossReconfigurationCloseRecreationAndManualFailure() {
        val callbacks = LinkedBlockingQueue<() -> Unit>()
        val attempts = AtomicInteger()
        val authorization = AdbAuthorization(context)
        fun session(): VehicleSession {
            lateinit var current: VehicleSession
            current = VehicleSession(context, ReadOnlyVehicle(emptyMap()), { callbacks.offer(it) }, { _, _ -> },
                { current.configure(emptySet(), true, connectionRequired = true) }, {},
                bridgeFactory = { disconnected, overlay ->
                    ShellVehicleBridge(context, disconnected, { _, _ ->
                        attempts.incrementAndGet()
                        authorization.pause()
                        throw AdbAuthorizationRequiredException()
                    }, overlay)
                })
            return current
        }
        fun completeFailure() { callbacks.poll(5, TimeUnit.SECONDS)?.invoke() ?: fail("Missing failure callback") }
        var current = session()
        current.configure(emptySet(), true, connectionRequired = true)
        completeFailure()
        assertEquals(1, attempts.get())
        assertEquals("authorization", current.adbState)
        repeat(3) { current.configure(emptySet(), true, connectionRequired = true) }
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMinutes(5))
        while (callbacks.isNotEmpty()) callbacks.poll()?.invoke()
        assertEquals(1, attempts.get())
        current.close()
        current = session()
        current.configure(emptySet(), true, connectionRequired = true)
        assertEquals("authorization", current.adbState)
        assertEquals(1, attempts.get())
        current.retryAuthorization()
        current.configure(emptySet(), true, connectionRequired = true)
        completeFailure()
        assertEquals(2, attempts.get())
        assertEquals("authorization", current.adbState)
        current.configure(emptySet(), true, connectionRequired = true)
        assertEquals(2, attempts.get())
        current.close()
    }

    @Test fun authorizationPausePreservesOrdinaryAppReadings() {
        AdbAuthorization(context).pause()
        val id = "system.android_version"
        val session = VehicleSession(context, ReadOnlyVehicle(mapOf(id to JSONObject())),
            { it() }, { _, _ -> }, {}, {},
            bridgeFactory = { _, _ -> throw AssertionError("Authorization pause started ADB") })
        session.configure(setOf(id), true, connectionRequired = true)
        val sample = session.read(id)
        assertEquals("authorization", session.adbState)
        assertEquals("available", sample.getString("quality"))
        assertEquals(android.os.Build.VERSION.RELEASE, sample.getString("value"))
        session.close()
    }

    @Test fun ordinaryConnectionFailureKeepsAutomaticBackoff() {
        val callbacks = LinkedBlockingQueue<() -> Unit>()
        val attempts = AtomicInteger()
        lateinit var session: VehicleSession
        session = VehicleSession(context, ReadOnlyVehicle(emptyMap()), { callbacks.offer(it) }, { _, _ -> },
            { session.configure(emptySet(), true, connectionRequired = true) }, {},
            bridgeFactory = { disconnected, overlay ->
                ShellVehicleBridge(context, disconnected, { _, _ ->
                    attempts.incrementAndGet()
                    throw java.net.ConnectException("unreachable")
                }, overlay)
            })
        session.configure(emptySet(), true, connectionRequired = true)
        callbacks.poll(5, TimeUnit.SECONDS)?.invoke() ?: fail("Missing failure callback")
        assertEquals("unreachable", session.adbState)
        assertNull(AdbAuthorization(context).required)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1))
        callbacks.poll(5, TimeUnit.SECONDS)?.invoke() ?: fail("Missing retry callback")
        callbacks.poll(5, TimeUnit.SECONDS)?.invoke() ?: fail("Missing second failure callback")
        assertEquals(2, attempts.get())
        session.close()
    }
}
