package com.signalswarm.signal_swarm

import android.accessibilityservice.AccessibilityService
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import com.signalswarm.signal_swarm.parser.GmailParser
import com.signalswarm.signal_swarm.parser.MessagesParser
import com.signalswarm.signal_swarm.parser.SNode
import com.signalswarm.signal_swarm.parser.ScreenModel

const val TAG = "SWARM"
const val MESSAGES_PKG = "com.google.android.apps.messaging"
const val GMAIL_PKG = "com.google.android.gm"
private val WATCHED = setOf(MESSAGES_PKG, GMAIL_PKG)

/** Reads Google Messages only (config XML is scoped to its package) and feeds parsed screens to the Flutter overlay engine. */
class SwarmAccessibilityService : AccessibilityService() {
    private val main = Handler(Looper.getMainLooper())
    private var overlay: OverlayHost? = null
    private var last: ScreenModel? = null
    private var lastJson = ""
    private var lastDraft: String? = null
    private var visible = false
    private var nonThreadStreak = 0

    private val parseRunnable = Runnable { parseNow() }
    private val watchdog = object : Runnable { // package filter hides "left Messages" events, so poll cheaply while visible
        override fun run() {
            if (visible) {
                if (appRoot()?.packageName?.toString() !in WATCHED) hideOverlay() else parseNow() // poll: Compose scrolling/IME can miss events
                main.postDelayed(this, 600)
            }
        }
    }

    override fun onServiceConnected() {
        Log.d(TAG, "service_connected")
        overlay = OverlayHost(this) { id, payload, reqId -> onAction(id, payload, reqId) }.also { it.start() }
        instance = this
    }

    override fun onAccessibilityEvent(e: AccessibilityEvent?) {
        if (e == null || e.packageName?.toString() !in WATCHED) return
        main.removeCallbacks(parseRunnable)
        main.postDelayed(parseRunnable, 120) // debounce
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        instance = null
        main.removeCallbacksAndMessages(null)
        overlay?.stop()
        Log.d(TAG, "service_destroyed")
        super.onDestroy()
    }

    private fun parseNow() {
        val root = appRoot() ?: return
        val pkg = root.packageName?.toString()
        if (pkg !in WATCHED) { hideOverlay(); return }
        val dm = resources.displayMetrics
        val snap = snapshot(root, 0, IntArray(1))
        val model = if (pkg == GMAIL_PKG) GmailParser.parse(snap, dm.widthPixels, dm.heightPixels) else MessagesParser.parse(snap, dm.widthPixels, dm.heightPixels)
        if (!model.inThread && last?.inThread == true && ++nonThreadStreak < 2) return // cold-open/transition flicker: needs two non-thread parses in a row
        if (model.inThread) nonThreadStreak = 0
        last = model
        if (!model.inThread) { // conversation list etc.: nothing to anchor to
            val j = "{\"t\":\"screen\",\"visible\":true,\"threadKey\":null,\"bubbles\":[]}"
            if (j != lastJson) { lastJson = j; overlay?.sendScreen(j); Log.d(TAG, "screen_sent thread=0") }
            markVisible(); return
        }
        val j = model.toJson().toString()
        if (j != lastJson) {
            lastJson = j
            overlay?.sendScreen(j)
            Log.d(TAG, "screen_sent thread=1 bubbles=${model.bubbles.size} in=${model.bubbles.count { it.direction == "in" }} draft=${model.draftText.length}")
        }
        if (lastDraft != model.draftText) {
            lastDraft = model.draftText
            overlay?.sendDraft(model.draftText)
        }
        markVisible()
    }

    /** Focused app window, not the active one: with the keyboard open the active window is the IME. */
    private fun appRoot(): AccessibilityNodeInfo? {
        val w = windows.firstOrNull { it.type == AccessibilityWindowInfo.TYPE_APPLICATION && (it.isFocused || it.isActive) }
        return w?.root ?: rootInActiveWindow
    }

    private fun markVisible() {
        if (!visible) { visible = true; main.postDelayed(watchdog, 700) }
        overlay?.show()
    }

    private fun hideOverlay() {
        if (!visible) return
        visible = false; lastJson = ""; lastDraft = null
        overlay?.hide()
        Log.d(TAG, "hide")
    }

    /** Eager snapshot; keeps live AccessibilityNodeInfo in [SNode.src] for performAction. */
    private fun snapshot(n: AccessibilityNodeInfo, depth: Int, count: IntArray): SNode {
        count[0]++
        val r = android.graphics.Rect(); n.getBoundsInScreen(r)
        val kids = ArrayList<SNode>()
        if (depth < 40) for (i in 0 until n.childCount) {
            if (count[0] > 2500) break
            val c = n.getChild(i) ?: continue
            if (c.isVisibleToUser) kids.add(snapshot(c, depth + 1, count))
        }
        return SNode(
            n.text?.toString() ?: "", n.contentDescription?.toString() ?: "", n.viewIdResourceName ?: "",
            n.className?.toString() ?: "", r.left, r.top, r.right, r.bottom, n.isClickable, n.isEditable,
            n.isShowingHintText, kids, n,
        )
    }

    /** Native actions: dont_send clears the compose box, send_anyway clicks the real send node. Others are Dart's job. */
    private fun onAction(id: String, payload: Map<String, Any?>, requestId: String) {
        val m = last
        var ok = false
        try {
            when (id) {
                "dont_send" -> (m?.composeNode?.src as? AccessibilityNodeInfo)?.let {
                    it.refresh()
                    ok = it.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,
                        Bundle().apply { putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, "") })
                }
                "send_anyway" -> (m?.sendNode?.src as? AccessibilityNodeInfo)?.let {
                    it.refresh(); ok = it.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                }
                else -> return
            }
        } catch (t: Throwable) { Log.d(TAG, "action_error id=$id") }
        Log.d(TAG, "action id=$id ok=$ok")
        overlay?.sendActionResult(id, requestId, ok)
        main.postDelayed(parseRunnable, 200)
    }

    companion object {
        @Volatile var instance: SwarmAccessibilityService? = null
    }
}
