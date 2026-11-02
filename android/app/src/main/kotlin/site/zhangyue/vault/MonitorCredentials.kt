package site.zhangyue.vault

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.DataInputStream
import javax.crypto.spec.GCMParameterSpec
import java.io.DataOutputStream
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/** No plaintext preferences or Intent extras. Files are excluded from Android backup. */
internal object MonitorCredentials {
    private const val ALIAS = "letian.foreground-monitor.session.v1"
    private fun file(context: Context) = File(context.noBackupFilesDir, "monitor-session.enc")
    @Synchronized fun save(context: Context, endpoint: String, bearer: String) {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val key = (store.getKey(ALIAS, null) as? SecretKey) ?: KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key) }
        val plaintext = "$endpoint\n$bearer".toByteArray(Charsets.UTF_8)
        val encrypted = try { cipher.doFinal(plaintext) } finally { plaintext.fill(0) }
        val temporary = File(context.noBackupFilesDir, "monitor-session.enc.tmp")
        try {
            temporary.outputStream().use { stream ->
                DataOutputStream(stream).apply { writeInt(cipher.iv.size); write(cipher.iv); write(encrypted); flush() }
                stream.fd.sync()
            }
            require(temporary.renameTo(file(context))) { "monitor_credential_save_failed" }
        } finally { temporary.delete() }
    }
    @Synchronized fun load(context: Context): Pair<String, String> {
        val source = file(context)
        require(source.length() in 17..32768) { "monitor_credential_invalid" }
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val key = store.getKey(ALIAS, null) as? SecretKey ?: throw IllegalStateException("monitor_credential_missing")
        return DataInputStream(source.inputStream()).use { input ->
            val size = input.readInt()
            require(size == 12) { "monitor_credential_invalid" }
            val iv = ByteArray(size).also { input.readFully(it) }
            val encrypted = input.readBytes()
            val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv)) }
            val plaintext = cipher.doFinal(encrypted)
            try {
                val values = plaintext.toString(Charsets.UTF_8).split('\n', limit = 2)
                require(values.size == 2) { "monitor_credential_invalid" }
                values[0] to values[1]
            } finally { plaintext.fill(0) }
        }
    }
    @Synchronized fun clear(context: Context) {
        file(context).delete()
        File(context.noBackupFilesDir, "monitor-session.enc.tmp").delete()
        KeyStore.getInstance("AndroidKeyStore").apply { load(null); if (containsAlias(ALIAS)) deleteEntry(ALIAS) }
    }
}
