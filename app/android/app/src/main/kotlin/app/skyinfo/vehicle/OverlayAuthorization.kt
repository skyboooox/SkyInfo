package app.skyinfo.vehicle

internal class OverlayAuthorization(private val granted: () -> Boolean, private val launch: () -> Unit) {
    private var pending: ((Boolean) -> Unit)? = null
    fun enable(completed: (Boolean) -> Unit) {
        if (pending != null) { completed(false); return }
        if (granted()) { completed(true); return }
        pending = completed
        try { launch() }
        catch (_: Exception) { pending = null; completed(false) }
    }
    fun returned() {
        val completed = pending ?: return
        pending = null
        completed(granted())
    }
}
