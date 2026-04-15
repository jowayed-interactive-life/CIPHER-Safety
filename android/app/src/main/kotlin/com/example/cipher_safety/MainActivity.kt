package com.example.cipher_safety

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.view.KeyEvent
import android.view.WindowManager
import androidx.core.content.ContextCompat
import com.example.cipher_safety.nats.NatsForegroundService
import com.example.cipher_safety.nats.NatsNativeStateStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val stateStore by lazy { NatsNativeStateStore(this) }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        Log.d(TAG, "onCreate intentAction=${intent?.action} hasSubject=${intent?.hasExtra(NatsForegroundService.EXTRA_SUBJECT) == true}")
        stateStore.persistIncomingAlertFromIntent(intent, TAG)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        Log.d(TAG, "onNewIntent intentAction=${intent.action} hasSubject=${intent.hasExtra(NatsForegroundService.EXTRA_SUBJECT)}")
        stateStore.persistIncomingAlertFromIntent(intent, TAG)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN &&
            NatsForegroundService.isVolumeKey(event.keyCode)
        ) {
            sendSilenceEmergencyIntent()
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startNatsService" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    stateStore.saveSessionOverrides(args)
                    val intent = Intent(this, NatsForegroundService::class.java).apply {
                        action = NatsForegroundService.ACTION_START
                    }
                    ContextCompat.startForegroundService(this, intent)
                    result.success(true)
                }

                "stopNatsService" -> {
                    stateStore.setServiceEnabled(false)
                    val intent = Intent(this, NatsForegroundService::class.java).apply {
                        action = NatsForegroundService.ACTION_STOP
                    }
                    startService(intent)
                    stateStore.clearRuntimeNatsConfig()
                    result.success(true)
                }

                "isIgnoringBatteryOptimizations" -> {
                    result.success(isIgnoringBatteryOptimizations())
                }

                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(true)
                }

                "debugShowEmergencyNotification" -> {
                    val args = call.arguments as? Map<*, *>
                    val intent = Intent(this, NatsForegroundService::class.java).apply {
                        action = NatsForegroundService.ACTION_DEBUG_ALERT
                        putExtra(
                            NatsForegroundService.EXTRA_SUBJECT,
                            args?.get("subject") as? String ?: "debug.subject",
                        )
                        putExtra(
                            NatsForegroundService.EXTRA_PAYLOAD,
                            args?.get("payload") as? String ?: "Debug emergency payload",
                        )
                    }
                    startService(intent)
                    result.success(true)
                }

                "confirmEmergencyAlert" -> {
                    val intent = Intent(this, NatsForegroundService::class.java).apply {
                        action = NatsForegroundService.ACTION_CONFIRM
                    }
                    startService(intent)
                    result.success(true)
                }

                "cannotComplyEmergencyAlert" -> {
                    val intent = Intent(this, NatsForegroundService::class.java).apply {
                        action = NatsForegroundService.ACTION_CANNOT_COMPLY
                    }
                    startService(intent)
                    result.success(true)
                }

                "silenceEmergencyAlert" -> {
                    val intent = Intent(this, NatsForegroundService::class.java).apply {
                        action = NatsForegroundService.ACTION_SILENCE
                    }
                    startService(intent)
                    result.success(true)
                }

                "startManualStreaming" -> {
                    val intent = Intent(this, NatsForegroundService::class.java).apply {
                        action = NatsForegroundService.ACTION_MANUAL_START_STREAM
                    }
                    startService(intent)
                    result.success(true)
                }

                "syncStreamingConfig" -> {
                    val args = call.arguments as? Map<*, *>
                    stateStore.saveStreamingConfig(
                        cameraId = args?.get("cameraId") as? String,
                        streamUrl = args?.get("streamUrl") as? String,
                        tabletId = args?.get("tabletId") as? String,
                        buildingName = args?.get("buildingName") as? String,
                    )
                    result.success(true)
                }

                "clearStreamingConfig" -> {
                    stateStore.clearStreamingConfig()
                    Log.d(TAG, "clearStreamingConfig")
                    result.success(true)
                }

                "setAppInForeground" -> {
                    val args = call.arguments as? Map<*, *>
                    val isForeground = args?.get("isForeground") as? Boolean ?: false
                    stateStore.setAppInForeground(isForeground)
                    result.success(true)
                }

                "consumePendingEmergencyAlert" -> {
                    result.success(stateStore.consumePendingEmergencyAlert(TAG))
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        return powerManager.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBatteryOptimizations() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        if (isIgnoringBatteryOptimizations()) return

        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:$packageName")
        }
        startActivity(intent)
    }

    private fun sendSilenceEmergencyIntent() {
        val intent = Intent(this, NatsForegroundService::class.java).apply {
            action = NatsForegroundService.ACTION_SILENCE
        }
        startService(intent)
    }

    companion object {
        private const val CHANNEL_NAME = "nats_service_channel"
        private const val TAG = "MainActivity"
    }
}
