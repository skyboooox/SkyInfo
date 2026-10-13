package app.skyinfo.vehicle

import android.content.Context
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.Typeface
import android.graphics.PixelFormat
import android.hardware.input.InputManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.GestureDetector
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.view.WindowInsets
import com.caverock.androidsvg.SVG
import org.json.JSONObject
import java.util.Locale
import kotlin.math.roundToInt

internal data class StripPlacement(val y: Int, val height: Int)
internal fun stripPlacement(barHeight: Int, requestedOffset: Int, minimumHeight: Int): StripPlacement {
    val minimum = minimumHeight.coerceIn(1, barHeight)
    val y = requestedOffset.coerceIn(0, barHeight - minimum)
    return StripPlacement(y, barHeight - y)
}

internal fun floatingCoordinate(fraction: Double?, initial: Int, screen: Int, size: Int): Int =
    (fraction?.let { (it * (screen - size).coerceAtLeast(0)).roundToInt() } ?: initial).coerceIn(0,(screen-size).coerceAtLeast(0))

internal fun overlayHit(x: Float, y: Float, width: Int, height: Int): Boolean =
    x >= 0 && y >= 0 && x < width && y < height

class OverlayWindow(private val context: Context, private val privileged: Boolean = false,
    private val changed: (JSONObject) -> Unit = {}) {
    private val windows = context.getSystemService(WindowManager::class.java)
    private val view = StripView(context)
    private val main = Handler(Looper.getMainLooper())
    private var parameters: WindowManager.LayoutParams? = null
    private var monitor: OverlayTouchMonitor? = null
    private var monitorReady = false
    private var unlocked = false
    private var armed = false
    private var dragging = false
    private var downX = 0f; private var downY = 0f
    private var windowX = 0; private var windowY = 0
    private var tap: TouchPoint? = null
    private var moved = false
    private var configuredX: Double? = null; private var configuredY: Double? = null
    private var screenWidth = 0; private var screenHeight = 0
    private val lockTask = Runnable { lock() }
    private val gestures = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
        override fun onDown(event: MotionEvent): Boolean {
            main.removeCallbacks(lockTask)
            downX = event.rawX; downY = event.rawY
            windowX = parameters?.x ?: 0; windowY = parameters?.y ?: 0
            dragging = unlocked
            main.postDelayed(lockTask,5000)
            return true
        }
        override fun onLongPress(event: MotionEvent) {
            if (!armed || !attached) return
            armed = false; unlocked = true; dragging = true
            main.removeCallbacks(lockTask); main.postDelayed(lockTask,5000); updateTouchability()
        }
    })
    init {
        view.setOnTouchListener { _, event ->
            if (!armed && !unlocked) false else {
                gestures.onTouchEvent(event)
                if (event.actionMasked == MotionEvent.ACTION_MOVE && dragging) parameters?.let { p ->
                    val x = floatingCoordinate(null,windowX + (event.rawX-downX).toInt(),screenWidth,p.width)
                    val y = floatingCoordinate(null,windowY + (event.rawY-downY).toInt(),screenHeight,p.height)
                    if (p.x != x || p.y != y) {
                        p.x = x; p.y = y; applyLayout()
                        main.removeCallbacks(lockTask); main.postDelayed(lockTask,5000)
                    }
                }
                if (event.actionMasked == MotionEvent.ACTION_POINTER_DOWN) { lock(); return@setOnTouchListener true }
                if (event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_CANCEL) {
                    if (dragging) savePosition()
                    dragging = false
                    main.removeCallbacks(lockTask); main.postDelayed(lockTask,5000)
                }
                true
            }
        }
    }
    private var attached = false
    val visible get() = attached
    var failure: String? = null
        private set
    fun update(config: JSONObject, fields: Map<String, JSONObject>, samples: Map<String, JSONObject>) {
        if (!config.optBoolean("overlayEnabled") || (!privileged && !Settings.canDrawOverlays(context)) || config.optJSONArray("overlays")?.length() == 0) { close(); return }
        val density = context.resources.displayMetrics.density
        val screen = context.resources.displayMetrics.widthPixels
        val viewportChanged = screenWidth != screen || screenHeight != context.resources.displayMetrics.heightPixels
        screenWidth = screen; screenHeight = context.resources.displayMetrics.heightPixels
        if (viewportChanged && attached) {
            monitor?.close(); monitor = null; monitorReady = false
            main.removeCallbacks(lockTask); armed = false; unlocked = false; dragging = false; view.editing = false
        }
        val barHeight = if (Build.VERSION.SDK_INT >= 30) windows.maximumWindowMetrics.windowInsets.getInsetsIgnoringVisibility(WindowInsets.Type.statusBars()).top else 0
        val statusHeight = barHeight.takeIf { it > 0 } ?: (56 * density).toInt()
        val placement = stripPlacement(statusHeight, (config.optDouble("overlayOffset",0.0) * density).toInt(), (24 * density).toInt())
        val left = (config.optDouble("overlayLeft",128.0) * density).toInt().coerceIn(0, screen / 2)
        val right = (config.optDouble("overlayRight",320.0) * density).toInt().coerceIn(0, screen / 2)
        val windowOpacity = if (!privileged && Build.VERSION.SDK_INT >= 31) context.getSystemService(InputManager::class.java).maximumObscuringOpacityForTouch.coerceAtMost(1f) else 1f
        view.configure(config, fields, samples, windowOpacity)
        val width = view.contentWidth((screen-left-right).coerceAtLeast((64*density).toInt()),placement.height)
        val initialX = (screen-width)/2
        fun coordinate(key: String) = if (config.has(key) && !config.isNull(key)) config.optDouble(key).takeIf { it.isFinite() && it in 0.0..1.0 } else null
        val fractionX = coordinate("overlayX"); val fractionY = coordinate("overlayY")
        val previous = parameters
        val reset = !attached || viewportChanged || fractionX != configuredX || fractionY != configuredY
        val defaultCentered = fractionX == null && configuredX == null && !armed && !unlocked
        val next = WindowManager.LayoutParams(width, placement.height,
            if (privileged) WindowManager.LayoutParams.TYPE_SYSTEM_ERROR else WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT).apply {
                gravity = Gravity.TOP or Gravity.LEFT
                title = "SkyInfo status strip"
                if (privileged) packageName = "com.android.shell"
                x = floatingCoordinate(if (reset) fractionX else null,if (reset || defaultCentered) initialX else previous?.x ?: initialX,screen,width)
                if (Build.VERSION.SDK_INT >= 30) setFitInsetsTypes(0)
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                y = floatingCoordinate(if (reset) fractionY else null,if (reset) placement.y else previous?.y ?: placement.y,screenHeight,placement.height)
                alpha = windowOpacity
            }
        parameters = next; configuredX = fractionX; configuredY = fractionY
        if (armed || unlocked) next.flags = next.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
        try {
            if (attached) windows.updateViewLayout(view,next) else {
                windows.addView(view,next); attached = true
                report()
            }
            if (privileged && monitor == null) {
                monitor = OverlayTouchMonitor(main,screenWidth,screenHeight,::observeTap) { state ->
                    monitorReady = state == "ready"
                    if (!monitorReady) lock() else report()
                }.also { it.start() }
            }
            failure = null
        }
        catch (error: Throwable) { failure = error.javaClass.simpleName; android.util.Log.w("SkyInfo.Vehicle","Status strip window failed",error); close() }
    }
    private fun observeTap(point: TouchPoint) {
        if (!attached || armed || unlocked) return
        val p = parameters ?: return
        when (point.action) {
            MotionEvent.ACTION_DOWN -> {
                tap = point.takeIf { overlayHit(point.x-p.x,point.y-p.y,p.width,p.height) }; moved = false
            }
            MotionEvent.ACTION_MOVE -> tap?.let {
                val slop = ViewConfiguration.get(context).scaledTouchSlop
                if (kotlin.math.abs(point.x-it.x) > slop || kotlin.math.abs(point.y-it.y) > slop) moved = true
            }
            MotionEvent.ACTION_UP -> {
                val start = tap; tap = null
                if (start != null && !moved && point.time-start.time <= ViewConfiguration.getLongPressTimeout() && overlayHit(point.x-p.x,point.y-p.y,p.width,p.height)) arm()
            }
            MotionEvent.ACTION_CANCEL -> tap = null
        }
    }
    fun arm(): Boolean {
        if (!attached) return false
        armed = true; unlocked = false; tap = null
        updateTouchability()
        main.removeCallbacks(lockTask); main.postDelayed(lockTask,5000)
        return true
    }
    private fun lock() {
        if (dragging) savePosition()
        armed = false; unlocked = false; dragging = false; tap = null
        main.removeCallbacks(lockTask); updateTouchability()
    }
    private fun updateTouchability() {
        parameters?.let { p ->
            p.flags = if (armed || unlocked) p.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
                else p.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
            view.editing = armed || unlocked
            view.invalidate(); applyLayout(); report()
        }
    }
    private fun applyLayout() {
        if (!attached) return
        try { windows.updateViewLayout(view,parameters!!) } catch (_: Throwable) { close() }
    }
    private fun report() {
        changed(JSONObject().put("state",if (unlocked) "unlocked" else if (armed) "armed" else "locked")
            .put("gesture",monitorReady).put("visible",attached))
    }
    private fun savePosition() {
        val p = parameters ?: return
        val x = if (screenWidth > p.width) p.x.toDouble()/(screenWidth-p.width) else 0.0
        val y = if (screenHeight > p.height) p.y.toDouble()/(screenHeight-p.height) else 0.0
        configuredX = x; configuredY = y
        changed(JSONObject().put("state","unlocked").put("gesture",monitorReady).put("visible",attached)
            .put("x",x).put("y",y))
    }
    fun close() {
        main.removeCallbacks(lockTask); monitor?.close(); monitor = null; monitorReady = false
        armed = false; unlocked = false; dragging = false; tap = null; view.editing = false
        if (attached) { try { windows.removeView(view) } catch (_: Throwable) { }; attached = false; report() }
    }
}
private class StripView(context: Context) : View(context) {
    private val chinese = Typeface.createFromAsset(context.assets,"flutter_assets/assets/fonts/ChillDINGothic_Std.otf")
    private val mono = Typeface.createFromAsset(context.assets,"flutter_assets/assets/fonts/IBMPlexMono-Medium.ttf")
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val icons = mutableMapOf<String, SVG>()
    private var config = JSONObject()
    private var samples = emptyMap<String, JSONObject>()
    private var definitions = emptyMap<String, JSONObject>()
    private var windowOpacity = 1f
    var editing = false
    private fun reading(module: JSONObject): String {
        val sample = samples[module.optString("field")]
        val raw = sample?.opt("value")
        return if (sample?.optString("quality") !in listOf("available","unverified") || raw == null) "—"
            else if (raw is Number) String.format(Locale.ROOT,"%.${module.optInt("digits",1).coerceIn(0,4)}f",raw.toDouble()) else raw.toString()
    }
    private fun span(module: JSONObject, font: Float): Float {
        val density = resources.displayMetrics.density
        paint.typeface = mono; paint.textSize = font
        val valueWidth = paint.measureText(reading(module))
        paint.typeface = chinese; paint.textSize = font*0.75f
        return (if(module.optString("icon").isEmpty()) 0f else font+8*density)+valueWidth+(if(unit(module).isEmpty()) 0f else 4*density)+paint.measureText(unit(module))+16*density
    }
    private fun unit(module: JSONObject): String {
        val id = module.optString("field"); val field = definitions[id]
        val custom = module.optString("unit")
        if(module.optBoolean("unitAuto")) return samples[id]?.optString("unit") ?: field?.optString("unit") ?: ""
        return if (field?.has("unitField") == true && (custom == NativeStrings.raw_value || custom == field.optString("unit")))
            samples[id]?.optString("unit")?.takeIf(String::isNotEmpty) ?: NativeStrings.raw_value else custom
    }
    fun contentWidth(maximum: Int, height: Int): Int {
        val font = (config.optDouble("overlayFont",18.0)*resources.displayMetrics.density).toFloat().coerceAtMost(height*0.65f)
        val modules = config.optJSONArray("overlays") ?: return maximum
        val widths = listOf("left","center","right").map { alignment ->
            (0 until modules.length()).map(modules::getJSONObject).filter { it.optString("alignment") == alignment }.sumOf { span(it,font).toDouble() }
        }.filter { it > 0 }
        return ((widths.maxOrNull() ?: 0.0)*widths.size+24*resources.displayMetrics.density).toInt().coerceIn(1,maximum)
    }
    fun configure(value: JSONObject, fields: Map<String, JSONObject>, readings: Map<String, JSONObject>, opacity: Float) {
        config = JSONObject(value.toString()); samples = readings.filterKeys(fields::containsKey); definitions = fields; windowOpacity = opacity; invalidate()
    }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val theme = config.optString("theme", "system")
        val dark = theme == "dark" || (theme == "system" && resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES)
        val background = if (dark) Color.rgb(37,37,37) else Color.WHITE
        val ink = if (dark) Color.rgb(239,239,239) else Color.rgb(32,32,32)
        val density = resources.displayMetrics.density
        val requestedFont = config.optDouble("overlayFont",18.0).toFloat() * density
        val modules = config.optJSONArray("overlays") ?: return
        val alignments = listOf("left","center","right").filter { alignment -> (0 until modules.length()).any { modules.getJSONObject(it).optString("alignment") == alignment } }
        for ((index, alignment) in alignments.withIndex()) {
            var font = requestedFont.coerceAtMost(height * 0.65f)
            val group = (0 until modules.length()).map(modules::getJSONObject).filter { it.optString("alignment") == alignment }
            val region = width / alignments.size.toFloat()
            val initial = group.sumOf { span(it,font).toDouble() }.toFloat()
            if (initial > region-24*density && initial > 0) font *= ((region-24*density)/initial).coerceAtLeast(0.1f)
            val total = group.sumOf { span(it,font).toDouble() }.toFloat()
            var x = index*region + when(alignment) { "center" -> (region-total)/2; "right" -> region-total-12*density; else -> 12*density }
            for (module in group) {
                val block = span(module,font)
                paint.color = stripBackgroundColor(background,config.optDouble("overlayOpacity",0.8),windowOpacity)
                val target = RectF(x-4*density,(height-font)/2-4*density,x+block-8*density,(height+font)/2+4*density)
                canvas.drawRect(target,paint)
                val iconId = module.optString("icon")
                if (Regex("^[a-z0-9-]+$").matches(iconId)) {
                    try {
                        val icon = icons.getOrPut(iconId) { SVG.getFromAsset(context.assets,"flutter_assets/assets/icons/$iconId.svg") }
                        canvas.save(); canvas.translate(x,(height-font)/2); canvas.scale(font/24,font/24)
                        val filter = Paint().apply { colorFilter = PorterDuffColorFilter(ink,PorterDuff.Mode.SRC_IN) }
                        canvas.saveLayer(0f,0f,24f,24f,filter); icon.renderToCanvas(canvas, RectF(0f,0f,24f,24f)); canvas.restore(); canvas.restore()
                    } catch (_: Throwable) { }
                }
                if(iconId.isNotEmpty()) x+=font+8*density
                paint.color=ink; paint.typeface=mono; paint.textSize=font
                val baseline = (height-paint.fontMetrics.ascent-paint.fontMetrics.descent)/2
                val text=reading(module); canvas.drawText(text,x,baseline,paint); x+=paint.measureText(text)+(if(unit(module).isEmpty()) 0f else 4*density)
                paint.typeface=chinese; paint.textSize=font*0.75f
                val unit=unit(module); canvas.drawText(unit,x,baseline,paint); x+=paint.measureText(unit)+16*density
            }
        }
        if (editing) {
            paint.color = Color.rgb(255,212,41); paint.style = Paint.Style.STROKE; paint.strokeWidth = 2*density
            canvas.drawRect(density,density,width-density,height-density,paint); paint.style = Paint.Style.FILL
        }
    }
}

internal fun stripBackgroundColor(color: Int, opacity: Double, windowOpacity: Float = 1f): Int {
    val alpha = (opacity.coerceIn(0.1,0.8) / windowOpacity.coerceIn(0.1f,1f) * 255).roundToInt().coerceIn(0,255)
    return Color.argb(alpha,Color.red(color),Color.green(color),Color.blue(color))
}
