package app.skyinfo.vehicle

import android.content.Context
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.interfaces.RSAPublicKey
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class NetworkAdbTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    @Test fun validatesLocalConnectionConfigurationAndExcludesPairCode() {
        assertEquals(AdbEndpoint("127.0.0.1",5555,false,"tcp"), AdbEndpoint.from(JSONObject()))
        for (bad in listOf("http://localhost", "user@localhost", "bad host", "x;id", "")) {
            assertThrows(IllegalArgumentException::class.java) { AdbEndpoint.from(JSONObject().put("adbHost", bad)) }
        }
        assertThrows(IllegalArgumentException::class.java) { AdbEndpoint.from(JSONObject().put("adbPort",0)) }
        assertThrows(IllegalArgumentException::class.java) { AdbEndpoint.from(JSONObject().put("adbPort",1.5)) }
        assertThrows(IllegalArgumentException::class.java) { AdbEndpoint.from(JSONObject().put("adbHost",12)) }
        assertThrows(IllegalArgumentException::class.java) { AdbEndpoint.from(JSONObject().put("adbMode","root")) }
        val saved = ConfigValidator.validate(JSONObject().put("adbHost","::1").put("adbPort",37121).put("adbEnabled",true).put("adbMode","pair").put("pairingCode","123456"), emptyMap())
        assertFalse(saved.has("pairingCode")); assertEquals("::1",saved.getString("adbHost"))
    }
    @Test fun independentRsaIdentitySurvivesEncodingAndAuthenticatesChallenge() {
        val first = AdbIdentity.generate(); val other = AdbIdentity.generate()
        val loaded = AdbIdentity.decode(first.privateKey.encoded, first.certificate.encoded)
        assertArrayEquals(first.certificate.encoded,loaded.certificate.encoded)
        assertFalse(first.certificate.publicKey.encoded.contentEquals(other.certificate.publicKey.encoded))
        val challenge = ByteArray(20) { it.toByte() }
        val type=Class.forName("io.github.muntashirakon.adb.AndroidPubkey")
        val signed = type.getDeclaredMethod("adbAuthSign",java.security.PrivateKey::class.java,ByteArray::class.java).apply { isAccessible=true }.invoke(null,loaded.privateKey,challenge) as ByteArray
        val plain = Cipher.getInstance("RSA/ECB/NoPadding").apply { init(Cipher.DECRYPT_MODE, first.certificate.publicKey) }.doFinal(signed)
        assertArrayEquals(challenge, plain.takeLast(20).toByteArray())
        assertEquals(2048, (loaded.certificate.publicKey as RSAPublicKey).modulus.bitLength())
        loaded.certificate.verify(loaded.certificate.publicKey)
    }
    @Test fun launchesOwnedProcessWithAuthenticatedAdbAndBidirectionalShell() {
        val identity = AdbIdentity.generate()
        FakeAdbd(identity).use { server ->
            val client = NetworkAdb(context,AdbEndpoint("127.0.0.1",server.port,true,"tcp"),{identity})
            val process = client.launch(arrayOf("/system/bin/app_process","/system/bin","app.skyinfo.vehicle.ShellVehicleMain","10","1234"), arrayOf("CLASSPATH=/data/app/a'b/base.apk","LD_LIBRARY_PATH=ignored"))
            process.outputStream.write("{\"request\":1,\"op\":\"identity\"}\n".toByteArray()); process.outputStream.flush()
            val response = JSONObject(process.inputStream.bufferedReader().readLine())
            assertEquals(2000,response.getJSONObject("result").getInt("uid"))
            assertTrue(server.launch.get(2,TimeUnit.SECONDS).contains("'CLASSPATH=/data/app/a'\"'\"'b/base.apk'"))
            assertFalse(server.launch.get().contains("LD_LIBRARY_PATH"))
            process.destroy(); assertTrue(process.waitFor(2,TimeUnit.SECONDS))
            server.done.get(2,TimeUnit.SECONDS)
            assertTrue(server.signatureVerified)
        }
    }
    @Test fun rejectsAnotherDeviceBeforeLaunchingBridge() {
        val error=assertThrows(IllegalStateException::class.java) { requireLocalHost("192.0.2.99") }
        assertEquals("adb_other_device",error.message)
        requireLocalHost("localhost")
    }
    @Test fun invalidPairingNeverOpensANetworkConnection() {
        val client=NetworkAdb(context,AdbEndpoint("127.0.0.1",1,false,"pair"))
        assertThrows(IllegalArgumentException::class.java) { client.pair(0,"123456") }
        assertThrows(IllegalArgumentException::class.java) { client.pair(40000,"12x456") }
    }
    private class FakeAdbd(private val identity: AdbIdentity) : AutoCloseable {
        val listener=ServerSocket(0)
        val port=listener.localPort
        val launch=CompletableFuture<String>()
        val done=CompletableFuture<Unit>()
        var signatureVerified=false
        var socket: Socket?=null
        init { Thread {
            try {
                socket=listener.accept().apply { soTimeout=5000 }
                val socket=socket!!
                val cnxn=read(socket);check(cnxn.op=="CNXN")
                val challenge=ByteArray(20) { (it+7).toByte() }
                send(socket,"AUTH",1,0,challenge)
                val auth=read(socket);check(auth.op=="AUTH"&&auth.a==2)
                val decoded=Cipher.getInstance("RSA/ECB/NoPadding").apply { init(Cipher.DECRYPT_MODE,identity.certificate.publicKey) }.doFinal(auth.data)
                check(decoded.takeLast(20).toByteArray().contentEquals(challenge));signatureVerified=true
                send(socket,"CNXN",0x01000001,4096,"device::\u0000".toByteArray())
                val next=read(socket);check(next.op=="OPEN")
                launch.complete(String(next.data).trimEnd('\u0000'))
                val stream=next.a;send(socket,"OKAY",12,stream)
                val request=read(socket);check(request.op=="WRTE")
                send(socket,"OKAY",12,stream)
                send(socket,"WRTE",12,stream,"{\"request\":1,\"result\":{\"uid\":2000}}\n".toByteArray())
                while(read(socket).op!="CLSE") {}
                done.complete(Unit)
            } catch(error: Throwable) { if(!launch.isDone)launch.completeExceptionally(error);done.complete(Unit) }
            finally { socket?.close() }
        }.apply { isDaemon=true;start() } }
        override fun close() { socket?.close();listener.close() }
        private data class Packet(val op:String,val a:Int,val b:Int,val data:ByteArray)
        private fun read(socket:Socket):Packet {
            val input=socket.getInputStream();val header=input.readNBytes(24);check(header.size==24)
            val bytes=ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)
            val op=bytes.int;val a=bytes.int;val b=bytes.int;val length=bytes.int;bytes.int;check(bytes.int==op.inv());check(length in 0..524288)
            val data=input.readNBytes(length);check(data.size==length)
            return Packet(String(ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(op).array()),a,b,data)
        }
        private fun send(socket:Socket,op:String,a:Int,b:Int,data:ByteArray=byteArrayOf()) {
            val command=ByteBuffer.wrap(op.toByteArray()).order(ByteOrder.LITTLE_ENDIAN).int
            val header=ByteBuffer.allocate(24).order(ByteOrder.LITTLE_ENDIAN).putInt(command).putInt(a).putInt(b).putInt(data.size).putInt(data.sumOf { it.toInt() and 255 }).putInt(command.inv()).array()
            socket.getOutputStream().apply { write(header);write(data);flush() }
        }
    }
}
