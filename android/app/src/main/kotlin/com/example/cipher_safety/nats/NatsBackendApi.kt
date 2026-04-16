package com.example.cipher_safety.nats

import android.util.Log
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

class NatsBackendApi(
    private val stateStore: NatsNativeStateStore,
) {
    fun postPanicThreatCreate(
        cameraId: String,
        reason: String,
        logTag: String,
    ) {
        val payload = JSONObject().put("camera_id", cameraId)
        postJson(
            endpoint = "$API_BASE_URL/threatsmeta/panic/create",
            payload = payload,
            logTag = logTag,
            failureMessage = "postPanicThreatCreate failed reason=$reason cameraId=$cameraId",
            successMessage = "postPanicThreatCreate success reason=$reason cameraId=$cameraId",
            exceptionMessage = "postPanicThreatCreate exception reason=$reason cameraId=$cameraId",
        )
    }

    private fun postJson(
        endpoint: String,
        payload: JSONObject,
        logTag: String,
        failureMessage: String,
        successMessage: String,
        exceptionMessage: String,
    ) {
        Thread {
            var connection: HttpURLConnection? = null
            try {
                connection = (URL(endpoint).openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    doOutput = true
                    connectTimeout = 15_000
                    readTimeout = 15_000
                    setRequestProperty("Content-Type", "application/json")
                    setRequestProperty("Accept", "application/json")
                    setRequestProperty("project", PROJECT_HEADER_VALUE)
                    setRequestProperty("organizationid", ORGANIZATION_ID_HEADER_VALUE)
                    setRequestProperty("productid", PRODUCT_ID_HEADER_VALUE)
                    val accessToken = stateStore.readAccessToken()
                    if (accessToken.isNotBlank()) {
                        setRequestProperty("Authorization", "Bearer $accessToken")
                    }
                }

                OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { writer ->
                    writer.write(payload.toString())
                }

                val status = connection.responseCode
                val responseBody = try {
                    val stream =
                        if (status in 200..299) connection.inputStream else connection.errorStream
                    stream?.bufferedReader()?.use { it.readText() }.orEmpty()
                } catch (_: Exception) {
                    ""
                }

                if (status !in 200..299) {
                    Log.w(logTag, "$failureMessage status=$status body=${responseBody.take(240)}")
                } else {
                    Log.i(logTag, "$successMessage body=${responseBody.take(240)}")
                }
            } catch (e: Exception) {
                Log.e(logTag, exceptionMessage, e)
            } finally {
                connection?.disconnect()
            }
        }.start()
    }

    companion object {
        private const val API_BASE_URL = "https://staging.api.cipher.interactivelife.me/api"
        private const val PROJECT_HEADER_VALUE = "cipher"
        private const val ORGANIZATION_ID_HEADER_VALUE = "698af675991550fcad337a3f"
        private const val PRODUCT_ID_HEADER_VALUE = "40095093-5ee8-44eb-b92a-68cb5ae9d04c"
    }
}
