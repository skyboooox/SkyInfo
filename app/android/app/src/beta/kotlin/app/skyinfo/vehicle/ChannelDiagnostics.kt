package app.skyinfo.vehicle

import org.json.JSONObject
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

internal object ChannelDiagnostics {
    const val enabled = true
    fun audit(fields: Map<String, JSONObject>, source: ThreadPoolExecutor, onTimeout: () -> Unit): JSONObject {
        val auditId = java.util.UUID.randomUUID().toString()
        val ordinary = ReadOnlyVehicle(fields)
        val counts = mutableMapOf<String,Int>()
        var blocked = false
        android.util.Log.i("SkyInfo.Adaptation",JSONObject().put("kind","start").put("audit_id",auditId).put("uid",android.os.Process.myUid()).put("count",fields.keys.count { !isDerived(it) }).put("at",System.currentTimeMillis()).toString())
        for (id in fields.keys.filterNot(::isDerived)) {
            val result = if (blocked) JSONObject().put("quality","not_attempted") else try {
                val future = source.submit<JSONObject> { ordinary.read(id) }
                try { future.get(2,TimeUnit.SECONDS) } catch (_: java.util.concurrent.TimeoutException) {
                    future.cancel(true); source.purge(); blocked = true; onTimeout(); JSONObject().put("quality","timeout")
                }
            } catch (_: Throwable) { JSONObject().put("quality","error") }
            val quality = result.optString("quality","error")
            counts[quality] = (counts[quality] ?: 0) + 1
            android.util.Log.i("SkyInfo.Adaptation",JSONObject().put("kind","read").put("audit_id",auditId).put("uid",android.os.Process.myUid()).put("id",id).put("at",System.currentTimeMillis()).put("result",result).toString())
        }
        val report = JSONObject().put("audit_id",auditId).put("uid",android.os.Process.myUid()).put("qualities",JSONObject(counts as Map<*,*>))
        android.util.Log.i("SkyInfo.Adaptation",JSONObject().put("kind","finished").put("audit",report).toString())
        return report
    }
}
