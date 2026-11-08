package com.signalswarm.signal_swarm.parser

import org.junit.Assert.*
import org.junit.Test
import org.w3c.dom.Element
import javax.xml.parsers.DocumentBuilderFactory

class GmailParserTest {
    private val bounds = Regex("\\[(\\d+),(\\d+)]\\[(\\d+),(\\d+)]")

    private fun toNode(e: Element): SNode {
        val b = bounds.find(e.getAttribute("bounds"))?.groupValues?.drop(1)?.map { it.toInt() } ?: listOf(0, 0, 0, 0)
        val kids = (0 until e.childNodes.length).map { e.childNodes.item(it) }.filterIsInstance<Element>().map { toNode(it) }
        val cls = e.getAttribute("class")
        return SNode(e.getAttribute("text"), e.getAttribute("content-desc"), e.getAttribute("resource-id"), cls, b[0], b[1], b[2], b[3],
            e.getAttribute("clickable") == "true", cls.endsWith("EditText"), false, kids)
    }

    private fun load(name: String): ScreenModel {
        val s = javaClass.getResourceAsStream("/fixtures/$name.xml") ?: error("missing fixture $name")
        return GmailParser.parse(toNode(DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(s).documentElement), 1080, 2400)
    }

    @Test fun phishEmail() {
        val s = load("gmail_email_phish")
        assertTrue(s.inThread)
        val e = s.email!!
        assertTrue(e.getString("subject").startsWith("Your account is limited"))
        assertEquals("PayPal Support", e.getString("fromName"))
        assertEquals("", e.getString("fromAddress")) // collapsed header shows no address
        assertEquals(432, s.header!!.y)
        assertEquals(236, s.header!!.h)
        val b = s.bubbles.single()
        assertEquals("in", b.direction)
        assertEquals(706, b.rect.y) // real text only, not the 427..1254 message container
        assertEquals(1021, b.rect.y + b.rect.h)
        assertTrue(b.text.startsWith("Dear customer,"))
        assertTrue(b.text.contains("See attached form."))
        val links = e.getJSONArray("links")
        assertEquals(1, links.length())
        val l = links.getJSONObject(0)
        assertEquals("https://www.paypal.com/verify", l.getString("href"))
        assertEquals(900, l.getJSONObject("rect").getInt("y"))
        assertEquals(493, l.getJSONObject("rect").getInt("w"))
        val a = e.getJSONArray("attachments")
        assertEquals(1, a.length())
        assertEquals("invoice_4491.html", a.getJSONObject(0).getString("name"))
        assertEquals(1060, a.getJSONObject(0).getJSONObject("rect").getInt("y"))
        assertEquals("email", s.toJson().getString("channel"))
        assertEquals(b.messageId, load("gmail_email_phish").bubbles[0].messageId)
    }

    @Test fun expandedHeaderShowsAddressAndReplyTo() {
        val s = load("gmail_email_phish_expanded")
        val e = s.email!!
        assertEquals("goatmoho@gmail.com", e.getString("fromAddress"))
        assertEquals("help@mailbox-relay.biz", e.getString("replyTo"))
        assertEquals("PayPal Support", e.getString("fromName"))
        assertEquals(1, e.getJSONArray("links").length())
        assertEquals(1, e.getJSONArray("attachments").length())
        assertEquals(432, s.header!!.y)
        assertEquals(1196, s.header!!.y + s.header!!.h) // header rect now covers the whole details card
        assertTrue(s.bubbles.single().rect.y >= 1196) // body sits below the expanded details card
        assertEquals("https://www.paypal.com/verify", e.getJSONArray("links").getJSONObject(0).getString("href"))
    }

    @Test fun inboxIsNotAnEmail() {
        assertFalse(load("conversation_list").inThread)
    }
}
