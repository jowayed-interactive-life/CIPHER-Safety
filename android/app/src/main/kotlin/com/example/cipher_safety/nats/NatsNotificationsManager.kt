package com.example.cipher_safety.nats

import android.content.Context
import android.net.Uri
import android.util.Log
import org.json.JSONObject
import java.io.BufferedInputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class NatsNotificationsManager(
    private val context: Context,
    private val client: NatsNotificationClient = NatsNotificationClient(),
) {
    @Volatile
    private var started = false

    private val executor: ExecutorService = Executors.newSingleThreadExecutor()

    fun start(onMessage: (payload: String, subject: String) -> Unit) {
        if (started) {
            Log.d(TAG, "start ignored; already started")
            return
        }
        started = true

        executor.execute {
            try {
                val session = readSession() ?: run {
                    Log.w(TAG, "missing session data (token/userId/organizationId)")
                    null
                }
                if (session != null && isDebuggableBuild()) {
                    logSessionData(session)
                }

                val direct = readDirectConfig()
                if (session == null && direct == null) {
                    Log.w(TAG, "no chat bus config and no direct NATS config; skip start")
                    started = false
                    return@execute
                }

                val resolvedConfig = if (session != null) {
                    resolveChatBusConfig(session)
                } else {
                    null
                } ?: direct

                if (resolvedConfig == null) {
                    Log.w(TAG, "unable to resolve NATS config; skip start")
                    started = false
                    return@execute
                }

                logResolvedConfig(
                    env = resolvedConfig.env,
                    urlSource = resolvedConfig.urlSource,
                    selectedServerUrl = resolvedConfig.serverUrl,
                    subjects = resolvedConfig.subjects,
                    token = session?.accessToken,
                )

                client.connect(resolvedConfig.serverUrl, onMessage)
                client.subscribe(resolvedConfig.subjects)
            } catch (e: Exception) {
                Log.e(TAG, "manager start failed", e)
                started = false
            }
        }
    }

    fun stop() {
        started = false
        executor.execute {
            try {
                client.unsubscribeAll()
            } catch (_: Exception) {
            }
            try {
                client.disconnect()
            } catch (_: Exception) {
            }
            Log.d(TAG, "manager stopped")
        }
    }

    private fun readSession(): SessionData? {
        val nativePrefs = context.getSharedPreferences(PREFS_NATIVE, Context.MODE_PRIVATE)
        val flutterPrefs = context.getSharedPreferences(PREFS_FLUTTER, Context.MODE_PRIVATE)

        val token = nativePrefs.getString(KEY_ACCESS_TOKEN, null)
            ?: flutterPrefs.getString("flutter.accessToken", null)
            ?: flutterPrefs.getString("flutter.access_token", null)

        val userId = nativePrefs.getString(KEY_USER_ID, null)
            ?: flutterPrefs.getString("flutter.userId", null)
            ?: flutterPrefs.getString("flutter.user_id", null)

        val organizationId = nativePrefs.getString(KEY_ORGANIZATION_ID, null)
            ?: flutterPrefs.getString("flutter.organizationId", null)
            ?: flutterPrefs.getString("flutter.organization_id", null)

        val chatBusAuthUrl = nativePrefs.getString(KEY_CHAT_BUS_AUTH_URL, null)
            ?: flutterPrefs.getString("flutter.chatBusAuthUrl", null)
            ?: flutterPrefs.getString("flutter.chat_bus_auth_url", null)

        if (token.isNullOrBlank() || userId.isNullOrBlank() || organizationId.isNullOrBlank()) {
            return null
        }

        return SessionData(
            accessToken = token,
            userId = userId,
            organizationId = organizationId,
            chatBusAuthUrl = chatBusAuthUrl,
        )
    }

    private fun readDirectConfig(): ResolvedNatsConfig? {
        val nativePrefs = context.getSharedPreferences(PREFS_NATIVE, Context.MODE_PRIVATE)
        val serverUrl = nativePrefs.getString(KEY_NATS_SERVER_URL, null)
        val env = nativePrefs.getString(KEY_NATS_ENV, null).orEmpty()
        val primarySubject = nativePrefs.getString(KEY_NATS_SUBJECT_PRIMARY, null)
        val mobileSubject = nativePrefs.getString(KEY_NATS_SUBJECT_MOBILE, null)
        val buildingSubject = nativePrefs.getString(KEY_NATS_SUBJECT_BUILDING, null)

        if (serverUrl.isNullOrBlank()) return null
        val subjects = listOfNotNull(primarySubject, mobileSubject, buildingSubject)
            .filter { it.isNotBlank() }
            .distinct()
        if (subjects.isEmpty()) return null

        return ResolvedNatsConfig(
            serverUrl = serverUrl,
            subjects = subjects,
            env = if (env.isBlank()) "direct" else env,
            urlSource = "direct",
        )
    }

    private fun resolveChatBusConfig(session: SessionData): ResolvedNatsConfig? {
        val auth = getChatBusAuth(session.accessToken, session.chatBusAuthUrl) ?: run {
            Log.w(TAG, "getChatBusAuth failed")
            return null
        }

        val selectedServerUrl = auth.urlDomainTcp ?: auth.urlTcp ?: auth.url
        val urlSource = when {
            auth.urlDomainTcp != null -> "urlDomainTcp"
            auth.urlTcp != null -> "urlTcp"
            auth.url != null -> "url"
            else -> null
        }

        if (selectedServerUrl.isNullOrBlank() || auth.env.isBlank()) {
            Log.w(TAG, "invalid chat bus config; env/url missing")
            return null
        }

        val subjects = listOf(
            "${auth.env}.${session.organizationId}.notify.user.${session.userId}",
            "${auth.env}.${session.organizationId}.notify.user.mobile.${session.userId}",
        )

        return ResolvedNatsConfig(
            serverUrl = selectedServerUrl,
            subjects = subjects,
            env = auth.env,
            urlSource = urlSource ?: "none",
        )
    }

    private fun getChatBusAuth(accessToken: String, endpointUrl: String?): ChatBusAuth? {
        if (endpointUrl.isNullOrBlank()) {
            Log.w(TAG, "chat bus auth endpoint is missing")
            return null
        }

        val connection = (URL(endpointUrl).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            setRequestProperty("Authorization", "Bearer $accessToken")
            setRequestProperty("Accept", "application/json")
            connectTimeout = 15_000
            readTimeout = 15_000
        }

        return try {
            val status = connection.responseCode
            if (status !in 200..299) {
                val err = connection.errorStream?.bufferedReader()?.use { it.readText() }.orEmpty()
                Log.w(TAG, "getChatBusAuth http=$status body=${err.take(240)}")
                null
            } else {
                val body = BufferedInputStream(connection.inputStream).bufferedReader().use { it.readText() }
                if (isDebuggableBuild()) {
                    Log.d(TAG, "getChatBusAuth success body=$body")
                }
                parseChatBusAuth(body)
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun parseChatBusAuth(rawBody: String): ChatBusAuth {
        val root = JSONObject(rawBody)
        val source = root.optJSONObject("data") ?: root
        return ChatBusAuth(
            urlDomainTcp = source.optString("urlDomainTcp").ifBlank { null },
            urlTcp = source.optString("urlTcp").ifBlank { null },
            url = source.optString("url").ifBlank { null },
            env = source.optString("env"),
        )
    }

    private fun logResolvedConfig(
        env: String,
        urlSource: String,
        selectedServerUrl: String,
        subjects: List<String>,
        token: String?,
    ) {
        Log.i(TAG, "env=$env")
        Log.i(TAG, "urlSource=$urlSource")
        Log.i(TAG, "server=${redactServerUrl(selectedServerUrl)}")
        Log.i(TAG, "subjects=$subjects")
        if (token != null) {
            Log.i(TAG, "token=${redactToken(token)}")
        } else {
            Log.i(TAG, "token=none")
        }
    }

    private fun logSessionData(session: SessionData) {
        Log.d(TAG, "session.userId=${session.userId}")
        Log.d(TAG, "session.organizationId=${session.organizationId}")
        Log.d(TAG, "session.chatBusAuthUrl=${session.chatBusAuthUrl ?: "none"}")
        Log.d(TAG, "session.accessToken=${session.accessToken}")
    }

    private fun isDebuggableBuild(): Boolean {
        return (context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

    private fun redactServerUrl(rawUrl: String): String {
        return try {
            val parsed = if (rawUrl.startsWith("nats://") || rawUrl.startsWith("tls://")) {
                Uri.parse(rawUrl)
            } else {
                Uri.parse("nats://$rawUrl")
            }
            "${parsed.host}:${parsed.port}"
        } catch (_: Exception) {
            "unparsable"
        }
    }

    private fun redactToken(token: String): String {
        val prefix = token.take(6)
        return "len=${token.length},prefix=$prefix***"
    }

    data class SessionData(
        val accessToken: String,
        val userId: String,
        val organizationId: String,
        val chatBusAuthUrl: String?,
    )

    data class ChatBusAuth(
        val urlDomainTcp: String?,
        val urlTcp: String?,
        val url: String?,
        val env: String,
    )

    data class ResolvedNatsConfig(
        val serverUrl: String,
        val subjects: List<String>,
        val env: String,
        val urlSource: String,
    )

    companion object {
        private const val TAG = "NatsConfig"
        private const val PREFS_NATIVE = "nats_service_prefs"
        private const val PREFS_FLUTTER = "FlutterSharedPreferences"

        const val KEY_ACCESS_TOKEN = "access_token"
        const val KEY_USER_ID = "user_id"
        const val KEY_ORGANIZATION_ID = "organization_id"
        const val KEY_CHAT_BUS_AUTH_URL = "chat_bus_auth_url"
        const val KEY_NATS_SERVER_URL = "nats_server_url"
        const val KEY_NATS_ENV = "nats_env"
        const val KEY_NATS_SUBJECT_PRIMARY = "nats_subject_primary"
        const val KEY_NATS_SUBJECT_MOBILE = "nats_subject_mobile"
        const val KEY_NATS_SUBJECT_BUILDING = "nats_subject_building"
        const val KEY_STREAM_CAMERA_ID = "stream_camera_id"
        const val KEY_STREAM_URL = "stream_url"
        const val KEY_STREAM_TABLET_ID = "stream_tablet_id"
        const val KEY_STREAM_BUILDING_NAME = "stream_building_name"
        const val KEY_SERVICE_ENABLED = "service_enabled"
        const val KEY_APP_IN_FOREGROUND = "app_in_foreground"
    }
}
