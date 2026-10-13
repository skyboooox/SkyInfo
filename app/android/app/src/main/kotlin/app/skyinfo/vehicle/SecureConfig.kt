package app.skyinfo.vehicle

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

interface SecretStore { fun secret(name: String): String }

class SecureConfig(context: Context) : SecretStore {
    private val prefs = context.getSharedPreferences("skyinfo", Context.MODE_PRIVATE)
    fun load(): JSONObject = JSONObject(prefs.getString("config", "{}") ?: "{}").also {
        if (migrateLocalHistory(it)) save(it)
    }
    fun save(config: JSONObject) { check(prefs.edit().putString("config", config.toString()).commit()) }
    fun stopped(): Boolean = prefs.getBoolean("stopped", false)
    fun stopped(value: Boolean) { prefs.edit().putBoolean("stopped", value).apply() }
    @Synchronized fun rememberCommand(id: String): Boolean {
        val seen = prefs.getString("commandIds", "")!!.split(',').filter(String::isNotEmpty).toMutableList()
        if (id in seen) return false
        seen.add(id)
        check(prefs.edit().putString("commandIds",seen.takeLast(256).joinToString(",")).commit())
        return true
    }
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("skyinfo.credentials", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("skyinfo.credentials", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    fun setSecret(name: String, value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        val encrypted = Base64.encodeToString(cipher.iv + cipher.doFinal(value.toByteArray()), Base64.NO_WRAP)
        check(prefs.edit().putString("secret.$name", encrypted).commit())
    }
    fun clearSecrets() {
        check(prefs.edit().remove("secret.haToken").remove("secret.mqttPassword").commit())
        KeyStore.getInstance("AndroidKeyStore").apply { load(null); deleteEntry("skyinfo.credentials") }
    }
    override fun secret(name: String): String {
        val encoded = prefs.getString("secret.$name", null) ?: return ""
        val bytes = Base64.decode(encoded, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        }
        return String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)))
    }
}
