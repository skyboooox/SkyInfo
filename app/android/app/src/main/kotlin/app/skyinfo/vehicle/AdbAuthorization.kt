package app.skyinfo.vehicle

import android.content.Context

/** Device-local authorization pause; configuration imports and service restarts preserve it. */
internal class AdbAuthorization(context: Context) {
    private val prefs = context.getSharedPreferences("skyinfo.adb.connection", Context.MODE_PRIVATE)
    private var manualAttempt = false
    val required: String? get() = prefs.getString("authorization", null)
    fun pause(state: String = "authorization") {
        check(state == "authorization" || state == "pair_required")
        check(prefs.edit().putString("authorization", state).commit())
    }
    fun authorized() { check(prefs.edit().remove("authorization").commit()); manualAttempt = false }
    fun retry() { manualAttempt = true }
    fun takeAttempt(): Boolean {
        if (required == null) { manualAttempt = false; return true }
        val allowed = manualAttempt
        manualAttempt = false
        return allowed
    }
}

internal class AdbAuthorizationRequiredException(cause: Throwable? = null) :
    java.io.IOException("adb_authorization_required", cause)
