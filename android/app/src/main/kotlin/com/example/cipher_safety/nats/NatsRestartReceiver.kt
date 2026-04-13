package com.example.cipher_safety.nats

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat

class NatsRestartReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action.orEmpty()
        if (action != ACTION_RESTART_SERVICE) return

        val prefs = context.getSharedPreferences(PREFS_NATIVE, Context.MODE_PRIVATE)
        val enabled = prefs.getBoolean(NatsNotificationsManager.KEY_SERVICE_ENABLED, false)
        if (!enabled) {
            Log.i(TAG, "restart skipped; service is disabled")
            return
        }

        val startIntent = Intent(context, NatsForegroundService::class.java).apply {
            this.action = NatsForegroundService.ACTION_START
        }
        ContextCompat.startForegroundService(context, startIntent)
        Log.i(TAG, "restart alarm fired; service start requested")
    }

    companion object {
        const val ACTION_RESTART_SERVICE = "com.example.cipher_safety.nats.ACTION_RESTART_SERVICE"
        private const val TAG = "NatsConfig"
        private const val PREFS_NATIVE = "nats_service_prefs"
    }
}
