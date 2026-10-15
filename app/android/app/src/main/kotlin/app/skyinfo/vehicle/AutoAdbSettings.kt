package app.skyinfo.vehicle

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Settings
import org.json.JSONObject
import java.util.concurrent.TimeUnit

internal class AutoAdbSettings(private val port: Port) {
    interface Port {
        fun read(key: String): Int?
        fun write(key: String): Boolean
        fun canWrite(): Boolean
        fun appPermission(): Boolean
        fun grantAppPermission(): Boolean
    }

    fun restore(enabled: Boolean, prepareAppPermission: Boolean = false): JSONObject {
        if (!enabled) return JSONObject().put("state", "disabled")
        if (prepareAppPermission) runCatching { port.grantAppPermission() }
        val settings = JSONObject()
        for (key in listOf(Settings.Global.ADB_ENABLED, "adb_wifi_enabled")) {
            val state = try {
                when {
                    port.read(key) == 1 -> "enabled"
                    !port.canWrite() -> "permission_required"
                    port.write(key) && port.read(key) == 1 -> "enabled"
                    else -> "error"
                }
            } catch (_: SecurityException) { "permission_required" }
            catch (_: Exception) { "error" }
            settings.put(key, state)
        }
        val states = settings.keys().asSequence().map(settings::getString).toList()
        val state = when {
            states.all { it == "enabled" } -> "enabled"
            "error" in states -> "error"
            else -> "permission_required"
        }
        return JSONObject().put("state", state).put("settings", settings)
            .put("appPermission", runCatching { port.appPermission() }.getOrDefault(false))
    }
}

internal class AndroidAdbSettings(private val context: Context, private val appUser: Int? = null) : AutoAdbSettings.Port {
    override fun read(key: String): Int? = Settings.Global.getString(context.contentResolver, key)?.toIntOrNull()
    override fun write(key: String) = Settings.Global.putInt(context.contentResolver, key, 1)
    override fun canWrite() = context.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED
    override fun appPermission() = context.packageManager.checkPermission(Manifest.permission.WRITE_SECURE_SETTINGS, context.packageName) == PackageManager.PERMISSION_GRANTED
    override fun grantAppPermission(): Boolean {
        if (appPermission()) return true
        val user = appUser ?: return false
        require(user >= 0 && context.packageName == "app.skyinfo.vehicle")
        val process = ProcessBuilder("/system/bin/pm", "grant", "--user", user.toString(), context.packageName,
            Manifest.permission.WRITE_SECURE_SETTINGS).redirectErrorStream(true).start()
        try { process.waitFor(2, TimeUnit.SECONDS) }
        finally { if (process.isAlive) process.destroyForcibly(); process.inputStream.close(); process.outputStream.close() }
        return appPermission()
    }
}
