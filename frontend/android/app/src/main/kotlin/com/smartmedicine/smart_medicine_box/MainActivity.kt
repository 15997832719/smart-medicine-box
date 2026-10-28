package com.smartmedicine.smart_medicine_box

import android.content.Context
import android.media.MediaPlayer
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private val secureStoreChannelName = "smart_medicine_box/secure_store"
    private val preferencesName = "smart_medicine_secure_store"
    private val ttsChannelName = "smart_medicine_box/tts"
    private var mediaPlayer: MediaPlayer? = null
    private var ttsResult: MethodChannel.Result? = null
    private val keyAlias = "smart_medicine_box_secure_store_key"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, secureStoreChannelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "write" -> {
                            val key = call.argument<String>("key")
                            val value = call.argument<String>("value")
                            if (key == null || value == null) {
                                result.error("INVALID_ARGUMENT", "key and value are required", null)
                            } else {
                                writeSecureValue(key, value)
                                result.success(true)
                            }
                        }
                        "read" -> {
                            val key = call.argument<String>("key")
                            if (key == null) result.error("INVALID_ARGUMENT", "key is required", null)
                            else result.success(readSecureValue(key))
                        }
                        "delete" -> {
                            val key = call.argument<String>("key")
                            if (key == null) result.error("INVALID_ARGUMENT", "key is required", null)
                            else {
                                deleteSecureValue(key)
                                result.success(true)
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("SECURE_STORE_FAILED", error.message, null)
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ttsChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(true)
                    "playFile" -> {
                        if (ttsResult != null) {
                            result.error("TTS_BUSY", "tts is already playing", null)
                            return@setMethodCallHandler
                        }
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("INVALID_ARGUMENT", "path is required", null)
                            return@setMethodCallHandler
                        }
                        completeTts(true)
                        val player = MediaPlayer()
                        mediaPlayer = player
                        ttsResult = result
                        try {
                            player.setDataSource(path)
                            player.setOnCompletionListener { completeTts(true) }
                            player.setOnErrorListener { _, _, _ ->
                                completeTts(false, "playback error")
                                true
                            }
                            player.prepare()
                            player.start()
                        } catch (error: Exception) {
                            completeTts(false, error.message)
                        }
                    }
                    "stop" -> completeTts(true)
                    else -> result.notImplemented()
                }
            }
    }

    private fun completeTts(success: Boolean, message: String? = null) {
        val result = ttsResult
        ttsResult = null
        try {
            mediaPlayer?.release()
        } catch (_: Exception) {
        }
        mediaPlayer = null
        if (success) result?.success(true) else result?.error("TTS_PLAY_FAILED", message ?: "tts play failed", null)
    }

    private fun preferences() = getSharedPreferences(preferencesName, Context.MODE_PRIVATE)

    private fun securePreferenceKey(key: String) = "encrypted_$key"

    private fun getOrCreateSecretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey(keyAlias, null)
        if (existing is SecretKey) return existing
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                keyAlias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build()
        )
        return generator.generateKey()
    }

    private fun writeSecureValue(key: String, value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey())
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        preferences().edit()
            .putString(securePreferenceKey(key), Base64.encodeToString(cipher.iv + encrypted, Base64.NO_WRAP))
            .apply()
    }

    private fun readSecureValue(key: String): String? {
        val encoded = preferences().getString(securePreferenceKey(key), null) ?: return null
        return try {
            val payload = Base64.decode(encoded, Base64.NO_WRAP)
            if (payload.size <= 12) return null
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                getOrCreateSecretKey(),
                GCMParameterSpec(128, payload.copyOfRange(0, 12))
            )
            String(cipher.doFinal(payload.copyOfRange(12, payload.size)), Charsets.UTF_8)
        } catch (_: Exception) {
            deleteSecureValue(key)
            null
        }
    }

    private fun deleteSecureValue(key: String) {
        preferences().edit().remove(securePreferenceKey(key)).apply()
    }
}
