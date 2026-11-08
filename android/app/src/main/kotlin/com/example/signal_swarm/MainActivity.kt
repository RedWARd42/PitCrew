package com.example.signal_swarm

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
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

/// Hosts the two platform channels the Dart side talks to:
///
///  * `swat/sms` — reads the real SMS inbox (content://sms/inbox) once the
///    user grants READ_SMS. Returns an empty list when permission is
///    missing; Dart then falls back to the synthetic demo inbox.
///  * `swat/overlay` — controls the floating-drone overlay service that
///    hovers over other apps, including the stock Messages app.
class MainActivity : FlutterActivity() {

    companion object {
        private const val SMS_CHANNEL = "swat/sms"
        private const val OVERLAY_CHANNEL = "swat/overlay"
        private const val COMMS_CHANNEL = "swat/comms"
        private const val ACCOUNT_CHANNEL = "swat/account"
        private const val ACCOUNT_PREFS = "swat_account"
        private const val SMS_PERMISSION_REQUEST = 4101
        private const val MAX_MESSAGES = 30
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
                        stopService(Intent(this, OverlayService::class.java))
                        result.success(null)
                    }
                    // Senders blocked from the overlay panel, so the
                    // in-app Blocked tab can show them too.
                    "getNativeBlocks" -> result.success(SwatPrefs.readBlocks(this))
                    // The overlay's incoming-text trigger needs RECEIVE_SMS
                    // (and READ_SMS for badge-tap scans of the store).
                    "requestSmsPermissions" -> {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(
                                Manifest.permission.READ_SMS,
                                Manifest.permission.RECEIVE_SMS,
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

    private fun canDrawOverlays(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)

    private fun openOverlaySettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName"),
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        }
    }

    private fun startOverlay(): Boolean {
        if (!canDrawOverlays()) return false
        val intent = Intent(this, OverlayService::class.java)
        ContextCompat.startForegroundService(this, intent)
        return true
    }
}
