package app.skyinfo.vehicle

import okhttp3.ConnectionSpec
import okhttp3.OkHttpClient
import java.net.Socket
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLEngine
import javax.net.ssl.SSLSession
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.X509ExtendedTrustManager
import javax.net.ssl.X509TrustManager

/** MQTT retains the configured trust manager and adds OkHttp's server certificate policy. */
internal object NetworkTls {
    private val strictHostnameVerifier by lazy {
        // Obtain OkHttp's public default verifier without creating another TLS context.
        OkHttpClient.Builder().connectionSpecs(listOf(ConnectionSpec.CLEARTEXT)).build().hostnameVerifier
    }
    private fun checkHostname(session: SSLSession?) {
        val peer = session ?: throw java.security.cert.CertificateException("TLS handshake context unavailable")
        val host = peer.peerHost?.takeIf { it.isNotBlank() }
            ?: throw java.security.cert.CertificateException("TLS peer hostname unavailable")
        if (!strictHostnameVerifier.verify(host,peer)) throw java.security.cert.CertificateException("TLS hostname verification failed")
    }
    fun socketFactory(delegate: X509TrustManager): SSLSocketFactory = SSLContext.getInstance("TLS").apply {
        init(null,arrayOf(trustManager(delegate)),null)
    }.socketFactory

    fun trustManager(delegate: X509TrustManager): X509TrustManager {
        // Basic delegates receive explicit HTTPS checks; Extended delegates retain their context.
        if (delegate !is X509ExtendedTrustManager) return object : X509ExtendedTrustManager() {
            override fun getAcceptedIssuers(): Array<X509Certificate> = delegate.acceptedIssuers
            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) = delegate.checkClientTrusted(chain,authType)
            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String, socket: Socket) = delegate.checkClientTrusted(chain,authType)
            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String, engine: SSLEngine) = delegate.checkClientTrusted(chain,authType)
            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
                delegate.checkServerTrusted(chain,authType)
                OkHttpCertificatePolicy.checkServerChain(chain)
            }
            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String, socket: Socket) {
                delegate.checkServerTrusted(chain,authType)
                if (socket is SSLSocket && socket.sslParameters.endpointIdentificationAlgorithm.equals("HTTPS",true)) checkHostname(socket.handshakeSession)
                OkHttpCertificatePolicy.checkServerChain(chain)
            }
            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String, engine: SSLEngine) {
                delegate.checkServerTrusted(chain,authType)
                if (engine.sslParameters.endpointIdentificationAlgorithm.equals("HTTPS",true)) checkHostname(engine.handshakeSession)
                OkHttpCertificatePolicy.checkServerChain(chain)
            }
        }
        return object : X509ExtendedTrustManager() {
            override fun getAcceptedIssuers(): Array<X509Certificate> = delegate.acceptedIssuers
            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) = delegate.checkClientTrusted(chain,authType)
            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String, socket: Socket) {
                delegate.checkClientTrusted(chain,authType,socket)
            }
            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String, engine: SSLEngine) {
                delegate.checkClientTrusted(chain,authType,engine)
            }
            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
                delegate.checkServerTrusted(chain,authType)
                OkHttpCertificatePolicy.checkServerChain(chain)
            }
            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String, socket: Socket) {
                delegate.checkServerTrusted(chain,authType,socket)
                OkHttpCertificatePolicy.checkServerChain(chain)
            }
            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String, engine: SSLEngine) {
                delegate.checkServerTrusted(chain,authType,engine)
                OkHttpCertificatePolicy.checkServerChain(chain)
            }
        }
    }
}
