package com.example.cipher_safety.nats

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat

class NatsBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val receivedAction = intent?.action.orEmpty()
        if (
            receivedAction != Intent.ACTION_BOOT_COMPLETED &&
            receivedAction != Intent.ACTION_MY_PACKAGE_REPLACED &&
            receivedAction != "android.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }

        val prefs = context.getSharedPreferences(PREFS_NATIVE, Context.MODE_PRIVATE)
        val enabled = prefs.getBoolean(NatsNotificationsManager.KEY_SERVICE_ENABLED, false)
        if (!enabled) {
            Log.i(TAG, "service disabled by user; skip auto-start")
            return
        }

        val startIntent = Intent(context, NatsForegroundService::class.java).apply {
            action = NatsForegroundService.ACTION_START
        }
        ContextCompat.startForegroundService(context, startIntent)
        Log.i(TAG, "auto-started service on action=$receivedAction")
    }

    companion object {
        private const val TAG = "NatsConfig"
        private const val PREFS_NATIVE = "nats_service_prefs"
    }
}
