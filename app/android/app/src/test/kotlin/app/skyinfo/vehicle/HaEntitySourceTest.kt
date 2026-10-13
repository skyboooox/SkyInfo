package app.skyinfo.vehicle

import okhttp3.*
import okhttp3.mockwebserver.*
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.concurrent.*

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class HaEntitySourceTest {
    @Test fun valueUpdatesKeepWholeFieldCacheAndDeliverOnlyOneFreshEntityDescriptor() {
        val cert = HeldCertificate.Builder().commonName("localhost").addSubjectAlternativeName("localhost").build()
        val server = MockWebServer()
        server.useHttps(HandshakeCertificates.Builder().heldCertificate(cert).build().sslSocketFactory(),false); server.start()
        val tls = HandshakeCertificates.Builder().addTrustedCertificate(cert.certificate).build()
        val http = OkHttpClient.Builder().sslSocketFactory(tls.sslSocketFactory(),tls.trustManager).build()
        val worker = Executors.newSingleThreadScheduledExecutor()
        val sockets = LinkedBlockingQueue<WebSocket>(); val deltas = LinkedBlockingQueue<JSONObject>()
        val initial = CountDownLatch(5); val changes = LinkedBlockingQueue<Boolean>()
        val samples = ConcurrentHashMap<String,JSONObject>()
        var subscription = 0
        fun lamp(brightness:Int) = JSONObject().put("entity_id","light.test").put("state","on")
            .put("attributes",JSONObject().put("friendly_name","Lamp").put("brightness",brightness)
                .put("supported_color_modes",JSONArray().put("brightness")))
        server.enqueue(MockResponse().withWebSocketUpgrade(object:WebSocketListener() {
            override fun onOpen(ws:WebSocket,response:Response) { sockets.offer(ws); ws.send("{\"type\":\"auth_required\"}") }
            override fun onMessage(ws:WebSocket,text:String) {
                val request = JSONObject(text); val type = request.optString("type")
                if(type == "auth") { ws.send("{\"type\":\"auth_ok\"}"); return }
                val value:Any = when(type) {
                    "subscribe_events" -> { subscription=request.getInt("id"); JSONObject.NULL }
                    "get_states" -> JSONArray().put(lamp(100)).apply { for(index in 0 until 300) put(JSONObject()
                        .put("entity_id","sensor.test_$index").put("state","1").put("attributes",JSONObject().put("raw",index))) }
                    "get_services" -> JSONObject().put("light",JSONObject().put("turn_on",JSONObject()).put("turn_off",JSONObject()))
                    else -> JSONArray()
                }
                ws.send(JSONObject().put("type","result").put("id",request.getInt("id")).put("success",true).put("result",value).toString())
            }
        }))
        val session = HaSession(object:SecretStore { override fun secret(name:String)="test-only" },{},{},http)
        lateinit var source:HaEntitySource
        source=HaEntitySource(session,{worker.execute(it)},{delay,task -> worker.schedule(task,delay,TimeUnit.MILLISECONDS)},
            { full -> if(source.state=="connected") { initial.countDown(); changes.offer(full) } },
            {id,sample -> samples[id]=sample},{deltas.offer(it)})
        fun run(task:()->Unit) { worker.submit(task).get(5,TimeUnit.SECONDS) }
        val id="ha|one|light.test|brightness"
        val config=JSONObject().put("haUrl",server.url("/").toString()).put("haConnectionId","one").put("haImportEnabled",true)
        try {
            run { source.configure(config,true,setOf(id)) }; session.configure(config,true)
            val socket=sockets.poll(5,TimeUnit.SECONDS)!!; assertTrue(initial.await(5,TimeUnit.SECONDS))
            lateinit var cached:Map<String,JSONObject>; lateinit var functions:JSONArray
            run { cached=source.fields(); functions=source.directory().getJSONArray("entities").getJSONObject(0).getJSONArray("functions"); changes.clear() }
            fun event(state:JSONObject)=socket.send(JSONObject().put("type","event").put("id",subscription).put("event",JSONObject()
                .put("data",JSONObject().put("entity_id","light.test").put("new_state",state))).toString())
            event(lamp(180)); val delta=deltas.poll(5,TimeUnit.SECONDS)!!
            assertEquals("ha|one|light.test",delta.getString("id")); assertEquals(180,delta.getJSONObject("attributes").getInt("brightness"))
            assertSame(functions,delta.getJSONArray("functions")); assertEquals(false,changes.poll(5,TimeUnit.SECONDS))
            run { assertSame(cached,source.fields()); assertEquals(180.0,samples[id]!!.getDouble("value"),0.0) }
            val altered=lamp(190); altered.getJSONObject("attributes").put("supported_color_modes",JSONArray().put("onoff"))
            event(altered); assertEquals(true,changes.poll(5,TimeUnit.SECONDS)); assertNull(deltas.poll(100,TimeUnit.MILLISECONDS))
            run { assertNotSame(cached,source.fields()); assertEquals(1,source.directory().getJSONArray("entities").getJSONObject(0).getJSONArray("functions").length()) }
        } finally { session.close(); worker.shutdownNow(); server.shutdown(); http.connectionPool.evictAll(); http.dispatcher.executorService.shutdown() }
    }
    @Test fun authenticationRejectionRemainsDistinctFromNetworkDisconnection() {
        val certificate = HeldCertificate.Builder().commonName("localhost").addSubjectAlternativeName("localhost").build()
        val server = MockWebServer()
        server.useHttps(HandshakeCertificates.Builder().heldCertificate(certificate).build().sslSocketFactory(), false)
        server.start()
        val tls = HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        val http = OkHttpClient.Builder().sslSocketFactory(tls.sslSocketFactory(), tls.trustManager).build()
        val worker = Executors.newSingleThreadScheduledExecutor()
        val rejected = CountDownLatch(1)
        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(ws: WebSocket, response: Response) { ws.send("{\"type\":\"auth_required\"}") }
            override fun onMessage(ws: WebSocket, text: String) {
                if (JSONObject(text).optString("type") == "auth") ws.send("{\"type\":\"auth_invalid\"}")
            }
        }))
        val session = HaSession(object : SecretStore { override fun secret(name: String) = "invalid-test-only" }, {}, {}, http)
        lateinit var source: HaEntitySource
        source = HaEntitySource(session, { task -> worker.execute(task) },
            { delay, task -> worker.schedule(task, delay, TimeUnit.MILLISECONDS) },
            { if (source.state == "auth_failed") rejected.countDown() }, { _, _ -> })
        val config = JSONObject().put("haUrl", server.url("/").toString()).put("haConnectionId", "one").put("haImportEnabled", true)
        try {
            worker.submit { source.configure(config, true, emptySet()) }.get(5, TimeUnit.SECONDS)
            session.configure(config, true)
            assertTrue("Authentication failure must reach the entity directory", rejected.await(3, TimeUnit.SECONDS))
            worker.submit {
                assertEquals("auth_failed", source.state)
                source.configure(JSONObject(config.toString()).put("haImportEnabled", false), true, emptySet())
                assertEquals("disabled", source.state)
            }.get(5, TimeUnit.SECONDS)
            assertEquals(1, server.requestCount)
        } finally {
            session.close(); worker.shutdownNow(); server.shutdown()
            http.connectionPool.evictAll(); http.dispatcher.executorService.shutdown()
        }
    }

    @Test fun sharedSessionReconcilesEventsAndConfirmsOnlyReadbackWithoutReplay() {
        val cert=HeldCertificate.Builder().commonName("localhost").addSubjectAlternativeName("localhost").build()
        val server=MockWebServer();server.useHttps(HandshakeCertificates.Builder().heldCertificate(cert).build().sslSocketFactory(),false);server.start()
        val tls=HandshakeCertificates.Builder().addTrustedCertificate(cert.certificate).build()
        val http=OkHttpClient.Builder().sslSocketFactory(tls.sslSocketFactory(),tls.trustManager).build()
        val worker=Executors.newSingleThreadScheduledExecutor()
        val sockets=LinkedBlockingQueue<WebSocket>();val results=LinkedBlockingQueue<JSONObject>();val calls=LinkedBlockingQueue<JSONObject>();val ready=LinkedBlockingQueue<Boolean>()
        val values=ConcurrentHashMap<String,JSONObject>()
        val stateUpdates=LinkedBlockingQueue<Boolean>()
        var subscribed=0;var serviceCount=0
        val id="ha|one|switch.test"
        fun state(value:String)=JSONObject().put("entity_id","switch.test").put("state",value).put("attributes",JSONObject().put("friendly_name","Test"))
            .put("last_updated",java.time.Instant.now().plusSeconds(2).toString()).put("last_changed",java.time.Instant.now().toString())
        fun event(ws:WebSocket,entity:String,value:JSONObject?) { ws.send(JSONObject().put("type","event").put("id",subscribed).put("event",JSONObject().put("data",JSONObject().put("entity_id",entity).put("new_state",value ?: JSONObject.NULL))).toString()) }
        fun response()=MockResponse().withWebSocketUpgrade(object:WebSocketListener(){
            override fun onOpen(ws:WebSocket,response:Response){sockets.offer(ws);ws.send("{\"type\":\"auth_required\"}")}
            override fun onMessage(ws:WebSocket,text:String){val m=JSONObject(text);val type=m.optString("type");val key=m.optInt("id")
                if(type=="auth"){ws.send("{\"type\":\"auth_ok\"}");return}
                fun result(value:Any)=ws.send(JSONObject().put("type","result").put("id",key).put("success",true).put("result",value).toString())
                when(type){
                    "subscribe_events"->{if(key>=100) subscribed=key;result(JSONObject.NULL)}
                    "get_states"->{event(ws,"sensor.removed",null);event(ws,"switch.test",state("on"));result(JSONArray().put(state("off")).put(JSONObject().put("entity_id","sensor.removed").put("state","1").put("attributes",JSONObject())))}
                    "get_services"->result(JSONObject().put("switch",JSONObject().put("turn_on",JSONObject()).put("turn_off",JSONObject())))
                    "call_service"->{serviceCount++;calls.offer(m);result(JSONObject.NULL)}
                    else->result(JSONArray())
                }
            }
        })
        server.enqueue(response());server.enqueue(response())
        val session=HaSession(object:SecretStore{override fun secret(name:String)="test-only"},{},{},http)
        lateinit var source:HaEntitySource
        source=HaEntitySource(session,{task->worker.execute(task)},{delay,task->worker.schedule(task,delay,TimeUnit.MILLISECONDS)},{directory->if(!directory) stateUpdates.offer(true);if(directory&&source.state=="connected"&&source.directory().getJSONArray("entities").optJSONObject(0)?.getJSONArray("functions")?.length()==1) ready.offer(true)},{key,value->values[key]=value})
        fun run(task:()->Unit){worker.submit(task).get(5,TimeUnit.SECONDS)}
        val config=JSONObject().put("haUrl",server.url("/").toString()).put("haConnectionId","one").put("haImportEnabled",true)
        try{
            run{source.configure(config,true,setOf(id))};session.configure(config,true)
            val ws=sockets.poll(5,TimeUnit.SECONDS)!!;assertEquals(true,ready.poll(5,TimeUnit.SECONDS))
            run{assertEquals("on",values[id]!!.getString("value"));assertFalse(source.fields().keys.any{it.contains("sensor.removed")})}
            run{source.control(id,"power",false,false,false){results.offer(it)}};assertEquals("not_added",results.poll(1,TimeUnit.SECONDS)!!.getString("status"));assertEquals(0,serviceCount)
            run{source.control(id,"power",false,false,true){results.offer(it)}}
            assertEquals("turn_off",calls.poll(5,TimeUnit.SECONDS)!!.getString("service"));assertNull(results.poll(150,TimeUnit.MILLISECONDS))
            run{assertEquals("on",values[id]!!.getString("value"));source.control(id,"power",true,false,true){results.offer(it)}}
            assertEquals("busy",results.poll(1,TimeUnit.SECONDS)!!.getString("status"))
            event(ws,"switch.test",state("off"));assertEquals("confirmed",results.poll(5,TimeUnit.SECONDS)!!.getString("status"));assertEquals(true,stateUpdates.poll(5,TimeUnit.SECONDS))
            run{source.control(id,"power",true,false,true){results.offer(it)}};assertNotNull(calls.poll(5,TimeUnit.SECONDS))
            session.networkLost();assertEquals("disconnected",results.poll(5,TimeUnit.SECONDS)!!.getString("status"))
            run{assertEquals("disconnected",values[id]!!.getString("quality"));source.control(id,"power",true,false,true){results.offer(it)}}
            assertEquals("disconnected",results.poll(1,TimeUnit.SECONDS)!!.getString("status"))
            session.networkAvailable();assertNotNull(sockets.poll(5,TimeUnit.SECONDS));assertEquals(true,ready.poll(5,TimeUnit.SECONDS));assertNull(calls.poll(250,TimeUnit.MILLISECONDS));assertEquals(2,serviceCount)
            assertEquals(2,server.requestCount)
        }finally{session.close();worker.shutdownNow();server.shutdown();http.connectionPool.evictAll();http.dispatcher.executorService.shutdown()}
    }
}
