package app.skyinfo.vehicle

/** One transport target shares backoff across telemetry, discovery, heartbeat and receipts. */
internal class PublicationGate(private val clock: () -> Long = android.os.SystemClock::elapsedRealtime) {
    private var until = 0L
    private var seconds = 1L
    private var blocked = false
    @Synchronized fun allowed() = !blocked && clock() >= until
    @Synchronized fun fail(permanent: Boolean) {
        if (permanent) { blocked = true; return }
        if (clock() < until || blocked) return
        until = clock() + seconds*1000
        seconds = (seconds*2).coerceAtMost(60)
    }
    @Synchronized fun reset() { until = 0; seconds = 1; blocked = false }
    @Synchronized fun waitMillis(): Long? = if (blocked) null else (until-clock()).coerceAtLeast(0)
}
internal class PublicationDeferredException : java.io.IOException("publication_deferred")
internal class HaAuthorizationException : java.io.IOException("ha_authorization_required")
