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
import com.example.cipher_safety.nats.NatsNotificationsManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        Log.d(TAG, "onCreate intentAction=${intent?.action} hasSubject=${intent?.hasExtra(NatsForegroundService.EXTRA_SUBJECT) == true}")
        persistIncomingAlertFromIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        Log.d(TAG, "onNewIntent intentAction=${intent.action} hasSubject=${intent.hasExtra(NatsForegroundService.EXTRA_SUBJECT)}")
        persistIncomingAlertFromIntent(intent)
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
                    saveSessionOverrides(call)
                    val intent = Intent(this, NatsForegroundService::class.java).apply {
                        action = NatsForegroundService.ACTION_START
                    }
                    ContextCompat.startForegroundService(this, intent)
                    result.success(true)
                }

                "stopNatsService" -> {
                    markServiceEnabled(false)
                    val intent = Intent(this, NatsForegroundService::class.java).apply {
                        action = NatsForegroundService.ACTION_STOP
                    }
                    startService(intent)
                    clearRuntimeNatsConfig()
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

                "syncStreamingConfig" -> {
                    val args = call.arguments as? Map<*, *>
                    saveStreamingConfig(
                        cameraId = args?.get("cameraId") as? String,
                        streamUrl = args?.get("streamUrl") as? String,
                        tabletId = args?.get("tabletId") as? String,
                        buildingName = args?.get("buildingName") as? String,
                    )
                    result.success(true)
                }

                "clearStreamingConfig" -> {
                    clearStreamingConfig()
                    result.success(true)
                }

                "setAppInForeground" -> {
                    val args = call.arguments as? Map<*, *>
                    val isForeground = args?.get("isForeground") as? Boolean ?: false
                    setAppInForeground(isForeground)
                    result.success(true)
                }

                "consumePendingEmergencyAlert" -> {
                    result.success(consumePendingEmergencyAlert())
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun saveSessionOverrides(call: MethodCall) {
        val args = call.arguments as? Map<*, *> ?: return
        val prefs = getSharedPreferences("nats_service_prefs", Context.MODE_PRIVATE)
        val editor = prefs.edit()

        (args["accessToken"] as? String)?.let { editor.putString(NatsNotificationsManager.KEY_ACCESS_TOKEN, it) }
        (args["userId"] as? String)?.let { editor.putString(NatsNotificationsManager.KEY_USER_ID, it) }
        (args["organizationId"] as? String)?.let { editor.putString(NatsNotificationsManager.KEY_ORGANIZATION_ID, it) }
        (args["chatBusAuthUrl"] as? String)?.let { editor.putString(NatsNotificationsManager.KEY_CHAT_BUS_AUTH_URL, it) }
        (args["serverUrl"] as? String)?.let { editor.putString(NatsNotificationsManager.KEY_NATS_SERVER_URL, it) }
        (args["env"] as? String)?.let { editor.putString(NatsNotificationsManager.KEY_NATS_ENV, it) }
        (args["primarySubject"] as? String)?.let { editor.putString(NatsNotificationsManager.KEY_NATS_SUBJECT_PRIMARY, it) }
        (args["mobileSubject"] as? String)?.let { editor.putString(NatsNotificationsManager.KEY_NATS_SUBJECT_MOBILE, it) }
        (args["buildingSubject"] as? String)?.let { editor.putString(NatsNotificationsManager.KEY_NATS_SUBJECT_BUILDING, it) }
        editor.putBoolean(NatsNotificationsManager.KEY_SERVICE_ENABLED, true)

        editor.apply()
    }

    private fun clearRuntimeNatsConfig() {
        val prefs = getSharedPreferences("nats_service_prefs", Context.MODE_PRIVATE)
        prefs.edit()
            .remove(NatsNotificationsManager.KEY_NATS_SERVER_URL)
            .remove(NatsNotificationsManager.KEY_NATS_ENV)
            .remove(NatsNotificationsManager.KEY_NATS_SUBJECT_PRIMARY)
            .remove(NatsNotificationsManager.KEY_NATS_SUBJECT_MOBILE)
            .apply()
    }

    private fun saveStreamingConfig(
        cameraId: String?,
        streamUrl: String?,
        tabletId: String?,
        buildingName: String?,
    ) {
        val prefs = getSharedPreferences("nats_service_prefs", Context.MODE_PRIVATE)
        prefs.edit().apply {
            if (!cameraId.isNullOrBlank()) {
                putString(NatsNotificationsManager.KEY_STREAM_CAMERA_ID, cameraId)
            }
            if (!streamUrl.isNullOrBlank()) {
                putString(NatsNotificationsManager.KEY_STREAM_URL, streamUrl)
            }
            if (!tabletId.isNullOrBlank()) {
                putString(NatsNotificationsManager.KEY_STREAM_TABLET_ID, tabletId)
            }
            if (!buildingName.isNullOrBlank()) {
                putString(NatsNotificationsManager.KEY_STREAM_BUILDING_NAME, buildingName)
            }
        }.apply()
        Log.d(
            TAG,
            "saveStreamingConfig cameraId=${cameraId ?: "<empty>"} tabletId=${tabletId ?: "<empty>"} buildingName=${buildingName ?: "<empty>"} hasStreamUrl=${!streamUrl.isNullOrBlank()}",
        )
    }

    private fun clearStreamingConfig() {
        val prefs = getSharedPreferences("nats_service_prefs", Context.MODE_PRIVATE)
        prefs.edit()
            .remove(NatsNotificationsManager.KEY_STREAM_CAMERA_ID)
            .remove(NatsNotificationsManager.KEY_STREAM_URL)
            .remove(NatsNotificationsManager.KEY_STREAM_TABLET_ID)
            .remove(NatsNotificationsManager.KEY_STREAM_BUILDING_NAME)
            .apply()
        Log.d(TAG, "clearStreamingConfig")
    }

    private fun markServiceEnabled(enabled: Boolean) {
        val prefs = getSharedPreferences("nats_service_prefs", Context.MODE_PRIVATE)
        prefs.edit().putBoolean(NatsNotificationsManager.KEY_SERVICE_ENABLED, enabled).apply()
    }

    private fun setAppInForeground(isForeground: Boolean) {
        val prefs = getSharedPreferences("nats_service_prefs", Context.MODE_PRIVATE)
        prefs.edit().putBoolean(NatsNotificationsManager.KEY_APP_IN_FOREGROUND, isForeground).apply()
    }

    private fun consumePendingEmergencyAlert(): Map<String, Any>? {
        val prefs = getSharedPreferences("nats_service_prefs", Context.MODE_PRIVATE)
        val subject = prefs.getString(NatsForegroundService.KEY_PENDING_ALERT_SUBJECT, null)
        val payload = prefs.getString(NatsForegroundService.KEY_PENDING_ALERT_PAYLOAD, null)
        val receivedAt = prefs.getLong(NatsForegroundService.KEY_PENDING_ALERT_RECEIVED_AT, 0L)

        if (subject.isNullOrBlank() || payload.isNullOrBlank()) {
            Log.d(TAG, "consumePendingEmergencyAlert empty")
            return null
        }

        Log.d(
            TAG,
            "consumePendingEmergencyAlert subject=$subject payloadLength=${payload.length} receivedAt=$receivedAt",
        )

        prefs.edit()
            .remove(NatsForegroundService.KEY_PENDING_ALERT_SUBJECT)
            .remove(NatsForegroundService.KEY_PENDING_ALERT_PAYLOAD)
            .remove(NatsForegroundService.KEY_PENDING_ALERT_RECEIVED_AT)
            .apply()

        return hashMapOf(
            "subject" to subject,
            "payload" to payload,
            "receivedAt" to receivedAt,
        )
    }

    private fun persistIncomingAlertFromIntent(intent: Intent?) {
        if (intent == null) return
        val subject = intent.getStringExtra(NatsForegroundService.EXTRA_SUBJECT)
        val payload = intent.getStringExtra(NatsForegroundService.EXTRA_PAYLOAD)
        if (subject.isNullOrBlank() || payload.isNullOrBlank()) {
            Log.d(TAG, "persistIncomingAlertFromIntent skipped hasSubject=${!subject.isNullOrBlank()} hasPayload=${!payload.isNullOrBlank()}")
            return
        }

        val prefs = getSharedPreferences("nats_service_prefs", Context.MODE_PRIVATE)
        prefs.edit()
            .putString(NatsForegroundService.KEY_PENDING_ALERT_SUBJECT, subject)
            .putString(NatsForegroundService.KEY_PENDING_ALERT_PAYLOAD, payload)
            .putLong(NatsForegroundService.KEY_PENDING_ALERT_RECEIVED_AT, System.currentTimeMillis())
            .apply()
        Log.d(TAG, "persistIncomingAlertFromIntent saved subject=$subject payloadLength=${payload.length}")
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
