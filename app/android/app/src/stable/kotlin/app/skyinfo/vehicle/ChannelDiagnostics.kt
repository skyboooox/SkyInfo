package app.skyinfo.vehicle

import org.json.JSONObject
import java.util.concurrent.ThreadPoolExecutor

internal object ChannelDiagnostics {
    const val enabled = false
    fun audit(fields: Map<String, JSONObject>, source: ThreadPoolExecutor, altitude: GnssAltitude? = null, onTimeout: () -> Unit): JSONObject =
        throw UnsupportedOperationException("Test tools are not included")
}
