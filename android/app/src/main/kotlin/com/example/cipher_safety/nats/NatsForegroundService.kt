package com.example.cipher_safety.nats

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.hardware.display.DisplayManager
import android.media.AudioManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import android.view.KeyEvent
import android.view.Surface
import android.view.WindowManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.example.cipher_safety.MainActivity
import com.example.cipher_safety.R
import com.pedro.common.ConnectChecker
import com.pedro.encoder.input.video.CameraHelper
import com.pedro.library.rtmp.RtmpCamera2
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicInteger

class NatsForegroundService : Service(), ConnectChecker {
    private val manager by lazy { NatsNotificationsManager(applicationContext) }
    private var stopRequested = false
    private var toneGenerator: ToneGenerator? = null
    private var emergencyActive = false
    private val mainHandler = Handler(Looper.getMainLooper())
    private var isTorchOn = false
    private var torchCameraId: String? = null
    private var rtmpCamera: RtmpCamera2? = null

    @Volatile
    private var isRunning = false

    private val autoStreamStartRunnable = Runnable {
        startConfiguredRtmpStream(reason = "no_response_timeout")
    }

    private val toneLoopRunnable = object : Runnable {
        override fun run() {
            if (!emergencyActive) return
            try {
                if (toneGenerator == null) {
                    toneGenerator = ToneGenerator(AudioManager.STREAM_ALARM, 100)
                }
                toneGenerator?.startTone(ToneGenerator.TONE_SUP_ERROR, 1200)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to play TONE_SUP_ERROR", e)
            }
            mainHandler.postDelayed(this, 1300L)
        }
    }

    private val torchLoopRunnable = object : Runnable {
        override fun run() {
            if (!emergencyActive) return
            toggleTorchInternal()
            mainHandler.postDelayed(this, 260L)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startServiceFlow()
            ACTION_STOP -> stopServiceFlow()
            ACTION_CONFIRM -> {
                stopEmergencyEffects(reason = intent.action ?: "user_action")
                cancelAutoStreamStart()
                stopConfiguredRtmpStream(reason = "confirmed")
                NotificationManagerCompat.from(this).cancel(EMERGENCY_NOTIFICATION_ID)
                clearPendingEmergencyAlert()
            }
            ACTION_CANNOT_COMPLY -> {
                stopEmergencyEffects(reason = intent.action ?: "user_action")
                cancelAutoStreamStart()
                startConfiguredRtmpStream(reason = "cannot_comply")
                NotificationManagerCompat.from(this).cancel(EMERGENCY_NOTIFICATION_ID)
                clearPendingEmergencyAlert()
            }
            ACTION_SILENCE -> {
                stopEmergencyEffects(reason = "hardware_volume_key")
            }
            ACTION_DEBUG_ALERT -> {
                createNotificationChannels()
                showRealtimeNotification(
                    payload = intent.getStringExtra(EXTRA_PAYLOAD) ?: "Debug emergency payload",
                    subject = intent.getStringExtra(EXTRA_SUBJECT) ?: "debug.subject",
                )
            }
            else -> Log.d(TAG, "unknown action=${intent?.action}")
        }
        return START_STICKY
    }

    override fun onDestroy() {
        manager.stop()
        isRunning = false
        cancelAutoStreamStart()
        stopConfiguredRtmpStream(reason = "service_destroy")
        stopEmergencyTone()
        stopEmergencyEffects(reason = "service_destroy")
        if (!stopRequested && isServiceEnabled()) {
            Log.i(TAG, "service destroyed unexpectedly; scheduling restart")
            scheduleRestart(2_000L)
        }
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        if (!isRunning) return
        Log.i(TAG, "task removed; scheduling restart")
        scheduleRestart(2_000L)
    }

    private fun startServiceFlow() {
        if (isRunning) {
            Log.d(TAG, "foreground service already running")
            return
        }
        stopRequested = false

        createNotificationChannels()
        startForeground(ONGOING_NOTIFICATION_ID, buildOngoingNotification())
        isRunning = true

        manager.start { payload, subject ->
            Log.d(TAG, "incoming subject=$subject payloadLength=${payload.length}")
            if (isDebuggableBuild()) {
                logLongMessage("incoming payload", payload)
            }
            when (classifyPayload(payload)) {
                PayloadAction.START_STREAM -> {
                    Log.i(TAG, "control payload received | action=start_stream")
                    handleStreamingControlPayload(payload, true)
                }
                PayloadAction.STOP_STREAM -> {
                    Log.i(TAG, "control payload received | action=stop_stream")
                    handleStreamingControlPayload(payload, false)
                }
                PayloadAction.RESOLVED_ALERT -> {
                    Log.i(TAG, "resolved alert payload received")
                    cancelAutoStreamStart()
                    stopEmergencyEffects(reason = "resolved_alert")
                    NotificationManagerCompat.from(this).cancel(EMERGENCY_NOTIFICATION_ID)
                    clearPendingEmergencyAlert()
                }
                PayloadAction.DISPLAY_ALERT -> {
                    showRealtimeNotification(payload, subject)
                }
                PayloadAction.IGNORE -> {
                    Log.d(TAG, "payload ignored | no alertMode and no streaming control")
                }
            }
        }
    }

    private fun stopServiceFlow() {
        stopRequested = true
        cancelAutoStreamStart()
        stopConfiguredRtmpStream(reason = "service_stop")
        manager.stop()
        isRunning = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val ongoingChannel = NotificationChannel(
            ONGOING_CHANNEL_ID,
            "NATS Background Service",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Keeps NATS realtime listener alive"
        }

        val messageChannel = NotificationChannel(
            MESSAGE_CHANNEL_ID,
            "NATS Realtime Alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Realtime alerts from NATS"
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 800, 400, 800, 400)
            enableLights(true)
            lightColor = android.graphics.Color.RED
            setBypassDnd(true)
            setSound(null, null)
        }

        notificationManager.createNotificationChannel(ongoingChannel)
        notificationManager.createNotificationChannel(messageChannel)
    }

    private fun buildOngoingNotification(): Notification {
        return NotificationCompat.Builder(this, ONGOING_CHANNEL_ID)
            .setContentTitle("CIPHER Security")
            .setContentText("Listening for realtime alerts")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }

    private fun showRealtimeNotification(payload: String, subject: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
            if (!granted) {
                Log.w(TAG, "POST_NOTIFICATIONS is not granted; cannot show alert notification")
                return
            }
        }

        savePendingEmergencyAlert(subject = subject, payload = payload)
        val isSilent = isSilentAlert(payload)

        val body = payload.take(200)
        val appLaunchIntent =
            packageManager.getLaunchIntentForPackage(packageName)?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            } ?: Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
        val launchIntent = Intent(this, EmergencyAlertActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val contentPendingIntent = PendingIntent.getActivity(
            this,
            OPEN_APP_REQUEST_CODE,
            appLaunchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val openAppPendingIntent = PendingIntent.getActivity(
            this,
            OPEN_ALERT_REQUEST_CODE,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val confirmIntent = Intent(this, NatsForegroundService::class.java).apply {
            action = ACTION_CONFIRM
        }
        val cannotComplyIntent = Intent(this, NatsForegroundService::class.java).apply {
            action = ACTION_CANNOT_COMPLY
        }
        val confirmPendingIntent = PendingIntent.getService(
            this,
            CONFIRM_REQUEST_CODE,
            confirmIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val cannotComplyPendingIntent = PendingIntent.getService(
            this,
            CANNOT_COMPLY_REQUEST_CODE,
            cannotComplyIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(this, MESSAGE_CHANNEL_ID)
            .setContentTitle("Emergency Alert")
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText("$subject\n$payload"))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setColor(android.graphics.Color.RED)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setDefaults(0)
            .setContentIntent(contentPendingIntent)
            .setFullScreenIntent(openAppPendingIntent, true)
            .addAction(0, "Confirm", confirmPendingIntent)
            .addAction(0, "Can not comply", cannotComplyPendingIntent)
            .setAutoCancel(true)
            .apply {
                if (isSilent) {
                    setSilent(true)
                    setOnlyAlertOnce(true)
                } else {
                    setLights(android.graphics.Color.RED, 1000, 500)
                    setVibrate(longArrayOf(0, 800, 400, 800, 400))
                }
            }
            .build()

        NotificationManagerCompat.from(this).notify(EMERGENCY_NOTIFICATION_ID, notification)
        if (isAppInForeground()) {
            Log.d(TAG, "app in foreground; skipping native emergency activity")
        } else {
            launchEmergencyActivity()
        }
        scheduleAutoStreamStart()
        if (isSilent) {
            stopEmergencyEffects(reason = "silent_alert")
        } else {
            startEmergencyEffects()
        }
    }

    private fun handleStreamingControlPayload(payload: String, isEnabled: Boolean) {
        val payloadMap = extractPayloadMap(payload)
        val cameraId = payloadMap?.optString("id").orEmpty()
            .ifBlank { payloadMap?.optString("cameraId").orEmpty() }
        if (isEnabled) {
            val savedStreamUrl = readConfiguredStreamUrl()
            if (savedStreamUrl.isNullOrBlank()) {
                Log.w(TAG, "handleStreamingControlPayload start skipped savedStreamUrl=<empty>")
                return
            }
            if (cameraId.isNotBlank()) {
                saveStreamingConfig(cameraId, savedStreamUrl)
            }
            Log.i(
                TAG,
                "handleStreamingControlPayload start using saved stream | cameraId=${cameraId.ifBlank { "<saved>" }} | streamUrl=$savedStreamUrl",
            )
            startConfiguredRtmpStream(reason = "control_signal")
        } else {
            cancelAutoStreamStart()
            stopConfiguredRtmpStream(reason = "control_signal_disabled")
        }
    }

    private fun classifyPayload(payload: String): PayloadAction {
        val payloadMap = extractPayloadMap(payload)
        val alertMode = payloadMap?.optString("alertMode").orEmpty()
        val isResolved = payloadMap?.optBoolean("isResolved", false) == true
        val hasControlId = payloadMap?.optString("id").orEmpty().isNotBlank() ||
            payloadMap?.optString("cameraId").orEmpty().isNotBlank()
        val hasIsEnabled = payloadMap?.has("isEnabled") == true ||
            payloadMap?.has("is_enabled") == true
        val isEnabled = payloadMap?.optBoolean("isEnabled", payloadMap.optBoolean("is_enabled", false))

        return when {
            hasControlId && hasIsEnabled && isEnabled == true -> PayloadAction.START_STREAM
            hasControlId && hasIsEnabled && isEnabled == false -> PayloadAction.STOP_STREAM
            alertMode.isNotBlank() && isResolved -> PayloadAction.RESOLVED_ALERT
            alertMode.isNotBlank() -> PayloadAction.DISPLAY_ALERT
            else -> PayloadAction.IGNORE
        }
    }

    private fun extractPayloadMap(payload: String): JSONObject? {
        val trimmed = payload.trim()
        return try {
            if (!trimmed.startsWith("{") || !trimmed.endsWith("}")) return null
            val root = JSONObject(trimmed)
            when {
                root.has("data") && root.opt("data") is JSONObject -> root.getJSONObject("data")
                else -> root
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun saveStreamingConfig(cameraId: String, streamUrl: String) {
        val prefs = getSharedPreferences(PREFS_NATIVE, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(NatsNotificationsManager.KEY_STREAM_CAMERA_ID, cameraId)
            .putString(NatsNotificationsManager.KEY_STREAM_URL, streamUrl)
            .apply()
        Log.d(TAG, "saveStreamingConfig service cameraId=$cameraId streamUrl=$streamUrl")
    }

    private fun scheduleAutoStreamStart() {
        cancelAutoStreamStart()
        val streamUrl = readConfiguredStreamUrl()
        Log.d(
            TAG,
            "scheduleAutoStreamStart hasStreamUrl=${!streamUrl.isNullOrBlank()} delayMinutes=4",
        )
        mainHandler.postDelayed(autoStreamStartRunnable, AUTO_STREAM_DELAY_MS)
    }

    private fun cancelAutoStreamStart() {
        mainHandler.removeCallbacks(autoStreamStartRunnable)
    }

    private fun startConfiguredRtmpStream(reason: String) {
        val streamUrl = readConfiguredStreamUrl()
        val cameraId = readConfiguredCameraId()
        if (streamUrl.isNullOrBlank()) {
            Log.w(TAG, "startConfiguredRtmpStream skipped reason=$reason streamUrl=<empty>")
            return
        }

        val current = rtmpCamera
        if (current?.isStreaming == true) {
            Log.d(TAG, "startConfiguredRtmpStream skipped reason=$reason alreadyStreaming=true")
            return
        }

        try {
            val camera = current ?: RtmpCamera2(applicationContext, this).also {
                rtmpCamera = it
            }
            val rotation = getStreamRotationDegrees()
            val preparedVideo = camera.prepareVideo(1280, 720, 30, 1_200_000, 2, rotation)
            val preparedAudio = if (ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.RECORD_AUDIO,
                ) == PackageManager.PERMISSION_GRANTED
            ) {
                camera.prepareAudio(64 * 1024, 32000, true, false, false)
            } else {
                Log.w(TAG, "startConfiguredRtmpStream audio permission missing; streaming video only")
                true
            }

            if (!preparedVideo || !preparedAudio) {
                Log.e(
                    TAG,
                    "startConfiguredRtmpStream prepare failed reason=$reason preparedVideo=$preparedVideo preparedAudio=$preparedAudio",
                )
                return
            }

            try {
                camera.startPreview(CameraHelper.Facing.FRONT, 1280, 720, 30, rotation)
            } catch (e: Exception) {
                Log.w(TAG, "startConfiguredRtmpStream startPreview warning", e)
            }

            Log.i(
                TAG,
                "startConfiguredRtmpStream starting reason=$reason cameraId=${cameraId ?: "<empty>"} url=$streamUrl rotation=$rotation",
            )
            camera.startStream(streamUrl)
        } catch (e: Exception) {
            Log.e(TAG, "startConfiguredRtmpStream failed reason=$reason", e)
        }
    }

    private fun stopConfiguredRtmpStream(reason: String) {
        val camera = rtmpCamera ?: run {
            Log.d(TAG, "stopConfiguredRtmpStream skipped reason=$reason camera=<null>")
            return
        }
        try {
            if (camera.isStreaming) {
                camera.stopStream()
            }
        } catch (e: Exception) {
            Log.w(TAG, "stopConfiguredRtmpStream stopStream warning reason=$reason", e)
        }
        try {
            camera.stopPreview()
        } catch (_: Exception) {
        }
        try {
            camera.stopCamera()
        } catch (_: Exception) {
        }
        rtmpCamera = null
        Log.i(TAG, "stopConfiguredRtmpStream reason=$reason")
    }

    private fun readConfiguredCameraId(): String? {
        val prefs = getSharedPreferences(PREFS_NATIVE, Context.MODE_PRIVATE)
        return prefs.getString(NatsNotificationsManager.KEY_STREAM_CAMERA_ID, null)
    }

    private fun readConfiguredStreamUrl(): String? {
        val prefs = getSharedPreferences(PREFS_NATIVE, Context.MODE_PRIVATE)
        return prefs.getString(NatsNotificationsManager.KEY_STREAM_URL, null)
    }

    private fun isSilentAlert(payload: String): Boolean {
        val trimmed = payload.trim()
        try {
            if (trimmed.startsWith("{") && trimmed.endsWith("}")) {
                val parsed = JSONObject(trimmed)
                val source =
                    when {
                        parsed.has("data") && parsed.get("data") is JSONObject -> parsed.getJSONObject("data")
                        else -> parsed
                    }
                if (source.has("isSilent")) {
                    return source.optBoolean("isSilent", false)
                }
                if (source.has("is_silent")) {
                    return source.optBoolean("is_silent", false)
                }
            }
        } catch (_: Exception) {
        }

        val regex = Regex("""['"]?(isSilent|is_silent)['"]?\s*[:=]\s*(true|false)""", RegexOption.IGNORE_CASE)
        val match = regex.find(payload) ?: return false
        return match.groupValues.getOrNull(2)?.equals("true", ignoreCase = true) == true
    }

    private fun launchEmergencyActivity() {
        try {
            val launchIntent = Intent(this, EmergencyAlertActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            startActivity(launchIntent)
        } catch (e: Exception) {
            Log.w(TAG, "direct emergency activity launch failed", e)
        }
    }

    private fun isServiceEnabled(): Boolean {
        val prefs = getSharedPreferences(PREFS_NATIVE, Context.MODE_PRIVATE)
        return prefs.getBoolean(NatsNotificationsManager.KEY_SERVICE_ENABLED, false)
    }

    private fun isAppInForeground(): Boolean {
        val prefs = getSharedPreferences(PREFS_NATIVE, Context.MODE_PRIVATE)
        return prefs.getBoolean(NatsNotificationsManager.KEY_APP_IN_FOREGROUND, false)
    }

    private fun savePendingEmergencyAlert(subject: String, payload: String) {
        val prefs = getSharedPreferences(PREFS_NATIVE, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_PENDING_ALERT_SUBJECT, subject)
            .putString(KEY_PENDING_ALERT_PAYLOAD, payload)
            .putLong(KEY_PENDING_ALERT_RECEIVED_AT, System.currentTimeMillis())
            .apply()
    }

    private fun clearPendingEmergencyAlert() {
        val prefs = getSharedPreferences(PREFS_NATIVE, Context.MODE_PRIVATE)
        prefs.edit()
            .remove(KEY_PENDING_ALERT_SUBJECT)
            .remove(KEY_PENDING_ALERT_PAYLOAD)
            .remove(KEY_PENDING_ALERT_RECEIVED_AT)
            .apply()
    }

    private fun scheduleRestart(delayMs: Long) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val restartIntent = Intent(this, NatsRestartReceiver::class.java).apply {
            action = NatsRestartReceiver.ACTION_RESTART_SERVICE
        }
        val pending = PendingIntent.getBroadcast(
            this,
            RESTART_REQUEST_CODE,
            restartIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val triggerAt = System.currentTimeMillis() + delayMs
        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
    }

    private fun isDebuggableBuild(): Boolean {
        return (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

    private fun logLongMessage(label: String, value: String) {
        if (value.isEmpty()) {
            Log.d(TAG, "$label=<empty>")
            return
        }

        val chunkSize = 3000
        var index = 0
        var part = 1
        val totalParts = (value.length + chunkSize - 1) / chunkSize

        while (index < value.length) {
            val end = minOf(index + chunkSize, value.length)
            val chunk = value.substring(index, end)
            Log.d(TAG, "$label part=$part/$totalParts $chunk")
            index = end
            part += 1
        }
    }

    private fun stopEmergencyTone() {
        try {
            toneGenerator?.stopTone()
            toneGenerator?.release()
        } catch (_: Exception) {
        } finally {
            toneGenerator = null
        }
    }

    private fun startEmergencyEffects() {
        if (emergencyActive) return
        emergencyActive = true
        startNativeVibration()
        mainHandler.post(toneLoopRunnable)
        mainHandler.post(torchLoopRunnable)
    }

    private fun stopEmergencyEffects(reason: String) {
        if (!emergencyActive) return
        emergencyActive = false
        mainHandler.removeCallbacks(toneLoopRunnable)
        mainHandler.removeCallbacks(torchLoopRunnable)
        stopEmergencyTone()
        stopNativeVibration()
        disableTorchInternal()
        Log.i(TAG, "emergency effects stopped reason=$reason")
    }

    private fun startNativeVibration() {
        try {
            val pattern = longArrayOf(0, 1000, 350, 1000, 350)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val vibrator = getSystemVibrator() ?: return
                vibrator.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                (getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator)?.vibrate(pattern, 0)
            }
        } catch (e: Exception) {
            Log.w(TAG, "native vibration start failed", e)
        }
    }

    private fun stopNativeVibration() {
        try {
            getSystemVibrator()?.cancel()
        } catch (_: Exception) {
        }
    }

    private fun getSystemVibrator(): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = getSystemService(VibratorManager::class.java)
            manager?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    private fun toggleTorchInternal() {
        try {
            val cameraId = resolveTorchCameraId() ?: return
            val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            isTorchOn = !isTorchOn
            cameraManager.setTorchMode(cameraId, isTorchOn)
        } catch (e: Exception) {
            if (isDebuggableBuild()) {
                Log.w(TAG, "torch toggle failed", e)
            }
        }
    }

    private fun disableTorchInternal() {
        try {
            val cameraId = resolveTorchCameraId() ?: return
            val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            cameraManager.setTorchMode(cameraId, false)
        } catch (_: Exception) {
        } finally {
            isTorchOn = false
        }
    }

    private fun resolveTorchCameraId(): String? {
        if (torchCameraId != null) return torchCameraId
        return try {
            val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val id = cameraManager.cameraIdList.firstOrNull { id ->
                val chars = cameraManager.getCameraCharacteristics(id)
                val hasFlash = chars.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
                val lensFacing = chars.get(CameraCharacteristics.LENS_FACING)
                hasFlash && lensFacing == CameraCharacteristics.LENS_FACING_BACK
            }
            torchCameraId = id
            id
        } catch (_: Exception) {
            null
        }
    }

    private fun getStreamRotationDegrees(): Int {
        val rotation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val displayManager = getSystemService(DisplayManager::class.java)
            displayManager?.getDisplay(android.view.Display.DEFAULT_DISPLAY)?.rotation
                ?: Surface.ROTATION_0
        } else {
            @Suppress("DEPRECATION")
            (getSystemService(Context.WINDOW_SERVICE) as? WindowManager)
                ?.defaultDisplay
                ?.rotation ?: Surface.ROTATION_0
        }
        return when (rotation) {
            Surface.ROTATION_0 -> 90
            Surface.ROTATION_90 -> 0
            Surface.ROTATION_180 -> 270
            Surface.ROTATION_270 -> 180
            else -> 90
        }
    }

    override fun onConnectionStarted(url: String) {
        Log.i(TAG, "RTMP onConnectionStarted url=$url")
    }

    override fun onConnectionSuccess() {
        Log.i(TAG, "RTMP onConnectionSuccess")
    }

    override fun onConnectionFailed(reason: String) {
        Log.e(TAG, "RTMP onConnectionFailed reason=$reason")
        stopConfiguredRtmpStream(reason = "connection_failed")
    }

    override fun onNewBitrate(bitrate: Long) {
        Log.d(TAG, "RTMP onNewBitrate bitrate=$bitrate")
    }

    override fun onDisconnect() {
        Log.i(TAG, "RTMP onDisconnect")
        stopConfiguredRtmpStream(reason = "disconnect")
    }

    override fun onAuthError() {
        Log.e(TAG, "RTMP onAuthError")
        stopConfiguredRtmpStream(reason = "auth_error")
    }

    override fun onAuthSuccess() {
        Log.i(TAG, "RTMP onAuthSuccess")
    }

    private enum class PayloadAction {
        DISPLAY_ALERT,
        RESOLVED_ALERT,
        START_STREAM,
        STOP_STREAM,
        IGNORE,
    }

    companion object {
        private const val PREFS_NATIVE = "nats_service_prefs"
        private const val AUTO_STREAM_DELAY_MS = 4 * 60 * 1000L
        const val ACTION_START = "com.example.cipher_safety.nats.ACTION_START"
        const val ACTION_STOP = "com.example.cipher_safety.nats.ACTION_STOP"
        const val ACTION_CONFIRM = "com.example.cipher_safety.nats.ACTION_CONFIRM"
        const val ACTION_CANNOT_COMPLY = "com.example.cipher_safety.nats.ACTION_CANNOT_COMPLY"
        const val ACTION_SILENCE = "com.example.cipher_safety.nats.ACTION_SILENCE"
        const val ACTION_DEBUG_ALERT = "com.example.cipher_safety.nats.ACTION_DEBUG_ALERT"
        const val EXTRA_SUBJECT = "extra_subject"
        const val EXTRA_PAYLOAD = "extra_payload"

        private const val TAG = "NatsConfig"
        private const val ONGOING_CHANNEL_ID = "nats_foreground_channel"
        private const val MESSAGE_CHANNEL_ID = "nats_messages_channel_v3"
        private const val ONGOING_NOTIFICATION_ID = 7071
        const val KEY_PENDING_ALERT_SUBJECT = "pending_alert_subject"
        const val KEY_PENDING_ALERT_PAYLOAD = "pending_alert_payload"
        const val KEY_PENDING_ALERT_RECEIVED_AT = "pending_alert_received_at"
        private const val RESTART_REQUEST_CODE = 8807
        private const val OPEN_APP_REQUEST_CODE = 8901
        private const val OPEN_ALERT_REQUEST_CODE = 8904
        private const val CONFIRM_REQUEST_CODE = 8902
        private const val CANNOT_COMPLY_REQUEST_CODE = 8903
        private const val EMERGENCY_NOTIFICATION_ID = 9901

        private val messageId = AtomicInteger(10_000)

        fun isVolumeKey(keyCode: Int): Boolean {
            return keyCode == KeyEvent.KEYCODE_VOLUME_DOWN ||
                keyCode == KeyEvent.KEYCODE_VOLUME_UP
        }
    }
}
