package app.skyinfo.vehicle

import android.content.Context
import android.os.Build
import io.github.muntashirakon.adb.AbsAdbConnectionManager
import io.github.muntashirakon.adb.AdbStream
import java.io.ByteArrayInputStream
import java.net.InetAddress
import java.net.NetworkInterface
import java.security.cert.Certificate
import java.util.concurrent.TimeUnit

internal class NetworkAdb(private val context: Context, private val endpoint: AdbEndpoint,
    private val identity: () -> AdbIdentity = { AdbIdentity.load(context) }) {
    private fun manager(): AbsAdbConnectionManager {
        val identity = identity()
        return object : AbsAdbConnectionManager() {
            override fun getPrivateKey() = identity.privateKey
            override fun getCertificate(): Certificate = identity.certificate
            override fun getDeviceName() = "SkyInfo"
        }.apply { setApi(Build.VERSION.SDK_INT); setTimeout(8, TimeUnit.SECONDS) }
    }
    fun launch(command: Array<String>, environment: Array<String>): Process {
        check(endpoint.enabled)
        requireLocalHost(endpoint.host)
        val client = manager()
        try {
            check(client.connect(endpoint.host, endpoint.port)) { "adb_authorization_required" }
            return AdbShellProcess(client, client.openStream("shell:" + bridgeShell(command, environment)))
        } catch (error: Throwable) { client.disconnect(); throw error }
    }
    fun pair(port: Int, code: String) {
        require(port in 1..65535 && Regex("^[0-9]{6}$").matches(code))
        requireLocalHost(endpoint.host)
        val client = manager()
        try { check(client.pair(endpoint.host, port, code)) } finally { client.disconnect() }
    }
    companion object {
        val operations = java.util.concurrent.ThreadPoolExecutor(1, 1, 0, TimeUnit.SECONDS, java.util.concurrent.ArrayBlockingQueue<Runnable>(1),
            { task -> Thread(task, "SkyInfo-adb-connect").apply { isDaemon = true } })
    }
}

internal class AdbShellProcess(private val client: AbsAdbConnectionManager, private val stream: AdbStream) : Process() {
    private val input = stream.openInputStream()
    private val output = stream.openOutputStream()
    override fun getInputStream() = input
    override fun getOutputStream() = output
    override fun getErrorStream() = ByteArrayInputStream(ByteArray(0))
    override fun destroy() { try { stream.close() } finally { client.disconnect() } }
    override fun isAlive() = !stream.isClosed
    override fun exitValue(): Int { if (isAlive) throw IllegalThreadStateException(); return 0 }
    override fun waitFor(): Int { while (isAlive) Thread.sleep(20); return 0 }
    override fun waitFor(timeout: Long, unit: TimeUnit): Boolean {
        val end = System.nanoTime() + unit.toNanos(timeout)
        while (isAlive && System.nanoTime() < end) Thread.sleep(20)
        return !isAlive
    }
}

internal fun requireLocalHost(host: String) {
    val local = NetworkInterface.getNetworkInterfaces().toList().flatMap { it.inetAddresses.toList() }.toSet()
    check(InetAddress.getAllByName(host).all { it.isLoopbackAddress || it in local }) { "adb_other_device" }
}
