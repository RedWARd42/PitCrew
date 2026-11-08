package com.example.signal_swarm

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.text.format.DateUtils
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/// Swat's existing account, theme, inbox and communication channels, plus
/// accessibility protection controls. Overlay rendering and scanning are Dart.
class MainActivity : FlutterActivity() {

    companion object {
        private const val SMS_CHANNEL = "swat/sms"
        private const val OVERLAY_CHANNEL = "swat/overlay"
        private const val COMMS_CHANNEL = "swat/comms"
        private const val ACCOUNT_CHANNEL = "swat/account"
        private const val ACCOUNT_PREFS = "swat_account"
        private const val THEME_CHANNEL = "swat/theme"
        private const val SETTINGS_PREFS = "swat_settings"
        private const val SMS_PERMISSION_REQUEST = 4101
        private const val MAX_MESSAGES = 30
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "swarm/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openAccessibilitySettings" -> {
                        openOverlaySettings()
                        result.success(null)
                    }
                    "isAccessibilityEnabled" -> result.success(canDrawOverlays())
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "readInbox" -> result.success(readInbox())
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, COMMS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "dial" -> result.success(openDialer(call.argument<String>("phone")))
                    "sms" -> result.success(
                        openSmsComposer(
                            call.argument<String>("phone"),
                            call.argument<String>("body"),
                        )
                    )
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ACCOUNT_CHANNEL)
            .setMethodCallHandler { call, result ->
                val prefs = getSharedPreferences(ACCOUNT_PREFS, MODE_PRIVATE)
                when (call.method) {
                    "getAccount" -> {
                        val email = prefs.getString("email", null)
                        if (email == null) {
                            result.success(null)
                        } else {
                            result.success(
                                mapOf(
                                    "name" to (prefs.getString("name", "") ?: ""),
                                    "email" to email,
                                )
                            )
                        }
                    }
                    "saveAccount" -> {
                        prefs.edit()
                            .putString("name", call.argument<String>("name") ?: "")
                            .putString("email", call.argument<String>("email") ?: "")
                            .apply()
                        result.success(null)
                    }
                    "clearAccount" -> {
                        prefs.edit().clear().apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, THEME_CHANNEL)
            .setMethodCallHandler { call, result ->
                val prefs = getSharedPreferences(SETTINGS_PREFS, MODE_PRIVATE)
                when (call.method) {
                    "getThemeMode" -> result.success(prefs.getString("theme_mode", null))
                    "setThemeMode" -> {
                        prefs.edit()
                            .putString("theme_mode", call.argument<String>("mode") ?: "dark")
                            .apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OVERLAY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canDrawOverlays" -> result.success(canDrawOverlays())
                    "openOverlaySettings" -> {
                        openOverlaySettings()
                        result.success(null)
                    }
                    "startOverlay" -> result.success(startOverlay())
                    "stopOverlay" -> {
                        SwarmAccessibilityService.instance?.disableSelf()
                        result.success(null)
                    }
                    // Senders blocked from the overlay panel, so the
                    // in-app Blocked tab can show them too.
                    "getNativeBlocks" -> result.success(SwatPrefs.readBlocks(this))
                    // Inbox permission is separate from Accessibility consent.
                    "requestSmsPermissions" -> {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(
                                Manifest.permission.READ_SMS,
                            ),
                            SMS_PERMISSION_REQUEST,
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ------------------------------------------------------------- SMS

    private fun readInbox(): List<Map<String, String>> {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.READ_SMS),
                SMS_PERMISSION_REQUEST,
            )
            // Empty for now — Dart shows the demo inbox; after the user
            // grants permission, the next refresh returns the real store.
            return emptyList()
        }

        val messages = mutableListOf<Map<String, String>>()
        val uri = Uri.parse("content://sms/inbox")
        val projection = arrayOf("address", "body", "date")
        contentResolver.query(uri, projection, null, null, "date DESC")?.use { cursor ->
            val addressIdx = cursor.getColumnIndex("address")
            val bodyIdx = cursor.getColumnIndex("body")
            val dateIdx = cursor.getColumnIndex("date")
            val timeFormat = SimpleDateFormat("h:mm a", Locale.US)
            val dayFormat = SimpleDateFormat("MMM d", Locale.US)
            while (cursor.moveToNext() && messages.size < MAX_MESSAGES) {
                val dateMs = if (dateIdx >= 0) cursor.getLong(dateIdx) else 0L
                val label = when {
                    dateMs == 0L -> ""
                    DateUtils.isToday(dateMs) -> timeFormat.format(Date(dateMs))
                    else -> dayFormat.format(Date(dateMs))
                }
                messages.add(
                    mapOf(
                        "address" to (if (addressIdx >= 0) cursor.getString(addressIdx) ?: "" else ""),
                        "body" to (if (bodyIdx >= 0) cursor.getString(bodyIdx) ?: "" else ""),
                        "timeLabel" to label,
                    )
                )
            }
        }
        return messages
    }

    // ------------------------------------------------------------- Comms

    private fun openDialer(phone: String?): Boolean {
        if (phone.isNullOrBlank()) return false
        val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$phone"))
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        return true
    }

    private fun openSmsComposer(phone: String?, body: String?): Boolean {
        if (phone.isNullOrBlank()) return false
        val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$phone"))
        if (!body.isNullOrBlank()) intent.putExtra("sms_body", body)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        return true
    }

    // ------------------------------------------------------------- Overlay

    private fun canDrawOverlays(): Boolean {
        val component = ComponentName(this, SwarmAccessibilityService::class.java)
        val enabled = Settings.Secure.getString(
            contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        return enabled.split(':').any {
            ComponentName.unflattenFromString(it) == component
        }
    }

    private fun openOverlaySettings() {
        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
    }

    private fun startOverlay(): Boolean {
        if (!canDrawOverlays()) {
            openOverlaySettings()
            return false
        }
        return true // Android starts the accessibility service after explicit consent.
    }
}
