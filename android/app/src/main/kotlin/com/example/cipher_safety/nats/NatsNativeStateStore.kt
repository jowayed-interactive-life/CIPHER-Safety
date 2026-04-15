package com.example.cipher_safety.nats

import android.content.Context
import android.content.Intent
import android.util.Log

class NatsNativeStateStore(private val context: Context) {
    fun saveSessionOverrides(args: Map<*, *>) {
        val editor = prefs.edit()

        (args["accessToken"] as? String)?.let { editor.putString(NatsNotificationsManager.KEY_ACCESS_TOKEN, it) }
        (args["userId"] as? String)?.let { editor.putString(NatsNotificationsManager.KEY_USER_ID, it) }
        (args["organizationId"] as? String)?.let {
            editor.putString(NatsNotificationsManager.KEY_ORGANIZATION_ID, it)
        }
        (args["chatBusAuthUrl"] as? String)?.let {
            editor.putString(NatsNotificationsManager.KEY_CHAT_BUS_AUTH_URL, it)
        }
        (args["serverUrl"] as? String)?.let {
            editor.putString(NatsNotificationsManager.KEY_NATS_SERVER_URL, it)
        }
        (args["env"] as? String)?.let { editor.putString(NatsNotificationsManager.KEY_NATS_ENV, it) }
        (args["primarySubject"] as? String)?.let {
            editor.putString(NatsNotificationsManager.KEY_NATS_SUBJECT_PRIMARY, it)
        }
        (args["mobileSubject"] as? String)?.let {
            editor.putString(NatsNotificationsManager.KEY_NATS_SUBJECT_MOBILE, it)
        }
        (args["buildingSubject"] as? String)?.let {
            editor.putString(NatsNotificationsManager.KEY_NATS_SUBJECT_BUILDING, it)
        }
        editor.putBoolean(NatsNotificationsManager.KEY_SERVICE_ENABLED, true)
        editor.apply()
    }

    fun clearRuntimeNatsConfig() {
        prefs.edit()
            .remove(NatsNotificationsManager.KEY_NATS_SERVER_URL)
            .remove(NatsNotificationsManager.KEY_NATS_ENV)
            .remove(NatsNotificationsManager.KEY_NATS_SUBJECT_PRIMARY)
            .remove(NatsNotificationsManager.KEY_NATS_SUBJECT_MOBILE)
            .apply()
    }

    fun saveStreamingConfig(
        cameraId: String? = null,
        streamUrl: String? = null,
        tabletId: String? = null,
        buildingName: String? = null,
    ) {
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
    }

    fun clearStreamingConfig() {
        prefs.edit()
            .remove(NatsNotificationsManager.KEY_STREAM_CAMERA_ID)
            .remove(NatsNotificationsManager.KEY_STREAM_URL)
            .remove(NatsNotificationsManager.KEY_STREAM_TABLET_ID)
            .remove(NatsNotificationsManager.KEY_STREAM_BUILDING_NAME)
            .apply()
    }

    fun setServiceEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(NatsNotificationsManager.KEY_SERVICE_ENABLED, enabled).apply()
    }

    fun isServiceEnabled(): Boolean {
        return prefs.getBoolean(NatsNotificationsManager.KEY_SERVICE_ENABLED, false)
    }

    fun setAppInForeground(isForeground: Boolean) {
        prefs.edit().putBoolean(NatsNotificationsManager.KEY_APP_IN_FOREGROUND, isForeground).apply()
    }

    fun isAppInForeground(): Boolean {
        return prefs.getBoolean(NatsNotificationsManager.KEY_APP_IN_FOREGROUND, false)
    }

    fun readAccessToken(): String {
        return prefs.getString(NatsNotificationsManager.KEY_ACCESS_TOKEN, null).orEmpty()
    }

    fun readConfiguredCameraId(): String? {
        return prefs.getString(NatsNotificationsManager.KEY_STREAM_CAMERA_ID, null)
    }

    fun readConfiguredStreamUrl(): String? {
        return prefs.getString(NatsNotificationsManager.KEY_STREAM_URL, null)
    }

    fun readConfiguredTabletId(): String? {
        return prefs.getString(NatsNotificationsManager.KEY_STREAM_TABLET_ID, null)
    }

    fun readConfiguredBuildingName(): String? {
        return prefs.getString(NatsNotificationsManager.KEY_STREAM_BUILDING_NAME, null)
    }

    fun savePendingEmergencyAlert(subject: String, payload: String) {
        prefs.edit()
            .putString(NatsForegroundService.KEY_PENDING_ALERT_SUBJECT, subject)
            .putString(NatsForegroundService.KEY_PENDING_ALERT_PAYLOAD, payload)
            .putLong(NatsForegroundService.KEY_PENDING_ALERT_RECEIVED_AT, System.currentTimeMillis())
            .apply()
    }

    fun clearPendingEmergencyAlert() {
        prefs.edit()
            .remove(NatsForegroundService.KEY_PENDING_ALERT_SUBJECT)
            .remove(NatsForegroundService.KEY_PENDING_ALERT_PAYLOAD)
            .remove(NatsForegroundService.KEY_PENDING_ALERT_RECEIVED_AT)
            .apply()
    }

    fun consumePendingEmergencyAlert(logTag: String): Map<String, Any>? {
        val subject = prefs.getString(NatsForegroundService.KEY_PENDING_ALERT_SUBJECT, null)
        val payload = prefs.getString(NatsForegroundService.KEY_PENDING_ALERT_PAYLOAD, null)
        val receivedAt = prefs.getLong(NatsForegroundService.KEY_PENDING_ALERT_RECEIVED_AT, 0L)

        if (subject.isNullOrBlank() || payload.isNullOrBlank()) {
            Log.d(logTag, "consumePendingEmergencyAlert empty")
            return null
        }

        Log.d(
            logTag,
            "consumePendingEmergencyAlert subject=$subject payloadLength=${payload.length} receivedAt=$receivedAt",
        )

        clearPendingEmergencyAlert()

        return hashMapOf(
            "subject" to subject,
            "payload" to payload,
            "receivedAt" to receivedAt,
        )
    }

    fun persistIncomingAlertFromIntent(intent: Intent?, logTag: String) {
        if (intent == null) return
        val subject = intent.getStringExtra(NatsForegroundService.EXTRA_SUBJECT)
        val payload = intent.getStringExtra(NatsForegroundService.EXTRA_PAYLOAD)
        if (subject.isNullOrBlank() || payload.isNullOrBlank()) {
            Log.d(
                logTag,
                "persistIncomingAlertFromIntent skipped hasSubject=${!subject.isNullOrBlank()} hasPayload=${!payload.isNullOrBlank()}",
            )
            return
        }

        savePendingEmergencyAlert(subject, payload)
        Log.d(logTag, "persistIncomingAlertFromIntent saved subject=$subject payloadLength=${payload.length}")
    }

    private val prefs
        get() = context.getSharedPreferences(PREFS_NATIVE, Context.MODE_PRIVATE)

    companion object {
        private const val PREFS_NATIVE = "nats_service_prefs"
    }
}
