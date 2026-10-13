package app.skyinfo.vehicle

import okhttp3.OkHttpClient
import org.eclipse.paho.client.mqttv3.*
import org.eclipse.paho.client.mqttv3.persist.MemoryPersistence
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.File
import java.security.KeyStore
import java.security.cert.CertificateFactory
import java.util.UUID
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManagerFactory

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class MqttTransportTest {
    private fun verify(protocol: String, secure: Boolean = true) {
        assumeTrue(System.getenv(if (secure) "SKYINFO_MQTT_TEST_TLS" else "SKYINFO_MQTT_TEST_TCP") == "1")
        val trust = KeyStore.getInstance(KeyStore.getDefaultType()).apply { load(null,null); File("/workspace/.dart_tool/mqtt-test/ca.crt").inputStream().use { setCertificateEntry("test",CertificateFactory.getInstance("X.509").generateCertificate(it)) } }
        val factory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()).apply { init(trust) }
        val ssl = SSLContext.getInstance("TLS").apply { init(null,factory.trustManagers,null) }.socketFactory
        val topic = "test/skyinfo/${UUID.randomUUID()}"
        val config = JSONObject().put("connection","mqtt").put("mqttHost","host.docker.internal").put("mqttPort",if (secure) 18884 else 18885).put("mqttTransport",if (secure) "tls" else "tcp").put("prefix","skyinfo_demo")
            .put("mqttControlEnabled",true).put("mqttProtocol",protocol).put("mqttTopic",topic).put("mqttState",true).put("uploaded",JSONArray().put("voltage"))
        val fields = mapOf("voltage" to JSONObject().put("id","voltage").put("name","电压").put("unit","V"))
        val messages = LinkedBlockingQueue<Pair<String,String>>()
        val observer = MqttClient("${if (secure) "ssl" else "tcp"}://host.docker.internal:${if (secure) 18884 else 18885}","observer-${UUID.randomUUID()}",MemoryPersistence())
        val client = ConnectionClient(RuntimeEnvironment.getApplication(),object : SecretStore { override fun secret(name: String) = "" },OkHttpClient(),ssl)
        val commands = LinkedBlockingQueue<Triple<JSONObject,String,Boolean>>()
        client.command = { data, nonce, retained -> commands.offer(Triple(data,nonce,retained)) }
        try {
            observer.setCallback(object : MqttCallback {
                override fun connectionLost(cause: Throwable?) { }
                override fun deliveryComplete(token: IMqttDeliveryToken?) { }
                override fun messageArrived(topic: String, message: MqttMessage) { messages.offer(topic to message.toString()) }
            })
            observer.timeToWait = 10000
            observer.connect(MqttConnectOptions().apply { if (secure) socketFactory = ssl; isHttpsHostnameVerificationEnabled = true; connectionTimeout = 5 })
            observer.subscribe("$topic/#",1)
            client.configure(config)
            client.publish(config,mapOf("voltage" to JSONObject().put("value",13.6).put("quality","available").put("updatedAt",1000).put("receivedAt",1000)),fields)
            client.heartbeat(config,JSONObject().put("vehicle","已取得读数"),fields)
            client.publishState(config,mapOf("voltage" to JSONObject().put("value",13.6).put("quality","disconnected").put("updatedAt",1000)),fields)
            assertEquals("已连接",client.status)
            val collected = mutableMapOf<String,String>()
            repeat(5) { val item = messages.poll(10,TimeUnit.SECONDS); assertNotNull(item); collected[item!!.first.substringAfterLast('/')] = item.second }
            assertEquals("online",collected["availability"])
            assertEquals(13.6,JSONObject(collected.getValue("telemetry")).getJSONObject("metrics").getJSONObject("voltage").getDouble("value"),0.0)
            assertTrue(JSONObject(collected.getValue("state")).getJSONObject("metrics").getJSONObject("voltage").isNull("value"))
            assertFalse(JSONObject(collected.getValue("heartbeat")).has("metrics"))
            val nonce = JSONObject(collected.getValue("meta")).getString("command_session")
            val time = System.currentTimeMillis()
            val command = JSONObject().put("schema_version",1).put("target","skyinfo_demo").put("command_id","mqtt_test")
                .put("command_session",nonce).put("action","app_overlay").put("value",1)
                .put("issued_at",java.time.Instant.ofEpochMilli(time).toString()).put("expires_at",java.time.Instant.ofEpochMilli(time+30000).toString())
            observer.publish("$topic/command",command.toString().toByteArray(),1,false)
            val received = commands.poll(5,TimeUnit.SECONDS); assertNotNull(received)
            val seen = mutableSetOf<String>(); val guard = RemoteCommands(seen::add)
            val accepted = guard.validateMqtt(received!!.first,"skyinfo_demo",received.second,received.third)
            client.controlResult(config,accepted.put("status","confirmed"))
            var ack: JSONObject? = null
            repeat(3) { val item = messages.poll(5,TimeUnit.SECONDS); if (item?.first == "$topic/command_result") ack = JSONObject(item.second) }
            assertEquals("mqtt_test",ack!!.getJSONObject("result").getString("id"))
            observer.publish("$topic/command",command.toString().toByteArray(),1,false)
            val duplicate = commands.poll(5,TimeUnit.SECONDS); assertNotNull(duplicate)
            try { guard.validateMqtt(duplicate!!.first,"skyinfo_demo",duplicate.second,duplicate.third); fail("duplicate accepted") } catch (_: IllegalArgumentException) { }
            val retained = JSONObject(command.toString()).put("command_id","mqtt_retained")
            observer.publish("$topic/command",retained.toString().toByteArray(),1,true)
            val old = commands.poll(5,TimeUnit.SECONDS); assertNotNull(old)
            if (protocol == "5") {
                assertTrue(old!!.third)
                try { guard.validateMqtt(old.first,"skyinfo_demo",old.second,old.third); fail("retained accepted") } catch (_: IllegalArgumentException) { }
            }
            client.configure(JSONObject(config.toString()).put("publishEnabled",false).put("uploaded",JSONArray()))
            assertEquals(nonce,client.commandSession)
            client.close()
            client.configure(config)
            client.heartbeat(config,JSONObject(),fields)
            assertNotEquals(nonce,client.commandSession)
            val replay = commands.poll(5,TimeUnit.SECONDS); assertNotNull(replay); assertTrue(replay!!.third)
            try { guard.validateMqtt(replay.first,"skyinfo_demo",replay.second,replay.third); fail("retained replay accepted") } catch (_: IllegalArgumentException) { }
            observer.publish("$topic/command",byteArrayOf(),1,true)
            val stale = JSONObject(command.toString()).put("command_id","mqtt_stale")
            observer.publish("$topic/command",stale.toString().toByteArray(),1,false)
            val rejected = commands.poll(5,TimeUnit.SECONDS); assertNotNull(rejected)
            try { guard.validateMqtt(rejected!!.first,"skyinfo_demo",rejected.second,rejected.third); fail("old session accepted") } catch (_: IllegalArgumentException) { }
            client.close()
        } finally { client.close(); try { observer.disconnect() } catch (_: Throwable) { }; observer.close(true) }
    }
    @Test fun mqtt5PlainTcpTelemetryAndSessionTopics() = verify("5",false)
    @Test fun mqtt311PlainTcpCompatibility() = verify("3.1.1",false)
    @Test fun mqtt5TlsTelemetryAndSessionTopics() = verify("5")
    @Test fun mqtt311TlsCompatibility() = verify("3.1.1")
    @Test fun untrustedBrokerCertificateIsRejected() {
        assumeTrue(System.getenv("SKYINFO_MQTT_TEST_TLS") == "1")
        val client = ConnectionClient(RuntimeEnvironment.getApplication(), object : SecretStore { override fun secret(name: String) = "" })
        val config = JSONObject().put("connection", "mqtt").put("mqttHost", "host.docker.internal").put("mqttPort", 18884).put("mqttProtocol", "5").put("mqttTopic", "test/rejected")
        try { client.heartbeat(config, JSONObject(), emptyMap()); assertNotEquals("已连接", client.status) } finally { client.close() }
    }
}
