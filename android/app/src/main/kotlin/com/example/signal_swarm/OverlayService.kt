package com.example.signal_swarm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.BackgroundColorSpan
import android.text.style.StyleSpan
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/// The fleet, living over the real Messages app.
///
/// A foreground service draws over whatever app is in front — including
/// the stock Android Messages app — using the system alert window
/// (`TYPE_APPLICATION_OVERLAY`, the chat-heads mechanism):
///
///  * a draggable SWAT badge (tap it to scan the latest text), and
///  * a full fleet scan panel: when a text arrives (see [SmsReceiver]) or
///    the badge is tapped, the panel opens *over the app the user is in*,
///    runs the six drones one by one over the message, highlights each
///    drone's evidence in the text, and offers Block & Report right there.
///
/// The message under scan comes from the SMS broadcast / the device SMS
/// store — the same store Messages reads — never from scraping another
/// app's screen. Honest platform limit: an overlay can warn and act on
/// its own surface; it cannot reach inside Messages and block a tap
/// there. Blocking/reporting here records the sender in the shared block
/// list the Swat app reads.
class OverlayService : Service() {

    companion object {
        private const val CHANNEL_ID = "swat_overlay"
        private const val NOTIFICATION_ID = 7001
        const val ACTION_SCAN = "com.example.signal_swarm.SCAN"

        private const val MAGENTA = 0xFFE20074.toInt()
        private const val PANEL_BG = 0xF215151F.toInt()
        private const val RED = 0xFFEF4444.toInt()
        private const val AMBER = 0xFFF59E0B.toInt()
        private const val GREEN = 0xFF22C55E.toInt()
    }

    private var windowManager: WindowManager? = null
    private var badgeView: View? = null
    private var panelView: View? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        startInForeground()
        SwatPrefs.setArmed(this, true)
        showBadge()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_SCAN) scanLatestMessage()
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        SwatPrefs.setArmed(this, false)
        hidePanel()
        badgeView?.let { view ->
            try {
                windowManager?.removeView(view)
            } catch (ignored: IllegalArgumentException) {
                // View was never attached (permission revoked mid-flight).
            }
        }
        badgeView = null
        super.onDestroy()
    }

    // ------------------------------------------------------------ badge
    private fun showBadge() {
        windowManager = getSystemService(WindowManager::class.java)
        val sizePx = dp(58)

        val badge = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(MAGENTA)
            setStroke(2, 0x66FFFFFF)
        }
        val drone = TextView(this).apply {
            text = "SWAT"
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 12.5f
            gravity = Gravity.CENTER
            background = badge
            elevation = 8f
        }

        val params = WindowManager.LayoutParams(
            sizePx,
            sizePx,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dp(16)
            y = dp(220)
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
                    if (moved < 12 && quick) {
                        if (panelView != null) hidePanel() else scanLatestMessage()
                    }
                    true
                }
                else -> false
            }
        }

        try {
            windowManager?.addView(drone, params)
            badgeView = drone
        } catch (ignored: Exception) {
            // Overlay permission was revoked between the check and now —
            // stop quietly instead of crashing the service.
            stopSelf()
        }
    }

    // ------------------------------------------------------------- scan
    /// Analyze the freshest message we know about: the one the receiver
    /// just stored, or the newest row of the SMS store.
    private fun scanLatestMessage() {
        val prefs = getSharedPreferences(SwatPrefs.OVERLAY_PREFS, MODE_PRIVATE)
        var sender = prefs.getString(SwatPrefs.KEY_LAST_SENDER, null)
        var body = prefs.getString(SwatPrefs.KEY_LAST_BODY, null)
        if (sender.isNullOrBlank() || body.isNullOrBlank()) {
            val newest = readNewestSms()
            sender = newest?.first
            body = newest?.second
        }
        if (sender.isNullOrBlank() || body.isNullOrBlank()) {
            showInfoPanel(
                "No text to scan yet",
                "When a text arrives, the fleet scans it right here. You " +
                    "can also open Swat and grant SMS permission so the " +
                    "badge can scan your latest message on tap.",
            )
            return
        }
        val analysis = KotlinScamAnalyzer.analyze(sender, body)
        showScanPanel(analysis)
    }

    private fun readNewestSms(): Pair<String, String>? {
        return try {
            val uri = Uri.parse("content://sms/inbox")
            contentResolver.query(
                uri, arrayOf("address", "body"), null, null, "date DESC",
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return null
                val address = cursor.getString(0) ?: return null
                val body = cursor.getString(1) ?: return null
                address to body
            }
        } catch (ignored: Exception) {
            // READ_SMS not granted — the info panel explains the way in.
            null
        }
    }

    private fun showScanPanel(analysis: KAnalysis) {
        hidePanel()
        val density = resources.displayMetrics.density
        val panelWidth = (resources.displayMetrics.widthPixels - (20 * density).toInt())

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(14), dp(16), dp(14))
            background = GradientDrawable().apply {
                setColor(PANEL_BG)
                cornerRadius = 18 * density
                setStroke((1.5f * density).toInt(), MAGENTA)
            }
            elevation = 12f
        }

        val verdictColor = when (analysis.verdict) {
            KVerdict.DANGEROUS -> RED
            KVerdict.CAUTION -> AMBER
            KVerdict.SAFE -> GREEN
        }
        val verdictChip = TextView(this).apply {
            text = "${analysis.riskScore}/100 · ${analysis.verdict.label}"
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 13.5f
            typeface = Typeface.DEFAULT_BOLD
            setPadding(dp(9), dp(4), dp(9), dp(4))
            background = GradientDrawable().apply {
                setColor(verdictColor)
                cornerRadius = 999f
            }
            visibility = View.INVISIBLE
        }
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(TextView(this@OverlayService).apply {
                text = "SWAT FLEET SCAN"
                setTextColor(MAGENTA)
                textSize = 15.5f
                typeface = Typeface.DEFAULT_BOLD
            })
            addView(View(this@OverlayService).apply {
                layoutParams = LinearLayout.LayoutParams(0, 0, 1f)
            })
            addView(verdictChip)
        }
        root.addView(header)

        root.addView(TextView(this).apply {
            text = "From ${analysis.sender}"
            setTextColor(0xB3FFFFFF.toInt())
            textSize = 14.5f
            setPadding(0, dp(6), 0, 0)
        })

        val messageText = TextView(this).apply {
            text = analysis.body
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 17f
            setPadding(0, dp(8), 0, 0)
            setLineSpacing(0f, 1.25f)
        }
        root.addView(messageText)

        // Drone chips: dim until their scan turn, then light up with the
        // points they contributed.
        val chipRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(12), 0, 0)
        }
        val chipLabels = mutableListOf<TextView>()
        val chipOrbs = mutableListOf<View>()
        for (drone in Drone.values()) {
            val column = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_HORIZONTAL
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            }
            val orb = View(this).apply {
                layoutParams = LinearLayout.LayoutParams(dp(34), dp(34))
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(drone.color)
                }
                alpha = 0.3f
            }
            val label = TextView(this).apply {
                text = drone.label
                setTextColor(drone.color)
                textSize = 12f
                gravity = Gravity.CENTER
                alpha = 0.3f
                setPadding(0, dp(3), 0, 0)
            }
            column.addView(orb)
            column.addView(label)
            chipRow.addView(column)
            chipOrbs.add(orb)
            chipLabels.add(label)
        }
        root.addView(chipRow)

        val findingsText = TextView(this).apply {
            setTextColor(0xB3FFFFFF.toInt())
            textSize = 14.5f
            setPadding(0, dp(10), 0, 0)
            visibility = View.GONE
        }
        root.addView(findingsText)

        val buttonRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(12), 0, 0)
            visibility = View.GONE
        }
        val blockButton = Button(this).apply {
            text = "Block & Report"
            setTextColor(0xFFFFFFFF.toInt())
            background = GradientDrawable().apply {
                setColor(MAGENTA)
                cornerRadius = 999f
            }
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.4f)
            setOnClickListener {
                SwatPrefs.addBlock(
                    this@OverlayService,
                    analysis.sender, analysis.body, analysis.riskScore,
                )
                showProtected(root, findingsText, buttonRow)
            }
        }
        val openButton = Button(this).apply {
            text = "Teach me"
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                marginStart = dp(8)
            }
            setOnClickListener {
                hidePanel()
                launchApp()
            }
        }
        val dismissButton = Button(this).apply {
            text = "Dismiss"
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                marginStart = dp(8)
            }
            setOnClickListener { hidePanel() }
        }
        buttonRow.addView(blockButton)
        buttonRow.addView(openButton)
        buttonRow.addView(dismissButton)
        root.addView(buttonRow)

        attachPanel(root, panelWidth)

        // The scan sequence: one drone at a time lights up and paints its
        // evidence into the message; then the verdict lands.
        val spannable = SpannableStringBuilder(analysis.body)
        val drones = Drone.values()
        for (i in drones.indices) {
            val drone = drones[i]
            handler.postDelayed({
                if (panelView !== root) return@postDelayed
                chipOrbs[i].alpha = 1f
                chipLabels[i].alpha = 1f
                chipOrbs[i].animate().scaleX(1.25f).scaleY(1.25f).setDuration(160)
                    .withEndAction {
                        chipOrbs[i].animate().scaleX(1f).scaleY(1f).setDuration(160).start()
                    }.start()
                val points = analysis.pointsFor(drone)
                chipLabels[i].text =
                    if (points > 0) "${drone.label} +$points" else drone.label
                for (finding in analysis.findingsFor(drone)) {
                    if (!finding.hasSpan) continue
                    val highlight = (drone.color and 0x00FFFFFF) or 0x59000000
                    spannable.setSpan(
                        BackgroundColorSpan(highlight),
                        finding.spanStart, finding.spanEnd,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                    )
                    spannable.setSpan(
                        StyleSpan(Typeface.BOLD),
                        finding.spanStart, finding.spanEnd,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                    )
                }
                messageText.text = spannable
            }, 350L + i * 300L)
        }
        handler.postDelayed({
            if (panelView !== root) return@postDelayed
            verdictChip.visibility = View.VISIBLE
            val flagged = analysis.findings.filter { it.isFlag }
            findingsText.text = if (flagged.isEmpty()) {
                "All six drones checked — nothing here matches a known " +
                    "scam pattern. Confidence ${analysis.confidence}%."
            } else {
                flagged.joinToString(" · ") { "${it.drone.label}: ${it.title}" } +
                    "\nTap Teach me for the step-by-step walkthrough in Swat."
            }
            findingsText.visibility = View.VISIBLE
            buttonRow.visibility = View.VISIBLE
            if (analysis.verdict == KVerdict.SAFE) blockButton.visibility = View.GONE
        }, 350L + drones.size * 300L + 250L)
    }

    private fun showProtected(
        root: LinearLayout,
        findingsText: TextView,
        buttonRow: LinearLayout,
    ) {
        findingsText.text =
            "PROTECTED — sender blocked and added to the shared block " +
                "list. Swat's Blocked tab has the full report."
        buttonRow.visibility = View.GONE
        handler.postDelayed({
            if (panelView === root) hidePanel()
        }, 2200L)
    }

    private fun showInfoPanel(title: String, message: String) {
        hidePanel()
        val density = resources.displayMetrics.density
        val panelWidth = (resources.displayMetrics.widthPixels - (20 * density).toInt())
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(14), dp(16), dp(14))
            background = GradientDrawable().apply {
                setColor(PANEL_BG)
                cornerRadius = 18 * density
                setStroke((1.5f * density).toInt(), MAGENTA)
            }
        }
        root.addView(TextView(this).apply {
            text = title
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 17f
            typeface = Typeface.DEFAULT_BOLD
        })
        root.addView(TextView(this).apply {
            text = message
            setTextColor(0xB3FFFFFF.toInt())
            textSize = 15f
            setPadding(0, dp(6), 0, 0)
        })
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(10), 0, 0)
        }
        row.addView(Button(this).apply {
            text = "Open Swat"
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            setOnClickListener {
                hidePanel()
                launchApp()
            }
        })
        row.addView(Button(this).apply {
            text = "Dismiss"
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                marginStart = dp(8)
            }
            setOnClickListener { hidePanel() }
        })
        root.addView(row)
        attachPanel(root, panelWidth)
    }

    private fun attachPanel(root: View, widthPx: Int) {
        val params = WindowManager.LayoutParams(
            widthPx,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = dp(56)
        }
        try {
            windowManager?.addView(root, params)
            panelView = root
        } catch (ignored: Exception) {
            stopSelf()
        }
    }

    private fun hidePanel() {
        panelView?.let { view ->
            try {
                windowManager?.removeView(view)
            } catch (ignored: IllegalArgumentException) {
            }
        }
        panelView = null
    }

    // ------------------------------------------------------------ helpers
    private fun overlayType(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

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
                    .setContentTitle("Swat fleet on patrol")
                    .setContentText("New texts are scanned over whatever app you're in.")
                    .setSmallIcon(android.R.drawable.ic_dialog_alert)
                    .build()
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
                    .setContentTitle("Swat fleet on patrol")
                    .setContentText("New texts are scanned over whatever app you're in.")
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

    private fun launchApp() {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        intent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (intent != null) startActivity(intent)
    }
}
