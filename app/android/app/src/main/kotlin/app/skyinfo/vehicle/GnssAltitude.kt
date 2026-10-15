package app.skyinfo.vehicle

import android.content.Context
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import org.json.JSONObject

internal const val GNSS_ALTITUDE = "location.gnss_altitude"
internal const val GNSS_MAX_AGE_MS = 120000L

internal fun altitudeSample(location: Location?, now: Long = System.currentTimeMillis(), elapsed: Long = SystemClock.elapsedRealtimeNanos()): JSONObject {
    val result = JSONObject().put("source",GNSS_ALTITUDE).put("transport","android_gnss")
        .put("unit","m").put("definitionVersion",1).put("altitudeReference","WGS84").put("readAt",now)
    if (location == null) return result.put("quality","disconnected")
    val age = ((elapsed - location.elapsedRealtimeNanos) / 1000000).coerceAtLeast(0)
    result.put("receivedAt",now).put("sourceAt",now-age).put("fixAgeMs",age)
    if (!location.hasAltitude() || !location.altitude.isFinite()) return result.put("quality","invalid")
    if (location.hasVerticalAccuracy() && location.verticalAccuracyMeters.isFinite()) result.put("verticalAccuracy",location.verticalAccuracyMeters)
    result.put("raw",location.altitude)
    if (age > GNSS_MAX_AGE_MS) return result.put("quality","stale")
    return result.put("receivedAt",now-age).put("value",location.altitude).put("quality","available")
}

class GnssAltitude(private val context: Context) {
    private val manager = context.getSystemService(LocationManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var listener: LocationListener? = null
    private var configuration: Triple<Boolean,Boolean,Boolean>? = null
    val subscribed: Boolean get() = listener != null
    val permitted: Boolean get() = context.checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
    fun configure(requested: Boolean, ready: Boolean, sample: (JSONObject) -> Unit) {
        val next = Triple(requested,ready,permitted)
        if (configuration == next) return
        close(); configuration = next
        if (!requested) return
        if (!next.third || !ready) { sample(failure("permission")); return }
        start(sample)
    }
    private var expiry: Runnable? = null
    @Volatile private var latest: JSONObject? = null
    fun read(): JSONObject = try {
        if (!permitted) failure("permission")
        else if (!manager.isProviderEnabled(LocationManager.GPS_PROVIDER)) failure("disconnected")
        else altitudeSample(manager.getLastKnownLocation(LocationManager.GPS_PROVIDER))
    } catch (_: SecurityException) { failure("permission") }
    catch (_: Exception) { failure("unsupported") }

    private fun start(sample: (JSONObject) -> Unit): Boolean {
        fun deliver(location: Location) {
            if (location.provider != LocationManager.GPS_PROVIDER) return
            val fresh = altitudeSample(location); latest = fresh
            sample(fresh)
            expiry?.let(main::removeCallbacks)
            if (fresh.optString("quality") == "available") {
                val stale = Runnable { if (listener != null && latest === fresh) sample(JSONObject(fresh.toString()).put("quality","stale").put("receivedAt",System.currentTimeMillis()).apply { remove("value") }) }
                expiry = stale
                main.postDelayed(stale,(GNSS_MAX_AGE_MS - fresh.optLong("fixAgeMs") + 1).coerceAtLeast(1))
            }
        }
        val current = object : LocationListener {
            override fun onLocationChanged(location: Location) { if (listener === this) deliver(location) }
            override fun onProviderEnabled(provider: String) {}
            override fun onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) {}
            override fun onProviderDisabled(provider: String) { if (provider == LocationManager.GPS_PROVIDER) sample(failure("disconnected")) }
        }
        return try {
            listener = current
            manager.requestLocationUpdates(LocationManager.PASSIVE_PROVIDER,0L,0f,current,Looper.getMainLooper())
            val cached = manager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
            if (cached != null) deliver(cached) else sample(failure("disconnected"))
            true
        } catch (_: SecurityException) { close(); sample(failure("permission")); false }
        catch (_: Exception) { close(); sample(failure("unsupported")); false }
    }
    fun close() {
        listener?.let { try { manager.removeUpdates(it) } catch (_: Exception) {} }
        listener = null; latest = null; configuration = null
        expiry?.let(main::removeCallbacks); expiry = null
    }
    private fun failure(quality: String) = altitudeSample(null).put("quality",quality)
}
