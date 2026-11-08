package com.example.signal_swarm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.TextView

/// The floating Swat drone.
///
/// A foreground service draws one magenta drone badge over whatever app is
/// in front — including the stock Android Messages app — using the system
/// alert window (`TYPE_APPLICATION_OVERLAY`, the chat-heads mechanism).
/// The user drags it anywhere; tapping it brings Swat forward so the
/// fleet can analyze the message on screen.
///
/// Honest platform limit: an overlay can *warn* and *launch*, it cannot
/// reach into Messages and block a tap or quarantine a text — no Android
/// API allows that for a third-party app. The protection flow (analysis,
/// walkthrough, block & report guidance) lives in the Flutter UI.
class OverlayService : Service() {

    companion object {
        private const val CHANNEL_ID = "swat_overlay"
        private const val NOTIFICATION_ID = 7001
    }

    private var windowManager: WindowManager? = null
    private var droneView: View? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        startInForeground()
        showDrone()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int =
        START_STICKY

    override fun onDestroy() {
        droneView?.let { view ->
            try {
                windowManager?.removeView(view)
            } catch (ignored: IllegalArgumentException) {
                // View was never attached (permission revoked mid-flight).
            }
        }
        droneView = null
        super.onDestroy()
    }

    private fun startInForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Swat drone patrol",
                NotificationManager.IMPORTANCE_LOW,
            )
            getSystemService(NotificationManager::class.java)
                ?.createNotificationChannel(channel)
        }
        val notification: Notification =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CHANNEL_ID)
                    .setContentTitle("Swat drone on patrol")
                    .setContentText("Floating over your apps. Tap the drone to scan a text.")
                    .setSmallIcon(android.R.drawable.ic_dialog_alert)
                    .build()
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
                    .setContentTitle("Swat drone on patrol")
                    .setContentText("Floating over your apps. Tap the drone to scan a text.")
                    .setSmallIcon(android.R.drawable.ic_dialog_alert)
                    .build()
            }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun showDrone() {
        windowManager = getSystemService(WindowManager::class.java)
        val sizePx = (58 * resources.displayMetrics.density).toInt()

        val badge = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(0xFFE20074.toInt())
            setStroke(2, 0x66FFFFFF)
        }
        val drone = TextView(this).apply {
            text = "SWAT"
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 11f
            gravity = Gravity.CENTER
            background = badge
            elevation = 8f
        }

        val overlayType =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }
        val params = WindowManager.LayoutParams(
            sizePx,
            sizePx,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (16 * resources.displayMetrics.density).toInt()
            y = (220 * resources.displayMetrics.density).toInt()
        }

        var startX = 0
        var startY = 0
        var touchX = 0f
        var touchY = 0f
        var downAt = 0L
        drone.setOnTouchListener { view, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = params.x
                    startY = params.y
                    touchX = event.rawX
                    touchY = event.rawY
                    downAt = System.currentTimeMillis()
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    params.x = startX + (event.rawX - touchX).toInt()
                    params.y = startY + (event.rawY - touchY).toInt()
                    windowManager?.updateViewLayout(view, params)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    val moved = kotlin.math.abs(event.rawX - touchX) +
                        kotlin.math.abs(event.rawY - touchY)
                    val quick = System.currentTimeMillis() - downAt < 300
                    if (moved < 12 && quick) launchApp()
                    true
                }
                else -> false
            }
        }

        try {
            windowManager?.addView(drone, params)
            droneView = drone
        } catch (ignored: Exception) {
            // Overlay permission was revoked between the check and now —
            // stop quietly instead of crashing the service.
            stopSelf()
        }
    }

    private fun launchApp() {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        intent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (intent != null) startActivity(intent)
    }
}
