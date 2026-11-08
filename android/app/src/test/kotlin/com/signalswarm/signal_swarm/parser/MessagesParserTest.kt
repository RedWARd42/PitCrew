package com.example.signal_swarm.parser

import org.junit.Assert.*
import org.junit.Test
import org.w3c.dom.Element
import javax.xml.parsers.DocumentBuilderFactory

class MessagesParserTest {
    private val bounds = Regex("\\[(\\d+),(\\d+)]\\[(\\d+),(\\d+)]")

    private fun toNode(e: Element): SNode {
        val b = bounds.find(e.getAttribute("bounds"))?.groupValues?.drop(1)?.map { it.toInt() } ?: listOf(0, 0, 0, 0)
        val kids = (0 until e.childNodes.length).map { e.childNodes.item(it) }.filterIsInstance<Element>().map { toNode(it) }
        val cls = e.getAttribute("class")
        return SNode(e.getAttribute("text"), e.getAttribute("content-desc"), e.getAttribute("resource-id"), cls,
            b[0], b[1], b[2], b[3], e.getAttribute("clickable") == "true", cls.endsWith("EditText"), false, kids)
    }

    private fun load(name: String): ScreenModel {
        val stream = javaClass.getResourceAsStream("/fixtures/$name.xml")!!
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(stream)
        return MessagesParser.parse(toNode(doc.documentElement), 1080, 2400)
    }

    @Test fun conversationListIsNotAThread() {
        val s = load("conversation_list")
        assertFalse(s.inThread); assertTrue(s.bubbles.isEmpty()); assertNull(s.threadKey)
    }

    @Test fun oneIncoming() {
        val s = load("thread_one_incoming")
        assertEquals("(469) 555-0182", s.senderRaw)
        assertEquals(1, s.bubbles.size) // banners ("Link previews", "Texting with") are not bubbles
        val b = s.bubbles[0]
        assertEquals("in", b.direction)
        assertTrue(b.text.startsWith("T-Mobile: your line will be suspended"))
        assertEquals(40, b.messageId.length)
        assertEquals("", s.draftText)
        assertNotNull(s.compose); assertNull(s.send)
        assertNotNull(s.header)
        assertTrue("link rect found", b.linkRects.isNotEmpty())
        // the URL is on the second line, to the right of "Verify:"
        val last = b.linkRects.last()
        assertTrue(last.y >= 1592 && last.y < 1718 && last.x >= 63 && last.x + last.w <= 924 + 5)
        assertTrue("url x=${last.x} w=${last.w}", last.x in 255..310 && last.w in 480..580)
    }

    @Test fun mixedDirections() {
        val s = load("thread_mixed")
        val dirs = s.bubbles.map { it.direction }
        assertTrue(dirs.contains("in") && dirs.contains("out"))
        val out = s.bubbles.first { it.direction == "out" }
        assertEquals(out.text, out.text.trim()) // leading space stripped
        assertTrue(out.rect.x > 540)
        assertEquals(s.bubbles.map { it.rect.y }, s.bubbles.map { it.rect.y }.sorted())
        assertEquals(s.bubbles.size, s.bubbles.map { it.messageId }.toSet().size)
    }

    @Test fun scrolledDropsClippedAndKeepsOrder() {
        val s = load("thread_scrolled")
        assertTrue(s.bubbles.all { it.rect.y >= (s.header!!.y + s.header.h) })
        assertTrue(s.bubbles.any { it.text.startsWith("Please act now") })
    }

    @Test fun draftAndSend() {
        val s = load("thread_draft_typed")
        assertEquals("Is this real %3F", s.draftText)
        assertNotNull(s.send); assertNotNull(s.sendNode)
        assertTrue(s.send!!.x > 900)
    }

    @Test fun shortCodeThread() {
        val s = load("thread_shortcode")
        assertEquals("22000", s.senderRaw)
        assertEquals("in", s.bubbles.single().direction)
    }

    @Test fun messageIdStableAcrossParses() {
        assertEquals(load("thread_mixed").bubbles.map { it.messageId }, load("thread_mixed").bubbles.map { it.messageId })
    }

    @Test fun jsonShape() {
        val j = load("thread_one_incoming").toJson()
        assertEquals("screen", j.getString("t"))
        assertEquals(1, j.getJSONArray("bubbles").length())
        assertTrue(j.getJSONObject("compose").has("x"))
    }
}
