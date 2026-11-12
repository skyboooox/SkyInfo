package app.skyinfo.vehicle

import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[34],manifest=Config.NONE)
class HaDiscoveryTest {
    private val field=JSONObject().put("id","1032/7/1128267816").put("name","低压电压").put("entityKey","low_voltage").put("unit","V")
    private val config=JSONObject().put("connection","ha").put("prefix","skyinfo_demo").put("haUrl","http://192.168.10.20:8123/")
    private val secret=object:SecretStore { override fun secret(name:String)="test" }
    @Test fun measurementsAndRawNumbersKeepTheirTypesWhileRealTextStaysText() {
        val normalized=haReading(JSONObject().put("value",13.7).put("quality","available"),field)
        assertTrue(normalized.get("value") is Number)
        val definition=haSensorDiscovery("device","skyinfo_demo","0.4.14",field,"sensor.legacy")
        assertEquals("measurement",definition.getString("state_class"));assertEquals("voltage",definition.getString("device_class"))
        assertEquals("V",definition.getString("unit_of_measurement"))
        assertEquals("sensor.legacy",definition.getString("default_entity_id"))
        val unknown=JSONObject(field.toString()).put("unit","").put("encoding","原值")
        assertTrue(haReading(JSONObject().put("value",30005).put("quality","unverified"),unknown).get("value") is Number)
        assertFalse(haSensorDiscovery("device","skyinfo_demo","0.4.14",unknown,"sensor.raw").has("state_class"))
        val text=JSONObject().put("id","system.os").put("name","系统版本").put("entityKey","os").put("encoding","文本")
        assertEquals("Android",haReading(JSONObject().put("value","Android").put("quality","available"),text).get("value"))
        assertFalse(haSensorDiscovery("device","skyinfo_demo","0.4.14",text,"sensor.os").has("state_class"))
    }
    @Test fun invalidNumericStringsDoNotBecomeTextMeasurementsOrZero() {
        for (value in listOf("13.7","NaN","65535",JSONObject.NULL)) {
            val result=haReading(JSONObject().put("value",value).put("raw",value).put("quality","available").put("updatedAt",1000),field)
            assertTrue(result.isNull("value"));assertEquals("invalid",result.getString("quality"))
            assertEquals(1000,result.getLong("updatedAt"));assertEquals(value,result.get("raw"))
        }
    }
    @Test fun enumCodesDoNotGetMeasurementStatistics() {
        val enum=JSONObject(field.toString()).put("unit","").put("encoding","枚举")
        assertFalse(haSensorDiscovery("device","skyinfo_demo","0.4.14",enum,"sensor.enum").has("state_class"))
        assertEquals(0,haReading(JSONObject().put("value",0).put("quality","available"),enum).getInt("value"))
    }
    @Test fun allFieldsShareAStableDeviceAndConfirmedClassesMatchUnits() {
        for ((unit,kind) in mapOf("mV" to "voltage","A" to "current","W" to "power","kW" to "power","°C" to "temperature","°F" to "temperature")) {
            val changed=JSONObject(field.toString()).put("unit",unit)
            val definition=haSensorDiscovery("stable","skyinfo_demo","0.4.14",changed,"sensor.legacy")
            assertEquals(kind,definition.getString("device_class"))
            assertEquals("skyinfo_stable",definition.getJSONObject("device").getJSONArray("identifiers").getString(0))
            assertEquals(unit,definition.getString("unit_of_measurement"))
        }
    }
    @Test fun onlyLegacyManagedStatesAreRemovedAndRegistrationIsNotRepeatedPerReading() {
        val calls=mutableListOf<String>();val publishes=mutableListOf<JSONObject>()
        val http=OkHttpClient.Builder().addInterceptor { chain ->
            val request=chain.request();calls.add(request.method)
            val body=if (request.method=="GET") JSONObject().put("attributes",JSONObject().put("metric_id",field.getString("id")).put("source",field.getString("id")).put("session_id","old")).toString() else "[]"
            if (request.method=="POST") { val b=okio.Buffer();request.body!!.writeTo(b);publishes.add(JSONObject(b.readUtf8()));assertEquals("/api/services/mqtt/publish",request.url.encodedPath) }
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK").body(body.toResponseBody()).build()
        }.build()
        val publisher=ConnectionClient(RuntimeEnvironment.getApplication(),secret,http)
        val sample=JSONObject().put("value",13.7).put("quality","available").put("raw",13.7).put("updatedAt",1000)
        repeat(2) { publisher.publish(config,mapOf(field.getString("id") to sample),mapOf(field.getString("id") to field)) }
        assertEquals(listOf("GET","DELETE","POST","POST","POST"),calls)
        assertTrue(publishes.first().getBoolean("retain"));assertFalse(publishes.last().getBoolean("retain"))
        val state=JSONObject(publishes.last().getString("payload"));assertTrue(state.get("value") is Number);assertEquals(13.7,state.getDouble("value"),0.0)
        assertEquals(1000,state.getLong("sampled_at"));assertEquals(13.7,state.getDouble("raw"),0.0)
    }
    @Test fun unmappedForeignEntitiesAreNeverDeletedOrOverwritten() {
        for (attrs in listOf("{\"friendly_name\":\"foreign\"}","{\"skyinfo_device\":\"another-device\"}")) {
        val calls=mutableListOf<String>()
        val http=OkHttpClient.Builder().addInterceptor { chain ->
            calls.add(chain.request().method)
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK").body((if(chain.request().method=="GET") "{\"attributes\":$attrs}" else "[]").toResponseBody()).build()
        }.build()
        val publisher=ConnectionClient(RuntimeEnvironment.getApplication(),secret,http)
        publisher.publish(config,mapOf(field.getString("id") to JSONObject().put("value",13.7).put("quality","available")),mapOf(field.getString("id") to field))
        assertEquals(if(attrs.contains("skyinfo_device")) listOf("GET") else listOf("GET","POST"),calls);assertNotEquals("已连接",publisher.status)
        }
    }
    @Test fun registeredUnavailableSensorsWithoutAttributesAreRecognizedByDeviceRegistry() {
        val config = JSONObject(config.toString()).put("haUrl", "http://192.168.10.30:8123/")
        val context=RuntimeEnvironment.getApplication()
        context.getSharedPreferences("skyinfo.device",0).edit().putString("id","stable").commit()
        val paths=mutableListOf<String>()
        val http=OkHttpClient.Builder().addInterceptor { chain ->
            val request=chain.request();paths.add(request.method+" "+request.url.encodedPath)
            assertEquals("192.168.10.30", request.url.host)
            val body=when(request.url.encodedPath) {
                "/api/states/sensor.skyinfo_skyinfo_demo_low_voltage" -> "{\"state\":\"unavailable\",\"attributes\":{}}"
                "/api/template" -> "[[\"mqtt\",\"skyinfo_stable\"]]"
                else -> "[]"
            }
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK").body(body.toResponseBody()).build()
        }.build()
        val publisher=ConnectionClient(context,secret,http)
        publisher.publish(config,mapOf(field.getString("id") to JSONObject().put("value",JSONObject.NULL).put("quality","invalid")),mapOf(field.getString("id") to field))
        assertEquals("已连接",publisher.status)
        assertEquals(listOf("GET /api/states/sensor.skyinfo_skyinfo_demo_low_voltage","POST /api/template","POST /api/services/mqtt/publish","POST /api/services/mqtt/publish"),paths)
        assertFalse(paths.any { it.startsWith("DELETE") })
    }
    @Test fun dynamicUnitsReconfigureDiscoveryButDisconnectedValuesStayUnavailable() {
        val messages=mutableListOf<JSONObject>()
        val http=OkHttpClient.Builder().addInterceptor { chain ->
            val request=chain.request()
            if (request.method=="POST") { val b=okio.Buffer();request.body!!.writeTo(b);messages.add(JSONObject(b.readUtf8())) }
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(if(request.method=="GET") 404 else 200).message("OK").body("{}".toResponseBody()).build()
        }.build()
        val paired=JSONObject(field.toString()).put("unitField","paired")
        val publisher=ConnectionClient(RuntimeEnvironment.getApplication(),secret,http)
        for (unit in listOf("°C","°F")) publisher.publish(config,mapOf(field.getString("id") to JSONObject().put("value",25).put("unit",unit).put("quality","available")),mapOf(field.getString("id") to paired))
        assertEquals(listOf("°C","°F"),messages.filter { it.getBoolean("retain") }.map { JSONObject(it.getString("payload")).getString("unit_of_measurement") })
        publisher.publish(config,mapOf(field.getString("id") to JSONObject().put("value",25).put("unit","°F").put("quality","disconnected").put("updatedAt",1000)),mapOf(field.getString("id") to paired))
        val state=JSONObject(messages.last().getString("payload"));assertTrue(state.isNull("value"));assertEquals("disconnected",state.getString("quality"));assertEquals(1000,state.getLong("sampled_at"))
    }
    @Test fun recoveryResendsCurrentControlStateOnceWithoutRetainingAvailabilityOrDuplicatingDiscovery() {
        val messages=mutableListOf<JSONObject>()
        val http=OkHttpClient.Builder().addInterceptor { chain ->
            val request=chain.request();val body=okio.Buffer();request.body!!.writeTo(body)
            messages.add(JSONObject(body.readUtf8()))
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK").body("[]".toResponseBody()).build()
        }.build()
        val publisher=ConnectionClient(RuntimeEnvironment.getApplication(),secret,http)
        val settings=JSONObject(config.toString()).put("haControlEnabled",true)
        publisher.publishControlEntities(settings,emptyMap(),"current/command",true)
        assertEquals(174,messages.size);assertTrue(messages.first().getBoolean("retain"))
        assertTrue(messages.drop(1).all { !it.getBoolean("retain") })
        val first=messages.drop(1).map { it.getString("payload") }
        messages.clear();publisher.publishControlEntities(settings,emptyMap(),"current/command",true)
        assertTrue(messages.isEmpty())
        publisher.invalidateControlStates();publisher.publishControlEntities(settings,emptyMap(),"current/command",true)
        assertEquals(173,messages.size);assertTrue(messages.all { !it.getBoolean("retain") })
        assertEquals(first,messages.map { it.getString("payload") })
        messages.clear();publisher.publishControlEntities(settings,emptyMap(),"current/command",true)
        assertTrue(messages.isEmpty())
    }
    @Test fun controlPublicationKeepsSampleTimestampsWhileIgnoringTimestampOnlyRefreshes() {
        val messages=mutableListOf<JSONObject>()
        val http=OkHttpClient.Builder().addInterceptor { chain ->
            val request=chain.request();val body=okio.Buffer();request.body!!.writeTo(body);messages.add(JSONObject(body.readUtf8()))
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK").body("[]".toResponseBody()).build()
        }.build()
        val publisher=ConnectionClient(RuntimeEnvironment.getApplication(),secret,http)
        val settings=JSONObject(config.toString()).put("haControlEnabled",true)
        val entity=EntityCatalog.controls(RuntimeEnvironment.getApplication()).first { it.getString("id")=="wireless_charging" }
        val options=entity.getJSONArray("options")
        val reading=JSONObject().put("quality","available").put("raw",options.getJSONObject(0).get("expected")).put("updatedAt",10)
        val samples=mapOf(entity.getString("readField") to reading)
        publisher.publishControlEntities(settings,samples,"current/command",true)
        val first=messages.first { it.getString("topic").endsWith("/wireless_charging/state") }
        assertEquals(10,JSONObject(first.getString("payload")).getInt("updatedAt"))
        messages.clear();reading.put("updatedAt",20)
        publisher.publishControlEntities(settings,samples,"current/command",true)
        assertTrue(messages.isEmpty());assertEquals(20,reading.getInt("updatedAt"))
        reading.put("raw",options.getJSONObject(1).get("expected"))
        publisher.publishControlEntities(settings,samples,"current/command",true)
        assertEquals(1,messages.size);assertEquals(20,JSONObject(messages.single().getString("payload")).getInt("updatedAt"))
    }
    @Test fun recoveryNeverMarksOfflineOrInvalidFeedbackAvailable() {
        val messages=mutableListOf<JSONObject>()
        val http=OkHttpClient.Builder().addInterceptor { chain ->
            val request=chain.request();val body=okio.Buffer();request.body!!.writeTo(body);messages.add(JSONObject(body.readUtf8()))
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK").body("[]".toResponseBody()).build()
        }.build()
        val publisher=ConnectionClient(RuntimeEnvironment.getApplication(),secret,http)
        val settings=JSONObject(config.toString()).put("haControlEnabled",true)
        publisher.publishControlEntities(settings,emptyMap(),"current/command",false)
        assertTrue(messages.drop(1).all { !JSONObject(it.getString("payload")).getBoolean("available") })
        messages.clear();publisher.invalidateControlStates();publisher.publishControlEntities(settings,emptyMap(),"current/command",true)
        val wireless=messages.first { it.getString("topic").endsWith("/wireless_charging/state") }
        assertFalse(JSONObject(wireless.getString("payload")).getBoolean("available"))
        messages.clear();settings.put("haControlEnabled",false);publisher.invalidateControlStates();publisher.publishControlEntities(settings,emptyMap(),"current/command",true)
        assertEquals(173,messages.size);assertTrue(messages.all { !JSONObject(it.getString("payload")).getBoolean("available") && !it.getBoolean("retain") })
    }
    @Test fun partiallyFailedRecoveryRetriesOnlyUndeliveredControlStates() {
        val messages=mutableListOf<JSONObject>();var failPublish=false;var failed=false
        val http=OkHttpClient.Builder().addInterceptor { chain ->
            val request=chain.request();val body=okio.Buffer();request.body!!.writeTo(body);val message=JSONObject(body.readUtf8())
            if (failPublish && !failed && messages.size==5) { failed=true;throw java.io.IOException("simulated publish failure") }
            messages.add(message)
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK").body("[]".toResponseBody()).build()
        }.build()
        val publisher=ConnectionClient(RuntimeEnvironment.getApplication(),secret,http)
        val settings=JSONObject(config.toString()).put("haControlEnabled",true)
        publisher.publishControlEntities(settings,emptyMap(),"current/command",true)
        messages.clear();publisher.invalidateControlStates();failPublish=true
        try { publisher.publishControlEntities(settings,emptyMap(),"current/command",true);fail("publish failure ignored") } catch (_:java.io.IOException) { }
        assertEquals(5,messages.size)
        publisher.retryPublication()
        publisher.publishControlEntities(settings,emptyMap(),"current/command",true)
        assertEquals(173,messages.size);assertEquals(173,messages.map { it.getString("topic") }.toSet().size)
        assertTrue(messages.all { !it.getBoolean("retain") })
    }

    @Test fun delayedHaStateSubscriptionReceivesFiniteNonRetainedSynchronization() {
        var clock=0L
        var subscribed=false
        val messages=mutableListOf<JSONObject>()
        val received=mutableMapOf<String,JSONObject>()
        val http=OkHttpClient.Builder().addInterceptor { chain ->
            val body=okio.Buffer();chain.request().body!!.writeTo(body)
            val message=JSONObject(body.readUtf8());messages.add(message)
            if(subscribed && !message.getBoolean("retain")) received[message.getString("topic")]=JSONObject(message.getString("payload"))
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK").body("[]".toResponseBody()).build()
        }.build()
        val publisher=ConnectionClient(RuntimeEnvironment.getApplication(),secret,http,controlClock={clock})
        val settings=JSONObject(config.toString()).put("haControlEnabled",true)
        publisher.publishControlEntities(settings,emptyMap(),"current/command",false)
        assertEquals(174,messages.size);assertTrue(received.isEmpty());assertEquals(1000L,publisher.controlSyncWaitMillis())
        subscribed=true;messages.clear()
        for(at in listOf(1000L,4000L,11000L)) {
            clock=at;publisher.publishControlEntities(settings,emptyMap(),"current/command",true)
            assertEquals(173,messages.size);assertTrue(messages.all { !it.getBoolean("retain") });messages.clear()
        }
        assertEquals(173,received.size);assertNull(publisher.controlSyncWaitMillis())
        assertTrue(received.entries.first { it.key.endsWith("/rear_wind/state") }.value.getBoolean("available"))
        assertFalse(received.entries.first { it.key.endsWith("/wireless_charging/state") }.value.getBoolean("available"))
        clock=9999999;repeat(20) { publisher.publishControlEntities(settings,emptyMap(),"current/command",true) }
        assertTrue(messages.isEmpty())
        publisher.invalidateControlStates(rediscover=true)
        publisher.publishControlEntities(settings,emptyMap(),"current/command",true)
        assertEquals(174,messages.size);assertTrue(messages.first().getBoolean("retain"));assertEquals(1000L,publisher.controlSyncWaitMillis())
    }
    @Test fun existingAggregateMigratesInPlaceWithOnlyReplacedComponentsRemoved() {
        val context: android.content.Context=RuntimeEnvironment.getApplication()
        val settings=JSONObject(config.toString()).put("haControlEnabled",true)
        val id=DeviceIdentity(context).id
        val key=java.security.MessageDigest.getInstance("SHA-256")
            .digest((HaEndpoint.identity(settings.getString("haUrl"))+"|"+id+"|"+settings.getString("prefix")).toByteArray())
            .joinToString("") { "%02x".format(it) }
        val prefs=context.getSharedPreferences("skyinfo.ha.control-publication",android.content.Context.MODE_PRIVATE)
        prefs.edit().putBoolean("initialized",true).putString(key,"active").commit()
        val messages=mutableListOf<JSONObject>()
        var failFinal=true
        val http=OkHttpClient.Builder().addInterceptor { chain ->
            val body=okio.Buffer();chain.request().body!!.writeTo(body);val message=JSONObject(body.readUtf8())
            if(message.getBoolean("retain") && JSONObject(message.getString("payload")).getJSONObject("components").length()==0 && failFinal) {
                failFinal=false;throw java.io.IOException("simulated interrupted discovery update")
            }
            messages.add(message)
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK").body("[]".toResponseBody()).build()
        }.build()
        var publisher=ConnectionClient(context,secret,http)
        assertThrows(java.io.IOException::class.java) { publisher.publishControlEntities(settings,emptyMap(),"current/command",true) }
        assertFalse(prefs.getBoolean("layout_$key",false));assertEquals(1,messages.size)
        publisher=ConnectionClient(context,secret,http);messages.clear()
        publisher.publishControlEntities(settings,emptyMap(),"current/command",true)
        val discoveries=messages.filter { it.getBoolean("retain") }
        assertEquals(2,discoveries.size)
        assertTrue(discoveries.all { it.getString("topic")=="homeassistant/device/skyinfo_${id}_controls/config" && it.getString("payload").isNotEmpty() })
        val migration=JSONObject(discoveries.first().getString("payload"));val final=JSONObject(discoveries.last().getString("payload"))
        val removed=migration.getJSONObject("components")
        assertEquals(472,removed.length());assertEquals(0,final.getJSONObject("components").length())
        assertFalse(removed.has("skyinfo_${id}_control_ac_power"));assertTrue(removed.has("skyinfo_${id}_control_ac_wind_level"))
        assertEquals("skyinfo_$id",final.getJSONObject("device").getJSONArray("identifiers").getString(0))
        assertEquals(17,final.getJSONArray("child_devices").length());assertTrue(prefs.getBoolean("layout_$key",false))
        messages.clear();publisher=ConnectionClient(context,secret,http)
        publisher.publishControlEntities(settings,emptyMap(),"new/command",true)
        assertEquals(1,messages.count { it.getBoolean("retain") })
        assertTrue(messages.all { it.getString("topic")!="current/command" && it.getString("topic")!="new/command" })
    }

}
