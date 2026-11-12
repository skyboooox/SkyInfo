package app.skyinfo.vehicle;

import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;
import java.util.Arrays;
import java.util.Collections;
import okhttp3.CipherSuite;
import okhttp3.Handshake;
import okhttp3.TlsVersion;
import okhttp3.internal.tls.CertificateBlocklist;

/** Single adapter to the security policy in the pinned OkHttp 4.12.1 dependency. */
final class OkHttpCertificatePolicy {
    private OkHttpCertificatePolicy() { }

    static void checkServerChain(X509Certificate[] chain) throws CertificateException {
        // This upstream policy only reads peer certificates; protocol/cipher are not inputs.
        Handshake certificates = Handshake.get(TlsVersion.TLS_1_3,
                CipherSuite.TLS_AES_128_GCM_SHA256, Arrays.asList(chain), Collections.emptyList());
        if (CertificateBlocklist.INSTANCE.isBlocklisted(certificates)) {
            throw new CertificateException("Peer certificate blocked by OkHttp security policy");
        }
    }
}
