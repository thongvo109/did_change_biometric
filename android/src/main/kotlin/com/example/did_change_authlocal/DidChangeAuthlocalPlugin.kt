package com.example.did_change_authlocal

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import androidx.annotation.RequiresApi
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.lifecycle.FlutterLifecycleAdapter
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import java.security.InvalidKeyException
import java.security.Key
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/**
 * DidChangeAuthlocalPlugin
 *
 * A Flutter plugin that detects biometric enrollment changes on Android using
 * two complementary mechanisms:
 *
 * ## 1. MethodChannel (One-shot check)
 * - `check`: Checks KeyStore key validity. Returns "biometric_valid" or throws
 *   error "biometric_did_change".
 * - `acknowledge_change`: Regenerates the KeyStore key after the app has
 *   processed a biometric change. Ensures change state persists until acknowledged.
 *
 * ## 2. EventChannel (Real-time monitoring stream)
 * - `did_change_authlocal/events`: A reactive stream that automatically
 *   monitors biometric enrollment changes. Emits [BiometricStatus] strings
 *   whenever the status changes.
 *
 * ### How monitoring works:
 * Android has no system broadcast for biometric enrollment changes. Instead,
 * this plugin combines two strategies:
 *
 * 1. **Lifecycle-aware re-check**: When the user navigates to Android Settings
 *    → Security → Fingerprint/Face and adds/removes biometrics, then returns
 *    to the app, the plugin detects the change instantly on `onResume`.
 *
 * 2. **Periodic polling**: A configurable background poll (default: 5 seconds)
 *    catches edge cases where the app stays in split-screen or PiP mode
 *    while the user modifies biometrics.
 *
 * The stream uses `distinctUntilChanged()` so Dart only receives events when
 * the actual status changes (not on every poll tick).
 *
 * ### Concurrency model:
 * Uses structured concurrency with a `SupervisorJob` scope that is cancelled
 * when the plugin detaches from the engine. All coroutines run on the Main
 * dispatcher since KeyStore operations are lightweight and Flutter requires
 * channel callbacks on the main thread.
 */
class DidChangeAuthlocalPlugin : FlutterPlugin, MethodCallHandler,
    ActivityAware {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var keyStore: KeyStore? = null

    // Coroutine scope tied to engine lifecycle — cancelled in onDetachedFromEngine
    private val pluginScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // Mutable state flow that holds the latest biometric status
    // SharedFlow with replay=1 so new listeners get the last known value
    private val _biometricStatus = MutableStateFlow<String?>(null)

    // Lifecycle observer for detecting app resume (from Settings, etc.)
    private var lifecycleObserver: DefaultLifecycleObserver? = null
    private var lifecycle: Lifecycle? = null

    // Polling job reference — cancelled when no listener is active
    private var pollingJob: Job? = null

    companion object {
        private const val KEY_NAME = "did_change_authlocal"
        private const val METHOD_CHANNEL = "did_change_authlocal"
        private const val EVENT_CHANNEL = "did_change_authlocal/events"
        private const val POLL_INTERVAL_MS = 5000L
    }

    // ═══════════════════════════════════════════════════════════════════
    // FlutterPlugin lifecycle
    // ═══════════════════════════════════════════════════════════════════

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(BiometricStreamHandler())
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        stopMonitoring()
        pluginScope.cancel()
    }

    // ═══════════════════════════════════════════════════════════════════
    // ActivityAware — needed to observe app lifecycle (foreground/background)
    // ═══════════════════════════════════════════════════════════════════

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        attachLifecycle(binding)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        attachLifecycle(binding)
    }

    override fun onDetachedFromActivity() {
        detachLifecycle()
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachLifecycle()
    }

    private fun attachLifecycle(binding: ActivityPluginBinding) {
        lifecycle = FlutterLifecycleAdapter.getActivityLifecycle(binding)
        lifecycleObserver = object : DefaultLifecycleObserver {
            override fun onResume(owner: LifecycleOwner) {
                // User returned from Settings or another app — re-check immediately
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    refreshBiometricStatus()
                }
            }
        }
        lifecycle?.addObserver(lifecycleObserver!!)
    }

    private fun detachLifecycle() {
        lifecycleObserver?.let { lifecycle?.removeObserver(it) }
        lifecycleObserver = null
        lifecycle = null
    }

    // ═══════════════════════════════════════════════════════════════════
    // MethodChannel handler (one-shot API)
    // ═══════════════════════════════════════════════════════════════════

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            result.error(
                "biometric_invalid",
                "Biometric change detection requires Android 7.0 (API 24) or higher",
                null
            )
            return
        }

        when (call.method) {
            "check" -> checkBiometric(result)
            "acknowledge_change" -> acknowledgeChange(result)
            else -> result.notImplemented()
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // EventChannel — real-time monitoring stream
    // ═══════════════════════════════════════════════════════════════════

    /**
     * StreamHandler that bridges Kotlin Flow → Flutter EventChannel.
     *
     * When Dart starts listening (`onListen`), we start polling + lifecycle
     * observation. When Dart cancels (`onCancel`), we stop polling to save
     * battery.
     */
    private inner class BiometricStreamHandler : EventChannel.StreamHandler {

        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            if (events == null) return
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
                events.error(
                    "biometric_invalid",
                    "Biometric change detection requires Android 7.0 (API 24) or higher",
                    null
                )
                return
            }

            // Trigger an initial check
            refreshBiometricStatus()

            // Collect StateFlow changes and emit to Dart
            pollingJob = pluginScope.launch {
                // Start periodic polling
                launch {
                    while (isActive) {
                        delay(POLL_INTERVAL_MS)
                        refreshBiometricStatus()
                    }
                }

                // Emit distinct status changes to Dart
                _biometricStatus
                    .filterNotNull()
                    .distinctUntilChanged()
                    .collect { status ->
                        events.success(status)
                    }
            }
        }

        override fun onCancel(arguments: Any?) {
            pollingJob?.cancel()
            pollingJob = null
        }
    }

    /**
     * Performs a KeyStore check and updates [_biometricStatus].
     *
     * This is called from:
     * 1. Lifecycle onResume (user returned from Settings)
     * 2. Periodic polling (catches split-screen/PiP edge cases)
     * 3. Initial subscription setup
     *
     * Thread-safe: StateFlow handles concurrent emissions correctly.
     */
    @RequiresApi(Build.VERSION_CODES.N)
    private fun refreshBiometricStatus() {
        pluginScope.launch {
            val status = withContext(Dispatchers.IO) {
                queryKeyStoreStatus()
            }
            _biometricStatus.value = status
        }
    }

    /**
     * Pure function that queries the KeyStore and returns a status string.
     * Safe to call from any dispatcher.
     *
     * @return One of: "biometric_valid", "biometric_did_change", "biometric_invalid"
     */
    @RequiresApi(Build.VERSION_CODES.N)
    private fun queryKeyStoreStatus(): String {
        return try {
            val cipher = getCipher()
            val secretKey = getOrCreateSecretKey()
            cipher.init(Cipher.ENCRYPT_MODE, secretKey)
            "biometric_valid"
        } catch (e: KeyPermanentlyInvalidatedException) {
            "biometric_did_change"
        } catch (e: InvalidKeyException) {
            "biometric_invalid"
        } catch (e: Exception) {
            "biometric_invalid"
        }
    }

    /**
     * Stops all monitoring: cancels polling job and resets state.
     */
    private fun stopMonitoring() {
        pollingJob?.cancel()
        pollingJob = null
    }

    // ═══════════════════════════════════════════════════════════════════
    // One-shot biometric check (MethodChannel)
    // ═══════════════════════════════════════════════════════════════════

    /**
     * Checks if biometric data has changed since the last acknowledged state.
     *
     * Does NOT regenerate the key on change detection (Issue #5 fix).
     * The key remains invalidated until [acknowledgeChange] is called.
     */
    @RequiresApi(Build.VERSION_CODES.N)
    private fun checkBiometric(result: Result) {
        pluginScope.launch {
            val status = withContext(Dispatchers.IO) {
                queryKeyStoreStatus()
            }

            when (status) {
                "biometric_valid" -> result.success("biometric_valid")
                "biometric_did_change" -> result.error(
                    "biometric_did_change",
                    "Biometric data has changed (fingerprint or face). Call acknowledgeChange() after processing.",
                    null
                )
                else -> result.error("biometric_invalid", "Invalid biometric state", null)
            }
        }
    }

    /**
     * Acknowledges that the biometric change has been processed by the app.
     *
     * Regenerates the KeyStore key and updates the monitoring stream so
     * subscribers immediately see "biometric_valid".
     */
    @RequiresApi(Build.VERSION_CODES.N)
    private fun acknowledgeChange(result: Result) {
        pluginScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    // Delete the invalidated key
                    ensureKeyStoreLoaded()
                    keyStore?.deleteEntry(KEY_NAME)

                    // Generate a fresh key
                    generateSecretKey(createKeyGenSpec())
                }

                // Update the stream so listeners are notified immediately
                _biometricStatus.value = "biometric_valid"

                result.success("acknowledged")
            } catch (e: Exception) {
                e.printStackTrace()
                result.error(
                    "acknowledge_error",
                    "Failed to acknowledge biometric change",
                    e.toString()
                )
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // KeyStore operations
    // ═══════════════════════════════════════════════════════════════════

    @RequiresApi(Build.VERSION_CODES.N)
    private fun getOrCreateSecretKey(): SecretKey {
        ensureKeyStoreLoaded()

        val existingKey = getCurrentKey(KEY_NAME)
        if (existingKey != null) {
            return existingKey as SecretKey
        }

        // No key exists yet — generate one
        generateSecretKey(createKeyGenSpec())
        return keyStore?.getKey(KEY_NAME, null) as SecretKey
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun createKeyGenSpec(): KeyGenParameterSpec {
        return KeyGenParameterSpec.Builder(
            KEY_NAME,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_CBC)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_PKCS7)
            .setUserAuthenticationRequired(true)
            // Invalidated when ANY biometric (fingerprint OR face) is enrolled
            .setInvalidatedByBiometricEnrollment(true)
            .build()
    }

    private fun ensureKeyStoreLoaded() {
        if (keyStore == null) {
            keyStore = KeyStore.getInstance("AndroidKeyStore")
        }
        keyStore?.load(null)
    }

    private fun getCurrentKey(keyName: String): Key? {
        ensureKeyStoreLoaded()
        return try {
            keyStore?.getKey(keyName, null)
        } catch (e: Exception) {
            null
        }
    }

    @RequiresApi(Build.VERSION_CODES.M)
    private fun getCipher(): Cipher {
        return Cipher.getInstance(
            "${KeyProperties.KEY_ALGORITHM_AES}/${KeyProperties.BLOCK_MODE_CBC}/${KeyProperties.ENCRYPTION_PADDING_PKCS7}"
        )
    }

    @RequiresApi(Build.VERSION_CODES.M)
    private fun generateSecretKey(keyGenParameterSpec: KeyGenParameterSpec) {
        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore"
        )
        keyGenerator.init(keyGenParameterSpec)
        keyGenerator.generateKey()
    }
}
