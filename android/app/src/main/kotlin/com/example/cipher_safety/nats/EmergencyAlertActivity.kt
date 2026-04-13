package com.example.cipher_safety.nats

import android.app.Activity
import android.graphics.BitmapFactory
import android.content.Intent
import android.graphics.Color
import android.util.Base64
import android.util.Log
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.KeyEvent
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.ImageView
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import org.json.JSONObject
import java.util.regex.Pattern

class EmergencyAlertActivity : Activity() {
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN &&
            NatsForegroundService.isVolumeKey(event.keyCode)
        ) {
            sendActionToService(NatsForegroundService.ACTION_SILENCE)
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setShowOnLockAndTurnScreenOn()

        val pendingAlert = loadPendingAlert()
        val subject = intent.getStringExtra(NatsForegroundService.EXTRA_SUBJECT)
            ?: pendingAlert?.first
            ?: ""
        val payload = intent.getStringExtra(NatsForegroundService.EXTRA_PAYLOAD)
            ?: pendingAlert?.second
            ?: ""
        val parsed = ParsedEmergencyPayload.fromRaw(payload)
        Log.d(
            TAG,
            "popup payloadLength=${payload.length} imagePresent=${!parsed.image.isNullOrBlank()} " +
                "imageLength=${parsed.image?.length ?: 0} instructionsPresent=${!parsed.instructions.isNullOrBlank()} " +
                "alertMode=${parsed.alertMode ?: ""} threatType=${parsed.threatType ?: ""}",
        )

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#8B0000"))
            setPadding(36, 60, 36, 36)
        }

        val title = TextView(this).apply {
            text = "EMERGENCY ALERT"
            textSize = 28f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER_HORIZONTAL
        }
        root.addView(
            title,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )

        val subjectView = TextView(this).apply {
            text = subject
            textSize = 16f
            setTextColor(Color.WHITE)
            setPadding(0, 24, 0, 12)
        }
        root.addView(subjectView)

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }

        parsed.imageBytes?.let { bytes ->
            Log.d(TAG, "popup imageBytesLength=${bytes.size}")
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.let { bitmap ->
                Log.d(TAG, "popup bitmap decode success width=${bitmap.width} height=${bitmap.height}")
                val imageView = ImageView(this).apply {
                    setImageBitmap(bitmap)
                    adjustViewBounds = true
                    scaleType = ImageView.ScaleType.FIT_CENTER
                    setPadding(0, 0, 0, 24)
                }
                content.addView(
                    imageView,
                    LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                    ),
                )
            } ?: Log.w(TAG, "popup bitmap decode returned null")
        } ?: run {
            if (!parsed.image.isNullOrBlank()) {
                Log.w(TAG, "popup image string present but base64 decode returned null")
            } else {
                Log.d(TAG, "popup image missing from parsed payload")
            }
        }

        if (!parsed.alertMode.isNullOrBlank()) {
            content.addView(buildMetaText("Mode: ${parsed.alertMode}"))
        }

        if (!parsed.threatType.isNullOrBlank()) {
            content.addView(buildMetaText("Threat: ${parsed.threatType}"))
        }

        val payloadView = TextView(this).apply {
            text = parsed.displayBody
            textSize = 18f
            setTextColor(Color.WHITE)
            setPadding(0, 8, 0, 24)
        }
        content.addView(payloadView)

        val scroll = ScrollView(this)
        scroll.addView(content)
        root.addView(
            scroll,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )

        val buttons = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }

        val confirm = Button(this).apply {
            text = "Confirm"
            setBackgroundColor(Color.parseColor("#0E7A0D"))
            setTextColor(Color.WHITE)
            setOnClickListener {
                sendActionToService(NatsForegroundService.ACTION_CONFIRM)
                finish()
            }
        }
        val cannot = Button(this).apply {
            text = "Can not comply"
            setBackgroundColor(Color.parseColor("#2E2E2E"))
            setTextColor(Color.WHITE)
            setOnClickListener {
                sendActionToService(NatsForegroundService.ACTION_CANNOT_COMPLY)
                finish()
            }
        }

        buttons.addView(
            confirm,
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                marginEnd = 12
            },
        )
        buttons.addView(
            cannot,
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
        )

        root.addView(
            buttons,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )

        setContentView(root)
    }

    private fun buildMetaText(value: String): TextView {
        return TextView(this).apply {
            text = value
            textSize = 16f
            setTextColor(Color.WHITE)
            setPadding(0, 0, 0, 12)
        }
    }

    private fun sendActionToService(action: String) {
        val intent = Intent(this, NatsForegroundService::class.java).apply {
            this.action = action
        }
        startService(intent)
    }

    private fun setShowOnLockAndTurnScreenOn() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
            )
        }
    }

    private fun loadPendingAlert(): Pair<String, String>? {
        val prefs = getSharedPreferences("nats_service_prefs", MODE_PRIVATE)
        val subject = prefs.getString(NatsForegroundService.KEY_PENDING_ALERT_SUBJECT, null)
        val payload = prefs.getString(NatsForegroundService.KEY_PENDING_ALERT_PAYLOAD, null)
        if (subject.isNullOrBlank() || payload.isNullOrBlank()) {
            return null
        }
        Log.d(TAG, "popup loaded pending alert subject=$subject payloadLength=${payload.length}")
        return subject to payload
    }

    private data class ParsedEmergencyPayload(
        val rawPayload: String,
        val image: String?,
        val threatType: String?,
        val instructions: String?,
        val alertMode: String?,
    ) {
        val displayBody: String
            get() = if (!instructions.isNullOrBlank()) instructions else rawPayload

        val imageBytes: ByteArray?
            get() {
                if (image.isNullOrBlank()) return null
                val value = image.trim()
                return try {
                    val base64Value = if (value.startsWith("data:image")) {
                        value.substringAfter(',', "")
                    } else {
                        value
                    }.replace("\\s".toRegex(), "")
                    if (base64Value.isBlank()) {
                        null
                    } else {
                        try {
                            Base64.decode(base64Value, Base64.DEFAULT)
                        } catch (_: Exception) {
                            Base64.decode(base64Value, Base64.NO_WRAP)
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "popup base64 decode failed", e)
                    null
                }
            }

        companion object {
            fun fromRaw(rawPayload: String): ParsedEmergencyPayload {
                val map = extractAlertObject(tryParseObject(rawPayload))
                val fallback = extractFallbackFields(rawPayload)
                return ParsedEmergencyPayload(
                    rawPayload = rawPayload,
                    image = map?.optString("image").takeUnless { it.isNullOrBlank() } ?: fallback.image,
                    threatType = map?.optString("threatType").takeUnless { it.isNullOrBlank() } ?: fallback.threatType,
                    instructions = map?.optString("instructions").takeUnless { it.isNullOrBlank() } ?: fallback.instructions,
                    alertMode = map?.optString("alertMode").takeUnless { it.isNullOrBlank() } ?: fallback.alertMode,
                )
            }

            private fun tryParseObject(raw: String): JSONObject? {
                val trimmed = raw.trim()
                if (!trimmed.startsWith("{") || !trimmed.endsWith("}")) return null

                try {
                    return JSONObject(trimmed)
                } catch (_: Exception) {
                }

                return try {
                    val normalizedKeys = Regex("([\\{,]\\s*)([A-Za-z_][A-Za-z0-9_]*)\\s*:")
                        .replace(trimmed) { matchResult ->
                            "${matchResult.groupValues[1]}\"${matchResult.groupValues[2]}\":"
                        }
                    val normalizedQuotes = normalizedKeys.replace('\'', '"')
                    JSONObject(normalizedQuotes)
                } catch (_: Exception) {
                    null
                }
            }

            private fun extractAlertObject(source: JSONObject?): JSONObject? {
                if (source == null) return null
                val nestedData = source.optJSONObject("data")
                if (nestedData != null) return nestedData

                val nestedDataString = source.optString("data").takeUnless { it.isNullOrBlank() }
                if (nestedDataString != null) {
                    try {
                        return JSONObject(nestedDataString)
                    } catch (_: Exception) {
                    }
                }

                return source
            }

            private fun extractFallbackFields(raw: String): FallbackFields {
                return FallbackFields(
                    image = matchField(raw, "image"),
                    threatType = matchField(raw, "threatType"),
                    instructions = matchField(raw, "instructions"),
                    alertMode = matchField(raw, "alertMode"),
                )
            }

            private fun matchField(raw: String, fieldName: String): String? {
                val pattern = Pattern.compile(
                    "$fieldName\\s*[:=]\\s*['\"]((?:\\\\.|[^'\"])*)['\"]",
                    Pattern.DOTALL,
                )
                val matcher = pattern.matcher(raw)
                if (!matcher.find()) return null
                val value = matcher.group(1)?.trim().orEmpty()
                return value.ifBlank { null }
            }
        }
    }

    private data class FallbackFields(
        val image: String?,
        val threatType: String?,
        val instructions: String?,
        val alertMode: String?,
    )

    companion object {
        private const val TAG = "EmergencyAlertActivity"
    }
}
