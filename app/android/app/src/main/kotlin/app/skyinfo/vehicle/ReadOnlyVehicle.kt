package app.skyinfo.vehicle

import android.os.Build
import android.os.IBinder
import android.os.Parcel
import org.json.JSONObject

class ReadOnlyVehicle(private val fields: Map<String, JSONObject>, private val altitude: GnssAltitude? = null) {
    fun read(id: String): JSONObject {
        require(fields.containsKey(id))
        if (id == GNSS_ALTITUDE) return altitude?.read() ?: failure("unsupported", id)
        if (isDerived(id)) return failure("unsupported", id)
        if (id == "system.android_version") return value(Build.VERSION.RELEASE, id)
        if (id == "system.firmware_version") return try {
            val properties = Class.forName("android.os.SystemProperties")
            val version = properties.getMethod("get", String::class.java).invoke(null, "apps.setting.product.outswver") as String
            if (version.isBlank()) failure("unsupported", id) else value(version, id)
        } catch (_: Throwable) { failure("unsupported", id) }
        val parts = id.split('/').map(String::toInt)
        val transaction = parts[1]
        require(transaction == 5 || transaction == 7)
        return try {
            val original = Class.forName("android.os.ServiceManager").getMethod("getService", String::class.java).invoke(null, "autoservice") as? IBinder
                ?: return failure("disconnected", id)
            val binder: IBinder = original
            val data = Parcel.obtain()
            val reply = Parcel.obtain()
            try {
                data.writeInterfaceToken("android.gui.BYDAutoServer")
                data.writeInt(parts[0])
                data.writeInt(parts[2])
                check(binder.transact(transaction, data, reply, 0))
                check(reply.dataAvail() >= 8)
                val status = reply.readInt()
                val result = if (status != 0) failure("error", id).put("statusCode", status)
                else if (transaction == 5) value(reply.readInt(), id)
                else {
                    val raw = reply.readFloat()
                    if (raw.isFinite()) value(raw.toDouble(), id) else failure("invalid", id).put("raw", raw.toString())
                }
                result.put("transport", if (android.os.Process.myUid() == 2000) "shell_binder" else "app_binder")
                    .put("clientUid", android.os.Process.myUid())
            } finally { data.recycle(); reply.recycle() }
        } catch (_: SecurityException) { failure("permission", id) }
        catch (_: Throwable) { failure("error", id) }
    }
    private fun failure(quality: String, id: String) = JSONObject().put("quality", quality).put("source", id)
    fun fromRaw(id: String, raw: Any): JSONObject { require(fields.containsKey(id)); return if (raw is Number && !raw.toDouble().isFinite()) failure("invalid", id).put("raw", raw.toString()).put("receivedAt", System.currentTimeMillis()) else value(if (raw is Float) raw.toDouble() else raw, id) }
    private fun value(raw: Any, id: String): JSONObject {
        val invalid = (fields.getValue(id).optString("encoding") == NativeStrings.text_d7f8312638 && raw is Number && raw.toInt() == 65535) || when(id) {
            BATTERY_CURRENT -> raw !is Number || invalidGbCurrentRaw(raw)
            "1012/5/339738642" -> raw is Number && raw.toDouble() !in 0.0..8000.0
            "1016/5/-1728052956", "1016/5/-1728052952", "1016/5/-1728052948", "1016/5/-1728052944" -> raw is Number && raw.toDouble() !in 0.0..4094.0
            "1000/5/766509068", "1009/5/876609592", "1038/5/440401932" -> raw is Number && raw.toDouble() == 65535.0
            "1014/7/1246777400", "1014/5/1145045040" -> raw is Number && raw.toDouble() !in 0.0..100.0
            else -> false
        }
        if (invalid) return failure("invalid", id).put("raw", raw)
        return JSONObject().put("value", decodeReading(raw, fields.getValue(id))).put("raw", raw)
        .apply { fields.getValue(id).optJSONObject("stateLabels")?.optString(raw.toString())?.takeIf(String::isNotEmpty)?.let { put("stateLabel",it) } }
        .put("unit", fields.getValue(id).optString("unit"))
        .put("definitionVersion", fields.getValue(id).optInt("definitionVersion", 1))
        .put("quality", if (id.startsWith("system.") || fields.getValue(id).optString("unit").isNotEmpty()) "available" else "unverified")
        .put("source", id).put("receivedAt", System.currentTimeMillis())
    }
}

internal fun invalidGbCurrentRaw(raw: Number): Boolean =
    !raw.toDouble().isFinite() || raw.toDouble() < 0 || raw.toDouble() >= 65534

internal fun decodeReading(raw: Any, field: JSONObject): Any =
    if (raw is Number && (field.has("valueOffset") || field.has("valueScale")))
        raw.toDouble() * field.optDouble("valueScale", 1.0) + field.optDouble("valueOffset", 0.0) else raw
