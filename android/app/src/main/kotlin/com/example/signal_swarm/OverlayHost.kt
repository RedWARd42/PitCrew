package com.example.signal_swarm

import android.accessibilityservice.AccessibilityService
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.WindowManager.LayoutParams as LP
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugins.GeneratedPluginRegistrant
import org.json.JSONArray
import org.json.JSONObject

/**
 * Owns the overlay FlutterEngine (entrypoint overlayMain), the full-screen non-touchable FX window and the small
 * touchable hit windows. All TYPE_ACCESSIBILITY_OVERLAY. Channel 'swarm/bridge', arguments = JSON strings.
 */
class OverlayHost(
    private val svc: AccessibilityService,
    private val onAction: (id: String, payload: Map<String, Any?>, requestId: String) -> Unit,
) {
    private val wm = svc.getSystemService(AccessibilityService.WINDOW_SERVICE) as WindowManager
    private val main = Handler(Looper.getMainLooper())
    private val dm get() = svc.resources.displayMetrics
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var fxView: FlutterView? = null
    private var fxParams: LP? = null
    private var dartReady = false
    private var panelOpen = false
    private var shown = false
    private var pendingScreen: String? = null

    private class Hit(val view: View, val lp: LP)
    private val hits = HashMap<String, Hit>()
    private var wantedTargets: Map<String, IntArray> = emptyMap()
    private var lastLayoutMs = 0L
    private var layoutPosted = false

    fun start() {
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(svc.applicationContext)
        loader.ensureInitializationComplete(svc.applicationContext, null)
        val e = FlutterEngine(svc.applicationContext)
        GeneratedPluginRegistrant.registerWith(e)
        engine = e
        installUrlLauncher(e)
        channel = MethodChannel(e.dartExecutor.binaryMessenger, "swarm/bridge").also { it.setMethodCallHandler(::onCall) }
        e.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "overlayMain"))
        e.lifecycleChannel.appIsResumed()

        val view = FlutterView(svc, FlutterTextureView(svc)) // texture view: reliable per-pixel alpha
        view.setBackgroundColor(Color.TRANSPARENT)
        val lp = LP(LP.MATCH_PARENT, LP.MATCH_PARENT, LP.TYPE_ACCESSIBILITY_OVERLAY, FX_FLAGS, PixelFormat.TRANSLUCENT).apply {
            gravity = Gravity.TOP or Gravity.START
            if (Build.VERSION.SDK_INT >= 28) layoutInDisplayCutoutMode = LP.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            title = "swarm-fx"
        }
        view.attachToFlutterEngine(e)
        view.visibility = View.GONE
        wm.addView(view, lp)
        fxView = view; fxParams = lp
        Log.d(TAG, "overlay_engine_started")
    }

    /** url_launcher_android needs a foreground Activity, which the service engine lacks (NO_ACTIVITY). Replace its pigeon handler. */
    private fun installUrlLauncher(e: FlutterEngine) {
        val name = "dev.flutter.pigeon.url_launcher_android.UrlLauncherApi.launchUrl"
        BasicMessageChannel(e.dartExecutor.binaryMessenger, name, StandardMessageCodec.INSTANCE).setMessageHandler { msg, reply ->
            val url = (msg as? List<*>)?.firstOrNull() as? String
            val ok = try {
                val uri = android.net.Uri.parse(url)
                val action = if (uri.scheme == "tel") android.content.Intent.ACTION_DIAL else android.content.Intent.ACTION_VIEW
                svc.startActivity(android.content.Intent(action, uri).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
                true
            } catch (t: Throwable) { false }
            Log.d(TAG, "launch scheme=${url?.substringBefore(':')} ok=$ok")
            reply.reply(listOf(ok))
        }
    }

    fun stop() {
        main.removeCallbacksAndMessages(null)
        clearHits()
        fxView?.let { it.detachFromFlutterEngine(); runCatching { wm.removeView(it) } }
        fxView = null
        engine?.destroy(); engine = null
    }

    // ---- Kotlin -> Dart ----
    private fun invoke(method: String, json: String) = channel?.invokeMethod(method, json)

    private fun sendInit() {
        val d = dm
        val ins = JSONObject()
        val rid = svc.resources.getIdentifier("status_bar_height", "dimen", "android")
        ins.put("top", if (rid > 0) svc.resources.getDimensionPixelSize(rid) else 0).put("bottom", 0).put("left", 0).put("right", 0)
        invoke("init", JSONObject().put("t", "init").put("density", d.density.toDouble())
            .put("screenW", d.widthPixels).put("screenH", d.heightPixels).put("insets", ins).toString())
    }

    fun sendScreen(json: String) {
        if (!dartReady) { pendingScreen = json; return }
        invoke("screen", json)
    }

    fun sendDraft(text: String) { if (dartReady) invoke("draftText", JSONObject().put("t", "draftText").put("text", text).toString()) }

    fun sendActionResult(id: String, requestId: String, ok: Boolean) =
        invoke("actionResult", JSONObject().put("t", "actionResult").put("id", id).put("requestId", requestId).put("ok", ok).toString())

    fun show() {
        shown = true
        fxView?.visibility = View.VISIBLE
        if (!panelOpen) applyHits()
    }

    fun hide() {
        shown = false
        invoke("hide", "{\"t\":\"hide\"}")
        fxView?.visibility = View.GONE
        if (panelOpen) setPanel(false)
        clearHits()
    }

    // ---- Dart -> Kotlin ----
    private fun args(c: io.flutter.plugin.common.MethodCall): JSONObject {
        val a = c.arguments
        return try { if (a is String) JSONObject(a) else if (a is Map<*, *>) JSONObject(a) else JSONObject() } catch (_: Throwable) { JSONObject() }
    }

    private fun onCall(c: io.flutter.plugin.common.MethodCall, r: MethodChannel.Result) {
        val a = args(c)
        when (c.method) {
            "ready" -> {
                dartReady = true
                Log.d(TAG, "dart_ready")
                sendInit()
                pendingScreen?.let { pendingScreen = null; invoke("screen", it) }
            }
            "hitTargets" -> {
                val arr = a.optJSONArray("targets") ?: JSONArray()
                val m = HashMap<String, IntArray>()
                for (i in 0 until arr.length()) {
                    val t = arr.getJSONObject(i); val rc = t.getJSONObject("rect")
                    m[t.getString("id")] = intArrayOf(rc.getDouble("x").toInt(), rc.getDouble("y").toInt(), rc.getDouble("w").toInt(), rc.getDouble("h").toInt())
                }
                wantedTargets = m
                scheduleLayout()
            }
            "panel" -> setPanel(a.optBoolean("open"))
            "action" -> {
                val p = a.optJSONObject("payload")
                val pm = HashMap<String, Any?>().also { mm -> p?.keys()?.forEach { k -> mm[k] = p.opt(k) } }
                onAction(a.optString("id"), pm, a.optString("requestId"))
            }
            "log" -> Log.d(TAG, "dart:" + a.optString("event").take(60))
        }
        r.success(null)
    }

    private fun setPanel(open: Boolean) {
        panelOpen = open
        val lp = fxParams ?: return
        lp.flags = if (open) FX_FLAGS and LP.FLAG_NOT_TOUCHABLE.inv() else FX_FLAGS
        runCatching { wm.updateViewLayout(fxView, lp) }
        if (open) clearHits() else if (shown) applyHits()
        Log.d(TAG, "panel open=$open")
    }

    // ---- hit windows (>=48dp, rate-limited to 50ms) ----
    private fun scheduleLayout() {
        if (panelOpen || !shown) return
        val wait = 50 - (System.currentTimeMillis() - lastLayoutMs)
        if (wait <= 0) applyHits()
        else if (!layoutPosted) { layoutPosted = true; main.postDelayed({ layoutPosted = false; applyHits() }, wait) }
    }

    private fun applyHits() {
        if (panelOpen || !shown) return
        lastLayoutMs = System.currentTimeMillis()
        val min = (48 * dm.density).toInt()
        for (id in hits.keys.toList()) if (id !in wantedTargets) hits.remove(id)?.let { runCatching { wm.removeView(it.view) } }
        for ((id, rc) in wantedTargets) {
            val w = maxOf(rc[2], min); val h = maxOf(rc[3], min)
            val x = rc[0] - (w - rc[2]) / 2; val y = rc[1] - (h - rc[3]) / 2
            val ex = hits[id]
            if (ex != null) {
                ex.lp.x = x; ex.lp.y = y; ex.lp.width = w; ex.lp.height = h
                runCatching { wm.updateViewLayout(ex.view, ex.lp) }
            } else {
                val v = View(svc).apply {
                    setBackgroundColor(Color.TRANSPARENT)
                    if (id.startsWith("card:")) setOnTouchListener { _, ev -> forwardToFx(ev); true } // cards hold Flutter buttons: replay raw touches into the FX view
                    else setOnClickListener { invoke("tap", JSONObject().put("t", "tap").put("id", id).toString()) }
                }
                val lp = LP(w, h, LP.TYPE_ACCESSIBILITY_OVERLAY, LP.FLAG_NOT_FOCUSABLE or LP.FLAG_LAYOUT_NO_LIMITS or LP.FLAG_LAYOUT_IN_SCREEN, PixelFormat.TRANSLUCENT)
                    .apply { gravity = Gravity.TOP or Gravity.START; this.x = x; this.y = y; title = "swarm-hit" }
                if (Build.VERSION.SDK_INT >= 28) lp.layoutInDisplayCutoutMode = LP.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                runCatching { wm.addView(v, lp); hits[id] = Hit(v, lp) }
            }
        }
    }

    private fun forwardToFx(ev: android.view.MotionEvent) {
        val fx = fxView ?: return
        val c = android.view.MotionEvent.obtain(ev)
        c.offsetLocation(ev.rawX - ev.x, ev.rawY - ev.y) // hit window -> FX view coords (FX is full-screen at 0,0)
        fx.dispatchTouchEvent(c)
        c.recycle()
    }

    private fun clearHits() {
        for (h in hits.values) runCatching { wm.removeView(h.view) }
        hits.clear()
    }

    companion object {
        const val FX_FLAGS = LP.FLAG_NOT_TOUCHABLE or LP.FLAG_NOT_FOCUSABLE or LP.FLAG_LAYOUT_IN_SCREEN or LP.FLAG_LAYOUT_NO_LIMITS
    }
}
