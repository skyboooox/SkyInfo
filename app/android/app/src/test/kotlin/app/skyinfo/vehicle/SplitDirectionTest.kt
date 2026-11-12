package app.skyinfo.vehicle

import org.junit.Assert.*
import org.junit.Test

class SplitDirectionTest {
    private class Fixture {
        var state: SplitDirectionState? = SplitDirectionState(2, true)
        var failure: String? = null
        var swaps = 0
        val waits = mutableListOf<Long>()
        val callbacks = ArrayDeque<() -> Unit>()
        val results = mutableListOf<SplitLayoutCheck>()
        val sequence = SplitDirectionSequence({ state }, { swaps++; failure }) { time, action ->
            waits.add(time); callbacks.add(action)
            val cancel: () -> Unit = { callbacks.remove(action); Unit }; cancel
        }
        fun step() { callbacks.removeFirst().invoke() }
        fun drain() { repeat(20) { if (callbacks.isEmpty()) return; step() }; fail("unbounded direction polling") }
    }
    @Test fun keepsMatchingDirectionWithoutSwappingEitherRatio() {
        for ((ratio, position) in listOf("3/7" to 1, "7/3" to 2)) {
            val f = Fixture(); f.state = SplitDirectionState(position, true)
            f.sequence.ensure(ratio, f.results::add); f.drain()
            assertEquals(0, f.swaps)
            assertTrue(f.results.single().directionVerified)
        }
    }
    @Test fun waitsForDualAreasBeforeOneSwapAndReadsBackAfterAnimation() {
        val f = Fixture(); f.state = SplitDirectionState(2, false)
        f.sequence.ensure("3/7", f.results::add); f.step()
        assertEquals(0, f.swaps); assertTrue(f.results.isEmpty())
        f.state = SplitDirectionState(2, true); f.step()
        assertEquals(1, f.swaps); assertEquals(1250L, f.waits.last())
        assertTrue(f.results.isEmpty())
        f.state = SplitDirectionState(1, true); f.step()
        assertTrue(f.results.single().directionVerified)
    }
    @Test fun neverTreatsMatchingPersistedSettingAsLiveDualWindow() {
        val f = Fixture(); f.state = SplitDirectionState(1, false)
        f.sequence.ensure("3/7", f.results::add); f.drain()
        assertEquals("split_not_established", f.results.single().reason)
        assertEquals(0, f.swaps)
    }
    @Test fun reportsUnavailableDeniedAndUnconfirmedWithoutRepeatedSwap() {
        val missing = Fixture(); missing.state = null
        missing.sequence.ensure("3/7", missing.results::add); missing.drain()
        assertEquals("direction_unavailable", missing.results.single().reason)
        val denied = Fixture(); denied.failure = "direction_denied"
        denied.sequence.ensure("3/7", denied.results::add); denied.drain()
        assertEquals("direction_denied", denied.results.single().reason)
        val unchanged = Fixture()
        unchanged.sequence.ensure("3/7", unchanged.results::add); unchanged.drain()
        assertEquals(1, unchanged.swaps)
        assertEquals("direction_unconfirmed", unchanged.results.single().reason)
        assertFalse(unchanged.results.single().directionVerified)
    }
    @Test fun closeCancelsQueuedAdjustment() {
        val f = Fixture()
        f.sequence.ensure("3/7", f.results::add); f.sequence.close()
        assertTrue(f.callbacks.isEmpty()); assertEquals(0, f.swaps); assertTrue(f.results.isEmpty())
    }
}
