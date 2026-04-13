package com.example.cipher_safety.nats

import android.util.Log
import io.nats.client.Connection
import io.nats.client.ConnectionListener
import io.nats.client.Dispatcher
import io.nats.client.ErrorListener
import io.nats.client.Nats
import io.nats.client.Options
import java.nio.charset.StandardCharsets
import java.time.Duration

class NatsNotificationClient {
    private val lock = Any()

    private var connection: Connection? = null
    private var dispatcher: Dispatcher? = null
    private val subscribedSubjects = linkedSetOf<String>()

    fun connect(
        serverUrl: String,
        onMessage: (payload: String, subject: String) -> Unit,
    ) {
        synchronized(lock) {
            if (connection != null && dispatcher != null) {
                return
            }

            val options = Options.Builder()
                .server(serverUrl)
                .maxReconnects(-1)
                .reconnectWait(Duration.ofSeconds(2))
                .connectionListener(ConnectionListener { _, event ->
                    Log.d(TAG, "connectionEvent=$event")
                })
                .errorListener(object : ErrorListener {
                    override fun errorOccurred(conn: Connection?, error: String?) {
                        Log.e(TAG, "errorOccurred=$error")
                    }

                    override fun exceptionOccurred(conn: Connection?, exp: Exception?) {
                        Log.e(TAG, "exceptionOccurred", exp)
                    }

                    override fun slowConsumerDetected(
                        conn: Connection?,
                        consumer: io.nats.client.Consumer?,
                    ) {
                        Log.w(TAG, "slowConsumerDetected")
                    }
                })
                .build()

            val newConnection = Nats.connect(options)
            val newDispatcher = newConnection.createDispatcher { message ->
                val payload = String(message.data, StandardCharsets.UTF_8)
                onMessage(payload, message.subject)
            }

            connection = newConnection
            dispatcher = newDispatcher
        }
    }

    fun subscribe(subjects: List<String>) {
        synchronized(lock) {
            val currentDispatcher = dispatcher ?: return

            subjects.forEach { subject ->
                if (subscribedSubjects.add(subject)) {
                    currentDispatcher.subscribe(subject)
                    Log.d(TAG, "subscribed subject=$subject")
                }
            }
        }
    }

    fun unsubscribeAll() {
        synchronized(lock) {
            val currentDispatcher = dispatcher ?: return
            subscribedSubjects.forEach { subject ->
                try {
                    currentDispatcher.unsubscribe(subject)
                } catch (e: Exception) {
                    Log.w(TAG, "unsubscribe failed for subject=$subject", e)
                }
            }
            subscribedSubjects.clear()
        }
    }

    fun disconnect() {
        synchronized(lock) {
            try {
                unsubscribeAll()
            } catch (_: Exception) {
            }

            try {
                connection?.close()
            } catch (e: Exception) {
                Log.w(TAG, "connection close failed", e)
            }

            dispatcher = null
            connection = null
        }
    }

    companion object {
        private const val TAG = "NatsConfig"
    }
}
