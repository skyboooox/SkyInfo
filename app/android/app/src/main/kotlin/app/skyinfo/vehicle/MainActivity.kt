package app.skyinfo.vehicle

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val main = Handler(Looper.getMainLooper())
    private var locationReply: MethodChannel.Result? = null
    private val runtime by lazy { RuntimeCoordinator.get(this) }
    private val overlayAuthorization by lazy {
        OverlayAuthorization({ Settings.canDrawOverlays(this) }, {
            startActivityForResult(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")), 102)
        })
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "app.skyinfo.vehicle/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { runtime.listen(events) }
            override fun onCancel(arguments: Any?) { runtime.listen(null) }
        })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.skyinfo.vehicle/runtime").setMethodCallHandler { call, result ->
            if (call.method == "auditFields" && !ChannelDiagnostics.enabled) {
                result.notImplemented(); return@setMethodCallHandler
            }
            when (call.method) {
                "requestLocation" -> {
                    if (locationReply != null) { result.error("pending",NativeStrings.text_245a5a7f18,null); return@setMethodCallHandler }
                    val prefs = getSharedPreferences("location_permission", MODE_PRIVATE)
                    if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        runtime.execute { runtime.reconfigure(); val snapshot = runtime.snapshot(); main.post { result.success(RuntimeCoordinator.jsonMap(snapshot)) } }
                    } else if (prefs.getBoolean("requested",false) && !shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_FINE_LOCATION)) {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,Uri.parse("package:$packageName")))
                        result.success(null)
                    } else {
                        prefs.edit().putBoolean("requested",true).apply(); locationReply = result
                        requestPermissions(arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION,Manifest.permission.ACCESS_FINE_LOCATION),103)
                    }
                }
                "setOverlayEnabled" -> {
                    fun completed(enabled: Boolean) { runtime.execute {
                        try { runtime.setOverlayEnabled(enabled); val snapshot = runtime.snapshot(); main.post { result.success(RuntimeCoordinator.jsonMap(snapshot)) } }
                        catch (_: Throwable) { main.post { result.error("runtime", NativeStrings.text_245a5a7f18, null) } }
                    } }
                    if (call.argument<Boolean>("enabled") == true) overlayAuthorization.enable(::completed) else completed(false)
                }
                "requestOverlay" -> { startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))); result.success(null) }
                "openStartup" -> {
                    val candidate = Intent().setComponent(ComponentName("com.byd.appstartmanagement", "com.byd.appstartmanagement.frame.AppStartManagement"))
                    try { startActivity(candidate) } catch (_: Exception) { startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))) }
                    result.success(null)
                }
                else -> runtime.execute {
                    fun reply(value: JSONObject) { main.post { result.success(RuntimeCoordinator.jsonMap(value)) } }
                    try {
                        when (call.method) {
                            "load" -> { runtime.applicationStarted(); reply(runtime.snapshot()) }
                            "save" -> {
                                val args = call.arguments as Map<*, *>
                                val config = JSONObject(args["config"] as Map<*, *>)
                                val secrets = listOf("haToken", "mqttPassword").mapNotNull { key -> (args[key] as? String)?.let { key to it } }.toMap()
                                runtime.save(config, secrets); reply(runtime.snapshot())
                            }
                            "importConfig" -> { runtime.save(JSONObject(call.argument<Map<String, Any?>>("config")!!), emptyMap()); reply(runtime.snapshot()) }
                            "reconnectAdb" -> { runtime.reconnectAdb(); reply(runtime.snapshot()) }
                            "pairAdb" -> runtime.pairAdb(call.argument<String>("host") ?: "", call.argument<Int>("port") ?: 0, call.argument<String>("code") ?: "", ::reply)
                            "refreshHa" -> { runtime.refreshHa(); reply(runtime.snapshot()) }
                            "haDirectory" -> reply(runtime.haDirectory())
                            "haControl" -> runtime.haControl(call.argument<String>("field") ?: "",call.argument<String>("function") ?: "",call.argument<Any>("value"),call.argument<Boolean>("confirmed") == true,::reply)
                            "diagnostics" -> reply(runtime.diagnostics())
                            "auditFields" -> reply(runtime.auditFields())
                            "controls" -> reply(runtime.controls())
                            "controlDefinitions" -> reply(JSONObject().put("controls",org.json.JSONArray(EntityCatalog.controls(this))))
                            "control" -> {
                                val value = call.argument<Number>("value") ?: throw IllegalArgumentException()
                                require(value.toDouble().isFinite() && value.toDouble() == value.toInt().toDouble())
                                reply(runtime.controlLocal(call.argument<String>("action") ?: throw IllegalArgumentException(),value.toInt()))
                            }
                            "clearCredentials" -> { runtime.clearCredentials(); reply(runtime.snapshot()) }
                            "clearHistory" -> { runtime.clearHistory(); reply(runtime.snapshot()) }
                            "refresh" -> { runtime.refresh(); reply(runtime.snapshot()) }
                            "saveOverlayAppearance" -> { runtime.saveOverlayAppearance(JSONObject(call.argument<Map<String, Any?>>("style") ?: throw IllegalArgumentException())); reply(runtime.snapshot()) }
                            "previewOverlayStyle" -> { runtime.previewOverlayStyle(call.argument<Map<String, Any?>>("style")?.let { JSONObject(it) }); reply(JSONObject()) }
                            "previewFields" -> { runtime.preview((call.argument<List<String>>("fields") ?: emptyList()).toSet()); reply(runtime.snapshot()) }
                            "resetOverlayPosition" -> { runtime.resetOverlayPosition(); reply(runtime.snapshot()) }
                            "editOverlay" -> { runtime.editOverlay(); reply(runtime.snapshot()) }
                            "stop" -> { runtime.stop(); reply(runtime.snapshot()) }
                            "resume" -> { runtime.resume(); reply(runtime.snapshot()) }
                            "visibility" -> { runtime.setVisible(call.argument<Boolean>("visible") ?: false, call.argument<Boolean>("information")); reply(JSONObject()) }
                            "checkConnection" -> runtime.checkConnection { reply(JSONObject().put("status", it)) }
                            "history" -> runtime.history(call.argument<String>("field")!!, call.argument<Int>("minutes") ?: 30, ::reply)
                            else -> main.post { result.notImplemented() }
                        }
                    } catch (_: Throwable) { main.post { result.error("runtime", NativeStrings.text_245a5a7f18, null) } }
                }
            }
        }
        if (Build.VERSION.SDK_INT >= 33) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 101)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 103) {
            val reply = locationReply; locationReply = null
            runtime.execute { runtime.reconfigure(); val snapshot = runtime.snapshot(); main.post { reply?.success(RuntimeCoordinator.jsonMap(snapshot)) } }
        }
    }
    override fun onDestroy() {
        locationReply?.success(null); locationReply = null
        super.onDestroy()
    }
    override fun onResume() { super.onResume(); runtime.execute { runtime.setVisible(true); runtime.reconfigure() } }
    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
        super.onConfigurationChanged(newConfig)
        runtime.execute { runtime.appearanceChanged() }
    }
    override fun onPause() { runtime.execute { runtime.setVisible(false) }; super.onPause() }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 102) overlayAuthorization.returned()
    }
}
