package app.skyinfo.vehicle

import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.net.Socket
import java.security.cert.CertificateException
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLEngine
import javax.net.ssl.SSLSocket
import javax.net.ssl.X509ExtendedTrustManager
import javax.net.ssl.X509TrustManager

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class NetworkTlsTest {
    private val normal = HeldCertificate.Builder().commonName("Anonymous TLS test").build().certificate
    private class RecordingTrust(private val issuer: X509Certificate, private val reject: Boolean = false) : X509ExtendedTrustManager() {
        val contexts = mutableListOf<Any?>()
        val issuers = arrayOf(issuer)
        private fun accepted(context: Any?) {
            contexts.add(context)
            if (reject) throw CertificateException("Original trust rejection")
        }
        override fun getAcceptedIssuers() = issuers
        override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) = accepted("client")
        override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String, socket: Socket) = accepted(socket)
        override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String, engine: SSLEngine) = accepted(engine)
        override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) = accepted("server")
        override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String, socket: Socket) = accepted(socket)
        override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String, engine: SSLEngine) = accepted(engine)
    }
    private fun basic(delegate: X509TrustManager) = object : X509TrustManager {
        override fun getAcceptedIssuers() = delegate.acceptedIssuers
        override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) = delegate.checkClientTrusted(chain,authType)
        override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) = delegate.checkServerTrusted(chain,authType)
    }
    private fun rejected(message: String, action: () -> Unit) {
        try { action(); fail("Certificate accepted") }
        catch (error: CertificateException) { assertEquals(message,error.message) }
    }
    @Test fun extendedDelegateReceivesOriginalSocketEngineAndClientChecks() {
        val delegate = RecordingTrust(normal)
        val protected = NetworkTls.trustManager(delegate) as X509ExtendedTrustManager
        val chain = arrayOf(normal); val socket = Socket(); val engine = SSLContext.getDefault().createSSLEngine()
        try {
            protected.checkServerTrusted(chain,"RSA")
            protected.checkServerTrusted(chain,"RSA",socket)
            protected.checkServerTrusted(chain,"RSA",engine)
            protected.checkClientTrusted(chain,"RSA")
            protected.checkClientTrusted(chain,"RSA",socket)
            protected.checkClientTrusted(chain,"RSA",engine)
            assertEquals(listOf("server",socket,engine,"client",socket,engine),delegate.contexts)
            assertSame(delegate.issuers,protected.acceptedIssuers)
        } finally { socket.close() }
    }
    @Test fun originalTrustRejectionsRemainRejectionsForEveryServerOverload() {
        val delegate = RecordingTrust(normal,reject = true)
        val protected = NetworkTls.trustManager(delegate) as X509ExtendedTrustManager
        val socket = Socket(); val engine = SSLContext.getDefault().createSSLEngine()
        try {
            rejected("Original trust rejection") { protected.checkServerTrusted(arrayOf(blockedIntermediate),"EC") }
            rejected("Original trust rejection") { protected.checkServerTrusted(arrayOf(blockedIntermediate),"EC",socket) }
            rejected("Original trust rejection") { protected.checkServerTrusted(arrayOf(blockedIntermediate),"EC",engine) }
            rejected("Original trust rejection") { NetworkTls.trustManager(basic(delegate)).checkServerTrusted(arrayOf(normal),"RSA") }
            assertEquals(4,delegate.contexts.size)
        } finally { socket.close() }
    }
    @Test fun upstreamCompromisedIntermediateIsRejectedAfterDelegateAcceptsIt() {
        val delegate = RecordingTrust(normal)
        val protected = NetworkTls.trustManager(delegate) as X509ExtendedTrustManager
        val chain = arrayOf(normal,blockedIntermediate); val socket = Socket(); val engine = SSLContext.getDefault().createSSLEngine()
        val message = "Peer certificate blocked by OkHttp security policy"
        try {
            rejected(message) { protected.checkServerTrusted(chain,"RSA") }
            rejected(message) { protected.checkServerTrusted(chain,"RSA",socket) }
            rejected(message) { protected.checkServerTrusted(chain,"RSA",engine) }
            val legacy = NetworkTls.trustManager(basic(delegate))
            assertTrue(legacy is X509ExtendedTrustManager)
            rejected(message) { legacy.checkServerTrusted(chain,"RSA") }
            assertEquals(4,delegate.contexts.size)
        } finally { socket.close() }
    }
    @Test fun basicHttpsTrustRejectsMissingSocketAndEngineHandshakeContexts() {
        val delegate = RecordingTrust(normal)
        val protected = NetworkTls.trustManager(basic(delegate)) as X509ExtendedTrustManager
        val context = SSLContext.getDefault()
        val socket = context.socketFactory.createSocket() as SSLSocket
        val engine = context.createSSLEngine("localhost",443)
        socket.sslParameters = socket.sslParameters.apply { endpointIdentificationAlgorithm = "HTTPS" }
        engine.sslParameters = engine.sslParameters.apply { endpointIdentificationAlgorithm = "HTTPS" }
        try {
            assertEquals("HTTPS",socket.sslParameters.endpointIdentificationAlgorithm)
            assertEquals("HTTPS",engine.sslParameters.endpointIdentificationAlgorithm)
            assertNull(socket.handshakeSession); assertNull(engine.handshakeSession)
            rejected("TLS handshake context unavailable") { protected.checkServerTrusted(arrayOf(normal),"RSA",socket) }
            rejected("TLS handshake context unavailable") { protected.checkServerTrusted(arrayOf(normal),"RSA",engine) }
            assertEquals(2,delegate.contexts.size)
        } finally { socket.close() }
    }
    private fun pahoHandshake(protocol: String, matchingHost: Boolean, extended: Boolean) {
        val root = HeldCertificate.Builder().certificateAuthority(1).commonName("Anonymous MQTT CA").build()
        val leaf = HeldCertificate.Builder().commonName("Anonymous MQTT server")
            .addSubjectAlternativeName(if (matchingHost) "localhost" else "other.example").signedBy(root).build()
        val serverTls = HandshakeCertificates.Builder().heldCertificate(leaf,root.certificate).build()
        val trust = HandshakeCertificates.Builder().addTrustedCertificate(root.certificate).build().trustManager
        val factory = NetworkTls.socketFactory(if (extended) trust else basic(trust))
        val server = MockWebServer()
        server.useHttps(serverTls.sslSocketFactory(),false); server.start()
        fun verify(start: () -> Unit, stop: () -> Unit) {
            try {
                if (matchingHost) start()
                else {
                    try { start(); fail("Trusted certificate with wrong hostname accepted") }
                    catch (expected: javax.net.ssl.SSLException) { }
                }
            } finally {
                try { stop() }
                catch (error: java.net.SocketException) { if (error.message != "Socket is closed") throw error }
            }
        }
        try {
            if (protocol == "5") {
                val module = org.eclipse.paho.mqttv5.client.internal.SSLNetworkModule(factory,"localhost",server.port,"anonymous-test")
                module.isHttpsHostnameVerificationEnabled = true; module.setSSLhandshakeTimeout(3)
                verify(module::start,module::stop)
            } else {
                val module = org.eclipse.paho.client.mqttv3.internal.SSLNetworkModule(factory,"localhost",server.port,"anonymous-test")
                module.isHttpsHostnameVerificationEnabled = true; module.setSSLhandshakeTimeout(3)
                verify(module::start,module::stop)
            }
        } finally { server.shutdown() }
    }
    @Test fun mqtt5KeepsPrivateCaTrustAndStrictHostnameWithExtendedTrust() {
        pahoHandshake("5",true,true); pahoHandshake("5",false,true)
    }
    @Test fun mqtt311KeepsPrivateCaTrustAndStrictHostnameWithExtendedTrust() {
        pahoHandshake("3.1.1",true,true); pahoHandshake("3.1.1",false,true)
    }
    @Test fun mqtt5KeepsPrivateCaTrustAndStrictHostnameWithBasicTrust() {
        pahoHandshake("5",true,false); pahoHandshake("5",false,false)
    }
    @Test fun mqtt311KeepsPrivateCaTrustAndStrictHostnameWithBasicTrust() {
        pahoHandshake("3.1.1",true,false); pahoHandshake("3.1.1",false,false)
    }
    companion object {
        // Public certificate fixture from OkHttp 4.12.1 CompromisedIntermediateTest.
        // Copyright (c) 2026 OkHttp Authors. Apache-2.0; see assets/licenses/LICENSE-Apache-2.0.txt.
        // https://github.com/lysine-dev/okhttp/blob/parent-4.12.1/okhttp/src/test/java/okhttp3/CompromisedIntermediateTest.kt
        private val blockedIntermediate: X509Certificate = CertificateFactory.getInstance("X.509").generateCertificate("""
            -----BEGIN CERTIFICATE-----
            MIIDaDCCAu6gAwIBAgIPKWkmwiejoVJjkrGUgqUEMAoGCCqGSM49BAMDMFYxCzAJ
            BgNVBAYTAklOMSUwIwYDVQQKDBxlTXVkaHJhIFRlY2hub2xvZ2llcyBMaW1pdGVk
            MSAwHgYDVQQDDBdlbVNpZ24gUm9vdCBUTFMgQ0EgLSBHMzAeFw0yNTA0MzAxNTM3
            NDFaFw00MDA0MjgxODMwMDBaMEAxCzAJBgNVBAYTAlVTMRQwEgYDVQQKDAtlTXVk
            aHJhIEluYzEbMBkGA1UEAwwSRU0gT1YgVExTIENBIC0gRzNDMHYwEAYHKoZIzj0C
            AQYFK4EEACIDYgAEE4JRzVKskpjByKrZdzId65fnCb0LTKCspV3IrVHc/J0ViaFZ
            fjpRIOHv1jHGPhg1ysrimGmmLhYx6KKBgatWYW3EXZGKvAnzqw5jz3kqpNztc4e+
            N7ulaVSfHAKycO1no4IBljCCAZIwHwYDVR0jBBgwFoAU4TqrIXzx401UrtRyt/2L
            WUIgkFQwHQYDVR0OBBYEFDTq6gzryQra+dDF4u2beMmHnhtsMB0GA1UdJQQWMBQG
            CCsGAQUFBwMBBggrBgEFBQcDAjBdBgNVHSAEVjBUMDkGCysGAQQBg44hAQABMCow
            KAYIKwYBBQUHAgEWHGh0dHA6Ly9yZXBvc2l0b3J5LmVtc2lnbi5jb20wDQYLKwYB
            BAGDjiEBAm4wCAYGZ4EMAQICMHUGCCsGAQUFBwEBBGkwZzAkBggrBgEFBQcwAYYY
            aHR0cDovL29jc3AtYy5lbXNpZ24uY29tMD8GCCsGAQUFBzAChjNodHRwOi8vcmVw
            b3NpdG9yeS5lbXNpZ24uY29tL2NlcnRzL0VNT1ZUTFNDQUczQy5wN2MwNwYDVR0f
            BDAwLjAsoCqgKIYmaHR0cDovL2NybC5lbXNpZ24uY29tLz9yb290dGxzY2FnMy5j
            cmwwDgYDVR0PAQH/BAQDAgEGMBIGA1UdEwEB/wQIMAYBAf8CAQAwCgYIKoZIzj0E
            AwMDaAAwZQIxAMSZt2xsPeumRdeSMSQ3CbzIZeQ/q7GDCWfeE1Pq+mhgA6gRM44c
            NVF3xJ+wsxJk+wIwFJbaDMokD8Ei6eNOiA8yUMYvfzQyngmrhZQMdPCK1SewrR79
            4rSb9vGqxZzelQth
            -----END CERTIFICATE-----
        """.trimIndent().byteInputStream()) as X509Certificate
    }
}
