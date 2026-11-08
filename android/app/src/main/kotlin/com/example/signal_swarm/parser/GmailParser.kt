package com.example.signal_swarm.parser

import org.json.JSONArray
import org.json.JSONObject

/**
 * Pure parser for an open email in Gmail (com.google.android.gm), written against a real uiautomator capture
 * (fixtures/gmail_email_phish*.xml). The open email lives under conversation_view_container; the inbox list is ignored.
 * Body = union of text-bearing TextViews inside the WebView, clipped to the visible area between the sender header
 * and the reply footer. shortcut: scrolled-away parts are simply absent from the tree, so rects are always on screen.
 */
object GmailParser {
    private val emailRe = Regex("""[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}""")
    private val urlRe = Regex("""(?i)\b(?:https?://|www\.)[^\s<>"]+|\b(?:[a-z0-9-]+\.)+(?:com|net|org|co|io|info|biz|xyz|top|ru|cn|me|us)(?:/[^\s<>"]*)?""")
    private val replyToRe = Regex("""(?i)reply[- ]?to:?\s*(.*)""")
    private val skipIds = setOf("conversation-header", "conversation-footer", "conversation-promotion", "initial-load-signal")

    private fun SNode.id() = resId.substringAfterLast('/')
    private fun SNode.clip(top: Int, bottom: Int): R? {
        val t = maxOf(t, top)
        val b = minOf(b, bottom)
        return if (b > t && r > l) R(l, t, r - l, b - t) else null
    }

    fun parse(root: SNode, screenW: Int, screenH: Int): ScreenModel {
        val none = ScreenModel(false, null, null, "", null, null, null, emptyList())
        val all = root.walk().toList()
        val container = all.firstOrNull { it.id() == "conversation_view_container" } ?: return none
        val inView = container.walk().toList()
        val web = inView.filter { it.cls.endsWith("WebView") }.maxByOrNull { it.w * it.h } ?: return none
        val subject = inView.firstOrNull { it.id() == "subject_and_folder_view" }?.text?.trim() ?: return none
        val upper = inView.firstOrNull { it.id() == "upper_header" }
        // expanded details card (From/Reply-to/To/Date): part of the header, body starts below it
        val card = inView.firstOrNull { it.id() == "header_extra_content" && it.h > 0 }
        val top = maxOf(upper?.b ?: inView.firstOrNull { it.id() == "conversation_header" }?.b ?: container.t, card?.b ?: 0)
        val footer = inView.firstOrNull { it.id() == "conversation_footer" && it.cls.endsWith("LinearLayout") }
        val bottom = minOf(footer?.t ?: container.b, all.firstOrNull { it.id() == "hub_tabs_nav" }?.t ?: container.b, container.b)

        val fromName = inView.firstOrNull { it.id() == "sender_name" }?.text?.trim().orEmpty()
        // header texts only (the sender row and anything the expanded header adds above the body)
        val webSet = web.walk().toSet()
        val headerNodes = inView.filter { n ->
            n !in webSet && n.id() != "subject_and_folder_view" && upper != null && n.t >= upper.t - 4 && n.t < web.t.coerceAtLeast(upper.b + 400)
        }
        val blobs = headerNodes.flatMap { listOf(it.text, it.desc) }.filter { it.isNotBlank() && !it.startsWith("Show contact") }
        fun detail(id: String) = inView.firstOrNull { it.id() == id }?.let { emailRe.find(it.text)?.value ?: emailRe.find(it.desc)?.value }
        // expanded header ids first; fall back to regexes over the header text
        val replyTo = detail("replyto_details") ?: blobs.firstNotNullOfOrNull { replyToRe.find(it)?.groupValues?.get(1)?.let { v -> emailRe.find(v)?.value } }
        val fromAddress = detail("from_details") ?: blobs.filter { replyToRe.find(it) == null }.firstNotNullOfOrNull { emailRe.find(it)?.value }.orEmpty()

        val inWeb = web.walk().filter { it !== web }.toList()
        val bodyNodes = inWeb.filter { it.cls.endsWith("TextView") && it.text.isNotBlank() && it.id() !in skipIds && it.t < bottom && it.b > top }
        val bodyText = bodyNodes.sortedWith(compareBy({ it.t }, { it.l })).joinToString("\n") { it.text.trim() }
        val rs = bodyNodes.mapNotNull { it.clip(top, bottom) }
        val bodyRect = if (rs.isEmpty()) R(web.l, top, web.w, 0) else {
            val l = rs.minOf { it.x }
            val t = rs.minOf { it.y }
            R(l, t, rs.maxOf { it.x + it.w } - l, rs.maxOf { it.y + it.h } - t)
        }

        val links = JSONArray()
        val linkRects = ArrayList<R>()
        val seen = HashSet<String>()
        // Known limit: Gmail's WebView exposes only the VISIBLE link text (content-desc == text), never the real href, so
        // href == text here. A text-vs-href mismatch cannot be detected through the accessibility tree, only lookalike visible URLs.
        // View nodes carry the URL in content-desc (best href); text-only URLs are a fallback when no View shares the rect
        for (n in inWeb.filter { it.desc.isNotBlank() && urlRe.containsMatchIn(it.desc) && it.id() !in skipIds }) {
            val r = n.clip(top, bottom) ?: continue
            if (!seen.add("${r.x},${r.y}")) continue
            links.put(JSONObject().put("text", n.desc.trim()).put("href", urlRe.find(n.desc)!!.value).put("rect", r.toJson()))
            linkRects.add(r)
        }
        for (n in inWeb.filter { it.text.isNotBlank() && it.id() !in skipIds && urlRe.matchEntire(it.text.trim()) != null }) {
            val r = n.clip(top, bottom) ?: continue
            if (!seen.add("${r.x},${r.y}")) continue
            links.put(JSONObject().put("text", n.text.trim()).put("href", n.text.trim()).put("rect", r.toJson()))
            linkRects.add(r)
        }

        val atts = JSONArray()
        for (n in inView.filter { it.id() == "message_attachment_tile" }) {
            val r = n.clip(top, bottom) ?: continue
            val title = n.walk().firstOrNull { it.id() == "attachment_tile_title" }?.text
            val name = title?.takeIf { it.isNotBlank() } ?: n.desc.substringAfter(", ", n.desc)
            atts.put(JSONObject().put("name", name.trim()).put("rect", R(n.l, r.y, n.w, r.h).toJson()))
        }

        val mid = MessagesParser.sha1("$fromAddress|$fromName|$subject|${bodyText.take(200)}")
        val header = upper?.let { R(0, it.t, screenW, maxOf(it.b, card?.b ?: 0) - it.t) }
        val email = JSONObject().put("subject", subject).put("fromName", fromName).put("fromAddress", fromAddress)
            .put("links", links).put("attachments", atts)
        if (replyTo != null) email.put("replyTo", replyTo)
        return ScreenModel(true, "e_" + mid.take(10), fromName.ifBlank { fromAddress }, "", header, null, null,
            listOf(Bubble(mid, "in", bodyText, bodyRect, linkRects)), email = email)
    }
}
