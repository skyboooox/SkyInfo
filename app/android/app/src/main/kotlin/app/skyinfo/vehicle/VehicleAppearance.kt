package app.skyinfo.vehicle

import android.content.Context
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import org.json.JSONObject

internal data class AppearanceState(val displayMode: Int?, val nightMode: Int?) {
    val brightness: String? get() = when (displayMode) {
        1 -> "dark"
        2 -> "light"
        3, null -> when (nightMode) { 1 -> "dark"; 2 -> "light"; else -> null }
        else -> null
    }
    val source: String get() = when {
        brightness == null -> "android"
        displayMode in listOf(1, 2) -> "byd_display_mode"
        else -> "byd_night_mode"
    }
    fun json(): JSONObject = JSONObject().put("brightness", brightness ?: JSONObject.NULL)
        .put("source", source).put("displayMode", displayMode ?: JSONObject.NULL)
        .put("nightMode", nightMode ?: JSONObject.NULL)

    fun overlayConfig(config: JSONObject): JSONObject = JSONObject(config.toString()).also {
        if (config.optString("theme", "system") == "system" && brightness != null) it.put("theme", brightness)
    }
}

internal class VehicleAppearance(private val context: Context, private val changed: () -> Unit) {
    private val resolver = context.contentResolver
    var current = AppearanceState(null, null)
        private set
    private var active = false
    private val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) { changed() }
    }

    fun refresh() {
        val mode = try {
            resolver.query(PROVIDER, arrayOf("key", "value"), "key=?", arrayOf("time_wallpaper_mode"), null)?.use { cursor ->
                val key = cursor.getColumnIndex("key")
                val value = cursor.getColumnIndex("value")
                var result: Int? = null
                if (key >= 0 && value >= 0) while (cursor.moveToNext()) {
                    if (cursor.getString(key) == "time_wallpaper_mode") result = cursor.getString(value)?.toIntOrNull()
                }
                result
            }
        } catch (_: Exception) { null }
        val night = try { Settings.Global.getInt(resolver, NIGHT_KEY) } catch (_: Exception) { null }
        current = AppearanceState(mode, night)
    }

    fun setActive(value: Boolean) {
        if (value == active) return
        active = value
        if (!value) {
            resolver.unregisterContentObserver(observer)
            return
        }
        for (uri in listOf(Uri.withAppendedPath(PROVIDER, "time_wallpaper_mode"), Settings.Global.getUriFor(NIGHT_KEY))) {
            try { resolver.registerContentObserver(uri, false, observer) } catch (_: Exception) { }
        }
        refresh()
    }

    companion object {
        private val PROVIDER = Uri.parse("content://carsettings/global")
        private const val NIGHT_KEY = "key_byd_night_mode"
    }
}
