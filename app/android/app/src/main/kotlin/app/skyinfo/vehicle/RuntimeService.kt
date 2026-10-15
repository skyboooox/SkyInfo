package app.skyinfo.vehicle

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.IBinder

class RuntimeService : Service() {
    private lateinit var notification: Notification
    private var locationActive = false
    @Synchronized fun setLocationActive(wanted: Boolean): Boolean {
        if (wanted == locationActive) return locationActive
        try {
            val base = if (android.os.Build.VERSION.SDK_INT >= 34) android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0
            startForeground(1, notification, base or if (wanted) android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION else 0)
            locationActive = wanted
        } catch (_: SecurityException) { locationActive = false }
        catch (_: IllegalStateException) { locationActive = false }
        return locationActive
    }
    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel("telemetry", NativeStrings.text_d56cdb9f8f, NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        notification = Notification.Builder(this, "telemetry").setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setContentTitle("SkyInfo").setContentText(NativeStrings.text_ecb3ae6beb).setContentIntent(open).setOngoing(true).build()
        if (android.os.Build.VERSION.SDK_INT >= 34) startForeground(1, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else startForeground(1,notification)
        RuntimeCoordinator.get(this).attach(this)
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        RuntimeCoordinator.get(this).execute { RuntimeCoordinator.get(this).reconfigure() }
        return START_STICKY
    }
    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
        super.onConfigurationChanged(newConfig)
        RuntimeCoordinator.get(this).execute { RuntimeCoordinator.get(this).appearanceChanged() }
    }
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onDestroy() { RuntimeCoordinator.get(this).detach(this); super.onDestroy() }
}
class StartupReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in listOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED)) return
        val store = SecureConfig(context)
        val config = store.load()
        if (!config.optBoolean("autoStart", true)) return
        if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED && store.stopped()) return
        store.stopped(false)
        RuntimeCoordinator.get(context).ensureRunning(fromBoot = true)
    }
}
