package app.skyinfo.vehicle

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

class VehicleControls(private val port: Port) {
    interface Port { fun read(device: Int, field: Int): Int; fun write(device: Int, fields: IntArray, values: IntArray): Int; fun environment(): JSONObject = JSONObject(); fun supports(readRequired: Boolean, arrayWrite: Boolean): Boolean = true }
    constructor(context: Context) : this(port(context))
    data class Definition(val id: String, val name: String, val device: Int, val read: Int, val write: Int, val min: Int, val max: Int, val source: Boolean = false, val verified: JSONObject? = null) {
        val inferred get() = verified?.optString("validation") == "inferred"
        fun validate(value: Int) { require(if (verified != null) (0 until verified.getJSONArray("options").length()).any { verified.getJSONArray("options").getJSONObject(it).getInt("value") == value } else value in min..max) { "value_out_of_range:$min..$max" } }
    }
    private fun read(d: Definition): Int = port.read(d.verified?.getJSONObject("read")?.getInt("device") ?: d.device,d.read)
    private fun validRead(d: Definition, value: Int): Boolean {
        val limits = d.verified?.optJSONArray("readLimits")
        return if (d.inferred) value in 0..65534 else if (limits != null) value in limits.getInt(0)..limits.getInt(1) else if (d.id == "ac_wind_level") value in 0..7 else value in d.min..d.max
    }
    fun snapshot(): JSONObject {
        val entries = JSONArray()
        for (d in definitions) {
            val e = metadata(d)
            try { if (d.inferred || d.read == 0) e.put("readable",false) else { val raw = read(d); e.put("raw",raw).put("readable",validRead(d,raw)) } }
            catch (error: Throwable) { e.put("readable",false).put("error",(error.cause ?: error).javaClass.simpleName) }
            entries.put(e)
        }
        return JSONObject().put("uid",android.os.Process.myUid()).put("identity",port.environment()).put("controls",entries)
    }
    @Synchronized fun execute(id: String, value: Int): JSONObject {
        val d = definition(id); d.validate(value)
        if (d.verified != null) return executeVerified(d,value)
        val result = JSONObject().put("action",id).put("requested",value).put("uid",android.os.Process.myUid())
        return try {
            if (!port.supports(true, id == "ac_temperature" || d.source)) return result.put("status","unsupported_environment")
            val before = read(d); result.put("before",before)
            if (!validRead(d,before)) return result.put("status","unsupported_state")
            val temperature = id == "ac_temperature"
            if (temperature) {
                val unit = port.read(1000,1077936167); val passenger = port.read(1000,1077936176)
                result.put("temperature_unit",unit).put("before_passenger",passenger)
                if (unit != 1 || passenger !in 17..33) return result.put("status","unsupported_state")
            }
            val fields = if (temperature) intArrayOf(501219392,501219368,501219376,501219384,501219349) else if (d.source) intArrayOf(d.write,501219349) else intArrayOf(d.write)
            val values = if (temperature) intArrayOf(1,value,0,0,0) else if (d.source) intArrayOf(value,0) else intArrayOf(value)
            val status = port.write(d.device,fields,values)
            result.put("native_status",status)
            if (status != 0) return result.put("status","rejected")
            if (temperature) {
                var mainReady = false
                repeat(4) { if (!mainReady) { mainReady = read(d) == value; if (!mainReady) Thread.sleep(150) } }
                if (!mainReady || Thread.currentThread().isInterrupted) return result.put("status","accepted_unconfirmed").put("actual",read(d))
                val passengerStatus = port.write(d.device,fields,intArrayOf(1,0,value,0,0))
                result.put("passenger_native_status",passengerStatus)
                if (passengerStatus != 0) return result.put("status","partial_unconfirmed")
            }
            val expected = value
            repeat(10) {
                val actual = read(d); result.put("actual",actual)
                val passenger = if (temperature) port.read(1000,1077936176) else expected
                if (temperature) result.put("actual_passenger",passenger)
                if (actual == expected && passenger == expected) return result.put("status","confirmed")
                Thread.sleep(200)
            }
            result.put("status","accepted_unconfirmed")
        } catch (error: Throwable) { val cause = error.cause ?: error; result.put("status",if (cause is SecurityException) "permission" else "error").put("error",cause.javaClass.simpleName) }
    }
    private fun executeVerified(d: Definition, value: Int): JSONObject {
        val spec = d.verified!!
        val options = spec.getJSONArray("options")
        val option = (0 until options.length()).map { options.getJSONObject(it) }.first { it.getInt("value") == value }
        val result = JSONObject().put("action",d.id).put("requested",value).put("uid",android.os.Process.myUid())
        return try {
            val env = port.environment(); result.put("identity",env)
            val write = option.getJSONObject("write")
            if (env.optString("protocol") != spec.optString("protocol", "CANFD") || !port.supports(d.read != 0, write.getJSONArray("features").length() > 1)) return result.put("status","unsupported_environment")
            val stopPlan = option.optJSONObject("stop")
            if (stopPlan != null && !port.supports(false,stopPlan.getJSONArray("features").length() > 1)) return result.put("status","unsupported_environment")
            if (d.read != 0) {
                val before = read(d); result.put("before",before)
                if (!validRead(d,before)) return result.put("status","unsupported_state")
                val features = spec.getJSONObject("read").getJSONArray("features")
                if (features.length() > 1) {
                    val values=JSONObject()
                    for (index in 0 until features.length()) {
                        val field=features.getInt(index);val raw=port.read(spec.getJSONObject("read").getInt("device"),field)
                        values.put(field.toString(),raw)
                        if (!validRead(d,raw)) return result.put("before_values",values).put("status","unsupported_state")
                    }
                    result.put("before_values",values)
                }
            }
            if (d.id in listOf("main_temp","deputy_temp") && port.read(1000,1077936167) != 1) return result.put("status","unsupported_state")
            val stop = option.optJSONObject("stop")
            val cleanup = stop?.let { plan -> stopper.schedule<Int>({ writePlan(plan) },plan.getLong("delayMs"),java.util.concurrent.TimeUnit.MILLISECONDS) }
            try { result.put("native_status",writePlan(option.getJSONObject("write"))) }
            finally {
                if (cleanup != null) {
                    val stopRanBeforeReturn = cleanup.isDone
                    var interrupted = false
                    var stopped = try { cleanup.get(2,java.util.concurrent.TimeUnit.SECONDS) }
                        catch (_: InterruptedException) { interrupted = true; cleanup.get(2,java.util.concurrent.TimeUnit.SECONDS) }
                    if (stopRanBeforeReturn) {
                        result.put("early_stop_native_status",stopped)
                        val finalStop = stopper.submit<Int> { writePlan(stop) }
                        stopped = try { finalStop.get(2,java.util.concurrent.TimeUnit.SECONDS) }
                            catch (_: InterruptedException) { interrupted = true; finalStop.get(2,java.util.concurrent.TimeUnit.SECONDS) }
                    }
                    result.put("stop_native_status",stopped)
                    if (interrupted) Thread.currentThread().interrupt()
                }
            }
            if (result.getInt("native_status") != 0) return result.put("status","rejected")
            if (result.has("stop_native_status") && result.getInt("stop_native_status") != 0) return result.put("status","stop_unconfirmed")
            val expected = if (option.isNull("expected")) null else option.getInt("expected")
            if (expected == null) {
                if (d.read != 0) result.put("actual",read(d))
                return result.put("status","accepted_unconfirmed")
            }
            repeat(10) {
                val actual = read(d); result.put("actual",actual)
                if (actual == expected) return result.put("status","confirmed")
                Thread.sleep(150)
            }
            result.put("status","accepted_unconfirmed")
        } catch (error: Throwable) { val cause = error.cause ?: error; result.put("status",if (cause is SecurityException) "permission" else "error").put("error",cause.javaClass.simpleName) }
    }
    private fun writePlan(plan: JSONObject) = port.write(plan.getInt("device"),array(plan.getJSONArray("features")),array(plan.getJSONArray("values")))
    companion object {
        private fun port(context: Context): Port {
            val type = Class.forName("android.hardware.BYDAutoManager")
            val manager = type.getConstructor(Context::class.java).newInstance(context)
            return object : Port {
                override fun environment(): JSONObject {
                    val properties = Class.forName("android.os.SystemProperties").getMethod("get",String::class.java)
                    return JSONObject().put("uid",android.os.Process.myUid()).put("user",context.applicationInfo.uid / 100000)
                        .put("firmware",properties.invoke(null,"apps.setting.product.outswver")).put("protocol",properties.invoke(null,"sys.car.protocol"))
                }
                override fun supports(readRequired: Boolean, arrayWrite: Boolean): Boolean = runCatching {
                    if (readRequired) type.getMethod("getInt",Int::class.javaPrimitiveType,Int::class.javaPrimitiveType)
                    if (arrayWrite) type.getMethod("setIntArray",Int::class.javaPrimitiveType,IntArray::class.java,IntArray::class.java)
                    else type.getMethod("setInt",Int::class.javaPrimitiveType,Int::class.javaPrimitiveType,Int::class.javaPrimitiveType)
                }.isSuccess
                override fun read(device: Int, field: Int) = type.getMethod("getInt",Int::class.javaPrimitiveType,Int::class.javaPrimitiveType).invoke(manager,device,field) as Int
                override fun write(device: Int, fields: IntArray, values: IntArray) = if (fields.size == 1)
                    type.getMethod("setInt",Int::class.javaPrimitiveType,Int::class.javaPrimitiveType,Int::class.javaPrimitiveType).invoke(manager,device,fields[0],values[0]) as Int
                    else type.getMethod("setIntArray",Int::class.javaPrimitiveType,IntArray::class.java,IntArray::class.java).invoke(manager,device,fields,values) as Int
            }
        }
        val definitions = listOf(
            Definition("ac_power",NativeStrings.text_8f9011f3d3,1000,1077936144,501219364,0,1,true),
            Definition("ac_control_mode",NativeStrings.text_a8f4df87fd,1000,1077936146,501219352,0,1,true),
            Definition("ac_cycle",NativeStrings.text_aa6df49460,1000,1077936148,501219355,0,1,true),
            Definition("ac_wind_level",NativeStrings.text_e16e4c3b56,1000,1077936156,501219340,1,7,true),
            Definition("ac_front_defrost",NativeStrings.text_6f3c1d5845,1000,1077936150,501219362,0,1,true),
            Definition("ac_temperature",NativeStrings.text_acb1e6af4e,1000,1077936168,501219368,17,33),
            Definition("ac_rear_defrost",NativeStrings.text_01059924f6,1000,1128267825,501219357,0,1,true),
            Definition("steering_wheel_heat",NativeStrings.text_e11376096a,1023,1116733454,944767029,1,2),
            Definition("wireless_charging",NativeStrings.text_64461dc36b,1009,1105199120,1312817218,1,2),
            Definition("seat_driver_heat",NativeStrings.text_7c5724a6d3,1023,1335885835,1125122068,1,3),
            Definition("seat_passenger_heat",NativeStrings.text_7465cedd30,1023,1335885843,1125122076,1,4),
            Definition("seat_driver_vent",NativeStrings.text_4e3c45d556,1023,1335885832,1125122064,1,4),
            Definition("seat_passenger_vent",NativeStrings.text_23afd6a7fa,1023,1335885840,1125122072,1,4)
        ) + planDefinitions(verifiedControlPlans) + planDefinitions(inferredControlPlans)
        private fun planDefinitions(json: String) = JSONArray(json).let { specs -> (0 until specs.length()).map { index ->
            val spec=specs.getJSONObject(index);val options=spec.getJSONArray("options");val first=options.getJSONObject(0).getJSONObject("write")
            val allowed=(0 until options.length()).map { options.getJSONObject(it).getInt("value") }
            Definition(spec.getString("id"),spec.getString("name"),first.getInt("device"),spec.getJSONObject("read").getJSONArray("features").optInt(0,0),first.getJSONArray("features").getInt(0),allowed.min(),allowed.max(),verified=spec)
        } }
        private val stopper = java.util.concurrent.Executors.newSingleThreadScheduledExecutor { task -> Thread(task,"SkyInfo-control-stop").apply { isDaemon = true } }
        private fun array(values: JSONArray) = IntArray(values.length()) { values.getInt(it) }
        fun metadata(d: Definition): JSONObject {
            val options = d.verified?.getJSONArray("options") ?: JSONArray((d.min..d.max).map { value -> JSONObject().put("value",value).put("label",legacyLabel(d.id,value)) })
            return JSONObject().put("id",d.id).put("name",d.name).put("min",d.min).put("max",d.max)
                .put("validation",if (d.inferred) "inferred" else "verified").put("assessment",d.verified?.optString("assessment") ?: "verified")
                .put("category",d.verified?.optString("category") ?: if (d.id.startsWith("seat_") || d.id == "steering_wheel_heat") NativeStrings.text_88c48ae75b else if (d.id == "wireless_charging") NativeStrings.text_72129c7bbb else NativeStrings.text_0f48e53559)
                .put("states",JSONObject().apply { for (index in 0 until options.length()) { val option=options.getJSONObject(index); if (d.verified == null) put(option.getInt("value").toString(),option.getString("label")) else if (!option.isNull("expected")) put(option.getInt("expected").toString(),option.getString("label")) } })
                .put("options",JSONArray((0 until options.length()).map { index -> val o=options.getJSONObject(index); JSONObject().put("value",o.getInt("value")).put("label",o.getString("label")) }))
        }
        fun entityCapability(d: Definition): String {
            if (d.id in listOf("ac_temperature","ac_wind_level")) return "number"
            val data=metadata(d);val options=data.getJSONArray("options")
            val labels=(0 until options.length()).map { options.getJSONObject(it).getString("label") }.toSet()
            val states=data.getJSONObject("states")
            if (!d.inferred && d.read != 0 && options.length()==2 && states.length()==2 && labels==setOf(NativeStrings.on,NativeStrings.close)) return "toggle"
            return if (!d.inferred && d.read != 0 && states.length()>0 && options.length()>1) "select" else "button"
        }
        private fun legacyLabel(id: String, value: Int): String = when {
            id == "ac_temperature" -> "${value}°C"
            id == "ac_wind_level" -> NativeStrings.text("native_level",mapOf("value" to value))
            id == "ac_cycle" -> if (value == 0) NativeStrings.text_5708518ee3 else NativeStrings.text_f587f15868
            id == "ac_control_mode" -> if (value == 0) NativeStrings.text_4afad87755 else NativeStrings.text_2a4a4de806
            id == "wireless_charging" -> if (value == 1) NativeStrings.on else NativeStrings.close
            id == "steering_wheel_heat" -> if (value == 1) NativeStrings.close else NativeStrings.on
            id.startsWith("seat_") -> if (value == 1) NativeStrings.close else NativeStrings.text("native_level",mapOf("value" to value-1))
            else -> if (value == 0) NativeStrings.close else NativeStrings.on
        }
        fun definition(id: String) = definitions.find { it.id == id } ?: throw IllegalArgumentException("unknown_action")
    }
}
