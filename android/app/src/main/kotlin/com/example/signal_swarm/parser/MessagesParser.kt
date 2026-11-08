package com.example.signal_swarm.parser

import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

/** Android-free node snapshot so the parser is unit-testable on the JVM. [src] keeps the live AccessibilityNodeInfo. */
class SNode(
    val text: String = "", val desc: String = "", val resId: String = "", val cls: String = "",
    val l: Int = 0, val t: Int = 0, val r: Int = 0, val b: Int = 0,
    val clickable: Boolean = false, val editable: Boolean = false, val showingHint: Boolean = false,
    val children: List<SNode> = emptyList(), val src: Any? = null,
) {
    val w get() = r - l
    val h get() = b - t
    fun walk(): Sequence<SNode> = sequence { yield(this@SNode); for (c in children) yieldAll(c.walk()) }
}

data class R(val x: Int, val y: Int, val w: Int, val h: Int) {
    fun toJson() = JSONObject().put("x", x).put("y", y).put("w", w).put("h", h)
}

data class Bubble(val messageId: String, val direction: String, val text: String, val rect: R, val linkRects: List<R>)

data class ScreenModel(
    val inThread: Boolean, val threadKey: String?, val senderRaw: String?, val draftText: String,
    val header: R?, val compose: R?, val send: R?, val bubbles: List<Bubble>,
    val composeNode: SNode? = null, val sendNode: SNode? = null,
    val email: JSONObject? = null,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("t", "screen"); put("visible", true)
        if (email != null) { put("channel", "email"); put("email", email) }
        put("threadKey", threadKey ?: JSONObject.NULL); put("senderRaw", senderRaw ?: JSONObject.NULL)
        put("draftText", draftText)
        put("header", header?.toJson() ?: JSONObject.NULL)
        put("compose", compose?.toJson() ?: JSONObject.NULL)
        put("send", send?.toJson() ?: JSONObject.NULL)
        put("bubbles", JSONArray().also { a ->
            for (b in bubbles) a.put(JSONObject().put("messageId", b.messageId).put("direction", b.direction)
                .put("text", b.text).put("rect", b.rect.toJson())
                .put("linkRects", JSONArray().also { l -> b.linkRects.forEach { l.put(it.toJson()) } }))
        })
    }
}

/** Pure parser for Google Messages (see docs/messages-ui-notes.md). Text + geometry first, resource ids only as hints. */
object MessagesParser {
    private val said = Regex("^(.+?) said\\s+(.*)$", RegexOption.DOT_MATCHES_ALL)
    private val hintText = Regex("^(text|rcs|chat|sms|mms)?\\s?message$", RegexOption.IGNORE_CASE)
    private val url = Regex("(?i)\\b(?:https?://)?(?:[a-z0-9-]+\\.)+[a-z]{2,}(?:/[^\\s]*)?")
    private val skipHeader = Regex("^(save .*\\?|saving this .*|report spam|add contact|messages|unread)$", RegexOption.IGNORE_CASE)

    fun sha1(s: String) = MessageDigest.getInstance("SHA-1").digest(s.toByteArray()).joinToString("") { "%02x".format(it) }

    fun parse(root: SNode, screenW: Int, screenH: Int): ScreenModel {
        val all = root.walk().toList()
        val edit = all.firstOrNull { it.editable && it.resId.endsWith("compose_message_text") }
            ?: all.firstOrNull { it.editable || it.cls.endsWith("EditText") }
        val inThread = edit != null || all.any { it.resId == "message_list" }
        if (!inThread) return ScreenModel(false, null, null, "", null, null, null, emptyList())

        val header = findHeader(all)
        val sender = header?.text?.trim()
        val threadKey = "t_" + sha1(sender ?: "?").take(10)
        val draft = edit?.let { if (it.showingHint || hintText.matches(it.text.trim())) "" else it.text } ?: ""
        val sendNode = all.firstOrNull { it.resId == "Compose:Draft:Send" }
            ?: all.firstOrNull { it.clickable && it.children.any { c -> c.desc.startsWith("Send") } }
            ?: all.firstOrNull { it.clickable && it.desc.startsWith("Send") }

        val top = header?.let { it.b + 45 } ?: 0
        val bottom = edit?.t ?: screenH
        val seen = HashMap<String, Int>()
        val bubbles = all.asSequence().filter { it.cls.endsWith("TextView") && it.text.isNotBlank() }
            .mapNotNull { n -> classify(n, screenW)?.let { n to it } }
            .sortedBy { it.first.t }
            .filter { (n, _) -> n.t < bottom && n.b > top && visibleFraction(n, top, bottom) >= 0.5 }
            .map { (n, dir) ->
                val text = n.text.trim()
                val ord = seen.merge(text, 1, Int::plus)!! - 1
                val rect = R((n.l - 24).coerceAtLeast(0), (n.t - 12).coerceAtLeast(top), n.w + 48, n.h + 24)
                Bubble(sha1(threadKey + text + ord), dir, text, rect, linkRects(n, text))
            }.toList()

        return ScreenModel(true, threadKey, sender, draft, header?.let { R(0, it.t - 45, screenW, it.h + 90) },
            edit?.let { R(it.l, it.t, it.w, it.h) },
            sendNode?.let { R(it.l, it.t, it.w, it.h) }, bubbles, edit, sendNode)
    }

    private fun visibleFraction(n: SNode, top: Int, bottom: Int): Float {
        val h = (n.b - n.t).coerceAtLeast(1)
        return (minOf(n.b, bottom) - maxOf(n.t, top)).toFloat() / h
    }

    /** Title TextView in the app bar: leftmost non-banner text whose top is in the top band. */
    private fun findHeader(all: List<SNode>): SNode? =
        all.filter { it.cls.endsWith("TextView") && it.text.isNotBlank() && it.t in 40..260 && it.b <= 270 && !skipHeader.matches(it.text.trim()) }
            .minByOrNull { it.l }

    /** in/out, or null when the node is not a bubble (date separators, banners, header, link-preview cards). */
    private fun classify(n: SNode, screenW: Int): String? {
        val m = said.find(n.desc)
        if (m != null) return if (m.groupValues[1].equals("You", true)) "out" else "in"
        if (n.resId != "message_text") return null // fallback only for Messages' bubble tag with no description
        val cx = (n.l + n.r) / 2
        if (Math.abs(cx - screenW / 2) < screenW * 0.15) return null // centered = system banner
        return if (cx > screenW / 2) "out" else "in"
    }

    /** Roboto-ish advance widths in em; good to a few percent, which is enough for a highlight box. */
    private fun adv(c: Char): Double = when (c) {
        ' ' -> .25; 'i', 'l', 'j', '.', ',', ':', ';', '!', '|' -> .26
        'f', 't', 'r', 'I', '-', '(', ')', '/' -> .34
        'm' -> .86; 'w' -> .76; 'M' -> .88; 'W' -> .95
        in '0'..'9' -> .56; in 'A'..'Z' -> .63; else -> .54
    }

    /** Best-effort: proportional-width greedy wrap fitted to the node's line count; limit: font metrics are guessed, upgrade by measuring with Paint on device. */
    fun linkRects(n: SNode, text: String): List<R> {
        val urls = url.findAll(text).filter { it.value.length > 4 }.toList()
        if (urls.isEmpty() || n.h <= 0 || n.w <= 0) return emptyList()
        val lines = Math.round(n.h / (n.w * 0.073)).toInt().coerceAtLeast(1)
        val rowH = n.h.toDouble() / lines
        val em = rowH / 1.5
        val starts = arrayListOf(0)
        var x = 0.0; var lastSpace = -1; var i = 0
        while (i < text.length) {
            val w = adv(text[i]) * em
            if (text[i] == ' ') lastSpace = i else if (text[i] == '/' && i > starts.last()) lastSpace = i // Android breaks URLs after '/'
            if (x + w > n.w * 0.96 && i > starts.last()) {
                val brk = if (lastSpace >= starts.last()) lastSpace + 1 else i
                starts.add(brk); x = 0.0; lastSpace = -1; i = brk; continue
            }
            x += w; i++
        }
        fun off(from: Int, to: Int): Double { var o = 0.0; for (k in from until to) o += adv(text[k]) * em; return o }
        val out = ArrayList<R>()
        for (u in urls) {
            var p = u.range.first
            val end = u.range.last + 1
            while (p < end) {
                val li = starts.indexOfLast { it <= p }
                val lineEnd = if (li + 1 < starts.size) starts[li + 1] else text.length
                val seg = minOf(end, lineEnd)
                val x0 = off(starts[li], p); val w = off(p, seg)
                out.add(R((n.l + x0).toInt(), (n.t + li * rowH).toInt(), w.toInt().coerceAtLeast(1), rowH.toInt()))
                p = seg
            }
        }
        return out
    }
}
