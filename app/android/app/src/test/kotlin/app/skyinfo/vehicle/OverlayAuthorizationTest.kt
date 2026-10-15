package app.skyinfo.vehicle

import org.junit.Assert.*
import org.junit.Test

class OverlayAuthorizationTest {
    @Test fun grantedPermissionDoesNotOpenSettings() {
        var launches = 0
        val results = mutableListOf<Boolean>()
        val request = OverlayAuthorization({ true }, { launches++ })
        request.enable(results::add)
        assertEquals(listOf(true), results); assertEquals(0, launches)
        request.returned(); assertEquals(1, results.size)
    }
    @Test fun returningFromSettingsUsesActualPermissionAndFinishesOnce() {
        var granted = false; var launches = 0
        val results = mutableListOf<Boolean>()
        val request = OverlayAuthorization({ granted }, { launches++ })
        request.enable(results::add)
        assertEquals(1, launches); assertTrue(results.isEmpty())
        request.returned(); assertEquals(listOf(false), results)
        request.enable(results::add); granted = true
        request.returned(); request.returned()
        assertEquals(listOf(false, true), results); assertEquals(2, launches)
    }
    @Test fun duplicateRequestsAndUnavailableSystemScreenDoNotLeaveAnUnfinishedRequest() {
        var launches = 0; val results = mutableListOf<Boolean>()
        val request = OverlayAuthorization({ false }, { launches++ })
        request.enable(results::add); request.enable(results::add)
        assertEquals(1, launches); assertEquals(listOf(false), results)
        request.returned(); assertEquals(listOf(false, false), results)
        val failed = OverlayAuthorization({ false }, { throw IllegalStateException() })
        failed.enable(results::add); failed.enable(results::add)
        assertEquals(4, results.size); assertTrue(results.none { it })
    }
}
