package app.skyinfo.vehicle

import android.content.Context
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class PublicationGateTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private val secrets = object : SecretStore { override fun secret(name: String) = "fixture" }
    private fun config(url: String) = JSONObject().put("connection","ha").put("haUrl",url).put("prefix","fixture")
    @Test fun allLanesShareBackoffAndPermanentFailuresNeedExplicitRecovery() {
        var now = 0L
        val gate = PublicationGate { now }
        assertTrue(gate.allowed()); gate.fail(false); assertFalse(gate.allowed())
        repeat(1000) { gate.fail(false) }
        now = 1000; assertTrue(gate.allowed()); gate.fail(false)
        now = 2999; assertFalse(gate.allowed()); now = 3000; assertTrue(gate.allowed())
        gate.fail(true); now = Long.MAX_VALUE/2; assertFalse(gate.allowed()); assertNull(gate.waitMillis())
        gate.reset(); assertTrue(gate.allowed())
    }
    @Test fun unauthorizedHttpStopsTelemetryDiscoveryAndReceiptsUntilExplicitCheck() {
        for (code in listOf(401,403)) MockWebServer().use { server ->
            server.enqueue(MockResponse().setResponseCode(code))
            val settings = config(server.url("/").toString())
            val publisher = ConnectionClient(context,secrets)
            publisher.configure(settings)
            val field = JSONObject().put("id","v").put("name","voltage").put("entityKey","voltage").put("unit","V")
            val samples = mapOf("v" to JSONObject().put("value",13.6).put("quality","available"))
            repeat(50) { publisher.publish(settings,samples,mapOf("v" to field)) }
            assertEquals(1,server.requestCount)
            assertEquals(NativeStrings.text_dda97ab7aa,publisher.status)
            assertThrows(PublicationDeferredException::class.java) { publisher.controlResult(settings,JSONObject().put("id","receipt")) }
            assertThrows(PublicationDeferredException::class.java) { publisher.publishControlEntities(JSONObject(settings.toString()).put("haControlEnabled",true),emptyMap(),"commands",true) }
            publisher.connectionState(NativeStrings.text_65fe35c45e)
            publisher.publish(settings,samples,mapOf("v" to field)); assertEquals(1,server.requestCount)
            server.enqueue(MockResponse().setResponseCode(200)); publisher.check()
            assertEquals(2,server.requestCount); assertNotNull(publisher.publicationWaitMillis())
            publisher.close()
        }
    }
    @Test fun controlPublicationIsOptInPersistsOfflineWorkAndSeparatesTargets() {
        val messages = mutableListOf<JSONObject>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request(); val buffer = okio.Buffer(); request.body!!.writeTo(buffer)
            messages.add(JSONObject(buffer.readUtf8()))
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK").body("[]".toResponseBody()).build()
        }.build()
        val a = config("http://a.example/")
        var publisher = ConnectionClient(context,secrets,http)
        publisher.publishControlEntities(a,emptyMap(),"",false); assertTrue(messages.isEmpty())
        a.put("haControlEnabled",true)
        publisher.publishControlEntities(a,emptyMap(),"commands",true); assertEquals(174,messages.size)
        val b = JSONObject(a.toString()).put("haUrl","http://b.example/")
        messages.clear(); publisher.publishControlEntities(b,emptyMap(),"commands",true); assertEquals(174,messages.size)
        messages.clear(); publisher.publishControlEntities(b,emptyMap(),"commands",true); assertTrue(messages.isEmpty())
        publisher = ConnectionClient(context,secrets,http)
        b.put("haControlEnabled",false)
        publisher.publishControlEntities(b,emptyMap(),"",false)
        assertEquals(173,messages.size)
        assertTrue(messages.all { !JSONObject(it.getString("payload")).getBoolean("available") && !it.getString("topic").startsWith("homeassistant/") })
        messages.clear(); publisher = ConnectionClient(context,secrets,http)
        publisher.publishControlEntities(b,emptyMap(),"",false); assertTrue(messages.isEmpty())
    }
    @Test fun legacyConfiguredHaGetsOneOfflinePassAndFreshTargetsStayQuiet() {
        val settings = config("http://legacy.example/")
        context.getSharedPreferences("skyinfo",Context.MODE_PRIVATE).edit().putString("config",settings.toString()).commit()
        val messages = mutableListOf<JSONObject>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val buffer = okio.Buffer(); chain.request().body!!.writeTo(buffer); messages.add(JSONObject(buffer.readUtf8()))
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK").body("[]".toResponseBody()).build()
        }.build()
        val publisher = ConnectionClient(context,secrets,http)
        publisher.publishControlEntities(settings,emptyMap(),"",false)
        assertEquals(173,messages.size); assertTrue(messages.all { !it.getString("topic").startsWith("homeassistant/") })
        messages.clear(); publisher.publishControlEntities(settings,emptyMap(),"",false); assertTrue(messages.isEmpty())
        publisher.publishControlEntities(config("http://fresh.example/"),emptyMap(),"",false); assertTrue(messages.isEmpty())
    }
}
