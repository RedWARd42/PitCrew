package com.example.signal_swarm

import kotlin.math.roundToInt

/// The detection engine, ported to Kotlin for the overlay.
///
/// This is a faithful port of `lib/services/scam_analyzer.dart` — same six
/// drone checks, same brand registry, same scoring — so the fleet can run
/// inside the overlay service over the stock Messages app, where no Dart
/// engine is alive. The Dart engine remains the source of truth for the
/// in-app experience (and the unit tests); keep the two in sync.
///
/// One honest difference: the overlay never sees a decoded QR payload
/// (that lives in the message's attachments, not its text), so Scanner
/// scores the "scan the QR code" push at the no-payload weight.
enum class Drone(val label: String, val color: Int) {
    ANGLER("Angler", 0xFFFF8A3D.toInt()),
    LINK("Link", 0xFF38BDF8.toInt()),
    SCANNER("Scanner", 0xFFA78BFA.toInt()),
    PRESSURE("Pressure", 0xFFF87171.toInt()),
    IMPERSONATOR("Impersonator", 0xFFF472B6.toInt()),
    SWAP("Swap", 0xFF34D399.toInt()),
}

data class KFinding(
    val drone: Drone,
    val title: String,
    val detail: String,
    val points: Int,
    val spanStart: Int = -1,
    val spanEnd: Int = -1,
    val evidence: String? = null,
) {
    val isFlag: Boolean get() = points > 0
    val hasSpan: Boolean get() = spanStart >= 0 && spanEnd > spanStart
}

enum class KVerdict(val label: String) {
    SAFE("LOOKS LEGIT"),
    CAUTION("BE CAREFUL"),
    DANGEROUS("SCAM — BLOCK & REPORT"),
}

data class KAnalysis(
    val sender: String,
    val body: String,
    val findings: List<KFinding>,
    val riskScore: Int,
    val confidence: Int,
) {
    val verdict: KVerdict
        get() = when {
            riskScore >= 60 -> KVerdict.DANGEROUS
            riskScore >= 30 -> KVerdict.CAUTION
            else -> KVerdict.SAFE
        }

    fun pointsFor(drone: Drone): Int =
        findings.filter { it.drone == drone }.sumOf { it.points }

    fun findingsFor(drone: Drone): List<KFinding> =
        findings.filter { it.drone == drone }
}

private data class Brand(
    val name: String,
    val officialDomains: Set<String>,
    val officialShortCodes: Set<String>,
    val aliases: List<String>,
)

private val knownBrands = listOf(
    Brand(
        "T-Mobile",
        setOf("t-mobile.com", "tmobile.com", "t-mobile.mymobileapp.com"),
        setOf("456", "2294", "4629"),
        listOf("t-mobile", "tmobile", "t mobile"),
    ),
    Brand(
        "Chase",
        setOf("chase.com", "jpmorganchase.com"),
        setOf("24273", "33748"),
        listOf("chase", "jpmorgan"),
    ),
    Brand(
        "Bank of America",
        setOf("bankofamerica.com", "bofa.com"),
        setOf("692632"),
        listOf("bank of america", "bofa"),
    ),
    Brand(
        "USPS",
        setOf("usps.com"),
        setOf("28777"),
        listOf("usps", "u.s. postal", "postal service"),
    ),
    Brand(
        "UPS",
        setOf("ups.com"),
        setOf("69877"),
        listOf("ups"),
    ),
    Brand(
        "FedEx",
        setOf("fedex.com"),
        setOf("29372"),
        listOf("fedex"),
    ),
    Brand(
        "Amazon",
        setOf("amazon.com", "amazon.co.uk"),
        setOf("262966"),
        listOf("amazon"),
    ),
    Brand(
        "Apple",
        setOf("apple.com", "icloud.com"),
        emptySet(),
        listOf("apple", "icloud"),
    ),
    Brand(
        "IRS",
        setOf("irs.gov"),
        emptySet(),
        listOf("irs", "internal revenue"),
    ),
)

private val urlShorteners = setOf(
    "bit.ly", "tinyurl.com", "t.co", "goo.gl",
    "rb.gy", "is.gd", "cutt.ly", "shorturl.at",
)

object KotlinScamAnalyzer {

    fun analyze(sender: String, body: String): KAnalysis {
        val findings = mutableListOf<KFinding>().apply {
            addAll(angler(sender, body))
            addAll(link(sender, body))
            addAll(scanner(body))
            addAll(pressure(body))
            addAll(impersonator(sender, body))
            addAll(swap(body))
        }
        val (risk, confidence) = scoreFindings(findings)
        return KAnalysis(sender, body, findings, risk, confidence)
    }

    private fun scoreFindings(findings: List<KFinding>): Pair<Int, Int> {
        val flagPoints = findings.filter { it.isFlag }.map { it.points }
            .sortedDescending()
        var risk = 0.0
        for (i in flagPoints.indices) {
            risk += flagPoints[i] * when (i) {
                0 -> 1.0
                1 -> 0.7
                else -> 0.45
            }
        }
        val flagging = findings.filter { it.isFlag }.map { it.drone }.toSet().size
        val confidence = if (flagging == 0) 92 else (55 + flagging * 12).coerceIn(55, 97)
        return risk.roundToInt().coerceIn(0, 100) to confidence
    }

    private fun claimedBrand(sender: String, body: String): Brand? {
        val text = "$sender $body".lowercase()
        return knownBrands.firstOrNull { brand ->
            brand.aliases.any { text.contains(it) }
        }
    }

    // ------------------------------------------------------------- Angler
    private fun angler(senderRaw: String, body: String): List<KFinding> {
        val brand = claimedBrand(senderRaw, body)
        val sender = senderRaw.trim()
        val isShortCode = Regex("^\\d{3,6}$").containsMatchIn(sender)
        val isLongNumber = Regex("^\\+?\\d[\\d\\s\\-()]{6,}$").containsMatchIn(sender)

        if (brand != null && brand.officialShortCodes.contains(sender)) {
            return listOf(
                KFinding(
                    Drone.ANGLER, "Verified sender",
                    "This came from $sender, a registered ${brand.name} short code. " +
                        "Carriers verify who can send from a short code, so this is a " +
                        "strong sign the message is really from ${brand.name}.",
                    0,
                )
            )
        }
        if (brand != null && isLongNumber) {
            val example =
                if (brand.officialShortCodes.isEmpty()) ""
                else " (e.g. ${brand.officialShortCodes.first()})"
            return listOf(
                KFinding(
                    Drone.ANGLER, "Spoofed sender",
                    "The message claims to be ${brand.name}, but it came from an " +
                        "ordinary phone number ($sender). ${brand.name} sends account " +
                        "alerts from a registered short code$example, " +
                        "not from a random number. Scammers rent numbers like this by " +
                        "the thousand.",
                    34, spanStart = 0, spanEnd = 0,
                )
            )
        }
        if (brand != null && !isShortCode) {
            return listOf(
                KFinding(
                    Drone.ANGLER, "Unverified sender name",
                    "The sender shows as \"$sender\", but display names can be set " +
                        "to anything — they are not verified by the carrier.",
                    18,
                )
            )
        }
        return listOf(
            KFinding(
                Drone.ANGLER, "Sender check passed",
                "Nothing about the sender contradicts who the message claims to be.",
                0,
            )
        )
    }

    // --------------------------------------------------------------- Link
    private val urlPattern =
        Regex("((?:https?://)?(?:[a-zA-Z0-9-]+\\.)+[a-zA-Z]{2,}(?:/[^\\s]*)?)")

    private fun extractUrls(text: String): List<String> {
        val urls = mutableListOf<String>()
        for (match in urlPattern.findAll(text)) {
            var url = match.value
            url = url.replace(Regex("[.,;:!?\\)\\]]+$"), "")
            if (url.contains('.') && !url.startsWith(" ")) urls.add(url)
        }
        return urls
    }

    private fun hostOf(url: String): String {
        var u = url.lowercase()
        u = u.replaceFirst(Regex("^https?://"), "")
        return u.split('/').first().split('?').first()
    }

    private fun isOfficial(host: String, brand: Brand): Boolean =
        brand.officialDomains.any { host == it || host.endsWith(".$it") }

    private fun judgeUrl(sender: String, body: String, url: String, start: Int, drone: Drone): KFinding {
        val host = hostOf(url)
        val brand = claimedBrand(sender, body)

        if (urlShorteners.contains(host)) {
            return KFinding(
                drone, "Shortened link hides its destination",
                "\"$host\" is a link shortener — the real destination is hidden " +
                    "until you tap. Legit account alerts almost never hide where a " +
                    "link goes.",
                22, start, start + url.length, url,
            )
        }
        if (Regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$").containsMatchIn(host)) {
            return KFinding(
                drone, "Link goes to a raw IP address",
                "The link points at a bare IP address instead of a company " +
                    "domain. Real companies do not run login pages on raw IPs.",
                30, start, start + url.length, url,
            )
        }
        if (host.contains("xn--")) {
            return KFinding(
                drone, "Lookalike characters in domain",
                "This domain uses encoded characters (punycode) that can render " +
                    "as letters that look like a real brand but are not.",
                28, start, start + url.length, url,
            )
        }
        if (brand != null) {
            if (isOfficial(host, brand)) {
                return KFinding(
                    drone, "Official domain",
                    "$host is a real ${brand.name} domain. Links in genuine alerts " +
                        "stay on the company's own domain.",
                    0, start, start + url.length, url,
                )
            }
            val squashed = host.replace("-", "").replace(".", "")
            val brandSquashed = brand.name.lowercase().replace(Regex("[^a-z]"), "")
            val lookalike = squashed.contains(brandSquashed) || brand.aliases.any { a ->
                host.contains(a.replace(" ", "-")) || host.contains(a.replace(" ", ""))
            }
            if (lookalike) {
                return KFinding(
                    drone, "Lookalike domain",
                    "\"$host\" is built to look like ${brand.name}, but it is NOT a " +
                        "${brand.name} domain. The real one is " +
                        "${brand.officialDomains.first()}. One extra word or hyphen in " +
                        "the domain means a completely different — and fake — site.",
                    36, start, start + url.length, url,
                )
            }
            return KFinding(
                drone, "Off-brand domain",
                "The message claims to be ${brand.name} but links to \"$host\", " +
                    "which is not a ${brand.name} domain.",
                30, start, start + url.length, url,
            )
        }
        return KFinding(
            drone, "Link present",
            "This message contains a link to $host. No brand is claimed, so " +
                "judge it by whether you were expecting it.",
            6, start, start + url.length, url,
        )
    }

    private fun link(sender: String, body: String): List<KFinding> {
        val urls = extractUrls(body)
        if (urls.isEmpty()) {
            return listOf(
                KFinding(
                    Drone.LINK, "No links",
                    "There is no link in this message to tap — a scam's " +
                        "favorite trap is missing.",
                    0,
                )
            )
        }
        return urls.map { url -> judgeUrl(sender, body, url, body.indexOf(url), Drone.LINK) }
    }

    // ------------------------------------------------------------ Scanner
    private fun scanner(body: String): List<KFinding> {
        val findings = mutableListOf<KFinding>()
        val qrMention = Regex("scan (the )?(qr|code)", RegexOption.IGNORE_CASE).find(body)
        if (qrMention != null) {
            findings.add(
                KFinding(
                    Drone.SCANNER, "Pushes you to scan a QR code",
                    "The message tells you to scan a QR code. A QR code hides its " +
                        "destination even better than a link — you cannot read where it " +
                        "goes before it opens. Carriers and banks do not ask you to scan " +
                        "QR codes from a text to \"verify\" an account.",
                    12,
                    qrMention.range.first, qrMention.range.last + 1,
                    qrMention.value,
                )
            )
        }
        if (findings.isEmpty()) {
            findings.add(
                KFinding(
                    Drone.SCANNER, "No QR code",
                    "No QR code attached to or mentioned in this message.",
                    0,
                )
            )
        }
        return findings
    }

    // ----------------------------------------------------------- Pressure
    private val pressurePhrases = listOf(
        "within 24 hours" to "a hard 24-hour deadline",
        "within 12 hours" to "a hard 12-hour deadline",
        "suspended" to "a threat to suspend the account/line",
        "will be closed" to "a threat to close the account",
        "will be locked" to "a threat to lock the account/card",
        "immediately" to "\"immediately\"",
        "act now" to "\"act now\"",
        "urgent" to "\"urgent\"",
        "final notice" to "\"final notice\"",
        "verify now" to "\"verify now\"",
        "expires today" to "a same-day expiry",
        "last chance" to "\"last chance\"",
    )

    private fun pressure(body: String): List<KFinding> {
        val lower = body.lowercase()
        data class Hit(val start: Int, val end: Int, val label: String)
        val hits = mutableListOf<Hit>()
        for ((phrase, label) in pressurePhrases) {
            val idx = lower.indexOf(phrase)
            if (idx >= 0) hits.add(Hit(idx, idx + phrase.length, label))
        }
        if (hits.isEmpty()) {
            return listOf(
                KFinding(
                    Drone.PRESSURE, "Calm tone",
                    "No deadlines, threats, or rush language. Real notices tell " +
                        "you what happened; scams tell you to hurry.",
                    0,
                )
            )
        }
        hits.sortBy { it.start }
        val letters = body.replace(Regex("[^a-zA-Z]"), "")
        val capsRatio = if (letters.isEmpty()) 0.0
        else letters.replace(Regex("[^A-Z]"), "").length.toDouble() / letters.length
        val points = (hits.size * 9 + if (capsRatio > 0.25) 6 else 0).coerceIn(0, 30)
        val first = hits.first()
        return listOf(
            KFinding(
                Drone.PRESSURE, "Pressure tactics (${hits.size})",
                "This message rushes you with ${hits.joinToString(", ") { it.label }}. " +
                    "That is deliberate: the FTC's scam script always adds pressure " +
                    "so you act before you think. A real company gives you time and " +
                    "other ways to reach them.",
                points, first.start, first.end,
                body.substring(first.start, first.end),
            )
        )
    }

    // ------------------------------------------------------- Impersonator
    private fun impersonator(sender: String, body: String): List<KFinding> {
        val findings = mutableListOf<KFinding>()
        val lower = body.lowercase()

        val credentialAsk = Regex(
            "(account pin|your pin|password|social security|ssn|card number|cvv)",
            RegexOption.IGNORE_CASE,
        ).find(body)
        if (credentialAsk != null &&
            Regex("(enter|confirm|verify|share|send|provide|reply)", RegexOption.IGNORE_CASE)
                .containsMatchIn(lower)
        ) {
            findings.add(
                KFinding(
                    Drone.IMPERSONATOR, "Asks for a secret only you should know",
                    "The message asks you to hand over a " +
                        "\"${credentialAsk.value}\". No carrier or bank will ever ask " +
                        "for that by text — the request itself is the scam, whoever it " +
                        "claims to be from.",
                    32,
                    credentialAsk.range.first, credentialAsk.range.last + 1,
                    credentialAsk.value,
                )
            )
        }

        val paymentAsk = Regex(
            "(gift card|wire transfer|western union|bitcoin|crypto|zelle.*stranger)",
            RegexOption.IGNORE_CASE,
        ).find(body)
        if (paymentAsk != null) {
            findings.add(
                KFinding(
                    Drone.IMPERSONATOR, "Unusual payment method demanded",
                    "It steers you toward paying by ${paymentAsk.value} — the " +
                        "payment rail scammers use because it cannot be reversed.",
                    30,
                    paymentAsk.range.first, paymentAsk.range.last + 1,
                    paymentAsk.value,
                )
            )
        }

        if (findings.isEmpty()) {
            val brand = claimedBrand(sender, body)
            findings.add(
                KFinding(
                    Drone.IMPERSONATOR,
                    if (brand == null) "No impersonation tells" else "Identity claim checked",
                    if (brand == null) {
                        "The message does not pretend to be a company or official."
                    } else {
                        "The message claims to be ${brand.name}. Read with Angler's " +
                            "sender check and Link's domain check — an impersonator " +
                            "usually fails at least one of them."
                    },
                    0,
                )
            )
        }
        return findings
    }

    // --------------------------------------------------------------- Swap
    private fun swap(body: String): List<KFinding> {
        val findings = mutableListOf<KFinding>()
        val codeAsk = Regex(
            "(6-digit code|verification code|one-time code|the code we (sent|texted))",
            RegexOption.IGNORE_CASE,
        ).find(body)
        if (codeAsk != null &&
            Regex("(send|share|enter|confirm|reply|give)", RegexOption.IGNORE_CASE)
                .containsMatchIn(body.lowercase())
        ) {
            findings.add(
                KFinding(
                    Drone.SWAP, "Verification-code fishing",
                    "It fishes for a verification code. Those codes are how a " +
                        "scammer takes over your number (a SIM-swap / port-out): they " +
                        "trigger a code to your phone, then talk you into handing it " +
                        "over. Never share a code that a text message itself sent you " +
                        "with anyone who asks for it.",
                    34,
                    codeAsk.range.first, codeAsk.range.last + 1,
                    codeAsk.value,
                )
            )
        }
        val simTalk = Regex(
            "(sim (card )?(will|swap|replace)|port (out|your number)|keep your number active|line will be)",
            RegexOption.IGNORE_CASE,
        ).find(body)
        if (simTalk != null) {
            findings.add(
                KFinding(
                    Drone.SWAP, "Number-takeover framing",
                    "The message talks about your line/number being changed or " +
                        "deactivated. That framing primes you for a SIM-swap pitch. " +
                        "Your real protection: a SIM-swap lock and account PIN set " +
                        "inside the official app — never through a texted link.",
                    18,
                    simTalk.range.first, simTalk.range.last + 1,
                    simTalk.value,
                )
            )
        }
        if (findings.isEmpty()) {
            findings.add(
                KFinding(
                    Drone.SWAP, "No SIM-swap tells",
                    "Nothing here fishes for a verification code or primes a " +
                        "number takeover.",
                    0,
                )
            )
        }
        return findings
    }
}
