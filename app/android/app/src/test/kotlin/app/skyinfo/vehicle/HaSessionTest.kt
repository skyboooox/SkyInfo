package app.skyinfo.vehicle

import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class HaSessionTest {
    private fun withServer(test: (MockWebServer, OkHttpClient) -> Unit) {
        val certificate = HeldCertificate.Builder().commonName("localhost").addSubjectAlternativeName("localhost").build()
        val serverTls = HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientTls = HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        val server = MockWebServer()
        server.useHttps(serverTls.sslSocketFactory(), false)
        server.start()
        val client = OkHttpClient.Builder().sslSocketFactory(clientTls.sslSocketFactory(),clientTls.trustManager).followRedirects(false).build()
        try { test(server,client) } finally { server.shutdown(); client.connectionPool.evictAll(); client.dispatcher.executorService.shutdown() }
    }
    private val secrets = object : SecretStore { override fun secret(name: String) = "temporary-test-token" }
    @Test fun authenticatesSubscribesAndReconnectsAfterServerClose() = withServer { server, http ->
        val messages = LinkedBlockingQueue<JSONObject>()
        val socket = AtomicReference<WebSocket>()
        val restored = CountDownLatch(3)
        fun response() = MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) { socket.set(webSocket); webSocket.send("{\"type\":\"auth_required\"}") }
            override fun onMessage(webSocket: WebSocket, text: String) {
                val message = JSONObject(text); messages.offer(message)
                when (message.optString("type")) {
                    "auth" -> webSocket.send("{\"type\":\"auth_ok\"}")
                    "subscribe_events" -> webSocket.send("{\"type\":\"event\",\"event\":{\"event_type\":\"homeassistant_started\"}}")
                }
            }
        })
        server.enqueue(response()); server.enqueue(response())
        val session = HaSession(secrets,{ restored.countDown() },{},http)
        try {
            session.configure(JSONObject().put("haUrl",server.url("/").toString()),true)
            assertEquals("temporary-test-token",messages.poll(5,TimeUnit.SECONDS)!!.getString("access_token"))
            assertEquals("homeassistant_started",messages.poll(5,TimeUnit.SECONDS)!!.getString("event_type"))
            socket.get().close(1001,"restart")
            assertTrue(restored.await(8,TimeUnit.SECONDS))
            assertEquals("/api/websocket",server.takeRequest(5,TimeUnit.SECONDS)!!.path)
            assertEquals("/api/websocket",server.takeRequest(5,TimeUnit.SECONDS)!!.path)
        } finally { session.close() }
    }
    @Test fun networkReturnReauthenticatesWithoutChangingSavedConfiguration() = withServer { server, http ->
        val restored = LinkedBlockingQueue<Boolean>()
        val sockets = LinkedBlockingQueue<WebSocket>()
        fun response() = MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(ws: WebSocket, response: Response) { sockets.offer(ws); ws.send("{\"type\":\"auth_required\"}") }
            override fun onMessage(ws: WebSocket, text: String) { if (JSONObject(text).optString("type") == "auth") ws.send("{\"type\":\"auth_ok\"}") }
        })
        server.enqueue(response()); server.enqueue(response())
        val session = HaSession(secrets,{ restored.offer(true) },{},http)
        try {
            session.configure(JSONObject().put("haUrl",server.url("/").toString()),true)
            assertEquals(true,restored.poll(5,TimeUnit.SECONDS)); assertNotNull(sockets.poll(1,TimeUnit.SECONDS))
            session.networkLost(); assertEquals("未连接",session.sessionState)
            session.networkAvailable()
            assertEquals(true,restored.poll(5,TimeUnit.SECONDS)); assertEquals("已认证",session.sessionState)
            assertEquals(2,server.requestCount)
        } finally { session.close() }
    }
    @Test fun commandSubscriptionUsesServerClockAndDispatchesEvents() = withServer { server, http ->
        val event = JSONObject().put("event_type","skyinfo_command")
            .put("time_fired","2026-10-08T16:00:00Z").put("context",JSONObject().put("id","test-clock"))
            .put("data",JSONObject().put("target","skyinfo_demo").put("action","app_overlay").put("value",0))
        val result = LinkedBlockingQueue<JSONObject>()
        server.enqueue(MockResponse().setHeader("Date","Thu, 08 Oct 2026 16:00:00 GMT").withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(ws: WebSocket, response: Response) { ws.send("{\"type\":\"auth_required\"}") }
            override fun onMessage(ws: WebSocket, text: String) {
                val message = JSONObject(text)
                if (message.optString("type") == "auth") ws.send("{\"type\":\"auth_ok\"}")
                if (message.optInt("id") == 2) {
                    ws.send(JSONObject().put("id",2).put("type","result").put("success",true).toString())
                    ws.send(JSONObject().put("id",2).put("type","event").put("event",event).toString())
                }
            }
        }))
        val session = HaSession(secrets,{}, {},http)
        session.command = { result.offer(RemoteCommands({true}) { session.currentTime() }.validate(it,"skyinfo_demo")) }
        try {
            session.configure(JSONObject().put("haUrl",server.url("/").toString()).put("haControlEnabled",true),true)
            assertEquals(0,result.poll(5,TimeUnit.SECONDS)!!.getInt("value"))
            assertEquals("已订阅",session.commandSubscription); assertEquals(1,session.commandEvents)
            assertTrue(kotlin.math.abs(session.currentTime()-1791475200000L) < 5000)
        } finally { session.close() }
    }
    @Test fun nativeEntitySubscriptionAcceptsOnlyCurrentNonRetainedSession() = withServer { server, http ->
        val topics = LinkedBlockingQueue<String>()
        val events = LinkedBlockingQueue<JSONObject>()
        val old = AtomicReference<String>()
        fun response() = MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) { webSocket.send("{\"type\":\"auth_required\"}") }
            override fun onMessage(webSocket: WebSocket, text: String) {
                val message=JSONObject(text)
                if(message.optString("type")=="auth") webSocket.send("{\"type\":\"auth_ok\"}")
                if(message.optString("type")=="mqtt/subscribe" && message.optInt("id")==3) {
                    val topic=message.getString("topic");topics.offer(topic)
                    assertEquals(0,message.getInt("qos"))
                    webSocket.send(JSONObject().put("type","result").put("id",3).put("success",true).toString())
                    fun event(target:String,retained:Boolean,value:Int) = JSONObject().put("id",3).put("type","event").put("event",JSONObject().put("topic",target).put("retain",retained).put("payload",JSONObject().put("action","ac_cycle").put("value",value).toString())).toString()
                    webSocket.send(event(topic,true,7))
                    webSocket.send(event(old.get() ?: "other/session",false,8))
                    webSocket.send(event(topic,false,1))
                    old.set(topic)
                }
            }
        })
        server.enqueue(response());server.enqueue(response())
        val session=HaSession(secrets,{}, {},http);session.entityCommand={events.offer(it)}
        try {
            val config=JSONObject().put("haUrl",server.url("/").toString()).put("haControlEnabled",true)
            session.configure(config,true)
            val first=topics.poll(5,TimeUnit.SECONDS)!!
            assertEquals(1,events.poll(5,TimeUnit.SECONDS)!!.getInt("value"));assertTrue(session.entitySubscription)
            session.networkLost();assertFalse(session.entitySubscription);session.networkAvailable()
            val second=topics.poll(5,TimeUnit.SECONDS)!!;assertNotEquals(first,second)
            assertEquals(1,events.poll(5,TimeUnit.SECONDS)!!.getInt("value"))
            assertNull(events.poll(300,TimeUnit.MILLISECONDS))
        } finally { session.close() }
    }
    @Test fun mqttBirthAndHaStartRestorePublicationWithoutSendingCommandsAndCoalesce() = withServer { server, http ->
        val restored = LinkedBlockingQueue<Boolean>()
        val subscriptions = LinkedBlockingQueue<JSONObject>()
        val commands = LinkedBlockingQueue<JSONObject>()
        val currentSocket = AtomicReference<WebSocket>()
        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(ws: WebSocket, response: Response) { currentSocket.set(ws); ws.send("{\"type\":\"auth_required\"}") }
            override fun onMessage(ws: WebSocket, text: String) {
                val message=JSONObject(text)
                if (message.optString("type")=="auth") ws.send("{\"type\":\"auth_ok\"}")
                if (message.optString("type")=="mqtt/subscribe") {
                    subscriptions.offer(message)
                    ws.send(JSONObject().put("id",message.getInt("id")).put("type","result").put("success",true).toString())
                }
            }
        }))
        val session=HaSession(secrets,{}, {},http)
        session.controlPublicationRestored={ restored.offer(true) };session.entityCommand={ commands.offer(it) }
        fun birth(topic:String="homeassistant/status",payload:String="online") = JSONObject().put("id",4).put("type","event")
            .put("event",JSONObject().put("topic",topic).put("payload",payload).put("retain",true)).toString()
        try {
            session.configure(JSONObject().put("haUrl",server.url("/").toString()).put("haControlEnabled",true),true)
            assertEquals(3,subscriptions.poll(5,TimeUnit.SECONDS)!!.getInt("id"))
            val birthSubscription=subscriptions.poll(5,TimeUnit.SECONDS)!!
            assertEquals(4,birthSubscription.getInt("id"));assertEquals("homeassistant/status",birthSubscription.getString("topic"))
            val ws=currentSocket.get()
            ws.send(birth("another/status"));ws.send(birth(payload="offline"))
            assertNull(restored.poll(350,TimeUnit.MILLISECONDS))
            ws.send(birth());ws.send(birth());ws.send(JSONObject().put("id",1).put("type","event").put("event",JSONObject().put("event_type","homeassistant_started")).toString())
            assertEquals(true,restored.poll(5,TimeUnit.SECONDS));assertNull(restored.poll(350,TimeUnit.MILLISECONDS))
            assertTrue(session.entitySubscription);assertNull(commands.poll(100,TimeUnit.MILLISECONDS))
            ws.send(birth());session.close()
            assertNull(restored.poll(500,TimeUnit.MILLISECONDS));assertFalse(session.entitySubscription)
        } finally { session.close() }
    }
    @Test fun rejectedAuthenticationDoesNotRetry() = withServer { server, http ->
        val states = LinkedBlockingQueue<String>()
        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) { webSocket.send("{\"type\":\"auth_required\"}") }
            override fun onMessage(webSocket: WebSocket, text: String) { webSocket.send("{\"type\":\"auth_invalid\"}") }
        }))
        val session = HaSession(secrets,{}, { states.offer(it) },http)
        try {
            session.configure(JSONObject().put("haUrl",server.url("/").toString()),true)
            assertEquals("认证失败",states.poll(5,TimeUnit.SECONDS))
            Thread.sleep(1800)
            assertEquals(1,server.requestCount)
        } finally { session.close() }
    }
    @Test fun silentAuthenticationTimesOut() = withServer { server, http ->
        val timedOut = CountDownLatch(1)
        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {}))
        val session = HaSession(secrets,{}, { if (it == "认证超时") timedOut.countDown() },http)
        try { session.configure(JSONObject().put("haUrl",server.url("/").toString()),true); assertTrue(timedOut.await(13,TimeUnit.SECONDS)) }
        finally { session.close() }
    }
    @Test fun customBirthAndDisabledBirthStillUseExplicitRestoreEvents() = withServer { server, http ->
        val subscriptions=LinkedBlockingQueue<JSONObject>()
        val restored=LinkedBlockingQueue<Boolean>()
        val sockets=LinkedBlockingQueue<WebSocket>()
        fun response()=MockResponse().withWebSocketUpgrade(object:WebSocketListener() {
            override fun onOpen(ws:WebSocket,response:Response) { sockets.offer(ws);ws.send(JSONObject().put("type","auth_required").toString()) }
            override fun onMessage(ws:WebSocket,text:String) {
                val message=JSONObject(text)
                if(message.optString("type")=="auth")ws.send(JSONObject().put("type","auth_ok").toString())
                if(message.optString("type")=="mqtt/subscribe") {
                    subscriptions.offer(message)
                    ws.send(JSONObject().put("id",message.getInt("id")).put("type","result").put("success",true).toString())
                }
            }
        })
        server.enqueue(response());server.enqueue(response())
        val session=HaSession(secrets,{},{},http);session.controlPublicationRestored={restored.offer(true)}
        val config=JSONObject().put("haUrl",server.url("/").toString()).put("haControlEnabled",true)
            .put("haBirthTopic","custom/ha_status").put("haBirthPayload","ready")
        fun birth(topic:String,payload:String)=JSONObject().put("type","event").put("id",4)
            .put("event",JSONObject().put("topic",topic).put("payload",payload)).toString()
        try {
            session.configure(config,true)
            val first=sockets.poll(5,TimeUnit.SECONDS)!!
            assertEquals(3,subscriptions.poll(5,TimeUnit.SECONDS)!!.getInt("id"))
            assertEquals("custom/ha_status",subscriptions.poll(5,TimeUnit.SECONDS)!!.getString("topic"))
            first.send(birth("homeassistant/status","online"));assertNull(restored.poll(350,TimeUnit.MILLISECONDS))
            first.send(birth("custom/ha_status","ready"));assertEquals(true,restored.poll(5,TimeUnit.SECONDS))
            session.configure(JSONObject(config.toString()).put("haBirthTopic",""),true)
            val second=sockets.poll(5,TimeUnit.SECONDS)!!
            assertEquals(3,subscriptions.poll(5,TimeUnit.SECONDS)!!.getInt("id"))
            assertNull(subscriptions.poll(350,TimeUnit.MILLISECONDS))
            second.send(birth("custom/ha_status","ready"));assertNull(restored.poll(350,TimeUnit.MILLISECONDS))
            second.send(JSONObject().put("type","event").put("id",1).put("event",JSONObject().put("event_type","homeassistant_started")).toString())
            assertEquals(true,restored.poll(5,TimeUnit.SECONDS))
        } finally { session.close() }
    }

}
