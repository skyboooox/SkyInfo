package app.skyinfo.vehicle

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.bouncycastle.asn1.x500.X500Name
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder
import java.math.BigInteger
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.spec.PKCS8EncodedKeySpec
import java.util.Date
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal data class AdbIdentity(val privateKey: PrivateKey, val certificate: X509Certificate) {
    companion object {
        fun generate(): AdbIdentity {
            val pair = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
            val name = X500Name("CN=SkyInfo")
            val now = System.currentTimeMillis()
            val cert = JcaX509v3CertificateBuilder(name, BigInteger(128, SecureRandom()), Date(now - 86400000),
                Date(now + 20L * 365 * 86400000), name, pair.public)
                .build(JcaContentSignerBuilder("SHA256withRSA").build(pair.private))
            return AdbIdentity(pair.private, JcaX509CertificateConverter().getCertificate(cert))
        }
        @Synchronized fun load(context: Context): AdbIdentity {
            val prefs = context.getSharedPreferences("skyinfo.adb", Context.MODE_PRIVATE)
            val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            val key = store.getKey("skyinfo.adb.identity", null) as? SecretKey ?: KeyGenerator.getInstance("AES", "AndroidKeyStore").apply {
                init(KeyGenParameterSpec.Builder("skyinfo.adb.identity", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
            }.generateKey()
            val saved = prefs.getString("identity", null)
            if (saved != null) {
                val bytes = Base64.decode(saved, Base64.NO_WRAP)
                val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, bytes.copyOfRange(0, 12))) }
                val parts = String(cipher.doFinal(bytes.copyOfRange(12, bytes.size))).split(':')
                return decode(Base64.decode(parts[0], Base64.NO_WRAP), Base64.decode(parts[1], Base64.NO_WRAP))
            }
            val identity = generate()
            val raw = Base64.encodeToString(identity.privateKey.encoded, Base64.NO_WRAP) + ":" + Base64.encodeToString(identity.certificate.encoded, Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key) }
            check(prefs.edit().putString("identity", Base64.encodeToString(cipher.iv + cipher.doFinal(raw.toByteArray()), Base64.NO_WRAP)).commit())
            return identity
        }
        fun decode(privateKey: ByteArray, certificate: ByteArray): AdbIdentity = AdbIdentity(
            KeyFactory.getInstance("RSA").generatePrivate(PKCS8EncodedKeySpec(privateKey)),
            CertificateFactory.getInstance("X.509").generateCertificate(certificate.inputStream()) as X509Certificate)
    }
}
